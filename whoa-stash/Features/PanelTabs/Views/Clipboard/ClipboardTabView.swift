import AppKit

/// Onglet Clipboard : titre, filtres, bouton « Clear » et une rangée de cartes qui défile à
/// l'horizontale. La vue n'est qu'une lecture de l'historique : `apply(items:)` la repeint.
final class ClipboardTabView: NSView {

  /// Appelé au clic sur « Clear ».
  var onClear: (() -> Void)?
  /// Appelé au clic sur une carte.
  var onSelect: ((ClipboardItem) -> Void)?

  /// Où lire l'image d'une carte : le store connaît le dossier, pas la vue.
  var imageURLProvider: ((ClipboardItem) -> URL?)?

  private let titleLabel = NSTextField(labelWithString: "Bro's Clipboard")
  private let filterPill = NSView()
  private var filterButtons: [FilterButton] = []
  private let clearButton = NSButton()
  private let scrollView = NSScrollView()
  private let documentView = NSView()
  private let emptyLabel = NSTextField(labelWithString: "Nothing copied yet")

  private var items: [ClipboardItem] = []
  private var filter: ClipboardFilter = .all

  private let titleHeight: CGFloat = 18
  private let filterHeight: CGFloat = 26
  private let rowGap: CGFloat = 8
  private let cardSpacing: CGFloat = 8

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setUp() {
    titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
    titleLabel.textColor = NSColor(white: 0.62, alpha: 1)
    addSubview(titleLabel)

    filterPill.wantsLayer = true
    filterPill.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
    addSubview(filterPill)
    for kind in ClipboardFilter.allCases {
      let button = FilterButton(filter: kind)
      button.onClick = { [weak self] in self?.select(filter: kind) }
      filterPill.addSubview(button)
      filterButtons.append(button)
    }

    clearButton.isBordered = false
    clearButton.title = " Clear"
    clearButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear")?
      .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
    clearButton.imagePosition = .imageLeading
    clearButton.font = .systemFont(ofSize: 13, weight: .regular)
    clearButton.contentTintColor = NSColor(white: 0.62, alpha: 1)
    clearButton.target = self
    clearButton.action = #selector(clearClicked)
    addSubview(clearButton)

    scrollView.drawsBackground = false
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = false
    scrollView.horizontalScrollElasticity = .allowed
    scrollView.verticalScrollElasticity = .none
    scrollView.documentView = documentView
    addSubview(scrollView)

    emptyLabel.font = .systemFont(ofSize: 12)
    emptyLabel.textColor = NSColor(white: 0.45, alpha: 1)
    emptyLabel.alignment = .center
    addSubview(emptyLabel)

    refreshFilterButtons()
  }

  // MARK: - État

  func apply(items: [ClipboardItem]) {
    let previous = visibleItems
    self.items = items
    rebuildCards()
    if previous != visibleItems { revealResults() }
  }

  private func select(filter newFilter: ClipboardFilter) {
    guard newFilter != filter else { return }
    filter = newFilter
    refreshFilterButtons()
    rebuildCards()
    revealResults()
  }

  private func revealResults() {
    guard window != nil, !isHiddenOrHasHiddenAncestor else { return }
    let content = visibleItems.isEmpty ? emptyLabel as NSView : documentView
    content.wantsLayer = true
    content.layer?.springReveal(x: 8, y: 0)
  }

  private func refreshFilterButtons() {
    filterButtons.forEach { $0.isSelectedFilter = $0.filter == filter }
  }

  @objc private func clearClicked() { onClear?() }

  private var visibleItems: [ClipboardItem] { items.filter { filter.matches($0.kind) } }

  private func rebuildCards() {
    documentView.subviews.forEach { $0.removeFromSuperview() }
    for item in visibleItems {
      let card = ClipboardCardView(item: item, imageURL: imageURLProvider?(item))
      card.onClick = { [weak self] in self?.onSelect?(item) }
      documentView.addSubview(card)
    }
    emptyLabel.isHidden = !visibleItems.isEmpty
    needsLayout = true
  }

