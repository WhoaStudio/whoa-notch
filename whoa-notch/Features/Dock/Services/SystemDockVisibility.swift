import AppKit
import ApplicationServices

/// Dit si le Dock macOS est à l'écran en ce moment, sur l'écran demandé. Son cadre Accessibilité (la liste d'icônes
/// enfant du processus Dock) sort de l'écran quand il est masqué ; sa fenêtre, elle, couvre
/// toujours tout l'écran et ne dit rien.
@MainActor
enum SystemDockVisibility {

  /// `nil` quand on ne peut pas le savoir (Accessibilité refusée, Dock introuvable).
  static func isVisible(on target: NSScreen) -> Bool? {
    guard AXIsProcessTrusted(),
      let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
        .first,
      let screen = NSScreen.screens.first
    else { return nil }
    let element = AXUIElementCreateApplication(dock.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.2)
    var children: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        == .success,
      let list = children as? [AXUIElement], let first = list.first
    else { return nil }
    var position: CFTypeRef?
    var size: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(first, kAXPositionAttribute as CFString, &position) == .success,
      AXUIElementCopyAttributeValue(first, kAXSizeAttribute as CFString, &size) == .success,
      let position, let size, CFGetTypeID(position) == AXValueGetTypeID(),
      CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
      AXValueGetValue(size as! AXValue, .cgSize, &extent)
    else { return nil }
    // Repère Accessibilité : origine en haut à gauche de l'écran principal, y vers le bas. Le Dock
    // masqué a son haut au bas de son écran ; affiché, son bas est à quelques points du bas. Masqué
    // sur un écran, il peut déborder sur le haut d'un écran placé dessous — d'où le test du bas.
    let dockFrame = CGRect(origin: origin, size: extent)
    let rect = CGRect(
      x: target.frame.minX, y: screen.frame.height - target.frame.maxY, width: target.frame.width,
      height: target.frame.height)
    let inside = dockFrame.intersection(rect)
    return !inside.isNull && inside.width * inside.height > dockFrame.width * dockFrame.height * 0.9
      && abs(dockFrame.maxY - rect.maxY) <= 25
  }
}
