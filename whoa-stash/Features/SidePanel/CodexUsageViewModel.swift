import AppKit
import OSLog

@MainActor
final class CodexUsageViewModel {
  private(set) var state: CodexUsageState = .loading {
    didSet {
      guard state != oldValue else { return }
      onStateChanged?()
    }
  }

  var onStateChanged: (() -> Void)?

  private let provider: CodexUsageProviding
  private let refreshInterval: TimeInterval = 60
  private let countdownInterval: TimeInterval = 30
  private var refreshTimer: Timer?
  private var countdownTimer: Timer?
  private var wakeObserver: NSObjectProtocol?
  private var inFlight: Task<Void, Never>?

  init(provider: CodexUsageProviding) {
    self.provider = provider
  }

  func activate() {
    refresh()
    refreshTimer = schedule(interval: refreshInterval) { [weak self] in self?.refresh() }
    countdownTimer = schedule(interval: countdownInterval) { [weak self] in self?.onStateChanged?()
    }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func refresh() {
    guard inFlight == nil else { return }
    inFlight = Task { [weak self] in
      guard let self else { return }
      do {
        self.state = .loaded(try await provider.fetchSnapshot())
      } catch {
        if CodexUsageState.requiresLogin(error) {
          self.state = .expired(reason: error.localizedDescription)
        } else if self.state.snapshot == nil {
          self.state = .unavailable(reason: error.localizedDescription)
        }
        Log.sidePanel.error(
          "rafraîchissement de l'utilisation Codex échoué — \(error.localizedDescription, privacy: .public)"
        )
      }
      self.inFlight = nil
    }
  }

  private func schedule(interval: TimeInterval, tick: @escaping @Sendable @MainActor () -> Void)
    -> Timer
  {
    let timer = Timer(timeInterval: interval, repeats: true) { _ in
      Task { @MainActor in tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    return timer
  }
}
