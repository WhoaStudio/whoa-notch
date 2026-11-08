import AppKit
import Combine

/// Branche l'accéléromètre sur le classifieur, puis sur l'exécuteur d'actions, selon les
/// réglages. Ne possède aucune fenêtre ; `apply(settings:)` est rappelé à chaque changement.
final class KnockController {

  /// Une frappe ou un clic dans cette fenêtre avant le pic en fait un bruit de saisie, pas un coup.
  private nonisolated static let inputGuard: TimeInterval = 0.15
  private nonisolated static let inputEvents: [CGEventType] = [
    .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown,
  ]

  private let sensor: KnockSensorProviding
  private let performer: KnockActionPerformer
  private var classifier = KnockClassifier()
  private var settings = KnockSettings()
  private var running = false
  private var flushTask: Task<Void, Never>?
  private var wakeCancellable: AnyCancellable?

  init(sensor: KnockSensorProviding, performer: KnockActionPerformer = KnockActionPerformer()) {
    self.sensor = sensor
    self.performer = performer
    // Le capteur perd son flux au réveil : on repart de zéro.
    wakeCancellable = NSWorkspace.shared.notificationCenter
      .publisher(for: NSWorkspace.didWakeNotification)
      .sink { [weak self] _ in
        guard let self, self.running else { return }
        self.stopSensor()
        self.classifier.reset()
        self.startSensor()
      }
  }

  var onNowPlayingCommand: ((NowPlayingCommand) -> Void)? {
    get { performer.onNowPlayingCommand }
    set { performer.onNowPlayingCommand = newValue }
  }

  func apply(settings: KnockSettings) {
    self.settings = settings
    classifier.threshold = KnockClassifier.threshold(forSensitivity: settings.sensitivity)
    classifier.hasDoubleAction = settings.hasDoubleAction
    if settings.requiresAccessibility, !AccessibilityPermissionService.shared.isTrusted {
      AccessibilityPermissionService.shared.requestAccess()
    }
    if settings.enabled, !running {
      startSensor()
      running = true
    } else if !settings.enabled, running {
      stopSensor()
      running = false
    }
  }

  private func startSensor() {
    sensor.start { [weak self] samples in self?.receive(samples) }
  }

  private func stopSensor() {
    sensor.stop()
    flushTask?.cancel()
  }

  private func receive(_ samples: [AccelSample]) {
    for sample in samples {
      handle(classifier.ingest(sample, recentInput: Self.hadRecentInput))
    }
    scheduleFlush()
  }

  private nonisolated static func hadRecentInput() -> Bool {
    inputEvents.contains {
      CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) < inputGuard
    }
  }

  /// Libère le coup simple en attente quand le délai de double coup est écoulé, même si le
  /// capteur ne livre plus rien d'ici là.
  private func scheduleFlush() {
    flushTask?.cancel()
    guard let deadline = classifier.pendingDeadline else { return }
    let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime) + 0.01
    flushTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled, let self else { return }
      self.handle(self.classifier.advance(to: ProcessInfo.processInfo.systemUptime))
    }
  }

  private func handle(_ knocks: [Knock]) {
    for knock in knocks {
      performer.perform(settings.action(taps: knock.count))
    }
  }
}
