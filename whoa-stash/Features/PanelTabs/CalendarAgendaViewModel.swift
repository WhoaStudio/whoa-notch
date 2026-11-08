import AppKit
import OSLog

/// Expose l'agenda du jour aux vues AppKit avec un simple callback — pas de Combine côté vue,
/// comme `ClaudeUsageViewModel`, dont ce modèle reprend la forme.
///
/// Une seule instance alimente tous les panneaux : il y en a un par écran, et c'est ce qui
/// garantit qu'ils montrent la même journée sans multiplier les lectures du magasin.
@MainActor
final class CalendarAgendaViewModel {

  private(set) var state: CalendarAgendaState = .loading {
    didSet {
      guard state != oldValue else { return }
      onStateChanged?()
    }
  }

  var onStateChanged: (() -> Void)?

  private let provider: CalendarAgendaProviding

  private var inFlight: Task<Void, Never>?
  private var changesTask: Task<Void, Never>?
  private var wakeObserver: NSObjectProtocol?

  /// Jour couvert par l'instantané courant, pour détecter le passage de minuit. Le panneau
  /// reste en mémoire plusieurs jours sans que l'app redémarre, et un agenda d'hier affiché
  /// sous la date d'aujourd'hui serait pire que pas d'agenda du tout.
  private var loadedDay: Date?

  init(provider: CalendarAgendaProviding) {
    self.provider = provider
  }

  func activate() {
    // L'accès est demandé une seule fois, et avant la première lecture : sans lui, celle-ci
    // ne renverrait que des journées vides.
    Task { [weak self] in
      guard let self else { return }
      let access = await provider.requestAccess()
      Log.calendar.info("accès aux calendriers — \(String(describing: access), privacy: .public)")

      guard access == .granted else {
        self.state = .unavailable(access)
        return
      }
      self.refresh()
      self.observeChanges()
    }

    // Au réveil, la machine peut avoir changé de jour et les calendriers distants s'être
    // synchronisés sans que l'app tourne : on repart d'une lecture fraîche.
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.refresh(force: true) }
    }
  }

  /// Rafraîchissement immédiat — appelé à l'activation, à chaque changement du magasin, et à
  /// chaque dépliage du panneau pour que la première image montrée soit à jour.
  ///
  /// `force` ignore le garde-fou du jour déjà chargé : utile au réveil et sur changement du
  /// magasin, où la journée n'a pas bougé mais son contenu, si.
  func refresh(force: Bool = false) {
    // Un accès refusé ne se rattrape pas en relisant : l'utilisateur doit passer par les
    // Réglages Système, qui feront redémarrer l'app.
    if case .unavailable = state, !force { return }
    guard inFlight == nil else { return }

    let now = Date()
    if !force, let loadedDay, Calendar.current.isDate(loadedDay, inSameDayAs: now),
      state.agenda != nil
    {
      return
    }

    inFlight = Task { [weak self] in
      guard let self else { return }
      do {
        let agenda = try await provider.fetchAgenda(for: now)
        self.loadedDay = Calendar.current.startOfDay(for: now)
        self.state = .loaded(agenda)
      } catch {
        // Un échec ponctuel ne doit pas effacer un agenda déjà affiché : la liste garde
        // sa dernière version connue plutôt que de clignoter.
        if self.state.agenda == nil {
          self.state = .unavailable(provider.accessStatus)
        }
        Log.calendar.error(
          "lecture de l'agenda échouée — \(error.localizedDescription, privacy: .public)")
      }
      self.inFlight = nil
    }
  }

  /// Les événements d'un seul jour, pour le panneau de la bande de la semaine. Sans état : la
  /// sélection vit dans chaque panneau, il y en a un par écran, et ce qui est lu ici ne
  /// remplace jamais l'agenda partagé du widget calendrier.
  ///
  /// Renvoie le même `CalendarAgendaState` que le widget, réduit à ce jour : l'écriteau d'accès
  /// refusé et le « No events » viennent alors de `AgendaListView`, sans second texte à tenir.
  func dayState(for date: Date) async -> CalendarAgendaState {
    guard provider.accessStatus == .granted else { return .unavailable(provider.accessStatus) }

    do {
      let agenda = try await provider.fetchAgenda(for: date)
      return CalendarAgendaState.loaded(agenda).showingFirstDayOnly
    } catch {
      Log.calendar.error(
        "lecture du jour échouée — \(error.localizedDescription, privacy: .public)")
      return .unavailable(provider.accessStatus)
    }
  }

  /// Suit `EKEventStoreChanged` — sans le nommer : le flux vient de la source, et c'est ce qui
  /// garde EventKit hors de ce fichier.
  private func observeChanges() {
    changesTask = Task { [weak self] in
      guard let self else { return }
      for await _ in provider.changes() {
        self.refresh(force: true)
      }
    }
  }
}
