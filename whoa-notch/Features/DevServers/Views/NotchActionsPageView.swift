import AppKit

/// Page Actions : des commandes à lancer, ajoutées à la main (nom, commande, dossier) ou lues dans
/// le `package.json` d'un projet (bouton « projet »). Les actions d'un même dossier se groupent
/// sous son nom ; chacune a un bouton qui la lance ou, tant qu'elle tourne, l'arrête.
final class NotchActionsPageView: NSView, NotchAnalyticsPage {

  var pageTitle: String { "Actions" }
  var pageSymbol: String { "play.rectangle" }
  var pageView: NSView { self }
  var acceptsTyping: Bool { true }

  var commands = DevServersCommands()

  private let nameField = NotchDevFieldView(placeholder: "Action name")
  private let commandField = NotchDevFieldView(placeholder: "Command", monospaced: true)
  private let folderButton = NotchUsageIconButton(
    symbolName: "folder", description: "Choose the working folder")
  private let projectButton = NotchUsageIconButton(
    symbolName: "shippingbox", description: "Add scripts from a project's package.json")
  private let addButton = NotchUsageIconButton(symbolName: "plus.circle.fill", description: "Add")
  private let list = NotchDevListView()
  private let emptyLabel = NSTextField(
    wrappingLabelWithString: "No action yet. Type a command above, or add a project to get its package.json scripts.")
  private var directory: String?
  private var state = DevServersState()
  /// Les gestes du menu des scripts, gardés le temps que le menu s'affiche.
  private var menuHandlers: [MenuHandler] = []

  private let fieldGap: CGFloat = 8
  private let buttonSize: CGFloat = 28

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    list.rowHeight = 54
    emptyLabel.font = .systemFont(ofSize: 12.5)
    emptyLabel.textColor = NSColor.white.withAlphaComponent(0.45)
    emptyLabel.alignment = .center
    [nameField, commandField, folderButton, projectButton, addButton, list, emptyLabel]
      .forEach(addSubview)
    nameField.onSubmit = { [weak self] in self?.commandField.focus() }
    commandField.onSubmit = { [weak self] in self?.submit() }
    addButton.onClick = { [weak self] in self?.submit() }
    folderButton.onClick = { [weak self] in self?.chooseFolder() }
    projectButton.onClick = { [weak self] in self?.addProject() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ newState: DevServersState) {
    guard newState.actions != state.actions || newState.servers != state.servers else { return }
    state = newState
    reload()
  }

  private func reload() {
    emptyLabel.isHidden = !state.actions.isEmpty
    var rows: [NSView] = []
    // Les actions sans dossier d'abord, puis une section par dossier.
    rows += state.actions.filter { $0.directory == nil }.map(makeRow)
    let byDirectory = Dictionary(
      grouping: state.actions.filter { $0.directory != nil }, by: { $0.directory ?? "" })
    let directories = byDirectory.keys.sorted {
      ($0 as NSString).lastPathComponent.localizedCaseInsensitiveCompare(
        ($1 as NSString).lastPathComponent) == .orderedAscending
    }
    for path in directories {
      rows.append(
        NotchDetectedGroupRowView(
          name: (path as NSString).lastPathComponent, path: path, isSystem: false))
      rows += (byDirectory[path] ?? []).map(makeRow)
    }
    list.setRows(rows)
  }

  private func makeRow(_ action: DevAction) -> NSView {
    let row = NotchActionRowView(
      action: action, isRunning: state.server(for: action)?.isRunning == true)
    row.onToggle = { [weak self] running in
      if running { self?.commands.stop(action.id) } else { self?.commands.run(action.id) }
    }
    row.onDelete = { [weak self] in self?.commands.delete(action.id) }
    return row
  }

  // MARK: - Saisie

  private func submit() {
    let command = commandField.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !command.isEmpty else { return }
    commands.add(nameField.text, command, directory)
    nameField.text = ""
    commandField.text = ""
    directory = nil
    updateFolderTint()
    nameField.focus()
  }

  /// Ouvre un sélecteur de dossier au-dessus du panneau de l'encoche.
  private func pickFolder(prompt: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = prompt
    // Le panneau de l'encoche est au-dessus des fenêtres ordinaires : la fenêtre de choix doit l'être aussi.
    panel.level = NSWindow.Level(rawValue: (window?.level.rawValue ?? 0) + 1)
    NSApp.activate()
    guard panel.runModal() == .OK else { return nil }
    return panel.url?.path
  }

  private func chooseFolder() {
    guard let path = pickFolder(prompt: "Choose") else { return }
    directory = path
    updateFolderTint()
  }

  private func updateFolderTint() {
    folderButton.toolTip =
      directory.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Choose the working folder"
    folderButton.alphaValue = directory == nil ? 1 : 0.6
  }

  // MARK: - Projet

