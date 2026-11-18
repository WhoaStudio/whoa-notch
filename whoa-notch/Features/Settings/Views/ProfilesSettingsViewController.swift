import AppKit
import Combine

/// Écran "Profiles" : créer un profil (nom, logo) et choisir ses applis.
final class ProfilesSettingsViewController: SettingsSectionViewController, NSTextFieldDelegate {

  private static let symbols: [(title: String, symbol: String)] = [
    ("Build", "hammer.fill"), ("Work", "briefcase.fill"), ("Home", "house.fill"),
    ("Play", "gamecontroller.fill"), ("Design", "paintbrush.pointed.fill"),
    ("Code", "chevron.left.forwardslash.chevron.right"), ("Music", "music.note"),
    ("Study", "book.fill"),
    ("Chat", "bubble.left.fill"), ("Media", "camera.fill"), ("Shop", "cart.fill"),
    ("Focus", "bolt.fill"),
    ("Web", "globe"), ("Favorites", "star.fill"), ("Apps", "square.grid.2x2.fill"),
    ("Mail", "envelope.fill"), ("Calendar", "calendar"), ("Notes", "note.text"),
    ("Photos", "photo.fill"),
    ("Movies", "film.fill"), ("Music Box", "headphones"), ("Terminal", "terminal.fill"),
    ("Cloud", "cloud.fill"),
    ("Ideas", "lightbulb.fill"), ("Tools", "wrench.and.screwdriver.fill"), ("Health", "heart.fill"),
    ("Travel", "airplane"), ("Sport", "figure.run"), ("Food", "fork.knife"),
    ("Nature", "leaf.fill"),
    ("Night", "moon.fill"), ("Alerts", "bell.fill"), ("Security", "lock.shield.fill"),
    ("Finance", "creditcard.fill"),
  ]

  private let viewModel = ProfilesSettingsViewModel.fromLaunchArguments() ?? ProfilesSettingsViewModel()
  private var cancellable: AnyCancellable?
  private var installed: [InstalledApp] = []

