import AppKit

/// Enveloppe d'un widget dans la rangée du dock : lui donne la place d'une icône (le bas reste libre
/// pour le point des applis) et en fait une source de glisser, pour le déplacer ou le sortir.
final class DockWidgetHostView: NSView, NSDraggingSource {

    let placement: DockWidgetPlacement
    private let widget: DockWidget
    /// Appelé à la fin d'un glisser : le point à l'écran et si un dépôt l'a accepté.
    var onDragEnded: ((NSPoint, NSDragOperation) -> Void)?
    /// Clic droit sur le widget.
    var onContextMenu: ((NSEvent) -> Void)?
    private var didDrag = false

    init(placement: DockWidgetPlacement, widget: DockWidget) {
        self.placement = placement
        self.widget = widget
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(widget.view)
        widget.start()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func tearDown() {
        widget.stop()
        removeFromSuperview()
    }

    override func layout() {
        super.layout()
        let size = bounds.width
        widget.view.frame = NSRect(x: 0, y: DockIconView.dotGap, width: size, height: size)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { didDrag = false }

    override func rightMouseDown(with event: NSEvent) { onContextMenu?(event) }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag else { return }
        didDrag = true
        let tile = widget.view
        guard let representation = tile.bitmapImageRepForCachingDisplay(in: tile.bounds) else { return }
        tile.cacheDisplay(in: tile.bounds, to: representation)
        let image = NSImage(size: tile.bounds.size)
        image.addRepresentation(representation)
        let item = DockWidgetDrag.item(
            for: DockWidgetDragPayload(kind: placement.kind, placementID: placement.id), image: image, size: tile.frame.width)
        item.draggingFrame = tile.frame
        alphaValue = 0.3
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        alphaValue = 1
        onDragEnded?(screenPoint, operation)
    }
}
