import AppKit

/// Carte cliquable : pastille colorée, titre en gras, texte gris dessous et flèche ↗.
final class SettingsBannerView: NSView {

  var onClick: (() -> Void)?

  init(pill: String, pillColor: NSColor, title: String, subtitle: String) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    let card = SettingsFillView(cornerRadius: SettingsMetrics.bannerCornerRadius)

    let pillBackground = SettingsFillView(
      fill: pillColor.withAlphaComponent(0.18), cornerRadius: 11)
    let pillLabel = NSTextField(labelWithString: pill)
    pillLabel.font = .systemFont(ofSize: 12, weight: .medium)
    pillLabel.textColor = pillColor
    pillLabel.translatesAutoresizingMaskIntoConstraints = false
    pillBackground.addSubview(pillLabel)

    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
    subtitleLabel.font = .systemFont(ofSize: 12)
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.preferredMaxLayoutWidth = SettingsMetrics.bannerWidth - 140

    let textStack = NSStackView(views: [titleLabel, subtitleLabel])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 2
    textStack.translatesAutoresizingMaskIntoConstraints = false

    let arrow = NSImageView(
      image: NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil) ?? NSImage()
    )
    arrow.contentTintColor = .labelColor
    arrow.translatesAutoresizingMaskIntoConstraints = false

    addSubview(card)
    card.addSubview(pillBackground)
    card.addSubview(textStack)
    card.addSubview(arrow)

    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: SettingsMetrics.bannerWidth),
      card.topAnchor.constraint(equalTo: topAnchor),
      card.bottomAnchor.constraint(equalTo: bottomAnchor),
      card.leadingAnchor.constraint(equalTo: leadingAnchor),
      card.trailingAnchor.constraint(equalTo: trailingAnchor),

      pillLabel.leadingAnchor.constraint(equalTo: pillBackground.leadingAnchor, constant: 10),
      pillLabel.trailingAnchor.constraint(equalTo: pillBackground.trailingAnchor, constant: -10),
      pillLabel.topAnchor.constraint(equalTo: pillBackground.topAnchor, constant: 3),
      pillLabel.bottomAnchor.constraint(equalTo: pillBackground.bottomAnchor, constant: -3),

      pillBackground.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
      pillBackground.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),

      textStack.leadingAnchor.constraint(equalTo: pillBackground.trailingAnchor, constant: 10),
      textStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
      textStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
      textStack.trailingAnchor.constraint(lessThanOrEqualTo: arrow.leadingAnchor, constant: -10),

      arrow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
      arrow.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
    ])

    addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(handleClick)))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func handleClick() {
    onClick?()
  }
}
