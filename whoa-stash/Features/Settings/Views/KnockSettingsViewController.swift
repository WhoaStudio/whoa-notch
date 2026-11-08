import AppKit
import Combine

/// Écran "Knock" : une action par motif de coups sur le châssis (simple, double) et la sensibilité.
final class KnockSettingsViewController: SettingsSectionViewController {

  private let viewModel = KnockSettingsViewModel()
  private var cancellable: AnyCancellable?

  private lazy var enabledCheckbox = NSButton.settingsCheckbox(
    "Enable knock detection", target: self, action: #selector(enabledChanged))
  private var dimmedRows: [SettingsFormRowView] = []
  private let sensitivitySlider = LabeledSliderView(minValue: 0, maxValue: 1, value: 0.7)
  private let accessibilityButton = NSButton(title: "", target: nil, action: nil)
  private let singlePopUp = NSPopUpButton()
  private let doublePopUp = NSPopUpButton()

  override func makeRows() -> [NSView] {
    sensitivitySlider.formatter = { String(format: "%.0f%%", $0 * 100) }
    sensitivitySlider.onChange = { [weak self] in self?.viewModel.setSensitivity($0) }

    accessibilityButton.bezelStyle = .rounded
    accessibilityButton.target = self
    accessibilityButton.action = #selector(accessibilityTapped)

    for popUp in [singlePopUp, doublePopUp] {
      KnockAction.allCases.forEach { popUp.addItem(withTitle: $0.displayName) }
      popUp.target = self
      popUp.action = #selector(actionChanged(_:))
    }

    let sensitivityRow = SettingsFormRowView(
      title: "Sensitivity", control: sensitivitySlider, caption: "Higher picks up lighter knocks")
    let singleRow = SettingsFormRowView(title: "Single knock", control: singlePopUp)
    let doubleRow = SettingsFormRowView(title: "Double knock", control: doublePopUp)
    dimmedRows = [sensitivityRow, singleRow, doubleRow]

    return [
      SettingsFormRowView(
        title: "Detection", control: enabledCheckbox,
        caption: "Knock on the Mac's body, next to the keyboard"),
      sensitivityRow,
      SettingsFormRowView(
        title: "Accessibility", control: accessibilityButton, caption: "Needed only by Lock screen"),
      makeSettingsDivider(),
      singleRow,
      doubleRow,
    ]
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    cancellable = viewModel.$settings.sink { [weak self] in self?.apply($0) }
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    refreshAccessibility()
  }

  private func apply(_ settings: KnockSettings) {
    enabledCheckbox.state = settings.enabled ? .on : .off
    sensitivitySlider.setValue(settings.sensitivity)
    singlePopUp.selectItem(at: KnockAction.allCases.firstIndex(of: settings.single) ?? 0)
    doublePopUp.selectItem(at: KnockAction.allCases.firstIndex(of: settings.double) ?? 0)
    for control in [singlePopUp, doublePopUp] { control.isEnabled = settings.enabled }
    dimmedRows.forEach { $0.isDimmed = !settings.enabled }
    refreshAccessibility()
  }

  private func refreshAccessibility() {
    let trusted = AccessibilityPermissionService.shared.isTrusted
    accessibilityButton.title = trusted ? "Granted" : "Grant access…"
    accessibilityButton.isEnabled = !trusted
  }

  @objc private func enabledChanged() {
    viewModel.setEnabled(enabledCheckbox.state == .on)
  }

  @objc private func actionChanged(_ sender: NSPopUpButton) {
    viewModel.setAction(
      KnockAction.allCases[sender.indexOfSelectedItem], taps: sender === singlePopUp ? 1 : 2)
  }

  @objc private func accessibilityTapped() {
    AccessibilityPermissionService.shared.requestAccess()
    AccessibilityPermissionService.shared.openSystemSettings()
  }
}
