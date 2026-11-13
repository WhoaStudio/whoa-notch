import AppKit
import Combine

/// Écran "General" : lancement au démarrage, raccourci global, panneau de l'encoche, couleur
/// d'accent, translucidité des panneaux, animations, retour haptique et sonore, et remise à zéro. Ne
/// contient aucune logique — tout transite par `GeneralSettingsViewModel`.
final class GeneralSettingsViewController: SettingsSectionViewController {

  private let viewModel = GeneralSettingsViewModel()
  private var cancellable: AnyCancellable?
  private var notchPanelCancellable: AnyCancellable?
  private var spotifyCancellable: AnyCancellable?
  private var spotifyStatusCancellable: AnyCancellable?
  private var updateStatusCancellable: AnyCancellable?
  private var availableRelease: ReleaseInfo?

  private lazy var launchAtLoginCheckbox = NSButton.settingsCheckbox(
    "Launch at login", target: self, action: #selector(launchAtLoginChanged))
  private lazy var menuBarIconCheckbox = NSButton.settingsCheckbox(
    "Show menu bar icon", target: self, action: #selector(menuBarIconChanged))
  private lazy var notchPanelCheckbox = NSButton.settingsCheckbox(
    "Show notch panel", target: self, action: #selector(notchPanelChanged))
  private lazy var volumeDialCheckbox = NSButton.settingsCheckbox(
    "Show volume dial", target: self, action: #selector(volumeDialChanged))
  private lazy var edgeSliderCheckbox = NSButton.settingsCheckbox(
    "Show edge slider", target: self, action: #selector(edgeSliderChanged))
  private lazy var sidePanelCheckbox = NSButton.settingsCheckbox(
    "Show side panel", target: self, action: #selector(sidePanelChanged))
  private let opensOnClickSwitch = NSSwitch()
  private var edgeSliderCancellable: AnyCancellable?
  private lazy var tabCheckboxes: [(tab: NotchTab, button: SettingsToggle)] = NotchTab
    .switchableTabs.map { tab in
      let button = NSButton.settingsCheckbox(
        "\(tab.title)", target: self, action: #selector(tabChanged(_:)))
      button.identifier = NSUserInterfaceItemIdentifier(tab.title)
      return (tab, button)
    }
  private lazy var animationsCheckbox = NSButton.settingsCheckbox(
    "Enable animations", target: self, action: #selector(animationsChanged))
  private lazy var hapticCheckbox = NSButton.settingsCheckbox(
    "Enable haptic feedback", target: self, action: #selector(hapticChanged))
  private lazy var soundCheckbox = NSButton.settingsCheckbox(
    "Enable sound feedback", target: self, action: #selector(soundChanged))
  private lazy var buttonSoundCheckbox = NSButton.settingsCheckbox(
    "Enable button sound", target: self, action: #selector(buttonSoundChanged))

  private lazy var autoUpdateCheckbox = NSButton.settingsCheckbox(
    "Check for updates automatically", target: self, action: #selector(autoUpdateChanged))
  private let updateStatusLabel = NSTextField(labelWithString: "")
  private let updateButton = NSButton(title: "Check for Updates…", target: nil, action: nil)

  private let shortcutPopUp = SettingsKeyPopUp()
  private let accentChoice = SettingsChoiceView(
    items: AccentColor.allCases.map {
      (title: $0.displayName, visual: SettingsChoiceView.swatch(color: $0.color))
    },
    ringsOnSelect: true)
  private let notchlessStyleChoice = SettingsChoiceView(
    items: NotchPanelStyle.allCases.map {
      (title: $0.displayName, visual: SettingsChoiceView.thumbnail(style: $0))
    },
    ringsOnSelect: false)
  private var notchlessStyleRow: SettingsFormRowView?
  private let panelOpacitySlider = LabeledSliderView(minValue: 0.35, maxValue: 1, value: 1)
  private let spotifyClientIDField = NSTextField()
  private let spotifyStatusLabel = NSTextField(labelWithString: "")
  private let spotifyButton = NSButton(title: "Connect", target: nil, action: nil)

  override func makeSections() -> [NSView] {
    shortcutPopUp.target = self
    shortcutPopUp.action = #selector(shortcutChanged)
    GlobalShortcut.allCases.forEach { shortcutPopUp.addItem(withTitle: $0.displayName) }

    opensOnClickSwitch.target = self
    opensOnClickSwitch.action = #selector(opensOnClickChanged)

    accentChoice.onChange = { [weak self] in
      self?.viewModel.setAccentColor(AccentColor.allCases[$0])
    }
    notchlessStyleChoice.onChange = { [weak self] in
      self?.viewModel.setNotchlessStyle(NotchPanelStyle.allCases[$0])
    }

    panelOpacitySlider.formatter = { String(format: "%.0f%%", $0 * 100) }
    panelOpacitySlider.onChange = { [weak self] in self?.viewModel.setPanelOpacity($0) }

    spotifyClientIDField.placeholderString = "Client ID"
    spotifyClientIDField.delegate = self
    spotifyClientIDField.target = self
    spotifyClientIDField.action = #selector(spotifyClientIDChanged)
    spotifyClientIDField.translatesAutoresizingMaskIntoConstraints = false
    spotifyClientIDField.widthAnchor.constraint(equalToConstant: 250).isActive = true

    spotifyStatusLabel.font = .systemFont(ofSize: 11)
    spotifyStatusLabel.textColor = .secondaryLabelColor
    spotifyButton.target = self
    spotifyButton.action = #selector(spotifyButtonTapped)
    spotifyButton.bezelStyle = .rounded
    let spotifyAccessory = NSStackView(views: [spotifyStatusLabel, spotifyButton])
    spotifyAccessory.orientation = .horizontal
    spotifyAccessory.spacing = 10

    updateStatusLabel.font = .systemFont(ofSize: 11)
    updateStatusLabel.textColor = .secondaryLabelColor
    updateButton.target = self
    updateButton.action = #selector(updateButtonTapped)
    updateButton.bezelStyle = .rounded
    let updateAccessory = NSStackView(views: [updateStatusLabel, updateButton])
    updateAccessory.orientation = .horizontal
    updateAccessory.spacing = 10

    let resetButton = NSButton(title: "Reset…", target: self, action: #selector(resetTapped))
    resetButton.bezelStyle = .rounded
    let onboardingButton = NSButton(
      title: "Show", target: self, action: #selector(showOnboardingTapped))
    onboardingButton.bezelStyle = .rounded

    let styleRow = SettingsFormRowView(
      title: "Style without notch", control: notchlessStyleChoice, alignsTop: true)
    notchlessStyleRow = styleRow
    let opensOnClickRow = SettingsFormRowView(
      title: "Open on click", control: opensOnClickSwitch,
      caption: "Off: the notch opens when you hover it. On: it opens only when you click it.")
    opensOnClickSwitch.controlSize = .regular

    return [
      SettingsGroupView(
        title: "Startup",
        rows: [
          SettingsFormRowView(toggle: launchAtLoginCheckbox),
          SettingsFormRowView(title: "Toggle shortcut", control: shortcutPopUp),
        ]),
      SettingsGroupView(
        title: "Surfaces",
        rows: [
          SettingsFormRowView(toggle: notchPanelCheckbox),
          SettingsFormRowView(toggle: sidePanelCheckbox),
          SettingsFormRowView(toggle: volumeDialCheckbox),
          SettingsFormRowView(toggle: edgeSliderCheckbox),
        ]),
      SettingsGroupView(
        title: "Notch panel",
        rows: [opensOnClickRow] + tabCheckboxes.map { SettingsFormRowView(toggle: $0.button) } + [
          styleRow
        ],
        footer: "Choose which tabs appear in the notch panel."),
      SettingsGroupView(
        title: "Appearance",
        rows: [
          SettingsFormRowView(title: "Accent color", control: accentChoice, alignsTop: true),
          SettingsFormRowView(title: "Panel opacity", control: panelOpacitySlider),
        ]),
      SettingsGroupView(
        title: "Feedback",
        rows: [
          SettingsFormRowView(toggle: animationsCheckbox),
          SettingsFormRowView(toggle: hapticCheckbox),
          SettingsFormRowView(toggle: soundCheckbox),
          SettingsFormRowView(toggle: buttonSoundCheckbox),
        ]),
      SettingsGroupView(
        title: "Spotify",
        rows: [
          SettingsFormRowView(
            title: "Client ID", control: spotifyClientIDField,
            caption:
              "For the Playing Next list. Create an app on developer.spotify.com and add the redirect URI \(SpotifyAuthorizer.redirectURI)."
          ),
          SettingsFormRowView(title: "Spotify account", control: spotifyAccessory),
        ]),
      SettingsGroupView(
        title: "Updates",
        rows: [
          SettingsFormRowView(toggle: autoUpdateCheckbox),
          SettingsFormRowView(title: "Latest version", control: updateAccessory),
        ]),
      SettingsGroupView(
        title: "System",
        rows: [
          SettingsFormRowView(
            toggle: menuBarIconCheckbox,
            caption:
              "Off: Whoa Notch has no menu bar item. Open Preferences from a panel's context menu."),
          SettingsFormRowView(title: "Show Onboarding", control: onboardingButton),
          SettingsFormRowView(
            title: "Reset Whoa Notch", control: resetButton,
            caption: "Restores default settings."),
        ]),
    ]
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    cancellable = viewModel.$settings.sink { [weak self] in self?.apply($0) }
    spotifyCancellable = viewModel.$spotify.sink { [weak self] in
      guard let self, spotifyClientIDField.currentEditor() == nil else { return }
      spotifyClientIDField.stringValue = $0.clientID
    }
    spotifyStatusCancellable = viewModel.$spotifyStatus.sink { [weak self] in
      self?.apply(spotifyStatus: $0)
    }
    updateStatusCancellable = UpdateChecker.shared.$status.sink { [weak self] in
      self?.apply(updateStatus: $0)
    }
    edgeSliderCancellable = viewModel.$edgeSlider.sink { [weak self] in
      self?.edgeSliderCheckbox.state = $0.enabled ? .on : .off
    }
    notchPanelCancellable = viewModel.$notchPanel.sink { [weak self] in
      let disabled = NotchTab.tabs(named: $0.disabledTabs)
      self?.tabCheckboxes.forEach { $0.button.state = disabled.contains($0.tab) ? .off : .on }
      self?.notchPanelCheckbox.state = $0.enabled ? .on : .off
      self?.opensOnClickSwitch.state = $0.opensOnClick ? .on : .off
      self?.opensOnClickSwitch.isEnabled = $0.enabled
      self?.notchlessStyleChoice.select(
        NotchPanelStyle.allCases.firstIndex(of: $0.notchlessStyle) ?? 0)
      self?.notchlessStyleRow?.isDimmed = !$0.enabled
    }
  }

  private func apply(updateStatus status: UpdateChecker.Status) {
    availableRelease = nil
    updateButton.isEnabled = true
    updateButton.title = "Check for Updates…"
    switch status {
    case .idle: updateStatusLabel.stringValue = ""
    case .checking:
      updateStatusLabel.stringValue = "Checking…"
      updateButton.isEnabled = false
    case .upToDate: updateStatusLabel.stringValue = "Up to date"
    case .available(let release):
      availableRelease = release
      updateStatusLabel.stringValue = "\(release.version) available"
      updateButton.title = "Download…"
    case .failed: updateStatusLabel.stringValue = "Could not check"
    }
  }

  private func apply(spotifyStatus status: SpotifyAccount.Status) {
    switch status {
    case .disconnected:
      spotifyStatusLabel.stringValue = "Not connected"
      spotifyButton.title = "Connect"
      spotifyButton.isEnabled = true
    case .connecting:
      spotifyStatusLabel.stringValue = "Waiting for your browser…"
      spotifyButton.title = "Connecting…"
      spotifyButton.isEnabled = false
    case .connected:
      spotifyStatusLabel.stringValue = "Connected"
      spotifyButton.title = "Disconnect"
      spotifyButton.isEnabled = true
    case .failed(let message):
      spotifyStatusLabel.stringValue = message
      spotifyButton.title = "Connect"
      spotifyButton.isEnabled = true
    }
  }

  private func apply(_ settings: GeneralSettings) {
    launchAtLoginCheckbox.state = settings.launchAtLogin ? .on : .off
    autoUpdateCheckbox.state = settings.autoCheckForUpdates ? .on : .off
    menuBarIconCheckbox.state = settings.showMenuBarIcon ? .on : .off
    volumeDialCheckbox.state = settings.volumeDialEnabled ? .on : .off
    sidePanelCheckbox.state = settings.sidePanelEnabled ? .on : .off
    accentChoice.select(AccentColor.allCases.firstIndex(of: settings.accentColor) ?? 0)
    animationsCheckbox.state = settings.enableAnimations ? .on : .off
    hapticCheckbox.state = settings.enableHapticFeedback ? .on : .off
    soundCheckbox.state = settings.enableSoundFeedback ? .on : .off
    buttonSoundCheckbox.state = settings.enableButtonSound ? .on : .off
    panelOpacitySlider.setValue(settings.panelOpacity)
    shortcutPopUp.selectItem(
      at: GlobalShortcut.allCases.firstIndex(of: settings.togglePanelShortcut) ?? 0)
  }

  @objc private func autoUpdateChanged() {
    viewModel.setAutoCheckForUpdates(autoUpdateCheckbox.state == .on)
  }

  @objc private func updateButtonTapped() {
    if let release = availableRelease {
      NSWorkspace.shared.open(release.url)
    } else {
      UpdateChecker.shared.checkNow()
    }
  }

  @objc private func launchAtLoginChanged() {
    viewModel.setLaunchAtLogin(launchAtLoginCheckbox.state == .on)
  }

  @objc private func menuBarIconChanged() {
    viewModel.setShowMenuBarIcon(menuBarIconCheckbox.state == .on)
  }

  @objc private func tabChanged(_ sender: NSSwitch) {
    guard let entry = tabCheckboxes.first(where: { $0.button.identifier == sender.identifier })
    else { return }
    viewModel.setTab(entry.tab, enabled: sender.state == .on)
  }

  @objc private func volumeDialChanged() {
    viewModel.setVolumeDialEnabled(volumeDialCheckbox.state == .on)
  }

  @objc private func edgeSliderChanged() {
    viewModel.setEdgeSliderEnabled(edgeSliderCheckbox.state == .on)
  }

  @objc private func sidePanelChanged() {
    viewModel.setSidePanelEnabled(sidePanelCheckbox.state == .on)
  }

  @objc private func animationsChanged() {
    viewModel.setEnableAnimations(animationsCheckbox.state == .on)
  }

  @objc private func hapticChanged() {
    viewModel.setEnableHapticFeedback(hapticCheckbox.state == .on)
  }

  @objc private func soundChanged() {
    viewModel.setEnableSoundFeedback(soundCheckbox.state == .on)
  }

  @objc private func buttonSoundChanged() {
    viewModel.setEnableButtonSound(buttonSoundCheckbox.state == .on)
  }

  @objc private func spotifyClientIDChanged() {
    viewModel.setSpotifyClientID(spotifyClientIDField.stringValue)
  }

  @objc private func spotifyButtonTapped() {
    if spotifyButton.title == "Disconnect" {
      viewModel.disconnectSpotify()
    } else {
      // L'identifiant tapé mais pas encore validé compte : on l'enregistre avant de se connecter.
      viewModel.setSpotifyClientID(spotifyClientIDField.stringValue)
      viewModel.connectSpotify()
    }
  }

  @objc private func opensOnClickChanged() {
    viewModel.setOpensOnClick(opensOnClickSwitch.state == .on)
  }

  @objc private func notchPanelChanged() {
    viewModel.setNotchPanelEnabled(notchPanelCheckbox.state == .on)
  }

  @objc private func shortcutChanged() {
    viewModel.setTogglePanelShortcut(GlobalShortcut.allCases[shortcutPopUp.indexOfSelectedItem])
  }

  @objc private func showOnboardingTapped() {
    OnboardingWindowController.shared.show()
  }

  /// Remise à zéro irréversible, donc confirmée : l'alerte est le seul endroit des
  /// Préférences où une action demande un accord avant d'agir.
  @objc private func resetTapped() {
    let alert = NSAlert()
    alert.messageText = "Restore default settings?"
    alert.informativeText = "Every setting goes back to its original value. This cannot be undone."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Reset")
    alert.addButton(withTitle: "Cancel")

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    viewModel.resetToDefaults()
  }
}

extension GeneralSettingsViewController: NSTextFieldDelegate {
  /// Enregistre l'identifiant quand on quitte le champ, sans attendre Entrée.
  func controlTextDidEndEditing(_ notification: Notification) {
    guard (notification.object as? NSTextField) === spotifyClientIDField else { return }
    spotifyClientIDChanged()
  }
}