  /// Choisit un projet, puis propose ses scripts : un seul, ou tous. Ils deviennent des actions
  /// dans le dossier du projet.
  private func addProject() {
    guard let path = pickFolder(prompt: "Add project") else { return }
    let scripts = PackageScripts.read(in: path)
    let known = Set(state.actions.filter { $0.directory == path }.map(\.command))
    let menu = NSMenu()
    menuHandlers = []
    guard !scripts.isEmpty else {
      let item = NSMenuItem(title: "No scripts in package.json", action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: projectButton.bounds.height), in: projectButton)
      return
    }
    let entries = scripts.map { script in
      (script, PackageScripts.command(for: script.name, in: path))
    }
    func add(_ chosen: [(PackageScripts.Script, String)]) {
      for (script, command) in chosen where !known.contains(command) {
        commands.add(script.name, command, path)
      }
    }
    let all = menuItem(title: "Add all scripts (\(entries.count))") { add(entries) }
    menu.addItem(all)
    menu.addItem(.separator())
    for entry in entries {
      let title = "\(entry.0.name) — \(entry.0.body)"
      let item = menuItem(title: title.count > 70 ? String(title.prefix(69)) + "…" : title) {
        add([entry])
      }
      item.state = known.contains(entry.1) ? .on : .off
      menu.addItem(item)
    }
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: projectButton.bounds.height), in: projectButton)
  }

  private final class MenuHandler: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
  }

  private func menuItem(title: String, _ run: @escaping () -> Void) -> NSMenuItem {
    let handler = MenuHandler(run)
    menuHandlers.append(handler)
    let item = NSMenuItem(title: title, action: #selector(MenuHandler.fire), keyEquivalent: "")
    item.target = handler
    return item
  }

  override func layout() {
    super.layout()
    let formY = bounds.maxY - NotchDevFieldView.height
    let buttons = buttonSize * 3 + fieldGap * 3
    let fieldsWidth = max(0, bounds.width - buttons - fieldGap)
    let nameWidth = fieldsWidth * 0.4
    nameField.frame = NSRect(
      x: 0, y: formY, width: nameWidth, height: NotchDevFieldView.height)
    commandField.frame = NSRect(
      x: nameField.frame.maxX + fieldGap, y: formY, width: fieldsWidth - nameWidth,
      height: NotchDevFieldView.height)
    folderButton.frame = NSRect(
      x: commandField.frame.maxX + fieldGap, y: formY, width: buttonSize,
      height: NotchDevFieldView.height)
    projectButton.frame = NSRect(
      x: folderButton.frame.maxX + fieldGap, y: formY, width: buttonSize,
      height: NotchDevFieldView.height)
    addButton.frame = NSRect(
      x: projectButton.frame.maxX + fieldGap, y: formY, width: buttonSize,
      height: NotchDevFieldView.height)
    let listTop = formY - 10
    list.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, listTop))
    emptyLabel.frame = NSRect(
      x: 24, y: listTop / 2 - 20, width: max(0, bounds.width - 48), height: 40)
  }
}

extension NotchDevFieldView {
  /// Met le curseur dans le champ.
  func focus() {
    window?.makeFirstResponder(subviews.first)
  }
}

/// Une action : son nom, sa commande et le bouton qui la lance ou l'arrête.
private final class NotchActionRowView: NotchDevRowView {

  var onToggle: ((_ isRunning: Bool) -> Void)?
  var onDelete: (() -> Void)?

  private let nameLabel = NSTextField(labelWithString: "")
  private let commandLabel = NSTextField(labelWithString: "")
  private let toggle: NotchUsageIconButton
  private let isRunning: Bool

  init(action: DevAction, isRunning: Bool) {
    self.isRunning = isRunning
    toggle = NotchUsageIconButton(
      symbolName: isRunning ? "stop.fill" : "play.fill",
      description: isRunning ? "Stop \(action.name)" : "Run \(action.name)")
    super.init(frame: .zero)
    nameLabel.stringValue = action.name
    nameLabel.font = .systemFont(ofSize: 15, weight: .medium)
    nameLabel.textColor = .white
    nameLabel.lineBreakMode = .byTruncatingTail
    commandLabel.stringValue = ">_ " + action.command
    commandLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    commandLabel.textColor = NSColor.white.withAlphaComponent(0.7)
    commandLabel.lineBreakMode = .byTruncatingMiddle
    [nameLabel, commandLabel, toggle].forEach(addSubview)
    toggle.onClick = { [weak self] in
      guard let self else { return }
      onToggle?(self.isRunning)
    }
    if let directory = action.directory {
      toolTip = (directory as NSString).abbreviatingWithTildeInPath
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = NSMenu()
    let item = NSMenuItem(title: "Delete", action: #selector(deleteAction), keyEquivalent: "")
    item.target = self
    menu.addItem(item)
    return menu
  }

  @objc private func deleteAction() { onDelete?() }

  override func layout() {
    super.layout()
    let button: CGFloat = 28
    toggle.frame = NSRect(
      x: bounds.maxX - button, y: (bounds.height - button) / 2, width: button, height: button)
    let textWidth = max(0, toggle.frame.minX - 12)
    let name = nameLabel.intrinsicContentSize.height
    let command = commandLabel.intrinsicContentSize.height
    let top = (bounds.height + name + command + 2) / 2
    nameLabel.frame = NSRect(x: 0, y: top - name, width: textWidth, height: name)
    commandLabel.frame = NSRect(x: 0, y: top - name - 2 - command, width: textWidth, height: command)
  }
}
