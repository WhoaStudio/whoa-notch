import AppKit

/// Une ligne de formulaire : libellé à gauche avec sa légende dessous, contrôle à droite.
/// Les contrôles hauts (choix à vignettes, bannière) passent sous le libellé. L'unité de base de
/// chaque groupe (`SettingsGroupView`) de Préférences.
final class SettingsFormRowView: NSView {

  private let titleLabel = NSTextField(labelWithString: "")
  private let control: NSView

  /// Atténue le libellé et le contrôle quand le réglage n'a pas d'effet pour l'instant.
  var isDimmed = false {
    didSet {
      titleLabel.textColor = isDimmed ? .tertiaryLabelColor : .labelColor
      let opacity: CGFloat = isDimmed ? 0.5 : 1
      if oldValue != isDimmed, window != nil, OverlayAnimation.allowsMotion {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = PanelFold.fadeDuration
          control.animator().alphaValue = opacity
        }
      } else {
        control.alphaValue = opacity
      }
    }
  }

  /// - Parameter alignsTop: `true` pour un contrôle haut, placé sous le libellé ; sinon il est
  ///   à droite, centré verticalement.
  init(title: String? = nil, control: NSView, caption: String? = nil, alignsTop: Bool = false) {
    self.control = control
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    titleLabel.stringValue = title ?? ""
    titleLabel.font = .systemFont(ofSize: 13)
    titleLabel.textColor = .labelColor
    titleLabel.isHidden = title == nil
    titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

    var textViews: [NSView] = []
    if title != nil { textViews.append(titleLabel) }
    let stacked = alignsTop || title == nil
    if let caption {
      let captionLabel = NSTextField(wrappingLabelWithString: caption)
      captionLabel.font = .systemFont(ofSize: 11)
      captionLabel.textColor = .secondaryLabelColor
      captionLabel.preferredMaxLayoutWidth = stacked ? 440 : SettingsMetrics.captionMaxWidth
      captionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      textViews.append(captionLabel)
    }
    let column = NSStackView(views: textViews)
    column.orientation = .vertical
    column.alignment = .leading
    column.spacing = 2
    column.translatesAutoresizingMaskIntoConstraints = false
    control.translatesAutoresizingMaskIntoConstraints = false
    addSubview(column)
    addSubview(control)

    let minHeight = heightAnchor.constraint(
      greaterThanOrEqualToConstant: SettingsMetrics.rowMinHeight)
    if stacked {
      var constraints = [
        minHeight,
        column.topAnchor.constraint(equalTo: topAnchor),
        column.leadingAnchor.constraint(equalTo: leadingAnchor),
        column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        control.leadingAnchor.constraint(equalTo: leadingAnchor),
        control.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        control.bottomAnchor.constraint(equalTo: bottomAnchor),
      ]
      constraints.append(
        textViews.isEmpty
          ? control.topAnchor.constraint(equalTo: topAnchor)
          : control.topAnchor.constraint(equalTo: column.bottomAnchor, constant: 8))
      NSLayoutConstraint.activate(constraints)
    } else {
      NSLayoutConstraint.activate([
        minHeight,
        column.leadingAnchor.constraint(equalTo: leadingAnchor),
        column.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
        column.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        column.centerYAnchor.constraint(equalTo: centerYAnchor),
        control.trailingAnchor.constraint(equalTo: trailingAnchor),
        control.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
        control.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        control.centerYAnchor.constraint(equalTo: centerYAnchor),
        column.trailingAnchor.constraint(
          lessThanOrEqualTo: control.leadingAnchor, constant: -SettingsMetrics.rowControlGap),
      ])
    }
  }

  /// Ligne d'un interrupteur : son libellé à gauche, l'`NSSwitch` à droite.
  convenience init(toggle: SettingsToggle, caption: String? = nil) {
    toggle.switchControl.controlSize = .regular
    self.init(title: toggle.title, control: toggle.switchControl, caption: caption)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

/// Filet horizontal entre deux groupes de réglages.
func makeSettingsDivider() -> NSView {
  let rule = NSBox()
  rule.boxType = .separator
  rule.translatesAutoresizingMaskIntoConstraints = false
  return rule
}

/// Réglage on/off du formulaire : libellé + `NSSwitch` natif. Expose `state`, `isEnabled` et `identifier`
/// comme la case à cocher qu'il remplace ; l'action est envoyée par l'`NSSwitch` (le `sender`).
final class SettingsToggle: NSStackView {
  let switchControl = NSSwitch()
  let title: String

  var state: NSControl.StateValue {
    get { switchControl.state }
    set { switchControl.state = newValue }
  }

  var isEnabled: Bool {
    get { switchControl.isEnabled }
    set { switchControl.isEnabled = newValue }
  }

  override var identifier: NSUserInterfaceItemIdentifier? {
    didSet { switchControl.identifier = identifier }
  }

  init(_ title: String, target: AnyObject, action: Selector) {
    self.title = title
    super.init(frame: .zero)
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 13)
    switchControl.controlSize = .small
    switchControl.target = target
    switchControl.action = action
    switchControl.setAccessibilityLabel(title)
    orientation = .horizontal
    spacing = 8
    addArrangedSubview(switchControl)
    addArrangedSubview(label)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas pris en charge") }
}

extension NSButton {
  /// Interrupteur natif du formulaire (voir `SettingsToggle`).
  static func settingsCheckbox(_ title: String, target: AnyObject, action: Selector)
    -> SettingsToggle
  {
    SettingsToggle(title, target: target, action: action)
  }
}

/// Pile verticale de contrôles courts (cases à cocher) dans une seule ligne de formulaire.
func makeSettingsControlStack(_ views: [NSView]) -> NSStackView {
  let stack = NSStackView(views: views)
  stack.orientation = .vertical
  stack.alignment = .leading
  stack.spacing = 8
  return stack
}

/// Bouton large à fond gris qui affiche le raccourci choisi (« ⌘ Space »), menu au clic.
final class SettingsKeyPopUp: NSPopUpButton {

  init() {
    super.init(frame: .zero, pullsDown: false)
    isBordered = false
    font = .systemFont(ofSize: 15, weight: .semibold)
    alignment = .center
    (cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.cornerCurve = .continuous
    updateBackground()
    translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: SettingsMetrics.keyButtonSize.width),
      heightAnchor.constraint(equalToConstant: SettingsMetrics.keyButtonSize.height),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateBackground()
  }

  private func updateBackground() {
    layer?.backgroundColor = SettingsPalette.fill.cgColor
  }
}
