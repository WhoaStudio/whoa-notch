import AppKit

/// Onglet Clipboard : titre, filtres, bouton « Clear » et une rangée de cartes qui défile à
/// l'horizontale. `apply(items:)` aligne les cartes sur l'historique sans rien reconstruire :
/// celles qui y sont gardent leur vue (donc leur aperçu), celles qui n'y sont plus sortent en
/// animation, les nouvelles entrent en tête.
final class ClipboardTabView: NSView {

  /// Appelé au clic sur « Clear ».
  var onClear: (() -> Void)?
  /// Appelé au clic sur une carte.
  var onSelect: ((ClipboardItem) -> Void)?
  var onDelete: ((ClipboardItem) -> Void)?
  var onTogglePin: ((ClipboardItem) -> Void)?

  /// Où lire l'image d'une carte : le store connaît le dossier, pas la vue.
  var imageURLProvider: ((ClipboardItem) -> URL?)?

  private let titleLabel = NSTextField(labelWithString: "Bro's Clipboard")
  private let filterPill = NSView()
  private let highlight = CALayer()
  private var filterButtons: [FilterButton] = []
  private let clearButton = NSButton()
  private let scrollView = ClipboardRowScrollView()
  private let documentView = NSView()
  private let emptyState = ClipboardEmptyStateView()

  private var items: [ClipboardItem] = []
  private var filter: ClipboardFilter = .all
  /// Cartes à l'écran, dans l'ordre d'affichage. Les cartes qui sortent n'y sont plus.
  private var cards: [ClipboardCardView] = []
  private var animatesNextLayout = false
  private var isCompact = false

  private let titleHeight: CGFloat = 18
  private let filterHeight: CGFloat = 26
  private let rowGap: CGFloat = 8
  /// Air entre la capsule de filtres et les cartes (la hauteur de l'onglet en tient compte).
  private let filterToRowGap: CGFloat = 16
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
    titleLabel.lineBreakMode = .byTruncatingTail
    addSubview(titleLabel)

    filterPill.wantsLayer = true
    filterPill.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
    highlight.backgroundColor = NSColor.white.cgColor
    filterPill.layer?.addSublayer(highlight)
    for kind in ClipboardFilter.allCases {
      let button = FilterButton(filter: kind)
      button.onClick = { [weak self] in self?.select(filter: kind) }
      filterPill.addSubview(button)
      filterButtons.append(button)
    }
    addSubview(filterPill)

    clearButton.isBordered = false
    clearButton.title = " Clear"
    clearButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear")?
      .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
    clearButton.imagePosition = .imageLeading
    clearButton.font = .systemFont(ofSize: 13, weight: .regular)
    clearButton.contentTintColor = NSColor(white: 0.62, alpha: 1)
    clearButton.target = self
    clearButton.action = #selector(clearClicked)
    clearButton.toolTip = "Clear the history (pinned clips stay)"
    addSubview(clearButton)

    scrollView.drawsBackground = false
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = false
    scrollView.horizontalScrollElasticity = .allowed
    scrollView.verticalScrollElasticity = .none
    scrollView.documentView = documentView
    addSubview(scrollView)

    emptyState.onShowAll = { [weak self] in self?.select(filter: .all) }
    emptyState.isHidden = true
    addSubview(emptyState)

