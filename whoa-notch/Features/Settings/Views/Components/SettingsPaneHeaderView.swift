import AppKit

/// Barre d'en-tête commune aux volets de Préférences, fixe en haut : icône dans un carré arrondi
/// et titre. Un fond dépoli n'apparaît qu'une fois le contenu défilé dessous.
final class SettingsPaneHeaderView: NSView {

  private let blur = NSVisualEffectView()

  init(category: SettingsCategory) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    blur.material = .headerView
    blur.blendingMode = .withinWindow
    blur.state = .active
    blur.alphaValue = 0
    blur.translatesAutoresizingMaskIntoConstraints = false
    addSubview(blur)

    let icon = SettingsSymbolTile(
      symbolName: category.symbolName, tint: category.tint, size: SettingsMetrics.headerIconSize)
    let title = NSTextField(labelWithString: category.title)
    title.font = .systemFont(ofSize: 15, weight: .semibold)
    title.setAccessibilityRole(.staticText)

    let row = NSStackView(views: [icon, title])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 8
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)

    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: SettingsMetrics.headerHeight),
      blur.topAnchor.constraint(equalTo: topAnchor),
      blur.bottomAnchor.constraint(equalTo: bottomAnchor),
      blur.leadingAnchor.constraint(equalTo: leadingAnchor),
      blur.trailingAnchor.constraint(equalTo: trailingAnchor),
      row.bottomAnchor.constraint(equalTo: bottomAnchor),
      row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsMetrics.contentInset),
      row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Montre le fond dépoli quand le contenu a défilé sous la barre.
  func setScrolled(_ scrolled: Bool) {
    let target: CGFloat = scrolled ? 1 : 0
    guard blur.alphaValue != target else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = SettingsMetrics.transitionDuration
      blur.animator().alphaValue = target
    }
  }
}

/// Symbole SF blanc sur un carré arrondi coloré — l'icône de la sidebar et de l'en-tête.
final class SettingsSymbolTile: NSView {

  init(symbolName: String, tint: NSColor, size: CGFloat) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.cornerRadius = size * 0.32
    layer?.cornerCurve = .continuous
    layer?.backgroundColor = tint.cgColor
    addRelief(size: size)

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .semibold)
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

  /// Effet de volume : dégradé vertical et liseré clair.
  private func addRelief(size: CGFloat) {
    guard let layer else { return }
    let radius = size * 0.32

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
  }
}
