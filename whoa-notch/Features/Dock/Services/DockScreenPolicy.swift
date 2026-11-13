import AppKit

/// Quels écrans accueillent le dock, selon le réglage « Screens » et les écrans décochés « Attached ».
enum DockScreenPolicy {

  /// `one` : le premier écran attaché de la liste ; `attached` et `all` : tous les écrans attachés
  /// (en mode `all`, `DockHost` donne ensuite un dock fixe à chacun).
  static func allowed(_ screens: [NSScreen], mode: DockScreenMode, detached: [String]) -> [NSScreen]
  {
    let attached = screens.filter { screen in
      screen.displayUUID.map { !detached.contains($0) } ?? true
    }
    switch mode {
    case .one: return Array(attached.prefix(1))
    case .attached, .all: return attached
    }
  }
}

extension NSScreen {
  /// Identifiant stable d'un écran, qui survit à un débranchement (contrairement à `displayID`).
  var displayUUID: String? {
    guard let id = displayID,
      let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
    else { return nil }
    return CFUUIDCreateString(nil, uuid) as String?
  }
}
