import AppKit
import Combine

/// Écran "Dock" : afficher le dock personnalisé, son thème, son raccourci, les applis épinglées et
/// le masquage du Dock macOS. L'apparence (taille, coins, ombre) est dans « Appearance ».
final class DockSettingsViewController: SettingsSectionViewController {

  private let viewModel = DockSettingsViewModel()
  private var cancellable: AnyCancellable?

  private lazy var enabledCheckbox = NSButton.settingsCheckbox(
    "Show dock", target: self, action: #selector(enabledChanged))
  private lazy var hideSystemCheckbox = NSButton.settingsCheckbox(
    "Hide macOS Dock", target: self, action: #selector(hideSystemChanged))
  private let accessibilityButton = NSButton(title: "", target: nil, action: nil)
  private let hotkeyRecorder = HotkeyRecorderView()
  private let themePopUp = NSPopUpButton()
  private var picker: AppPickerView?

  override func makeSections() -> [NSView] {
    accessibilityButton.bezelStyle = .rounded
    accessibilityButton.target = self
    accessibilityButton.action = #selector(accessibilityTapped)
    themePopUp.target = self
    themePopUp.action = #selector(themeChanged)
    themePopUp.menu?.autoenablesItems = false
    for theme in DockTheme.allCases {
      themePopUp.addItem(withTitle: theme.displayName)
      guard !theme.isAvailable, let item = themePopUp.lastItem else { continue }
      item.isEnabled = false
      item.badge = NSMenuItemBadge(string: "Coming soon...")
    }
    hotkeyRecorder.onChange = { [weak self] in self?.viewModel.setToggleHotkey($0) }

    let picker = AppPickerView(apps: InstalledApps.scan(), size: NSSize(width: 460, height: 400))
    picker.onToggle = { [weak self] app, on in
      self?.viewModel.setPinnedApp(app.pinned, selected: on)
    }
    self.picker = picker

    return [
      SettingsGroupView(rows: [
        SettingsFormRowView(
          toggle: enabledCheckbox,
          caption: "Pinned and running apps at the bottom of the screen"),
        SettingsFormRowView(
          title: "Theme", control: themePopUp,
          caption:
            "Dark keeps the solid background; Liquid Glass shows the desktop through the dock"),
        SettingsFormRowView(
          title: "Hotkey", control: hotkeyRecorder,
          caption:
            "Click a modifier to switch it on or off, then click the last tile and press a key. Shows or hides the dock from anywhere",
          alignsTop: true),
      ]),
      SettingsGroupView(rows: [
        SettingsFormRowView(
          title: "Apps", control: picker,
          caption:
            "Click an app to pin it to the dock. Pinned apps are the ones Launch all opens in the notch panel",
          alignsTop: true)
      ]),
      SettingsGroupView(
        title: "macOS Dock",
        rows: [
          SettingsFormRowView(
            toggle: hideSystemCheckbox,
            caption:
              "Turns on auto-hide with a very long delay. Restored when turned off and when Whoa Notch quits"
          ),
          SettingsFormRowView(
            title: "Accessibility", control: accessibilityButton,
            caption: "Needed to bring back minimised windows"),
        ]),
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

  private func apply(_ settings: DockSettings) {
    enabledCheckbox.state = settings.enabled ? .on : .off
    hideSystemCheckbox.state = settings.hideSystemDock ? .on : .off
    let shown = settings.theme.isAvailable ? settings.theme : .dark
    themePopUp.selectItem(at: DockTheme.allCases.firstIndex(of: shown) ?? 0)
    hotkeyRecorder.setHotkey(settings.toggleHotkey)
    picker?.setSelected(Set(settings.pinnedApps.map(\.bundleID)))
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

  @objc private func themeChanged() {
    viewModel.setTheme(DockTheme.allCases[themePopUp.indexOfSelectedItem])
  }

  @objc private func hideSystemChanged() {
    viewModel.setHideSystemDock(hideSystemCheckbox.state == .on)
  }

  @objc private func accessibilityTapped() {
    AccessibilityPermissionService.shared.requestAccess()
    AccessibilityPermissionService.shared.openSystemSettings()
  }
}