  private let profilePopUp = NSPopUpButton()
  private let newButton = NSButton(title: "New", target: nil, action: nil)
  private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
  private let nameField = NSTextField()
  private let symbolPopUp = NSPopUpButton()
  private lazy var activeCheckbox = NSButton.settingsCheckbox(
    "Show in the dock", target: self, action: #selector(activeChanged))
  private var picker: AppPickerView?
  private let widgetsView = ProfileWidgetsView()
  private let preview = DockPreviewView(size: NSSize(width: 460, height: 104))
  private var editingRows: [SettingsFormRowView] = []

  override func makeRows() -> [NSView] {
    newButton.bezelStyle = .rounded
    newButton.target = self
    newButton.action = #selector(newTapped)
    deleteButton.bezelStyle = .rounded
    deleteButton.target = self
    deleteButton.action = #selector(deleteTapped)
    profilePopUp.target = self
    for popUp in [profilePopUp, symbolPopUp] {
      // Largeur fixe : un titre qui change de longueur redimensionnait le bouton en laissant l'ancien texte peint.
      popUp.translatesAutoresizingMaskIntoConstraints = false
      popUp.widthAnchor.constraint(equalToConstant: 180).isActive = true
    }
    profilePopUp.action = #selector(profileSelected)

    let header = NSStackView(views: [profilePopUp, newButton, deleteButton])
    header.orientation = .horizontal
    header.spacing = 8

    nameField.delegate = self
    nameField.target = self
    nameField.action = #selector(nameChanged)
    nameField.translatesAutoresizingMaskIntoConstraints = false
    nameField.widthAnchor.constraint(equalToConstant: 200).isActive = true

    for entry in Self.symbols {
      symbolPopUp.addItem(withTitle: entry.title)
      symbolPopUp.lastItem?.image = NSImage(
        systemSymbolName: entry.symbol, accessibilityDescription: nil)
    }
    symbolPopUp.target = self
    symbolPopUp.action = #selector(symbolChanged)

    let nameRow = SettingsFormRowView(title: "Name", control: nameField)
    let logoRow = SettingsFormRowView(title: "Logo", control: symbolPopUp)
    let activeRow = SettingsFormRowView(title: "Dock", control: activeCheckbox)
    preview.onMove = { [weak self] id, index in
      self?.viewModel.moveEntry(id, toRemainingIndex: index)
    }
    preview.onInsertApp = { [weak self] app, index in
      self?.viewModel.insertApp(app, atRowIndex: index)
    }
    preview.onInsertWidget = { [weak self] kind, index in
      self?.viewModel.insertWidget(kind: kind, atRowIndex: index)
    }
    preview.onRemove = { [weak self] id in self?.viewModel.removeEntry(id) }
    let layoutRow = SettingsFormRowView(
      title: "Layout", control: preview,
      caption:
        "Drag to reorder. Drop an app from the list below or from Finder, or a widget from the buttons below, to add it. Drag an item out or click its cross to remove it",
      alignsTop: true)
    installed = InstalledApps.scan()
    let picker = AppPickerView(apps: installed, size: NSSize(width: 460, height: 400))
    picker.onToggle = { [weak self] app, on in self?.viewModel.setApp(app.pinned, selected: on) }
    self.picker = picker
    let appsRow = SettingsFormRowView(
      title: "Apps", control: picker, caption: "The apps this profile shows in the dock",
      alignsTop: true)
    widgetsView.onAdd = { [weak self] in self?.viewModel.addWidget(kind: $0) }
    let widgetsRow = SettingsFormRowView(
      title: "Widgets", control: widgetsView,
      caption:
        "Click to add a widget at the end of the dock, or drag it into the layout above to place it",
      alignsTop: true)
    editingRows = [nameRow, logoRow, activeRow, layoutRow, appsRow, widgetsRow]

    return [
      SettingsFormRowView(title: "Profile", control: header), makeSettingsDivider(), nameRow,
      logoRow, activeRow, makeSettingsDivider(), layoutRow, appsRow, widgetsRow,
    ]
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    cancellable = Publishers.CombineLatest(viewModel.$settings, viewModel.$selectedID)
      .sink { [weak self] settings, selectedID in self?.apply(settings, selectedID: selectedID) }
  }

  /// Prend les valeurs publiées : `@Published` émet avant d'écrire, le view model est encore à l'ancien état.
  private func apply(_ settings: DockSettings, selectedID: String?) {
    let profiles = settings.profiles
    if profilePopUp.itemTitles != profiles.map(\.name) {
      profilePopUp.removeAllItems()
      profiles.forEach { profilePopUp.addItem(withTitle: $0.name) }
    }
    let selected = selectedID.flatMap { id in profiles.first { $0.id == id } }
    if let selected, let index = profiles.firstIndex(where: { $0.id == selected.id }) {
      profilePopUp.selectItem(at: index)
    }
    profilePopUp.isEnabled = !profiles.isEmpty
    // Il en reste toujours un : le dock ne se retrouve jamais sans profil.
    deleteButton.isEnabled = selected != nil && profiles.count > 1
    editingRows.forEach { $0.isDimmed = selected == nil }
    [nameField, symbolPopUp].forEach { ($0 as? NSControl)?.isEnabled = selected != nil }
    activeCheckbox.isEnabled = selected != nil
    picker?.setEnabled(selected != nil)
    preview.setEnabled(selected != nil)
    widgetsView.setEnabled(selected != nil)

    guard let selected else {
      nameField.stringValue = ""
      picker?.setSelected([])
      preview.setContent(apps: [], widgets: [])
      return
    }
    if nameField.currentEditor() == nil { nameField.stringValue = selected.name }
    symbolPopUp.selectItem(at: Self.symbols.firstIndex { $0.symbol == selected.symbol } ?? 0)
    [profilePopUp, symbolPopUp].forEach {
      $0.synchronizeTitleAndSelectedItem()
      $0.needsDisplay = true
    }
    activeCheckbox.state = settings.activeProfileID == selected.id ? .on : .off
    picker?.setSelected(Set(selected.apps.map(\.bundleID)))
    preview.setContent(apps: selected.apps, widgets: selected.widgets)
  }

  @objc private func profileSelected() {
    let profiles = viewModel.settings.profiles
    let index = profilePopUp.indexOfSelectedItem
    guard profiles.indices.contains(index) else { return }
    viewModel.selectedID = profiles[index].id
  }

  @objc private func newTapped() { viewModel.create() }
  @objc private func deleteTapped() { viewModel.deleteSelected() }

  @objc private func nameChanged() {
    let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    viewModel.update { $0.name = name }
  }

  func controlTextDidEndEditing(_ notification: Notification) { nameChanged() }

  @objc private func symbolChanged() {
    viewModel.update { $0.symbol = Self.symbols[symbolPopUp.indexOfSelectedItem].symbol }
  }

  @objc private func activeChanged() { viewModel.setActive(activeCheckbox.state == .on) }
}
