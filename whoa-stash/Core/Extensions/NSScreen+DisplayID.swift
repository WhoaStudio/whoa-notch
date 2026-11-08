import AppKit

extension NSScreen {
  /// Identifiant matériel de l'écran, stable contrairement à sa position dans
  /// `NSScreen.screens` : cette position change dès qu'un écran est branché ou débranché,
  /// donc tout ce qui doit survivre à un changement de configuration s'indexe là-dessus.
  var displayID: CGDirectDisplayID? {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }

  /// Écran sous le curseur. C'est lui qui décide où un widget du bord doit apparaître :
  /// le curseur a atteint *ce* bord-là, pas celui de l'écran où le widget se trouvait.
  static var underCursor: NSScreen? {
    let location = NSEvent.mouseLocation
    return screens.first { $0.frame.contains(location) }
  }

  /// Écran qui porte la fenêtre. `NSWindow.screen` est `nil` tant que la fenêtre n'est pas
  /// affichée — un panel qu'on vient de refermer, typiquement — d'où le repli sur le curseur,
  /// qui est de toute façon l'écran où ce panel réapparaîtra.
  static func hosting(_ window: NSWindow?) -> NSScreen? {
    window?.screen ?? underCursor
  }
}
