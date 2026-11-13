import AppKit

/// Dit quels écrans portent une app en plein écran. Lit seulement la géométrie, le niveau et le
/// propriétaire des fenêtres à l'écran : aucune permission d'enregistrement d'écran n'est requise.
nonisolated enum FullScreenDetector {

  private static let tolerance: CGFloat = 1

  /// Un écran est en plein écran quand une fenêtre d'une autre app le recouvre (hors encoche) et
  /// que la barre de menus y est masquée — ou que la fenêtre épouse l'écran au point près.
  /// `topInsets` : hauteur de la zone de l'encoche par écran, que le plein écran peut laisser libre.
  static func fullScreenDisplays(topInsets: [CGDirectDisplayID: CGFloat]) -> Set<CGDirectDisplayID>
  {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else {
      return []
    }
    let ownPID = ProcessInfo.processInfo.processIdentifier

    var menuBars: [CGRect] = []
    var appWindows: [CGRect] = []
    for info in infos {
      guard
        let layer = info[kCGWindowLayer as String] as? Int,
        let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsDict)
      else { continue }

      if layer == 24, info[kCGWindowName as String] as? String == "Menubar" {
        menuBars.append(bounds)
      } else if layer == 0, (info[kCGWindowOwnerPID as String] as? Int32) != ownPID {
        appWindows.append(bounds)
      }
    }

    var result: Set<CGDirectDisplayID> = []
    for (displayID, topInset) in topInsets {
      let display = CGDisplayBounds(displayID)
      let menuBarVisible = menuBars.contains {
        abs($0.minX - display.minX) <= tolerance && abs($0.minY - display.minY) <= tolerance
      }
      let covered = appWindows.contains { window in
        let exact =
          abs(window.minX - display.minX) <= tolerance
          && abs(window.minY - display.minY) <= tolerance
          && abs(window.width - display.width) <= tolerance
          && abs(window.height - display.height) <= tolerance
        if exact { return true }
        // Sous l'encoche : même largeur, collée au bas de l'écran, et pas de barre de menus.
        return !menuBarVisible
          && abs(window.minX - display.minX) <= tolerance
          && abs(window.width - display.width) <= tolerance
          && abs(window.maxY - display.maxY) <= tolerance
          && window.height >= display.height - topInset - tolerance
      }
      if covered { result.insert(displayID) }
    }
    return result
  }
}
