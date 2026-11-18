import AppKit

/// Barre d'onglets de l'onglet Analytics : une pastille par page, et une pastille de sélection
/// qui glisse de l'une à l'autre au ressort.
final class NotchAnalyticsTabBarView: NSView {

  static let height: CGFloat = 26

  var onSelect: ((Int) -> Void)?

  private let highlight = CALayer()
  private var items: [Item] = []
  private var selected = 0

  private static let itemGap: CGFloat = 4

  init(pages: [NotchAnalyticsPage]) {
    super.init(frame: .zero)
    wantsLayer = true
    highlight.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
    highlight.cornerRadius = Self.height / 2
    layer?.addSublayer(highlight)
    for (index, page) in pages.enumerated() {
      let item = Item(title: page.pageTitle, symbol: page.pageSymbol)
      item.onClick = { [weak self] in self?.onSelect?(index) }
      addSubview(item)
      items.append(item)
    }
    applySelection()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func select(_ index: Int, animated: Bool) {
    guard index != selected, items.indices.contains(index) else { return }
    let from = highlight.frame
    selected = index
    applySelection()
    let target = itemFrames()[index]
    setHighlight(target, from: animated ? from : nil)
  }

  private func applySelection() {
    for (index, item) in items.enumerated() { item.isSelected = index == selected }
  }

  private func itemFrames() -> [NSRect] {
    var x: CGFloat = 0
    return items.map { item in
      let frame = NSRect(x: x, y: 0, width: item.fittingWidth, height: Self.height)
      x = frame.maxX + Self.itemGap
      return frame
    }
  }

  /// Pose la pastille sur `frame` ; avec `from`, elle y arrive au ressort depuis ce cadre.
  private func setHighlight(_ frame: NSRect, from: NSRect?) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    highlight.frame = frame
    CATransaction.commit()
    guard let from else { return }
    highlight.springAnimate(
      keyPath: "position.x", to: frame.midX, from: from.midX, preset: .snappy)
    highlight.springAnimate(
      keyPath: "bounds.size.width", to: frame.width, from: from.width, preset: .snappy)
  }

  override func layout() {
    super.layout()
    let frames = itemFrames()
    for (item, frame) in zip(items, frames) { item.frame = frame }
    if frames.indices.contains(selected) { setHighlight(frames[selected], from: nil) }
  }

  // MARK: - Pastille

  private final class Item: NSView {
    var onClick: (() -> Void)?
    var isSelected = false {
      didSet { applyTint() }
    }

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private static let padding: CGFloat = 11
    private static let gap: CGFloat = 5
    private static let iconSize: CGFloat = 13

    init(title: String, symbol: String) {
      super.init(frame: .zero)
      let configuration = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .medium)
      iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
        .withSymbolConfiguration(configuration)
      iconView.imageScaling = .scaleProportionallyDown
      label.stringValue = title
      label.font = .systemFont(ofSize: 12.5, weight: .medium)
      addSubview(iconView)
      addSubview(label)
      applyTint()
      setAccessibilityElement(true)
      setAccessibilityRole(.button)
      setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    var fittingWidth: CGFloat {
      Self.padding + Self.iconSize + Self.gap + ceil(label.intrinsicContentSize.width) + Self.padding
    }

    private func applyTint() {
      let color = NSColor.white.withAlphaComponent(isSelected ? 1 : 0.55)
      label.textColor = color
      iconView.contentTintColor = color
    }

    override func layout() {
      super.layout()
      iconView.frame = NSRect(
        x: Self.padding, y: (bounds.height - Self.iconSize) / 2,
        width: Self.iconSize, height: Self.iconSize)
      let size = label.intrinsicContentSize
      label.frame = NSRect(
        x: iconView.frame.maxX + Self.gap, y: (bounds.height - size.height) / 2,
        width: ceil(size.width), height: size.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
  }
}
