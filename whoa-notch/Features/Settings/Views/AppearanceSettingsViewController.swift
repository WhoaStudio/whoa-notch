import AppKit
import Combine

/// Écran "Appearance" : taille, espacement, coins et ajustement du dock, couleurs des widgets, fond
/// des icônes, ombre, transparence et animations. Ne contient aucune logique — tout transite par
/// `AppearanceSettingsViewModel`.
final class AppearanceSettingsViewController: SettingsSectionViewController {

  private let viewModel = AppearanceSettingsViewModel()
  private var cancellable: AnyCancellable?
  private var animationCancellables = Set<AnyCancellable>()

  private let sizeSlider = LabeledSliderView(minValue: 50, maxValue: 150, value: 100)
  private let spacingSlider = LabeledSliderView(minValue: 0, maxValue: 16, value: 8)
  private let cornerSlider = LabeledSliderView(minValue: 0, maxValue: 24, value: 20)
  private let fitControl = NSSegmentedControl(
    labels: ["Adapt Size", "Scroll"], trackingMode: .selectOne, target: nil, action: nil)
  private let colorControl = NSSegmentedControl(
    labels: ["Colorful", "Monochrome"], trackingMode: .selectOne, target: nil, action: nil)
  private lazy var tileToggle = NSButton.settingsCheckbox(
    "Tile backgrounds & borders", target: self, action: #selector(tileChanged))
  private lazy var shadowToggle = NSButton.settingsCheckbox(
    "Dock shadow", target: self, action: #selector(shadowChanged))
  private let iconStylePopUp = NSPopUpButton()
  private lazy var transparencyToggle = NSButton.settingsCheckbox(
    "Reduce transparency", target: self, action: #selector(transparencyChanged))
  private lazy var animationsToggle = NSButton.settingsCheckbox(
    "Enable animations", target: self, action: #selector(animationsChanged))

  override func makeSections() -> [NSView] {
    sizeSlider.formatter = { String(format: "%.0f %%", $0) }
    sizeSlider.onChange = { [weak self] in self?.viewModel.setDockSize($0) }
    spacingSlider.formatter = { String(format: "%.0f pt", $0) }
    spacingSlider.onChange = { [weak self] in self?.viewModel.setWidgetSpacing($0) }
    cornerSlider.formatter = { String(format: "%.1f pt", $0) }
    cornerSlider.onChange = { [weak self] in self?.viewModel.setCornerRadius($0) }

    fitControl.target = self
    fitControl.action = #selector(fitChanged)
    // « Scroll » n'est pas encore rendu : la rangée défile au lieu de se réduire. Même traitement
    // que le thème Liquid Glass, qui est présent mais marqué « Coming soon… ».
    fitControl.setEnabled(false, forSegment: 1)
    colorControl.target = self
    colorControl.action = #selector(colorChanged)
    iconStylePopUp.addItems(withTitles: ["Default", "Grayscale"])
    iconStylePopUp.target = self
    iconStylePopUp.action = #selector(iconStyleChanged)

    return [
      SettingsGroupView(
        title: "Size and spacing",
        rows: [
          SettingsFormRowView(
            title: "Dock Size", control: sizeSlider,
            caption: "Relative to the icon size set for the macOS Dock"),
          SettingsFormRowView(title: "Widget Spacing", control: spacingSlider),
          SettingsFormRowView(title: "Corner Radius", control: cornerSlider),
          SettingsFormRowView(
            title: "When widgets don't fit", control: fitControl,
            caption: "Adapt Size shrinks the icons to fit the screen. Scroll is coming soon..."),
        ]),
      SettingsGroupView(
        title: "Widget presentation",
        rows: [
          SettingsFormRowView(
            title: "Widget Colors", control: colorControl,
            caption: "Monochrome removes accent colours from the widgets in the dock."),
          SettingsFormRowView(
            toggle: tileToggle, caption: "A subtle fill and outline behind each icon."),
          SettingsFormRowView(toggle: shadowToggle, caption: "A soft shadow under the dock."),
          SettingsFormRowView(title: "App Icon Style", control: iconStylePopUp),
        ]),
      SettingsGroupView(
        title: "Performance",
        rows: [
          SettingsFormRowView(
            toggle: transparencyToggle, caption: "Paints the dock background without transparency."),
          SettingsFormRowView(
            toggle: animationsToggle, caption: "Same setting as Enable animations in General."),
        ]),
    ]
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    cancellable = viewModel.$dock.sink { [weak self] in self?.apply($0) }
    viewModel.$animationsEnabled.sink { [weak self] in
      self?.animationsToggle.state = $0 ? .on : .off
    }
    .store(in: &animationCancellables)
  }

  private func apply(_ dock: DockSettings) {
    sizeSlider.setValue(dock.dockSize)
    spacingSlider.setValue(dock.widgetSpacing)
    cornerSlider.setValue(dock.cornerRadius)
    fitControl.selectedSegment = 0
    colorControl.selectedSegment = dock.monochromeWidgets ? 1 : 0
    tileToggle.state = dock.tileBackgrounds ? .on : .off
    shadowToggle.state = dock.dockShadow ? .on : .off
    iconStylePopUp.selectItem(at: dock.grayscaleIcons ? 1 : 0)
    transparencyToggle.state = dock.reduceTransparency ? .on : .off
  }

  @objc private func fitChanged() {
    viewModel.setAdaptsToFit(fitControl.selectedSegment == 0)
  }

  @objc private func colorChanged() {
    viewModel.setMonochromeWidgets(colorControl.selectedSegment == 1)
  }

  @objc private func tileChanged() {
    viewModel.setTileBackgrounds(tileToggle.state == .on)
  }

  @objc private func shadowChanged() {
    viewModel.setDockShadow(shadowToggle.state == .on)
  }

  @objc private func iconStyleChanged() {
    viewModel.setGrayscaleIcons(iconStylePopUp.indexOfSelectedItem == 1)
  }

  @objc private func transparencyChanged() {
    viewModel.setReduceTransparency(transparencyToggle.state == .on)
  }

  @objc private func animationsChanged() {
    viewModel.setAnimationsEnabled(animationsToggle.state == .on)
  }
}
