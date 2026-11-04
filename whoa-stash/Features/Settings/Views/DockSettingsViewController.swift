import AppKit
import Combine
import UniformTypeIdentifiers

/// Écran "Dock" : afficher le dock personnalisé et masquer le Dock macOS.
final class DockSettingsViewController: SettingsSectionViewController {

    private let viewModel = DockSettingsViewModel()
    private var cancellable: AnyCancellable?

    private lazy var enabledCheckbox = NSButton.settingsCheckbox(
        "Show dock", target: self, action: #selector(enabledChanged))
    private lazy var autoHideCheckbox = NSButton.settingsCheckbox(
        "Hide automatically", target: self, action: #selector(autoHideChanged))
    private lazy var magnificationCheckbox = NSButton.settingsCheckbox(
        "Magnify icons", target: self, action: #selector(magnificationChanged))
    private lazy var hideSystemCheckbox = NSButton.settingsCheckbox(
        "Hide macOS Dock", target: self, action: #selector(hideSystemChanged))
    private let accessibilityButton = NSButton(title: "", target: nil, action: nil)
    private let hotkeyRecorder = HotkeyRecorderView()
    private let appsStack = NSStackView()
    private let themePopUp = NSPopUpButton()
    private lazy var addAppButton = NSButton(title: "Add app…", target: self, action: #selector(addAppTapped))

    override func makeRows() -> [NSView] {
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

        return [
            SettingsFormRowView(title: "Dock", control: enabledCheckbox, caption: "Pinned and running apps at the bottom of the screen"),
            SettingsFormRowView(
                title: "Auto-hide", control: autoHideCheckbox,
                caption: "The dock slides away and comes back when the cursor touches the bottom edge, in the middle of the screen"),
            SettingsFormRowView(
                title: "Magnification", control: magnificationCheckbox,
                caption: "Icons grow under the cursor. The enlarged size is the one set for the macOS Dock"),
            SettingsFormRowView(title: "Theme", control: themePopUp, caption: "Dark keeps the solid background; Liquid Glass shows the desktop through the dock"),
            SettingsFormRowView(
                title: "Hotkey", control: hotkeyRecorder, caption: "Click a modifier to switch it on or off, then click the last tile and press a key. Shows or hides the dock from anywhere", alignsTop: true),
            SettingsFormRowView(
                title: "macOS Dock", control: hideSystemCheckbox,
                caption: "Turns on auto-hide with a very long delay. Restored when turned off and when Whoa Stash quits"),
            makeSettingsDivider(),
            SettingsFormRowView(
                title: "Apps", control: makeAppsList(),
                caption: "Ticked apps are opened by the Launch all button in the notch panel. Same list as the pinned apps in the dock"),
            makeSettingsDivider(),
            SettingsFormRowView(
                title: "Accessibility", control: accessibilityButton,
                caption: "Needed to bring back minimised windows"),
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
        autoHideCheckbox.state = settings.autoHide ? .on : .off
        magnificationCheckbox.state = settings.magnification ? .on : .off
        let shown = settings.theme.isAvailable ? settings.theme : .dark
        themePopUp.selectItem(at: DockTheme.allCases.firstIndex(of: shown) ?? 0)
        hotkeyRecorder.setHotkey(settings.toggleHotkey)
        refreshAccessibility()
        reloadApps(settings)
    }

    private func makeAppsList() -> NSView {
        addAppButton.bezelStyle = .rounded
        appsStack.orientation = .vertical
        appsStack.alignment = .leading
        appsStack.spacing = 6
        let container = NSStackView(views: [appsStack, addAppButton])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        return container
    }

    private func reloadApps(_ settings: DockSettings) {
        appsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for app in settings.pinnedApps {
            let name = DockModel.displayName(path: app.path)
            let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: app.path))
            icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
            let label = NSTextField(labelWithString: name)
            let include = NSButton(checkboxWithTitle: "", target: self, action: #selector(includeTapped(_:)))
            include.state = settings.launchExcluded.contains(app.bundleID) ? .off : .on
            include.identifier = NSUserInterfaceItemIdentifier(app.bundleID)
            include.toolTip = "Open with Launch all"
            let remove = NSButton(
                image: NSImage(systemSymbolName: "minus.circle", accessibilityDescription: "Remove \(name)") ?? NSImage(),
                target: self, action: #selector(removeAppTapped(_:)))
            remove.isBordered = false
            remove.identifier = NSUserInterfaceItemIdentifier(app.bundleID)
            let row = NSStackView(views: [include, icon, label, remove])
            row.spacing = 8
            appsStack.addArrangedSubview(row)
        }
    }

    @objc private func addAppTapped() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { viewModel.addApp(at: $0) }
    }

    @objc private func includeTapped(_ sender: NSButton) {
        guard let bundleID = sender.identifier?.rawValue else { return }
        viewModel.setLaunchIncluded(sender.state == .on, bundleID: bundleID)
    }

    @objc private func removeAppTapped(_ sender: NSButton) {
        guard let bundleID = sender.identifier?.rawValue else { return }
        viewModel.removeApp(bundleID: bundleID)
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

    @objc private func autoHideChanged() {
        viewModel.setAutoHide(autoHideCheckbox.state == .on)
    }

    @objc private func magnificationChanged() {
        viewModel.setMagnification(magnificationCheckbox.state == .on)
    }

    @objc private func hideSystemChanged() {
        viewModel.setHideSystemDock(hideSystemCheckbox.state == .on)
    }

    @objc private func accessibilityTapped() {
        AccessibilityPermissionService.shared.requestAccess()
        AccessibilityPermissionService.shared.openSystemSettings()
    }
}
