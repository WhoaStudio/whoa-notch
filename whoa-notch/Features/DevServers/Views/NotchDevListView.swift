import AppKit

/// Liste verticale de lignes de hauteur fixe, qui défile quand elle dépasse la page.
final class NotchDevListView: NSScrollView {

  var rowHeight: CGFloat = 52

  private let document = FlippedView()
  private var rows: [NSView] = []

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    drawsBackground = false
    hasVerticalScroller = false
    hasHorizontalScroller = false
    verticalScrollElasticity = .allowed
    horizontalScrollElasticity = .none
    documentView = document
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setRows(_ newRows: [NSView]) {
    rows.forEach { $0.removeFromSuperview() }
    rows = newRows
    rows.forEach(document.addSubview)
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let heights = rows.map { ($0 as? NotchDevRowView)?.preferredHeight ?? rowHeight }
    let height = max(bounds.height, heights.reduce(0, +))
    document.frame = NSRect(x: 0, y: 0, width: bounds.width, height: height)
    var y: CGFloat = 0
    for (row, rowHeight) in zip(rows, heights) {
      row.frame = NSRect(x: 0, y: y, width: bounds.width, height: rowHeight)
      y += rowHeight
    }
  }

  private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
  }
}

/// Une ligne de liste : un filet fin en bas, comme entre les actions de la maquette.
class NotchDevRowView: NSView {

  /// Hauteur propre à la ligne ; `nil` : celle de la liste.
  var preferredHeight: CGFloat?
  /// Faux pour une ligne sans filet (en-tête de groupe).
  var showsSeparator = true {
    didSet { separator.isHidden = !showsSeparator }
  }

  private let separator = CALayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    separator.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
    layer?.addSublayer(separator)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    separator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
    CATransaction.commit()
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Champ de saisie sur un fond arrondi, dans le ton sombre de l'encoche.
final class NotchDevFieldView: NSView {

  static let height: CGFloat = 28

  var onSubmit: (() -> Void)?

  private let field = NSTextField()

  var text: String {
    get { field.stringValue }
    set { field.stringValue = newValue }
  }

  init(placeholder: String, monospaced: Bool = false) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.textColor = .white
    field.font =
      monospaced
      ? .monospacedSystemFont(ofSize: 12.5, weight: .regular) : .systemFont(ofSize: 13)
    field.placeholderAttributedString = NSAttributedString(
      string: placeholder,
      attributes: [
        .foregroundColor: NSColor.white.withAlphaComponent(0.55), .font: field.font as Any,
      ])
    field.lineBreakMode = .byTruncatingTail
    field.cell?.usesSingleLineMode = true
    field.target = self
    field.action = #selector(submit)
    addSubview(field)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func submit() { onSubmit?() }

  override func layout() {
    super.layout()
    let height = field.intrinsicContentSize.height
    field.frame = NSRect(
      x: 10, y: (bounds.height - height) / 2, width: max(0, bounds.width - 20), height: height)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  /// Un clic n'importe où sur le fond met le curseur dans le champ.
  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(field)
  }
}
