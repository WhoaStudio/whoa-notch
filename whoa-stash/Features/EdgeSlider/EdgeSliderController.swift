import AppKit

/// Fenêtre flottante, transparente, collée au bord droit de l'écran.
/// Se révèle au survol de la souris (comme le "Edge Slider" de Stash).
@MainActor
final class EdgeSliderController: NSObject {

    private var window: NSPanel!
    private var sliderView: EdgeSliderView!
    private let viewModel: EdgeSliderViewModel
    private let storage: SettingsStorage

    init(storage: SettingsStorage = .shared) {
        self.storage = storage
        viewModel = EdgeSliderViewModel(settings: storage)
        super.init()
    }

    func activate() {
        guard let screen = NSScreen.main else { return }

        let prefs = storage.settings.edgeSlider
        let width: CGFloat = 6      // largeur de la zone sensible au repos
        let height: CGFloat = prefs.sliderHeight
        let x = prefs.edgePosition == .right ? screen.frame.maxX - width : screen.frame.minX
        let y = screen.frame.midY - height / 2

        let frame = NSRect(x: x, y: y, width: width, height: height)

        window = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar          // reste au-dessus des autres fenêtres
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        sliderView = EdgeSliderView(frame: NSRect(origin: .zero, size: frame.size))
        sliderView.viewModel = viewModel
        window.contentView = sliderView

        window.orderFrontRegardless()
        setEnabled(prefs.enabled)
    }

    /// Montre ou retire la zone sensible du bord de l'écran.
    func setEnabled(_ enabled: Bool) {
        guard let window else { return }
        if enabled {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }
}
