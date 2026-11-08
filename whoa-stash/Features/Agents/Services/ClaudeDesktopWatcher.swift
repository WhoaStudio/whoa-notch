import AppKit
import ApplicationServices
import Combine
import OSLog

/// Claude Desktop n'a pas de hooks. Quand on le quitte pendant qu'il écrit, on regarde une fois par
/// seconde, par Accessibilité, si son bouton Stop est encore là ; quand il disparaît, la réponse est prête.
///
/// Rien du chat n'est lu : seuls le rôle et le libellé des boutons sont examinés. Claude Desktop est
/// une app Electron, dont l'arbre d'accessibilité reste vide tant qu'on n'a pas posé
/// `AXManualAccessibility` sur l'app.
final class ClaudeDesktopWatcher {

  nonisolated static let bundleID = "com.anthropic.claudefordesktop"

  var onEvent: ((AgentEvent) -> Void)?

  private var settingsCancellable: AnyCancellable?
  private var observers: [NSObjectProtocol] = []
  private var pollTask: Task<Void, Never>?

  func apply(enabled: Bool) {
    enabled ? start() : stop()
  }

  func bind(to storage: SettingsStorage) {
    settingsCancellable = storage.$settings
      .map(\.ai.desktopWatcherEnabled)
      .removeDuplicates()
      .sink { [weak self] in self?.apply(enabled: $0) }
  }

  private func start() {
    guard observers.isEmpty else { return }
    let center = NSWorkspace.shared.notificationCenter
    observers = [
      center.addObserver(
        forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
      ) {
        [weak self] note in
        let pid = Self.claudePID(in: note)
        MainActor.assumeIsolated { self?.appChanged(pid, deactivated: false) }
      },
      center.addObserver(
        forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main
      ) {
        [weak self] note in
        let pid = Self.claudePID(in: note)
        MainActor.assumeIsolated { self?.appChanged(pid, deactivated: true) }
      },
      center.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
      ) {
        [weak self] note in
        let pid = Self.claudePID(in: note)
        MainActor.assumeIsolated { self?.appActivated(pid) }
      },
    ]
    if let app = Self.claudeApp() { Self.prepare(pid: app.processIdentifier) }
    Log.agents.info("Veille de Claude Desktop activée")
  }

  private func stop() {
    observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    observers = []
    pollTask?.cancel()
    pollTask = nil
  }

  private static func claudeApp() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
  }

  /// Le pid de Claude Desktop si la notification le concerne.
  private nonisolated static func claudePID(in note: Notification) -> pid_t? {
    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    return app?.bundleIdentifier == bundleID ? app?.processIdentifier : nil
  }

  private func appChanged(_ pid: pid_t?, deactivated: Bool) {
    guard let pid else { return }
    Self.prepare(pid: pid)
    if deactivated { beginPolling(pid: pid) }
  }

  /// Revenir sur Claude : on voit la réponse soi-même, pas de notification.
  private func appActivated(_ pid: pid_t?) {
    guard pid != nil else { return }
    pollTask?.cancel()
    pollTask = nil
  }

  /// Une fois par seconde, tant que Claude n'est pas au premier plan : d'abord attendre de voir le
  /// bouton Stop (réponse en cours), puis attendre qu'il disparaisse.
  private func beginPolling(pid: pid_t) {
    pollTask?.cancel()
    guard AXIsProcessTrusted() else { return }
    pollTask = Task { [weak self] in
      guard await Self.isGenerating(pid: pid) else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        if Task.isCancelled { return }
        if await Self.isGenerating(pid: pid) { continue }
        self?.onEvent?(AgentEvent(kind: .desktopReply, project: "Claude"))
        self?.pollTask = nil
        return
      }
    }
  }

  // MARK: - Accessibilité

  /// Demande à Electron d'exposer son arbre d'accessibilité.
  private static func prepare(pid: pid_t) {
    guard AXIsProcessTrusted() else { return }
    AXUIElementSetAttributeValue(
      AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
  }

  /// Vrai si un bouton « Stop… » existe dans les fenêtres de l'app. Parcours borné, hors main actor.
  @concurrent
  private static func isGenerating(pid: pid_t) async -> Bool {
    let app = AXUIElementCreateApplication(pid)
    var windows: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
      let roots = windows as? [AXUIElement]
    else { return false }

    var queue = roots
    var visited = 0
    while !queue.isEmpty, visited < 3000 {
      let element = queue.removeFirst()
      visited += 1
      if isStopButton(element) { return true }
      var children: CFTypeRef?
      if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        == .success,
        let list = children as? [AXUIElement]
      {
        queue.append(contentsOf: list)
      }
    }
    return false
  }

  private nonisolated static func isStopButton(_ element: AXUIElement) -> Bool {
    func string(_ attribute: String) -> String? {
      var value: CFTypeRef?
      guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
      }
      return value as? String
    }
    guard string(kAXRoleAttribute) == kAXButtonRole else { return false }
    let label = (string(kAXDescriptionAttribute) ?? string(kAXTitleAttribute) ?? "").lowercased()
    return label.hasPrefix("stop")
  }
}
