import AppKit

/// Groupe de réglages commun à tous les volets : titre gris optionnel, carte arrondie contenant
/// les lignes séparées par des filets, légende de pied optionnelle.
final class SettingsGroupView: NSView {

  private let card = NSView()

  init(title: String? = nil, rows: [NSView], footer: String? = nil) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    card.wantsLayer = true
    card.layer?.cornerRadius = SettingsMetrics.groupCornerRadius
    card.layer?.cornerCurve = .continuous
    card.layer?.borderWidth = 1
    card.translatesAutoresizingMaskIntoConstraints = false

    let inset = SettingsMetrics.groupInset
    let rowStack = NSStackView()
    rowStack.orientation = .vertical
    rowStack.alignment = .leading
    rowStack.spacing = SettingsMetrics.groupRowSpacing
    rowStack.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(rowStack)
    NSLayoutConstraint.activate([
      rowStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
      rowStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
      rowStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
      rowStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
    ])
    for (index, row) in rows.enumerated() {
      if index > 0 {
        let rule = makeSettingsDivider()
        rowStack.addArrangedSubview(rule)
        rule.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true
      }
      rowStack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true
    }

    var views: [NSView] = []
    if let title {
      let label = NSTextField(labelWithString: title)
      label.font = .systemFont(ofSize: 13, weight: .semibold)
      label.textColor = .secondaryLabelColor
      views.append(label)
    }
    views.append(card)
    if let footer {
      let label = NSTextField(wrappingLabelWithString: footer)
      label.font = .systemFont(ofSize: 12)
      label.textColor = .secondaryLabelColor
      views.append(label)
    }
    let outer = NSStackView(views: views)
    outer.orientation = .vertical
    outer.alignment = .leading
    outer.spacing = 8
    outer.translatesAutoresizingMaskIntoConstraints = false
    addSubview(outer)
    NSLayoutConstraint.activate([
      outer.topAnchor.constraint(equalTo: topAnchor),
      outer.bottomAnchor.constraint(equalTo: bottomAnchor),
      outer.leadingAnchor.constraint(equalTo: leadingAnchor),
      outer.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    card.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
    if footer != nil, let label = views.last {
      label.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
    }
    updateColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func updateColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      card.layer?.backgroundColor = SettingsPalette.fill.cgColor
      card.layer?.borderColor = SettingsPalette.rule.cgColor
    }
  }
}
