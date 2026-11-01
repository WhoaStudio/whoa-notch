import AppKit

/// Capsule de navigation du panneau de l'encoche : une barre à part, posée sous le panneau et
/// détachée de lui, qui porte les onglets. Rien que des glyphes — un onglet ne porte pas son intitulé ici, c'est le cercle qui dit lequel est actif.
///
/// Ce cercle est un seul calque, partagé par tous les onglets, qui **se déplace** d'une bulle à
/// l'autre sur un ressort plutôt que d'apparaître et disparaître. C'est ce glissement qui relie
/// visuellement les deux onglets, et il impose que le cercle soit un calque de la capsule et non
/// de la bulle.
///
/// Comme le reste du panneau déplié, cette vue reçoit de vrais événements de souris : la fenêtre
/// ne les laisse plus passer une fois dépliée (voir `NotchPanelWindow`), parce qu'un onglet se
/// clique. Elle vit hors du conteneur de contenu du panneau, qui est découpé par la silhouette :
/// la capsule est justement ce qui se trouve en dehors.
final class NotchTabCapsuleView: NSView {

    /// Appelé au clic sur un onglet, y compris celui déjà actif — le contrôleur du contenu décide
    /// quoi en faire.
    var onSelect: ((NotchTab) -> Void)?

    private let circleLayer = CALayer()
    private let items: [NotchTabBubbleView]

    private var selectedTab: NotchTab

    /// Largeur de la capsule : les bulles des onglets, leurs écarts, et les deux marges. Une constante — rien de ce qu'elle porte ne change de taille —, dont
    /// le panneau se sert pour centrer la capsule sous lui.
    static var width: CGFloat {
        let count = CGFloat(NotchTab.barTabs.count)
        return 2 * TabBarMetrics.capsuleHorizontalPadding
            + count * TabBarMetrics.bubbleSize
            + max(0, count - 1) * TabBarMetrics.bubbleSpacing
    }

    init(selectedTab: NotchTab) {
        self.selectedTab = selectedTab
        items = NotchTab.barTabs.map(NotchTabBubbleView.init(tab:))
        super.init(frame: .zero)
        wantsLayer = true
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        layer?.cornerCurve = .continuous
        layer?.borderWidth = PanelGeometry.strokeWidth

        // Ajouté avant les bulles : le cercle doit rester *derrière* les glyphes, et l'ordre des
        // sous-calques suit l'ordre d'ajout.
        circleLayer.cornerCurve = .continuous
        layer?.addSublayer(circleLayer)

        for item in items {
            item.onClick = { [weak self] tab in self?.onSelect?(tab) }
            addSubview(item)
        }

        applyPalette()
        applySelection(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }

    private func applyPalette() {
        let palette = OverlayPalette.resolved(for: effectiveAppearance)
        layer?.backgroundColor = palette.tabCapsuleFill
        layer?.borderColor = palette.strokeColor
        circleLayer.backgroundColor = palette.tabCircleFill
        items.forEach { $0.applyPalette(palette) }
    }

    func select(_ tab: NotchTab, animated: Bool) {
        guard tab != selectedTab else { return }
        selectedTab = tab
        applySelection(animated: animated)
    }

    /// Place le cercle sous l'onglet actif et met les glyphes au bon niveau de présence. Le
    /// cercle n'est animé que lorsqu'il a déjà une position à quitter — au premier passage, comme
    /// après une remise en page, il est posé d'emblée.
    private func applySelection(animated: Bool) {
        for item in items {
            item.setActive(item.tab == selectedTab)
        }

        // Un onglet hors de la capsule (Stay Awake) n'a pas de bulle : le cercle s'efface, et
        // revient sans glisser depuis une place qui n'est plus celle de personne.
        guard let active = items.first(where: { $0.tab == selectedTab }) else {
            circleLayer.opacity = 0
            return
        }
        let target = active.frame
        let wasHidden = circleLayer.opacity == 0
        circleLayer.opacity = 1

        guard animated, !wasHidden, !circleLayer.frame.isEmpty else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            circleLayer.frame = target
            circleLayer.cornerRadius = target.height / 2
            CATransaction.commit()
            return
        }

        // Toutes les bulles ont la même taille : seule la position change d'un onglet à l'autre,
        // et c'est la seule propriété à porter au ressort.
        circleLayer.springAnimate(
            keyPath: "position",
            to: CGPoint(x: target.midX, y: target.midY),
            preset: .gentle
        )
    }

    /// Pose la rangée de bulles de gauche à droite. Rien ne se
    /// resserre : la capsule reçoit exactement la largeur que `width` annonce.
    override func layout() {
        super.layout()

        layer?.cornerRadius = bounds.height / 2

        let size = TabBarMetrics.bubbleSize
        let y = bounds.midY - size / 2
        var x = bounds.minX + TabBarMetrics.capsuleHorizontalPadding

        for item in items {
            item.frame = NSRect(x: x, y: y, width: size, height: size)
            x += size + TabBarMetrics.bubbleSpacing
        }

        // Les cadres des bulles viennent de changer : le cercle doit les suivre sans rejouer le
        // glissement, qui n'a de sens qu'au changement d'onglet.
        applySelection(animated: false)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width, height: TabBarMetrics.capsuleHeight)
    }
}

// MARK: - Une bulle

/// La bulle d'un onglet : son glyphe, seul et centré. Ne dessine pas le cercle — il appartient à
/// la capsule, qui le fait glisser d'une bulle à l'autre.
private final class NotchTabBubbleView: NSView {

    let tab: NotchTab
    var onClick: ((NotchTab) -> Void)?

    private let iconView = NSImageView()
    private var palette = OverlayPalette.resolved(for: .currentDrawing())
    private var isActive = false

    init(tab: NotchTab) {
        self.tab = tab
        super.init(frame: .zero)
        wantsLayer = true
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: TabBarMetrics.iconSize,
            weight: .semibold
        )
        iconView.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title)?
            .withSymbolConfiguration(configuration)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        applyContentStyle()
    }

    func applyPalette(_ palette: OverlayPalette) {
        self.palette = palette
        applyContentStyle()
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        applyContentStyle()
    }

    /// Le glyphe de l'onglet actif est posé **sur** le cercle d'accent, et prend donc la teinte
    /// qui contraste avec lui ; les autres restent en retrait, à même la capsule.
    private func applyContentStyle() {
        iconView.contentTintColor = isActive ? palette.tabPillContent : palette.tabInactiveContent
    }

    override func layout() {
        super.layout()
        let icon = TabBarMetrics.iconSize
        iconView.frame = NSRect(
            x: bounds.midX - icon / 2,
            y: bounds.midY - icon / 2,
            width: icon,
            height: icon
        )
    }

    /// Le glyphe est une sous-vue, et c'est lui que la pile de vues désignerait au clic. La bulle
    /// répond donc elle-même pour tout son cadre, sans quoi `mouseUp` irait à l'image, qui
    /// l'ignore.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        // Rien au `mouseDown` : l'onglet ne bascule qu'au relâché, et seulement si le curseur est
        // encore dessus — un clic amorcé puis emmené ailleurs ne doit pas changer d'onglet.
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }
        ButtonSound.shared.playClick()
        onClick?(tab)
    }
}
