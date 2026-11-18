import AppKit

/// Un bouton de la galerie : un clic ajoute le widget au bout du dock, un glisser le dépose dans la
/// maquette à l'endroit voulu.
@MainActor
private final class WidgetGalleryButton: NSButton, NSDraggingSource {

  private let kind: DockWidgetKind
  private static let dragSide: CGFloat = 44
  private static let dragThreshold: CGFloat = 4

  init(kind: DockWidgetKind, target: AnyObject, action: Selector) {
    self.kind = kind
    super.init(frame: .zero)
    title = "Add \(kind.title)"
    image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
    imagePosition = .imageLeading
    bezelStyle = .rounded
    self.target = target
    self.action = action
    identifier = NSUserInterfaceItemIdentifier(kind.id)
    toolTip = "Click to add, or drag into the dock above"
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  /// Sans cela, `NSButton` garde la main jusqu'au relâchement et un glisser ne part jamais : on
  /// suit la souris nous-mêmes, clic si elle ne bouge presque pas, glisser sinon.
  override func mouseDown(with event: NSEvent) {
    guard isEnabled, let window else { return }
    let start = event.locationInWindow
    isHighlighted = true
    defer { isHighlighted = false }
    while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      if next.type == .leftMouseUp {
        if bounds.contains(convert(next.locationInWindow, from: nil)) {
          sendAction(action, to: target)
        }
        return
      }
      let moved = hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y)
      if moved > Self.dragThreshold {
        isHighlighted = false
        beginDrag(with: next)
        return
      }
    }
  }

  private func beginDrag(with event: NSEvent) {
    let item = DockWidgetDrag.item(
      for: DockWidgetDragPayload(kind: kind.id, placementID: nil), image: tileImage(),
      size: Self.dragSide)
    let origin = convert(event.locationInWindow, from: nil)
    item.draggingFrame = NSRect(
      x: origin.x - Self.dragSide / 2, y: origin.y - Self.dragSide / 2, width: Self.dragSide,
      height: Self.dragSide)
    beginDraggingSession(with: [item], event: event, source: self)
  }

  /// La tuile du widget, telle qu'elle se dessine avant d'avoir des données.
  private func tileImage() -> NSImage {
    let tile = kind.make().view
    tile.frame = NSRect(x: 0, y: 0, width: Self.dragSide, height: Self.dragSide)
    tile.layoutSubtreeIfNeeded()
    guard let representation = tile.bitmapImageRepForCachingDisplay(in: tile.bounds)
    else { return NSImage() }
    tile.cacheDisplay(in: tile.bounds, to: representation)
    let image = NSImage(size: tile.bounds.size)
    image.addRepresentation(representation)
    return image
  }

  nonisolated func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .withinApplication ? .copy : []
  }
}

/// La galerie des widgets d'un profil : un bouton par type du registre. Les widgets déjà posés se
/// voient et se retirent dans la maquette du dock, au-dessus. Agit sur le profil choisi, actif ou non.
@MainActor
final class ProfileWidgetsView: NSStackView {

  var onAdd: ((String) -> Void)?
  private var addButtons: [NSButton] = []

  init() {
    super.init(frame: .zero)
    orientation = .horizontal
    spacing = 8
    for kind in DockWidgetRegistry.all {
      let button = WidgetGalleryButton(
        kind: kind, target: self, action: #selector(addTapped(_:)))
      addArrangedSubview(button)
      addButtons.append(button)
    }
  }

  @available(*, unavailable) required init(coder: NSCoder) { fatalError() }

  func setEnabled(_ enabled: Bool) { addButtons.forEach { $0.isEnabled = enabled } }

  @objc private func addTapped(_ sender: NSButton) {
    guard let id = sender.identifier?.rawValue else { return }
    onAdd?(id)
  }
}