    refreshFilterButtons()
  }

  // MARK: - État

  func apply(items: [ClipboardItem]) {
    self.items = items
    sync()
  }

  private func select(filter newFilter: ClipboardFilter) {
    guard newFilter != filter else { return }
    filter = newFilter
    refreshFilterButtons()
    sync()
  }

  /// Épinglées d'abord, puis l'ordre de l'historique (le plus récent en tête).
  private var visibleItems: [ClipboardItem] {
    let matching = items.filter { filter.matches($0.kind) }
    return matching.filter(\.isPinned) + matching.filter { !$0.isPinned }
  }

  private var canAnimate: Bool {
    window != nil && !isHiddenOrHasHiddenAncestor && OverlayAnimation.allowsMotion
  }

  /// Aligne les cartes sur la liste : garde, retire, ajoute, replace.
  private func sync() {
    let target = visibleItems
    let animated = canAnimate
    let previousFirst = cards.first?.item.id
    let current = Dictionary(
      cards.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })
    let keptIDs = Set(target.map(\.id))
    let isClearing = !cards.isEmpty && target.allSatisfy { current[$0.id] != nil }
      && cards.count - target.count > 2

    var leaving = 0
    for card in cards where !keptIDs.contains(card.item.id) {
      let delay = isClearing && animated ? min(0.04 * Double(leaving), 0.24) : 0
      leaving += 1
      card.leave(delay: delay) { [weak card] in card?.removeFromSuperview() }
    }

    var arrivals: [ClipboardCardView] = []
    cards = target.map { item in
      if let existing = current[item.id] {
        if existing.item != item { existing.apply(item: item) }
        return existing
      }
      let card = ClipboardCardView(item: item, imageURL: imageURLProvider?(item))
      card.onClick = { [weak self, weak card] in
        guard let item = card?.item else { return }
        self?.onSelect?(item)
      }
      card.onDelete = { [weak self, weak card] in
        guard let item = card?.item else { return }
        self?.onDelete?(item)
      }
      card.onTogglePin = { [weak self, weak card] in
        guard let item = card?.item else { return }
        self?.onTogglePin?(item)
      }
      documentView.addSubview(card)
      arrivals.append(card)
      return card
    }

    for (index, card) in arrivals.enumerated() {
      card.appear(delay: animated ? min(0.04 * Double(index), 0.2) : 0)
    }

    animatesNextLayout = animated
    updateEmptyState(animated: animated)
    updateClearButton()
    needsLayout = true

    // Une carte vient d'arriver ou de remonter en tête : on ramène la rangée au début pour
    // que l'arrivée se voie.
    if let first = cards.first?.item.id, first != previousFirst { scrollToStart(animated: animated) }
  }

  private func scrollToStart(animated: Bool) {
    let clip = scrollView.contentView
    guard clip.bounds.origin.x != 0 else { return }
    let target = NSPoint(x: 0, y: clip.bounds.origin.y)
    if animated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.28
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        clip.animator().setBoundsOrigin(target)
      }
      scrollView.reflectScrolledClipView(clip)
    } else {
      clip.scroll(to: target)
      scrollView.reflectScrolledClipView(clip)
    }
  }

  private func updateEmptyState(animated: Bool) {
    let wasHidden = emptyState.isHidden
    if cards.isEmpty {
      emptyState.apply(
        filter: filter,
        hasOtherClips: !items.isEmpty)
    }
    emptyState.isHidden = !cards.isEmpty
    if wasHidden, !emptyState.isHidden, animated {
      emptyState.layer?.crossfadeIn(delay: 0.1, duration: 0.22)
    }
  }

  private func updateClearButton() {
    let canClear = items.contains { !$0.isPinned }
    clearButton.isEnabled = canClear
    clearButton.alphaValue = canClear ? 1 : 0.4
  }

  private func refreshFilterButtons() {
    filterButtons.forEach { $0.isSelectedFilter = $0.filter == filter }
    animatesNextHighlight = canAnimate
    needsLayout = true
  }
  private var animatesNextHighlight = false

  @objc private func clearClicked() { onClear?() }

  /// Remet « il y a N min » à jour sur chaque carte.
  func refreshAges() {
    cards.forEach { $0.refreshAge() }
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()
    let width = bounds.width

    clearButton.sizeToFit()
    let fullWidth = filterButtons.reduce(CGFloat(0)) { $0 + ceil($1.intrinsicWidth(compact: false)) }
    // Capsule + « Clear » ne tiennent pas côte à côte : les filtres non choisis passent en icône.
    isCompact = fullWidth + clearButton.frame.width + 12 > width

    titleLabel.frame = CGRect(
      x: 0, y: bounds.maxY - titleHeight, width: max(0, width), height: titleHeight)

    let filterY = titleLabel.frame.minY - rowGap / 2 - filterHeight
    var x: CGFloat = 0
    for button in filterButtons {
      let compact = isCompact && !button.isSelectedFilter
      button.isCompact = compact
      let buttonWidth = ceil(button.intrinsicWidth(compact: compact))
      button.frame = CGRect(x: x, y: 0, width: buttonWidth, height: filterHeight)
      x += buttonWidth
    }
    filterPill.frame = CGRect(x: 0, y: filterY, width: x, height: filterHeight)
    filterPill.layer?.cornerRadius = filterHeight / 2
    placeHighlight(animated: animatesNextHighlight)
    animatesNextHighlight = false

    clearButton.frame.origin = CGPoint(
      x: width - clearButton.frame.width, y: filterY + (filterHeight - clearButton.frame.height) / 2
    )

    let rowHeight = ClipboardCardView.size.height
    let rowTop = filterY - filterToRowGap
    scrollView.frame = CGRect(x: 0, y: max(0, rowTop - rowHeight), width: width, height: rowHeight)
    emptyState.frame = scrollView.frame

    let animated = animatesNextLayout
    animatesNextLayout = false
    var cardX: CGFloat = 0
    for card in cards {
      card.place(
        CGRect(origin: CGPoint(x: cardX, y: 0), size: ClipboardCardView.size), animated: animated)
      cardX += ClipboardCardView.size.width + cardSpacing
    }
    documentView.frame = CGRect(
      x: 0, y: 0, width: max(width, cardX - cardSpacing), height: rowHeight)
  }

  /// Le fond blanc du filtre choisi glisse d'un bouton à l'autre au ressort.
  private func placeHighlight(animated: Bool) {
    guard let selected = filterButtons.first(where: \.isSelectedFilter) else { return }
    let previousPosition = highlight.presentation()?.position ?? highlight.position
    let previousBounds = highlight.presentation()?.bounds ?? highlight.bounds
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    highlight.frame = selected.frame
    highlight.cornerRadius = selected.frame.height / 2
    CATransaction.commit()
    guard animated, previousBounds.width > 0, previousPosition != highlight.position
      || previousBounds != highlight.bounds
    else { return }
    highlight.springAnimate(
      keyPath: "position", to: NSValue(point: highlight.position),
      from: NSValue(point: previousPosition))
    highlight.springAnimate(
      keyPath: "bounds", to: NSValue(rect: highlight.bounds), from: NSValue(rect: previousBounds))
  }
}

