import AppKit

/// En-tête commun à tous les volets de Préférences : icône dans un carré arrondi, titre en gras
/// et sous-titre gris.
final class SettingsPaneHeaderView: NSView {

  init(category: SettingsCategory) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    let size = SettingsMetrics.headerIconSize
    let icon = SettingsSymbolTile(symbolName: category.symbolName, tint: category.tint, size: size)

    let title = NSTextField(labelWithString: category.title)
    title.font = .systemFont(ofSize: 26, weight: .bold)
    let subtitle = NSTextField(wrappingLabelWithString: category.subtitle)
    subtitle.font = .systemFont(ofSize: 14)
    subtitle.textColor = .secondaryLabelColor
    subtitle.preferredMaxLayoutWidth = 460
    subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let text = NSStackView(views: [title, subtitle])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 2

    let row = NSStackView(views: [icon, text])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 14
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)

    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: topAnchor),
      row.bottomAnchor.constraint(equalTo: bottomAnchor),
      row.leadingAnchor.constraint(equalTo: leadingAnchor),
      row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

/// Symbole SF blanc sur un carré arrondi coloré — l'icône de la sidebar et de l'en-tête.
final class SettingsSymbolTile: NSView {

  init(symbolName: String, tint: NSColor, size: CGFloat) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.cornerRadius = size * 0.25
    layer?.cornerCurve = .continuous
    layer?.backgroundColor = tint.cgColor
    addRelief(size: size)

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .medium)
    let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
      .withSymbolConfiguration(config)
    let imageView = NSImageView(image: image ?? NSImage())
    imageView.contentTintColor = .white
    imageView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(imageView)

    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: size),
      heightAnchor.constraint(equalToConstant: size),
      imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Effet de volume : dégradé vertical, liseré clair et ombre portée douce.
  private func addRelief(size: CGFloat) {
    guard let layer else { return }
    let radius = size * 0.25

    let gradient = CAGradientLayer()
    gradient.frame = CGRect(x: 0, y: 0, width: size, height: size)
    gradient.colors = [
      NSColor.white.withAlphaComponent(0.30).cgColor,
      NSColor.black.withAlphaComponent(0.12).cgColor,
    ]
    gradient.startPoint = CGPoint(x: 0.5, y: 1)
    gradient.endPoint = CGPoint(x: 0.5, y: 0)
    gradient.cornerRadius = radius
    gradient.cornerCurve = .continuous
    layer.addSublayer(gradient)

    layer.borderWidth = 0.5
    layer.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
    layer.shadowColor = NSColor.black.cgColor
    layer.shadowOpacity = 0.35
    layer.shadowOffset = CGSize(width: 0, height: -1.5)
    layer.shadowRadius = 2.5
  }
}
