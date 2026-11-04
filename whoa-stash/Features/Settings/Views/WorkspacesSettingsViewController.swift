import AppKit
import Combine

/// Écran "Workspaces" : créer un espace (nom, logo, couleur) et choisir ses applis.
final class WorkspacesSettingsViewController: SettingsSectionViewController, NSTextFieldDelegate {

    private static let symbols: [(title: String, symbol: String)] = [
        ("Build", "hammer.fill"), ("Work", "briefcase.fill"), ("Home", "house.fill"),
        ("Play", "gamecontroller.fill"), ("Design", "paintbrush.pointed.fill"),
        ("Code", "chevron.left.forwardslash.chevron.right"), ("Music", "music.note"), ("Study", "book.fill"),
        ("Chat", "bubble.left.fill"), ("Media", "camera.fill"), ("Shop", "cart.fill"), ("Focus", "bolt.fill"),
        ("Web", "globe"), ("Favorites", "star.fill"), ("Apps", "square.grid.2x2.fill"),
    ]

    private let viewModel = WorkspacesSettingsViewModel()
    private var cancellable: AnyCancellable?
    private var installed: [InstalledApp] = []

    private let workspacePopUp = NSPopUpButton()
    private let newButton = NSButton(title: "New", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let nameField = NSTextField()
    private let symbolPopUp = NSPopUpButton()
    private let colorWell = NSColorWell(style: .minimal)
    private lazy var activeCheckbox = NSButton.settingsCheckbox(
        "Show in the dock", target: self, action: #selector(activeChanged))
    private var picker: AppPickerView?
    private let widgetsView = WorkspaceWidgetsView()
    private let preview = DockPreviewView(size: NSSize(width: 460, height: 76))
    private var editingRows: [SettingsFormRowView] = []

    override func makeRows() -> [NSView] {
        newButton.bezelStyle = .rounded
        newButton.target = self
        newButton.action = #selector(newTapped)
        deleteButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        workspacePopUp.target = self
        for popUp in [workspacePopUp, symbolPopUp] {
            // Largeur fixe : un titre qui change de longueur redimensionnait le bouton en laissant l'ancien texte peint.
            popUp.translatesAutoresizingMaskIntoConstraints = false
            popUp.widthAnchor.constraint(equalToConstant: 180).isActive = true
        }
        workspacePopUp.action = #selector(workspaceSelected)

        let header = NSStackView(views: [workspacePopUp, newButton, deleteButton])
        header.orientation = .horizontal
        header.spacing = 8

        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(nameChanged)
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 200).isActive = true

        for entry in Self.symbols {
            symbolPopUp.addItem(withTitle: entry.title)
            symbolPopUp.lastItem?.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
        }
        symbolPopUp.target = self
        symbolPopUp.action = #selector(symbolChanged)

        colorWell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            colorWell.widthAnchor.constraint(equalToConstant: 56), colorWell.heightAnchor.constraint(equalToConstant: 28),
        ])
        colorWell.target = self
        colorWell.action = #selector(colorChanged)

        let nameRow = SettingsFormRowView(title: "Name", control: nameField)
        let logoRow = SettingsFormRowView(title: "Logo", control: symbolPopUp)
        let colorRow = SettingsFormRowView(title: "Color", control: colorWell)
        let activeRow = SettingsFormRowView(title: "Dock", control: activeCheckbox)
        preview.onPlace = { [weak self] app, index in self?.viewModel.placeApp(app, at: index) }
        preview.onRemove = { [weak self] app in self?.viewModel.setApp(app, selected: false) }
        let layoutRow = SettingsFormRowView(
            title: "Layout", control: preview,
            caption: "Drag to reorder. Drop an app from the list below to add it, drag an icon out to remove it", alignsTop: true)
        installed = InstalledApps.scan()
        let picker = AppPickerView(apps: installed, size: NSSize(width: 460, height: 400))
        picker.onToggle = { [weak self] app, on in self?.viewModel.setApp(app.pinned, selected: on) }
        self.picker = picker
        let appsRow = SettingsFormRowView(title: "Apps", control: picker, caption: "The apps this workspace shows in the dock", alignsTop: true)
        widgetsView.onAdd = { [weak self] in self?.viewModel.addWidget(kind: $0) }
        widgetsView.onRemove = { [weak self] in self?.viewModel.removeWidget(id: $0) }
        let widgetsRow = SettingsFormRowView(
            title: "Widgets", control: widgetsView,
            caption: "Widgets this workspace shows in the dock. Drag one in the dock to move it, or out of the dock to remove it", alignsTop: true)
        editingRows = [nameRow, logoRow, colorRow, activeRow, layoutRow, appsRow, widgetsRow]

        return [SettingsFormRowView(title: "Workspace", control: header), makeSettingsDivider(), nameRow, logoRow, colorRow, activeRow, makeSettingsDivider(), layoutRow, appsRow, widgetsRow]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        cancellable = Publishers.CombineLatest(viewModel.$settings, viewModel.$selectedID)
            .sink { [weak self] settings, selectedID in self?.apply(settings, selectedID: selectedID) }
    }

    /// Prend les valeurs publiées : `@Published` émet avant d'écrire, le view model est encore à l'ancien état.
    private func apply(_ settings: DockSettings, selectedID: String?) {
        let workspaces = settings.workspaces
        if workspacePopUp.itemTitles != workspaces.map(\.name) {
            workspacePopUp.removeAllItems()
            workspaces.forEach { workspacePopUp.addItem(withTitle: $0.name) }
        }
        let selected = selectedID.flatMap { id in workspaces.first { $0.id == id } }
        if let selected, let index = workspaces.firstIndex(where: { $0.id == selected.id }) {
            workspacePopUp.selectItem(at: index)
        }
        workspacePopUp.isEnabled = !workspaces.isEmpty
        // Il en reste toujours un : le dock ne se retrouve jamais sans espace.
        deleteButton.isEnabled = selected != nil && workspaces.count > 1
        editingRows.forEach { $0.isDimmed = selected == nil }
        [nameField, symbolPopUp, colorWell].forEach { ($0 as? NSControl)?.isEnabled = selected != nil }
        activeCheckbox.isEnabled = selected != nil
        picker?.setEnabled(selected != nil)
        preview.setEnabled(selected != nil)
        widgetsView.setEnabled(selected != nil)

        guard let selected else {
            nameField.stringValue = ""
            picker?.setSelected([])
            preview.setApps([])
            widgetsView.apply([])
            return
        }
        if nameField.currentEditor() == nil { nameField.stringValue = selected.name }
        symbolPopUp.selectItem(at: Self.symbols.firstIndex { $0.symbol == selected.symbol } ?? 0)
        [workspacePopUp, symbolPopUp].forEach {
            $0.synchronizeTitleAndSelectedItem()
            $0.needsDisplay = true
        }
        colorWell.color = NSColor(hex: selected.colorHex)
        activeCheckbox.state = settings.activeWorkspaceID == selected.id ? .on : .off
        picker?.setSelected(Set(selected.apps.map(\.bundleID)))
        preview.setApps(selected.apps)
        widgetsView.apply(selected.widgets)
    }

    @objc private func workspaceSelected() {
        let workspaces = viewModel.settings.workspaces
        let index = workspacePopUp.indexOfSelectedItem
        guard workspaces.indices.contains(index) else { return }
        viewModel.selectedID = workspaces[index].id
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

    @objc private func colorChanged() {
        viewModel.update { $0.colorHex = colorWell.color.hexString }
    }

    @objc private func activeChanged() { viewModel.setActive(activeCheckbox.state == .on) }
}