  /// Remet « il y a N min » à jour sur chaque carte.
  func refreshAges() {
    documentView.subviews.compactMap { $0 as? ClipboardCardView }.forEach { $0.refreshAge() }
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()
    let width = bounds.width

    titleLabel.frame = CGRect(x: 0, y: bounds.maxY - titleHeight, width: 200, height: titleHeight)

    let filterY = titleLabel.frame.minY - rowGap / 2 - filterHeight
    var x: CGFloat = 0
    for button in filterButtons {
      let buttonWidth = ceil(button.intrinsicWidth)
      button.frame = CGRect(x: x, y: 0, width: buttonWidth, height: filterHeight)
      x += buttonWidth
    }
    filterPill.frame = CGRect(x: 0, y: filterY, width: x, height: filterHeight)
    filterPill.layer?.cornerRadius = filterHeight / 2

    clearButton.sizeToFit()
    clearButton.frame.origin = CGPoint(
      x: width - clearButton.frame.width, y: filterY + (filterHeight - clearButton.frame.height) / 2
    )

    let rowHeight = ClipboardCardView.size.height
    let rowTop = filterY - rowGap
    scrollView.frame = CGRect(x: 0, y: max(0, rowTop - rowHeight), width: width, height: rowHeight)

    var cardX: CGFloat = 0
    for card in documentView.subviews {
      card.frame = CGRect(origin: CGPoint(x: cardX, y: 0), size: ClipboardCardView.size)
      cardX += ClipboardCardView.size.width + cardSpacing
    }
    documentView.frame = CGRect(
      x: 0, y: 0, width: max(width, cardX - cardSpacing), height: rowHeight)
    emptyLabel.sizeToFit()
    emptyLabel.frame = CGRect(
      x: 0, y: scrollView.frame.midY - emptyLabel.frame.height / 2, width: width,
      height: emptyLabel.frame.height)
  }
}

/// Un filtre de la capsule du haut : glyphe puis texte, fond clair quand il est choisi.
private final class FilterButton: NSView {

  let filter: ClipboardFilter
  var onClick: (() -> Void)?

  var isSelectedFilter = false {
    didSet { applyStyle() }
  }

  private static let iconSize: CGFloat = 12
  private static let iconGap: CGFloat = 5

  private let iconView = NSImageView()
  private let label: NSTextField

  var intrinsicWidth: CGFloat {
    Self.iconSize + Self.iconGap + label.intrinsicContentSize.width + 24
  }

  init(filter: ClipboardFilter) {
    self.filter = filter
    label = NSTextField(labelWithString: filter.title)
    super.init(frame: .zero)
    wantsLayer = true
    label.font = .systemFont(ofSize: 12.5, weight: .medium)
    label.alignment = .center
    let configuration = NSImage.SymbolConfiguration(pointSize: Self.iconSize, weight: .medium)
    iconView.image = NSImage(
      systemSymbolName: filter.symbolName, accessibilityDescription: filter.title)?
      .withSymbolConfiguration(configuration)
    iconView.imageScaling = .scaleProportionallyUpOrDown
    addSubview(iconView)
    addSubview(label)
    applyStyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func applyStyle() {
    layer?.backgroundColor = isSelectedFilter ? NSColor.white.cgColor : nil
    let ink: NSColor = isSelectedFilter ? .black : .white
    label.textColor = ink
    iconView.contentTintColor = ink
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = bounds.height / 2
    let size = label.intrinsicContentSize
    let iconX: CGFloat = 12
    iconView.frame = CGRect(
      x: iconX, y: (bounds.height - Self.iconSize) / 2, width: Self.iconSize, height: Self.iconSize)
    let labelX = iconX + Self.iconSize + Self.iconGap
    label.frame = CGRect(
      x: labelX, y: (bounds.height - size.height) / 2, width: bounds.width - labelX - 12,
      height: size.height)
  }

  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
  }
}
