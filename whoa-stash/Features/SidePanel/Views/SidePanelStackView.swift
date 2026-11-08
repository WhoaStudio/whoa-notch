import AppKit

/// Contenu du panneau latéral : les bagues d'utilisation, empilées verticalement.
///
/// La bande n'a ni onglets ni semaine — ils appartiennent au panneau de l'encoche, qui a la
/// largeur et la permanence pour les porter. Ce qu'elle montre tient sur une seule vue, et
/// celle-ci existe pour que `SidePanelContentView` n'ait pas à mêler la silhouette et son contenu.
///
/// La liste vit dans un défilement : la pile peut réclamer plus de hauteur que le panneau n'en a,
/// une fois celui-ci arrêté par la zone visible de l'écran (`SidePanelGeometry.panelFrame`).
/// L'ascenseur est en surimpression et s'efface de lui-même, pour ne rien ajouter à la surface
/// quand tout tient.
final class SidePanelStackView: NSView {

  private let scrollView = NSScrollView()
  private let ringStrip = ClaudeUsageRingStripView()

  /// Dernière hauteur donnée à la vue de document : le retour en haut de liste ne vaut que
  /// pour une pile qui change de taille, pas pour chaque mise en page — sans quoi la moindre
  /// repose du cadre annulerait le défilement en cours.
  private var lastDocumentHeight: CGFloat?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true

    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    // Keep wheel/trackpad scrolling without showing a scrollbar in the narrow side panel.
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.verticalScrollElasticity = .allowed
    scrollView.contentView.drawsBackground = false
    scrollView.documentView = ringStrip
    addSubview(scrollView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(claudeState: ClaudeUsageState, copilotState: CopilotUsageState, animated: Bool) {
    ringStrip.apply(claudeState: claudeState, copilotState: copilotState, animated: animated)
  }

  func setHighlightedRing(_ index: Int?) {
    ringStrip.setHighlightedRing(index)
  }

  /// Cadre d'une bague dans le repère de cette vue.
  func ringFrame(at index: Int) -> NSRect? {
    guard let frame = ringStrip.ringFrame(at: index) else { return nil }
    return ringStrip.convert(frame, to: self)
  }

  var ringCount: Int { ringStrip.ringCount }

  override func layout() {
    super.layout()
    scrollView.frame = bounds

    // La vue de document prend toute la largeur offerte et au moins la hauteur visible : en
    // deçà, rien ne défile et la pile se centre d'elle-même dans ce qu'elle a.
    let visible = scrollView.contentView.bounds.size
    let height = max(ringStrip.contentHeight, visible.height)
    ringStrip.frame = NSRect(x: 0, y: 0, width: visible.width, height: height)

    // Le haut de la liste d'abord : la vue de document n'est pas retournée, donc son origine
    // naturelle est en bas.
    guard lastDocumentHeight != height else { return }
    lastDocumentHeight = height
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: height - visible.height))
    scrollView.reflectScrolledClipView(scrollView.contentView)
  }
}
