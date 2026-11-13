import AppKit

extension NSPasteboard.PasteboardType {
  /// Un widget glissé depuis la galerie ou depuis le dock : `type<tab>identifiant de placement`.
  static let dockWidget = NSPasteboard.PasteboardType("com.whoastudio.whoa-notch.dock-widget")
}

/// Ce que porte un glisser de widget. `placementID` est vide pour un widget qui vient de la
/// galerie, renseigné pour un widget déjà dans le dock.
struct DockWidgetDragPayload: Equatable {
  var kind: String
  var placementID: String?
}

enum DockWidgetDrag {

  static func item(for payload: DockWidgetDragPayload, image: NSImage, size: CGFloat)
    -> NSDraggingItem
  {
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString("\(payload.kind)\t\(payload.placementID ?? "")", forType: .dockWidget)
    let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
    item.setDraggingFrame(NSRect(x: 0, y: 0, width: size, height: size), contents: image)
    return item
  }

  static func payload(from pasteboard: NSPasteboard) -> DockWidgetDragPayload? {
    guard let text = pasteboard.string(forType: .dockWidget) else { return nil }
    let parts = text.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(
      String.init)
    guard let kind = parts.first, !kind.isEmpty else { return nil }
    let placementID = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
    return DockWidgetDragPayload(kind: kind, placementID: placementID)
  }
}
