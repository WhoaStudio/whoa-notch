import Foundation

/// Tient les requêtes lues dans les journaux et les rafraîchit à la demande. Pousse l'état par
/// `onChanged`, comme les autres modèles de vue ; les filtres et les mesures sont du ressort de
/// la vue (`ActivityAggregator`).
@MainActor
final class AgentActivityViewModel {

  private(set) var records: [ActivityRecord] = [] {
    didSet {
      guard records != oldValue else { return }
      onChanged?()
    }
  }

  private(set) var isLoading = false
  var onChanged: (() -> Void)?

  private let provider: AgentActivityProviding
  private let calendar: Calendar
  private var loadedMonthOffset: Int?
  private var inFlight: Task<Void, Never>?

  init(provider: AgentActivityProviding, calendar: Calendar = .current) {
    self.provider = provider
    self.calendar = calendar
  }

  /// Charge les journaux jusqu'au début du mois `monthOffset`. Un second appel en cours est
  /// ignoré sauf s'il remonte plus loin dans le temps.
  func load(monthOffset: Int = 0) {
    if let loadedMonthOffset, loadedMonthOffset >= monthOffset, inFlight != nil { return }
    inFlight?.cancel()
    loadedMonthOffset = max(monthOffset, loadedMonthOffset ?? 0)

    let since = ActivityAggregator.month(
      offset: loadedMonthOffset ?? 0, now: Date(), calendar: calendar
    ).start
    isLoading = true
    onChanged?()
    inFlight = Task { [weak self, provider] in
      let loaded = await provider.records(since: since)
      guard !Task.isCancelled, let self else { return }
      self.records = loaded
      self.isLoading = false
      self.inFlight = nil
      self.onChanged?()
    }
  }
}
