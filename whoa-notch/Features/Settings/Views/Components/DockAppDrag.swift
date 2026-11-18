import AppKit

extension NSPasteboard.PasteboardType {
  /// Une appli glissée entre le sélecteur et la maquette du dock : `bundleID<tab>chemin`.
  static let dockApp = NSPasteboard.PasteboardType("com.whoastudio.whoa-notch.dock-app")
}

enum DockAppDrag {

  static func item(for app: DockPinnedApp, image: NSImage, size: CGFloat) -> NSDraggingItem {
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString("\(app.bundleID)\t\(app.path)", forType: .dockApp)
    let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
    item.setDraggingFrame(NSRect(x: 0, y: 0, width: size, height: size), contents: image)
    return item
  }

  static func app(from pasteboard: NSPasteboard) -> DockPinnedApp? {
    guard let text = pasteboard.string(forType: .dockApp) else { return nil }
    let parts = text.split(separator: "\t", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return nil }
    return DockPinnedApp(bundleID: parts[0], path: parts[1])
  }

  /// Une appli glissée, d'où qu'elle vienne : le sélecteur, la maquette, ou un fichier `.app` du
  /// Finder (qui doit avoir un identifiant de bundle).
  static func app(fromAny pasteboard: NSPasteboard) -> DockPinnedApp? {
    if let app = app(from: pasteboard) { return app }
    guard
      let url = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first(where: {
        $0.pathExtension == "app"
      }),
      let bundleID = Bundle(url: url)?.bundleIdentifier
    else { return nil }
    return DockPinnedApp(bundleID: bundleID, path: url.path)
  }
}
