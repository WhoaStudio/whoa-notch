import AppKit

/// Un `NSSlider` avec sa valeur affichée à droite — utilisé pour chaque réglage continu
/// des Préférences (delay, intensité, sensibilité...).
final class LabeledSliderView: NSView {

  let slider = NSSlider()
  private let valueLabel = NSTextField(labelWithString: "")

  var formatter: (Double) -> String = { String(format: "%.2f", $0) } {
    didSet { updateLabel() }
  }
  var onChange: ((Double) -> Void)?

  init(minValue: Double, maxValue: Double, value: Double) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    slider.minValue = minValue
    slider.maxValue = maxValue
    slider.doubleValue = value
    slider.isContinuous = true
    slider.target = self
    slider.action = #selector(sliderChanged)
    slider.translatesAutoresizingMaskIntoConstraints = false

    valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    valueLabel.textColor = .secondaryLabelColor
    valueLabel.alignment = .right
    valueLabel.translatesAutoresizingMaskIntoConstraints = false

    addSubview(slider)
    addSubview(valueLabel)

    NSLayoutConstraint.activate([
      slider.leadingAnchor.constraint(equalTo: leadingAnchor),
      slider.centerYAnchor.constraint(equalTo: centerYAnchor),
      slider.widthAnchor.constraint(equalToConstant: SettingsMetrics.sliderWidth),

      valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 8),
      valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
      valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      valueLabel.widthAnchor.constraint(equalToConstant: 44),
    ])

    updateLabel()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setValue(_ value: Double) {
    slider.doubleValue = value
    updateLabel()
  }

  @objc private func sliderChanged() {
    updateLabel()
    onChange?(slider.doubleValue)
  }

  private func updateLabel() {
    valueLabel.stringValue = formatter(slider.doubleValue)
  }
}
