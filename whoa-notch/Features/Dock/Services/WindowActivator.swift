import AppKit
import ApplicationServices
import os

/// Une fenêtre d'une appli, vue par Accessibilité.
struct DockWindow {
  var title: String
  var isMinimized: Bool
  fileprivate var element: AXUIElement
}

/// Lance une appli ou ramène sa fenêtre devant, en la désminimisant par Accessibilité
/// (même approche que DockDoor : `kAXWindowsAttribute`, `kAXMinimizedAttribute`, `AXRaise`).
@MainActor
final class WindowActivator {

  private let accessibility: AccessibilityPermissionService

  init(accessibility: AccessibilityPermissionService = .shared) {
    self.accessibility = accessibility
  }

  private func runningApp(_ item: DockItem) -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleID).first(where: {
      !$0.isTerminated
    })
  }

  func activate(_ item: DockItem) {
    guard let app = runningApp(item) else {
      launch(item)
      return
    }
    if app.isHidden { app.unhide() }

    guard accessibility.isTrusted else {
      // Sans Accessibilité on ne peut pas désminimiser : on demande l'accès et on active
      // l'appli, ce qui suffit quand la fenêtre n'est pas minimisée.
      accessibility.requestAccess()
      app.activate()
      return
    }

    let windows = Self.windows(of: app.processIdentifier)
    if windows.isEmpty {
      // Aucune fenêtre (fermée) : relancer déclenche la réouverture de l'appli.
      launch(item)
      return
    }
    raise(windows.first(where: \.isMinimized) ?? windows[0], of: app)
  }

  /// Fenêtres de l'appli, pour le menu contextuel ; vide sans Accessibilité.
  func windows(for item: DockItem) -> [DockWindow] {
    guard accessibility.isTrusted, let app = runningApp(item) else { return [] }
    return Self.windows(of: app.processIdentifier)
  }

  func raise(_ window: DockWindow, of item: DockItem) {
    guard let app = runningApp(item) else { return }
    raise(window, of: app)
  }

  private func raise(_ window: DockWindow, of app: NSRunningApplication) {
    if window.isMinimized {
      AXUIElementSetAttributeValue(
        window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }
    AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    app.activate()
  }

  func hide(_ item: DockItem) { runningApp(item)?.hide() }

  func quit(_ item: DockItem) { runningApp(item)?.terminate() }

  func launch(_ item: DockItem) {
    let url = URL(fileURLWithPath: item.path)
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) {
      _, error in
      if let error {
        Log.dock.error("Lancement impossible : \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private static func windows(of pid: pid_t) -> [DockWindow] {
    let element = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(element, 1)
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
      let windows = value as? [AXUIElement]
    else { return [] }
    return windows.map { window in
      DockWindow(
        title: string(window, kAXTitleAttribute), isMinimized: isMinimized(window), element: window)
    }
  }

  private static func string(_ element: AXUIElement, _ attribute: String) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
      return ""
    }
    return value as? String ?? ""
  }

  private static func isMinimized(_ window: AXUIElement) -> Bool {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success
    else { return false }
    return (value as? Bool) ?? false
  }
}