/// Rangée de cartes : la molette d'une souris (qui ne défile qu'à la verticale) fait défiler la
/// rangée à l'horizontale. Un trackpad garde son défilement naturel.
private final class ClipboardRowScrollView: NSScrollView {

  override func scrollWheel(with event: NSEvent) {
    guard !event.hasPreciseScrollingDeltas, event.scrollingDeltaX == 0,
      event.scrollingDeltaY != 0, let document = documentView
    else { return super.scrollWheel(with: event) }
    let clip = contentView
    let maxX = max(0, document.frame.width - clip.bounds.width)
    let x = min(max(0, clip.bounds.origin.x - event.scrollingDeltaY * 12), maxX)
    clip.scroll(to: NSPoint(x: x, y: clip.bounds.origin.y))
    reflectScrolledClipView(clip)
  }
}

/// État vide : une icône, une phrase et un indice. Quand seul le filtre ne retient rien, le
/// bouton « Show all clips » ramène à tout l'historique.
private final class ClipboardEmptyStateView: NSView {

  var onShowAll: (() -> Void)?

  private let iconView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let hintLabel = NSTextField(labelWithString: "")
  private let showAllButton = HomePillButton()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    iconView.contentTintColor = NSColor(white: 0.45, alpha: 1)
    iconView.imageScaling = .scaleNone
    addSubview(iconView)

    titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
    titleLabel.textColor = NSColor(white: 0.7, alpha: 1)
    titleLabel.alignment = .center
    titleLabel.lineBreakMode = .byTruncatingTail
    addSubview(titleLabel)

