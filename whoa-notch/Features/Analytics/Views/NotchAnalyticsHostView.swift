import AppKit

/// Le contenu de l'onglet Analytics : l'en-tête d'usage (fixe), la barre d'onglets, puis la page
/// choisie. Un clic sur un onglet ou un balayage à deux doigts (ou à la souris) change de page,
/// avec le même mouvement dans les deux cas.
///
/// Le balayage ne se déclenche pas sur la carte du fournisseur, qui garde le sien.
final class NotchAnalyticsHostView: NSView {

  /// Appelé quand la page affichée change : la fenêtre en tire le focus clavier.
  var onPageChanged: (() -> Void)?

  private let header: NotchUsageHeaderView
  private let tabBar: NotchAnalyticsTabBarView
  private let container = NSView()
  private let pages: [NotchAnalyticsPage]
  private let pager = NotchUsageSwipePager()
  private(set) var selectedIndex = 0

  static let barGap: CGFloat = 8
  static let sectionGap: CGFloat = 12
  /// Hauteur que la barre d'onglets ajoute au contenu : de quoi garder aux pages la place que
  /// l'ancien onglet avait sous son en-tête.
  static let barBlockHeight = barGap + NotchAnalyticsTabBarView.height

  var selectedPage: NotchAnalyticsPage { pages[selectedIndex] }

  init(header: NotchUsageHeaderView, pages: [NotchAnalyticsPage]) {
    precondition(!pages.isEmpty, "au moins une page")
    self.header = header
    self.pages = pages
    tabBar = NotchAnalyticsTabBarView(pages: pages)
    super.init(frame: .zero)
    container.wantsLayer = true
    [header, tabBar, container].forEach(addSubview)
    for (index, page) in pages.enumerated() {
      page.pageView.isHidden = index != 0
      container.addSubview(page.pageView)
    }
    header.title = pages[0].pageTitle
    tabBar.onSelect = { [weak self] index in self?.select(index, animated: true) }

    // Choisir un fournisseur dans l'en-tête ramène à la page Usage, qui le montre.
    let providerSelect = header.onSelect
    header.onSelect = { [weak self] provider in
      providerSelect?(provider)
      self?.select(0, animated: true)
    }

    pager.width = { [weak self] in self?.bounds.width ?? 1 }
    pager.allows = { [weak self] page in
      guard let self else { return false }
      return pages.indices.contains(selectedIndex - page)
    }
    pager.presentedOffset = { [weak self] in self?.container.layer?.presentedTranslationX ?? 0 }
    pager.onTrack = { [weak self] x in self?.container.layer?.trackSwipe(to: x) }
    pager.onCancel = { [weak self] from, velocity in
      self?.container.layer?.settleSwipe(from: from, velocity: velocity)
    }
    pager.onCommit = { [weak self] page, from, _ in
      guard let self else { return }
      let target = selectedIndex - page
      container.layer?.commitSwipe(page: page, from: from) { [weak self] in
        self?.show(target)
      }
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func select(_ index: Int, animated: Bool) {
    guard index != selectedIndex, pages.indices.contains(index) else { return }
    tabBar.select(index, animated: animated)
    // Une page plus loin dans la barre arrive de la droite : le geste vers la gauche (-1).
    let direction = index > selectedIndex ? -1 : 1
    guard animated else {
      show(index)
      return
    }
    container.layer?.commitSwipe(page: direction, from: 0) { [weak self] in self?.show(index) }
    // Le contenu change à la fin de la sortie ; la barre et le titre suivent tout de suite.
    header.title = pages[index].pageTitle
  }

  /// Affiche la page `index`, sans animation.
  private func show(_ index: Int) {
    guard pages.indices.contains(index) else { return }
    selectedIndex = index
    for (position, page) in pages.enumerated() { page.pageView.isHidden = position != index }
    tabBar.select(index, animated: true)
    header.title = pages[index].pageTitle
    needsLayout = true
    onPageChanged?()
  }

  // MARK: - Événements

  override func scrollWheel(with event: NSEvent) {
    if !pager.scrollWheel(event) { super.scrollWheel(with: event) }
  }

  override func mouseDown(with event: NSEvent) { pager.mouseDown(event) }
  override func mouseDragged(with event: NSEvent) { pager.mouseDragged(event) }
  override func mouseUp(with event: NSEvent) { pager.mouseUp(event) }

  override func layout() {
    super.layout()
    header.frame = NSRect(
      x: 0, y: bounds.maxY - NotchUsageHeaderView.height, width: bounds.width,
      height: NotchUsageHeaderView.height)
    tabBar.frame = NSRect(
      x: 0, y: header.frame.minY - Self.barGap - NotchAnalyticsTabBarView.height,
      width: bounds.width, height: NotchAnalyticsTabBarView.height)
    container.frame = NSRect(
      x: 0, y: 0, width: bounds.width,
      height: max(0, tabBar.frame.minY - Self.sectionGap))
    for page in pages { page.pageView.frame = container.bounds }
  }
}
