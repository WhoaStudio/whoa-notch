import AppKit
import Combine

/// Écran "Brightness" : visibilité de l'overlay, pourcentage, délai de fermeture, intensité
/// du glow, sensibilité au scroll, position et taille du widget.
final class BrightnessSettingsViewController: SettingsSectionViewController {

  private let viewModel = BrightnessSettingsViewModel()
  private var cancellable: AnyCancellable?

  private lazy var enableOverlayCheckbox = NSButton.settingsCheckbox(
    "Enable overlay", target: self, action: #selector(enableOverlayChanged))
  private lazy var showPercentageCheckbox = NSButton.settingsCheckbox(
    "Show brightness percentage", target: self, action: #selector(showPercentageChanged))
  private let autoHideDelaySlider = LabeledSliderView(minValue: 0, maxValue: 2, value: 0.2)
  private let scrollSensitivitySlider = LabeledSliderView(minValue: 0.5, maxValue: 2, value: 1)
  private let glowIntensitySlider = LabeledSliderView(minValue: 0, maxValue: 2, value: 1)
  private let widgetPositionPopUp = NSPopUpButton()
  private let widgetSizePopUp = NSPopUpButton()

  override func makeRows() -> [NSView] {
    autoHideDelaySlider.formatter = { String(format: "%.1fs", $0) }
    autoHideDelaySlider.onChange = { [weak self] in self?.viewModel.setAutoHideDelay($0) }

    scrollSensitivitySlider.formatter = { String(format: "%.1f×", $0) }
    scrollSensitivitySlider.onChange = { [weak self] in self?.viewModel.setScrollSensitivity($0) }

    glowIntensitySlider.formatter = { String(format: "%.1f×", $0) }
    glowIntensitySlider.onChange = { [weak self] in self?.viewModel.setGlowIntensity($0) }

    widgetPositionPopUp.target = self
    widgetPositionPopUp.action = #selector(widgetPositionChanged)
    EdgePosition.allCases.forEach { widgetPositionPopUp.addItem(withTitle: $0.displayName) }

    widgetSizePopUp.target = self
    widgetSizePopUp.action = #selector(widgetSizeChanged)
    WidgetSize.allCases.forEach { widgetSizePopUp.addItem(withTitle: $0.displayName) }

    return [
      SettingsFormRowView(
        title: "Overlay",
        control: makeSettingsControlStack([enableOverlayCheckbox, showPercentageCheckbox])),
      SettingsFormRowView(title: "Auto hide delay", control: autoHideDelaySlider),
      makeSettingsDivider(),
      SettingsFormRowView(title: "Scroll sensitivity", control: scrollSensitivitySlider),
      SettingsFormRowView(title: "Glow intensity", control: glowIntensitySlider),
      makeSettingsDivider(),
      SettingsFormRowView(title: "Widget position", control: widgetPositionPopUp),
      SettingsFormRowView(title: "Widget size", control: widgetSizePopUp),
    ]
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    cancellable = viewModel.$settings.sink { [weak self] in self?.apply($0) }
  }

  private func apply(_ settings: BrightnessSettings) {
    enableOverlayCheckbox.state = settings.enableOverlay ? .on : .off
    showPercentageCheckbox.state = settings.showPercentage ? .on : .off
    autoHideDelaySlider.setValue(settings.autoHideDelay)
    scrollSensitivitySlider.setValue(settings.scrollSensitivity)
    glowIntensitySlider.setValue(settings.glowIntensity)
    widgetPositionPopUp.selectItem(
      at: EdgePosition.allCases.firstIndex(of: settings.widgetPosition) ?? 0)
    widgetSizePopUp.selectItem(at: WidgetSize.allCases.firstIndex(of: settings.widgetSize) ?? 0)
  }

  @objc private func enableOverlayChanged() {
    viewModel.setEnableOverlay(enableOverlayCheckbox.state == .on)
  }

  @objc private func showPercentageChanged() {
    viewModel.setShowPercentage(showPercentageCheckbox.state == .on)
  }

  @objc private func widgetPositionChanged() {
    viewModel.setWidgetPosition(EdgePosition.allCases[widgetPositionPopUp.indexOfSelectedItem])
  }

  @objc private func widgetSizeChanged() {
    viewModel.setWidgetSize(WidgetSize.allCases[widgetSizePopUp.indexOfSelectedItem])
  }
}
