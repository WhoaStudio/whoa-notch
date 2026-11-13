import AppKit

/// Un choix parmi plusieurs, présenté en vignettes avec un libellé dessous. L'option choisie a
/// son libellé dans une pastille ; `ringsOnSelect` y ajoute un anneau autour de la vignette.
final class SettingsChoiceView: NSView {

  var onChange: ((Int) -> Void)?

  private var items: [SettingsChoiceItemView] = []

  init(items choices: [(title: String, visual: SettingsFillView)], ringsOnSelect: Bool) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    items = choices.enumerated().map { index, choice in
      let item = SettingsChoiceItemView(
        title: choice.title, visual: choice.visual, ringsOnSelect: ringsOnSelect)
      item.onClick = { [weak self] in
        self?.select($0)
        self?.onChange?($0)
      }
      item.index = index
      return item
    }

    let stack = NSStackView(views: items)
    stack.orientation = .horizontal
    stack.alignment = .top
    stack.spacing = SettingsMetrics.choiceSpacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    select(0)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func select(_ index: Int) {
    for (i, item) in items.enumerated() { item.isSelected = i == index }
  }

  // MARK: - Visuels

  /// Pastille ronde d'une couleur, au centre d'un cercle qui porte l'anneau de sélection.
  static func swatch(color: NSColor) -> SettingsFillView {
    let size = SettingsMetrics.iconChoiceSize
    let outer = SettingsFillView(fill: .clear, cornerRadius: size / 2)
    let inner = SettingsFillView(fill: color, cornerRadius: (size - 14) / 2)
    outer.addSubview(inner)
    NSLayoutConstraint.activate([
      outer.widthAnchor.constraint(equalToConstant: size),
      outer.heightAnchor.constraint(equalToConstant: size),
      inner.centerXAnchor.constraint(equalTo: outer.centerXAnchor),
      inner.centerYAnchor.constraint(equalTo: outer.centerYAnchor),
      inner.widthAnchor.constraint(equalToConstant: size - 14),
      inner.heightAnchor.constraint(equalToConstant: size - 14),
    ])
    return outer
  }

  /// Vignette d'écran dégradé montrant la forme du panneau : encoche collée au bord haut, ou
  /// îlot flottant en dessous.
  static func thumbnail(style: NotchPanelStyle) -> SettingsFillView {
    let size = SettingsMetrics.thumbnailSize
    let frame = SettingsFillView(fill: .clear, cornerRadius: 10)
    let gradient = GradientView()
    let bar = SettingsFillView(fill: .black, cornerRadius: 5)

    switch style {
    case .notch:
      bar.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    case .island:
      break
    }

    frame.addSubview(gradient)
    frame.addSubview(bar)
    NSLayoutConstraint.activate([
      frame.widthAnchor.constraint(equalToConstant: size.width),
      frame.heightAnchor.constraint(equalToConstant: size.height),
      gradient.topAnchor.constraint(equalTo: frame.topAnchor),
      gradient.bottomAnchor.constraint(equalTo: frame.bottomAnchor),
      gradient.leadingAnchor.constraint(equalTo: frame.leadingAnchor),
      gradient.trailingAnchor.constraint(equalTo: frame.trailingAnchor),
      bar.centerXAnchor.constraint(equalTo: frame.centerXAnchor),
      bar.widthAnchor.constraint(equalToConstant: 34),
      bar.heightAnchor.constraint(equalToConstant: 11),
      bar.topAnchor.constraint(equalTo: frame.topAnchor, constant: style == .notch ? 0 : 9),
    ])
    return frame
  }
}

/// Fond en dégradé violet → rose des vignettes, arrondi comme la vignette qui le porte.
private final class GradientView: NSView {
  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func makeBackingLayer() -> CALayer {
    let layer = CAGradientLayer()
    layer.colors = [NSColor.systemPurple.cgColor, NSColor.systemPink.cgColor]
    layer.startPoint = CGPoint(x: 0, y: 0)
    layer.endPoint = CGPoint(x: 1, y: 1)
    layer.cornerRadius = 10
    layer.cornerCurve = .continuous
    return layer
  }
}

private final class SettingsChoiceItemView: NSView {

  var index = 0
  var onClick: ((Int) -> Void)?
  var isSelected = false { didSet { refresh() } }

  private let visual: SettingsFillView
  private let ringsOnSelect: Bool
  private let pill = SettingsFillView(fill: .clear, cornerRadius: 11)
  private let label: NSTextField

  init(title: String, visual: SettingsFillView, ringsOnSelect: Bool) {
    self.visual = visual
    self.ringsOnSelect = ringsOnSelect
    self.label = NSTextField(labelWithString: title)
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    label.translatesAutoresizingMaskIntoConstraints = false
    pill.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
      label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
      label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 3),
      label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -3),
    ])

    let stack = NSStackView(views: [visual, pill])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])

    addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(handleClick)))
    refresh()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func refresh() {
    pill.fillColor = isSelected ? SettingsPalette.fill : .clear
    label.font = .systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
    label.textColor = isSelected ? .labelColor : .secondaryLabelColor
    if ringsOnSelect {
      visual.borderColor = isSelected ? .labelColor : SettingsPalette.rule
      visual.borderWidth = isSelected ? 2 : 1
    }
  }

  @objc private func handleClick() {
    onClick?(index)
  }
}