    hintLabel.font = .systemFont(ofSize: 11)
    hintLabel.textColor = NSColor(white: 0.45, alpha: 1)
    hintLabel.alignment = .center
    hintLabel.lineBreakMode = .byTruncatingTail
    addSubview(hintLabel)

    showAllButton.title = "Show all clips"
    showAllButton.onClick = { [weak self] in self?.onShowAll?() }
    addSubview(showAllButton)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(filter: ClipboardFilter, hasOtherClips: Bool) {
    let symbol = hasOtherClips ? filter.symbolName : "doc.on.clipboard"
    iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 22, weight: .light))
    if hasOtherClips {
      titleLabel.stringValue = "No \(filter.title.lowercased()) yet"
      hintLabel.stringValue = "Other clips are hidden by this filter"
    } else {
      titleLabel.stringValue = "Nothing copied yet"
      hintLabel.stringValue = "Copy text, a link, an image or a file — it shows up here"
    }
    showAllButton.isHidden = !hasOtherClips
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let iconHeight: CGFloat = 26
    let titleHeight: CGFloat = 16
    let hintHeight: CGFloat = 14
    let buttonHeight: CGFloat = 20
    let showsButton = !showAllButton.isHidden
    let total = iconHeight + 4 + titleHeight + 2 + hintHeight + (showsButton ? 6 + buttonHeight : 0)
    var y = bounds.midY + total / 2

    y -= iconHeight
    iconView.frame = CGRect(x: 0, y: y, width: bounds.width, height: iconHeight)
    y -= 4 + titleHeight
    titleLabel.frame = CGRect(x: 8, y: y, width: max(0, bounds.width - 16), height: titleHeight)
    y -= 2 + hintHeight
    hintLabel.frame = CGRect(x: 8, y: y, width: max(0, bounds.width - 16), height: hintHeight)
    if showsButton {
      y -= 6 + buttonHeight
      let width = showAllButton.fittingWidth
      showAllButton.frame = CGRect(
        x: bounds.midX - width / 2, y: y, width: width, height: buttonHeight)
    }
  }
}

/// Un filtre de la capsule du haut : glyphe puis texte. Le fond blanc du filtre choisi est
/// dessiné par la capsule (il glisse d'un filtre à l'autre) ; le bouton ne change que d'encre.
private final class FilterButton: NSView {

  let filter: ClipboardFilter
  var onClick: (() -> Void)?

  var isSelectedFilter = false {
    didSet { applyStyle() }
  }

  /// Seule l'icône : quand la capsule et « Clear » ne tiennent pas sur la largeur.
  var isCompact = false {
    didSet { label.isHidden = isCompact }
  }

  private static let iconSize: CGFloat = 12
  private static let iconGap: CGFloat = 5

  private let iconView = NSImageView()
  private let label: NSTextField

  func intrinsicWidth(compact: Bool) -> CGFloat {
    compact
      ? Self.iconSize + 20
      : Self.iconSize + Self.iconGap + label.intrinsicContentSize.width + 24
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
    toolTip = filter.title
    setAccessibilityRole(.button)
    setAccessibilityLabel(filter.title)
    applyStyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func applyStyle() {
    let ink: NSColor = isSelectedFilter ? .black : .white
    label.textColor = ink
    iconView.contentTintColor = ink
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func accessibilityPerformPress() -> Bool {
    onClick?()
    return true
  }

  override func layout() {
    super.layout()
    let size = label.intrinsicContentSize
    let iconX: CGFloat = isCompact ? (bounds.width - Self.iconSize) / 2 : 12
    iconView.frame = CGRect(
      x: iconX, y: (bounds.height - Self.iconSize) / 2, width: Self.iconSize, height: Self.iconSize)
    let labelX = iconX + Self.iconSize + Self.iconGap
    label.frame = CGRect(
      x: labelX, y: (bounds.height - size.height) / 2, width: max(0, bounds.width - labelX - 12),
      height: size.height)
  }

  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
  }
}
