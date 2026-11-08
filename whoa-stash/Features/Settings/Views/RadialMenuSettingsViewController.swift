import AppKit
import Combine
import UniformTypeIdentifiers

/// Écran "Radial Menu" : le bouton de souris qui l'ouvre et la liste ordonnée des éléments
/// (applis lancées, raccourcis de Raccourcis.app exécutés).
final class RadialMenuSettingsViewController: SettingsSectionViewController {

  private let viewModel = RadialMenuSettingsViewModel()
  private var cancellable: AnyCancellable?

  private lazy var enabledCheckbox = NSButton.settingsCheckbox(
    "Enable radial menu", target: self, action: #selector(enabledChanged))
  private let buttonPopUp = NSPopUpButton()
  private let accessibilityButton = NSButton(title: "", target: nil, action: nil)
  private let itemsStack = NSStackView()
  private lazy var addAppButton = NSButton(
    title: "Add app…", target: self, action: #selector(addAppTapped))
  private lazy var addShortcutButton = NSButton(
    title: "Add shortcut…", target: self, action: #selector(addShortcutTapped))
  private var dimmedRows: [SettingsFormRowView] = []

  override func makeRows() -> [NSView] {
    RadialMouseButton.allCases.forEach { buttonPopUp.addItem(withTitle: $0.displayName) }
    buttonPopUp.target = self
    buttonPopUp.action = #selector(buttonChanged)

    accessibilityButton.bezelStyle = .rounded
    accessibilityButton.target = self
    accessibilityButton.action = #selector(accessibilityTapped)

    let buttonRow = SettingsFormRowView(
      title: "Mouse button", control: buttonPopUp,
      caption:
        "Hold the button to open the menu under the cursor, move toward an item, release to run it. A short press keeps the menu open: click an item, or press Esc. Three fingers: rest three fingers on the trackpad to open it; it stays open until the cursor leaves the disk. Turn off three-finger swipes and drag in System Settings ▸ Trackpad first"
    )
    let itemsRow = SettingsFormRowView(
      title: "Items", control: makeItemsList(),
      caption: "Up to \(RadialMenuSettings.maxItems). The first one is at the top, then clockwise",
      alignsTop: true)
    dimmedRows = [buttonRow]

    return [
      SettingsFormRowView(
        title: "Radial menu", control: enabledCheckbox,
        caption: "The chosen mouse button no longer reaches other apps while this is on"),
      buttonRow,
      SettingsFormRowView(
        title: "Accessibility", control: accessibilityButton,
        caption: "Needed to catch the mouse button"),
      makeSettingsDivider(),
      itemsRow,
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

  private func apply(_ settings: RadialMenuSettings) {
    enabledCheckbox.state = settings.enabled ? .on : .off
    buttonPopUp.selectItem(at: RadialMouseButton.allCases.firstIndex(of: settings.button) ?? 0)
    buttonPopUp.isEnabled = settings.enabled
    dimmedRows.forEach { $0.isDimmed = !settings.enabled }
    addAppButton.isEnabled = !viewModel.isFull
    addShortcutButton.isEnabled = !viewModel.isFull
    refreshAccessibility()
    reloadItems(settings.items)
  }

  private func refreshAccessibility() {
    let trusted = AccessibilityPermissionService.shared.isTrusted
    accessibilityButton.title = trusted ? "Granted" : "Grant access…"
    accessibilityButton.isEnabled = !trusted
  }

  private func makeItemsList() -> NSView {
    addAppButton.bezelStyle = .rounded
    addShortcutButton.bezelStyle = .rounded
    itemsStack.orientation = .vertical
    itemsStack.alignment = .leading
    itemsStack.spacing = 6
    let buttons = NSStackView(views: [addAppButton, addShortcutButton])
    buttons.spacing = 8
    let container = NSStackView(views: [itemsStack, buttons])
    container.orientation = .vertical
    container.alignment = .leading
    container.spacing = 8
    return container
  }

  private func reloadItems(_ items: [RadialMenuItem]) {
    itemsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for (index, item) in items.enumerated() {
      let icon = NSImageView(image: Self.icon(for: item))
      icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
      icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
      let label = NSTextField(labelWithString: item.name)
      label.lineBreakMode = .byTruncatingTail
      label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      let kind = NSTextField(labelWithString: item.kind == .app ? "App" : "Shortcut")
      kind.textColor = .tertiaryLabelColor
      kind.font = .systemFont(ofSize: 11)
      let up = makeButton("chevron.up", "Move up", #selector(moveUpTapped(_:)), item.id)
      up.isEnabled = index > 0
      let down = makeButton("chevron.down", "Move down", #selector(moveDownTapped(_:)), item.id)
      down.isEnabled = index < items.count - 1
      let remove = makeButton(
        "minus.circle", "Remove \(item.name)", #selector(removeTapped(_:)), item.id)
      let row = NSStackView(views: [icon, label, kind, up, down, remove])
      row.spacing = 8
      itemsStack.addArrangedSubview(row)
    }
  }

  private func makeButton(_ symbol: String, _ description: String, _ action: Selector, _ id: String)
    -> NSButton
  {
    let button = NSButton(
      image: NSImage(systemSymbolName: symbol, accessibilityDescription: description) ?? NSImage(),
      target: self, action: action)
    button.isBordered = false
    button.identifier = NSUserInterfaceItemIdentifier(id)
    return button
  }

  private static func icon(for item: RadialMenuItem) -> NSImage {
    switch item.kind {
    case .app:
      return NSWorkspace.shared.icon(
        forFile: AppLauncher.resolveURL(item.pinnedApp)?.path ?? item.path)
    case .shortcut:
      return NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: item.name)
        ?? NSImage()
    }
  }

  @objc private func enabledChanged() { viewModel.setEnabled(enabledCheckbox.state == .on) }

  @objc private func buttonChanged() {
    viewModel.setButton(RadialMouseButton.allCases[buttonPopUp.indexOfSelectedItem])
  }

  @objc private func accessibilityTapped() {
    AccessibilityPermissionService.shared.requestAccess()
    AccessibilityPermissionService.shared.openSystemSettings()
  }

  @objc private func addAppTapped() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = true
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    guard panel.runModal() == .OK else { return }
    panel.urls.forEach { viewModel.addApp(at: $0) }
  }

  @objc private func addShortcutTapped() {
    Task { @MainActor in
      let names = await ShortcutsCatalog.names()
      let menu = NSMenu()
      if names.isEmpty {
        let empty = menu.addItem(
          withTitle: "No shortcuts found in Shortcuts.app", action: nil, keyEquivalent: "")
        empty.isEnabled = false
      }
      for name in names {
        let entry = NSMenuItem(
          title: name, action: #selector(shortcutChosen(_:)), keyEquivalent: "")
        entry.target = self
        menu.addItem(entry)
      }
      menu.popUp(
        positioning: nil, at: NSPoint(x: 0, y: addShortcutButton.bounds.height + 4),
        in: addShortcutButton)
    }
  }

  @objc private func shortcutChosen(_ sender: NSMenuItem) {
    viewModel.add(.shortcut(named: sender.title))
  }

  @objc private func removeTapped(_ sender: NSButton) {
    guard let id = sender.identifier?.rawValue else { return }
    viewModel.remove(id: id)
  }

  @objc private func moveUpTapped(_ sender: NSButton) {
    guard let id = sender.identifier?.rawValue else { return }
    viewModel.move(id: id, by: -1)
  }

  @objc private func moveDownTapped(_ sender: NSButton) {
    guard let id = sender.identifier?.rawValue else { return }
    viewModel.move(id: id, by: 1)
  }
}
