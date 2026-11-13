import AppKit

/// Onglet Notes : la liste des notes à gauche, l'éditeur de texte brut à droite. La vue n'est
/// qu'une lecture des notes : `apply(notes:)` la repeint, et chaque action remonte par callback.
///
/// Gestes : survol d'une ligne pour la supprimer, balayage vers la gauche sur une ligne,
/// glisser une ligne (ou du texte sélectionné) vers une autre app. Raccourcis : ⌘N, ⇧⌘⌫, ⌥⌘↑/↓.
final class NotesTabView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {

  var onCreate: (() -> Void)?
  var onEdit: ((UUID, String) -> Void)?
  var onDelete: ((UUID) -> Void)?

  private let titleLabel = NSTextField(labelWithString: "Notes")
  private let countLabel = NSTextField(labelWithString: "")
  private let addButton = NSButton()
  private let deleteButton = NSButton()
  private let tableScroll = NSScrollView()
  private let table = NSTableView()
  private let divider = NSBox()
  private let editorBackdrop = NSView()
  private let editorScroll = NSScrollView()
  private let textView = NoteTextView(frame: .zero)
  private let emptyIcon = NSImageView()
  private let emptyTitle = NSTextField(labelWithString: "No notes yet")
  private let savedView = NSView()
  private let savedIcon = NSImageView()
  private let savedLabel = NSTextField(labelWithString: "Saved")
  private let undoPill = HomePillButton()

  private var notes: [Note] = []
  private var selectedID: UUID?
  /// Levé pendant qu'on repeint : les callbacks AppKit qui en résultent ne sont pas des actions.
  private var isApplying = false
  /// Levé pendant qu'une frappe crée la note : l'éditeur garde alors le texte tapé.
  private var keepsEditorText = false
  /// Dernière note supprimée, rendue par « Undo delete ».
  private var lastDeleted: Note?
  private var savedTask: Task<Void, Never>?
  private var undoTask: Task<Void, Never>?

  private let headerHeight: CGFloat = 28
  private let listWidth: CGFloat = 184
  private let rowHeight: CGFloat = 46

  private static let rowIdentifier = NSUserInterfaceItemIdentifier("noteRow")
  private static let rowBackgroundIdentifier = NSUserInterfaceItemIdentifier("noteRowBackground")

  fileprivate static let bodyFont = NSFont.systemFont(ofSize: 13)
  fileprivate static let headingFont = NSFont.systemFont(ofSize: 17, weight: .semibold)

  private static let bodyAttributes: [NSAttributedString.Key: Any] = [
    .font: bodyFont,
    .foregroundColor: NSColor.white.withAlphaComponent(0.92),
  ]

  fileprivate static let headingAttributes: [NSAttributedString.Key: Any] = {
    let paragraph = NSMutableParagraphStyle()
    paragraph.paragraphSpacing = 6
    return [
      .font: headingFont,
      .foregroundColor: NSColor.white,
      .paragraphStyle: paragraph,
    ]
  }()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private func setUp() {
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = .white
    addSubview(titleLabel)

    countLabel.wantsLayer = true
    countLabel.font = .systemFont(ofSize: 13)
    countLabel.textColor = .white.withAlphaComponent(0.4)
    addSubview(countLabel)

    configure(
      addButton, symbol: "square.and.pencil", description: "New note (⌘N)",
      action: #selector(addClicked))
    configure(
      deleteButton, symbol: "trash", description: "Delete note (⇧⌘⌫)",
      action: #selector(deleteClicked))

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
    column.resizingMask = .autoresizingMask
    table.addTableColumn(column)
    table.headerView = nil
    table.backgroundColor = .clear
    table.rowHeight = rowHeight
    table.style = .plain
    table.selectionHighlightStyle = .regular
    table.allowsEmptySelection = true
    table.allowsTypeSelect = false
    table.intercellSpacing = NSSize(width: 0, height: 2)
    table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    table.setDraggingSourceOperationMask(.copy, forLocal: false)
    table.setDraggingSourceOperationMask([], forLocal: true)
    table.dataSource = self
    table.delegate = self
    tableScroll.documentView = table
    tableScroll.drawsBackground = false
    tableScroll.hasVerticalScroller = false
    tableScroll.hasHorizontalScroller = false
    addSubview(tableScroll)

    divider.boxType = .separator
    addSubview(divider)

    // Fond discret qui apparaît quand l'éditeur a le clavier.
    editorBackdrop.wantsLayer = true
    editorBackdrop.layer?.cornerRadius = 10
    editorBackdrop.layer?.cornerCurve = .continuous
    editorBackdrop.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
    editorBackdrop.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
    editorBackdrop.layer?.borderWidth = 0.5
    editorBackdrop.layer?.opacity = 0
    addSubview(editorBackdrop)

    // Même réglage que `NSTextView.scrollableTextView()` : sans hauteur libre et sans
    // conteneur qui suit la largeur, le texte long ne défile pas.
    textView.minSize = .zero
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: 0, height: CGFloat.greatestFiniteMagnitude)
    textView.isRichText = false
    textView.allowsUndo = true
    textView.font = Self.bodyFont
    textView.typingAttributes = Self.bodyAttributes
    textView.insertionPointColor = .white
    textView.selectedTextAttributes = [
      .backgroundColor: NSColor.white.withAlphaComponent(0.22)
    ]
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 10, height: 10)
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.delegate = self
    textView.onFocusChanged = { [weak self] focused in self?.setEditorFocused(focused) }
    editorScroll.documentView = textView
    editorScroll.drawsBackground = false
    editorScroll.hasVerticalScroller = true
    editorScroll.autohidesScrollers = true
    editorScroll.scrollerStyle = .overlay
    editorScroll.verticalScroller?.knobStyle = .light
    editorScroll.wantsLayer = true
    addSubview(editorScroll)

    emptyIcon.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 24, weight: .light))
    emptyIcon.contentTintColor = .white.withAlphaComponent(0.3)
    emptyIcon.wantsLayer = true
    addSubview(emptyIcon)

    emptyTitle.font = .systemFont(ofSize: 12, weight: .medium)
    emptyTitle.textColor = .white.withAlphaComponent(0.4)
    emptyTitle.alignment = .center
    emptyTitle.wantsLayer = true
    addSubview(emptyTitle)

    savedIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
    savedIcon.contentTintColor = .white.withAlphaComponent(0.45)
    savedLabel.font = .systemFont(ofSize: 11)
    savedLabel.textColor = .white.withAlphaComponent(0.45)
    savedView.wantsLayer = true
    savedView.layer?.opacity = 0
    savedView.addSubview(savedIcon)
    savedView.addSubview(savedLabel)
    addSubview(savedView)

    undoPill.title = "Undo delete"
    undoPill.isHidden = true
    undoPill.onClick = { [weak self] in self?.undoDelete() }
    addSubview(undoPill)
  }

  private func configure(_ button: NSButton, symbol: String, description: String, action: Selector)
  {
    button.isBordered = false
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    button.contentTintColor = .white.withAlphaComponent(0.6)
    button.toolTip = description
    button.target = self
    button.action = action
    addSubview(button)
  }

  // MARK: - État

  func apply(notes newNotes: [Note]) {
    isApplying = true
    defer { isApplying = false }

    let old = notes
    let oldIDs = old.map(\.id)
    let previousID = selectedID
    let hadNotes = !old.isEmpty
    notes = newNotes
    let newIDs = newNotes.map(\.id)

    if let current = selectedID, newIDs.contains(current) {
      // La sélection tient.
    } else if let previousID, let oldIndex = oldIDs.firstIndex(of: previousID),
      !newNotes.isEmpty
    {
      // La note ouverte a disparu : la voisine prend sa place.
      selectedID = newNotes[min(oldIndex, newNotes.count - 1)].id
    } else {
      selectedID = newNotes.first?.id
    }

    updateRows(from: old, to: newNotes)
    if let selectedID, let index = newIDs.firstIndex(of: selectedID) {
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      table.scrollRowToVisible(index)
    } else {
      table.deselectAll(nil)
    }

    // Le texte n'est réécrit que s'il diffère : celui qu'on tape ici revient identique, et
    // le réécrire ferait sauter le curseur.
    let text = newNotes.first { $0.id == selectedID }?.text ?? ""
    if !keepsEditorText, textView.string != text || previousID != selectedID {
      setEditorText(text)
    }

    let hasNotes = !newNotes.isEmpty
    deleteButton.isEnabled = hasNotes
    let count = hasNotes ? "\(newNotes.count)" : ""
    if countLabel.stringValue != count {
      countLabel.stringValue = count
      countLabel.layer?.springReveal(y: -4)
    }

    if hadNotes, previousID != selectedID, selectedID != nil {
      let from = previousID.flatMap { oldIDs.firstIndex(of: $0) }
      let to = selectedID.flatMap { newIDs.firstIndex(of: $0) }
      if let from, let to {
        revealEditor(x: to > from ? 8 : -8)
      } else {
        revealEditor(x: 0, y: -4)
      }
    }

    tableScroll.isHidden = !hasNotes
    emptyIcon.isHidden = hasNotes
    emptyTitle.isHidden = hasNotes
    if hadNotes != hasNotes, !hasNotes {
      emptyIcon.layer?.springReveal(y: -6)
      emptyTitle.layer?.crossfadeIn(delay: 0.08)
    }
    needsLayout = true
  }

  /// Met à jour la liste : une insertion, une suppression ou une remontée en tête sont animées,
  /// tout autre changement repeint.
  private func updateRows(from old: [Note], to new: [Note]) {
    let oldIDs = old.map(\.id)
    let newIDs = new.map(\.id)

    if oldIDs == newIDs {
      let changed = IndexSet(new.indices.filter { old[$0] != new[$0] })
      if !changed.isEmpty { table.reloadData(forRowIndexes: changed, columnIndexes: [0]) }
      return
    }

    let animated = OverlayAnimation.allowsMotion && window != nil && !isHiddenOrHasHiddenAncestor
    guard animated else {
      table.reloadData()
      return
    }

    var withoutRemoved = oldIDs
    if newIDs.count == oldIDs.count - 1,
      let removed = oldIDs.firstIndex(where: { !newIDs.contains($0) })
    {
      withoutRemoved.remove(at: removed)
      if withoutRemoved == newIDs {
        table.removeRows(at: IndexSet(integer: removed), withAnimation: [.slideUp, .effectFade])
        return
      }
    }
    if newIDs.count == oldIDs.count + 1, Array(newIDs.dropFirst()) == oldIDs {
      table.insertRows(at: IndexSet(integer: 0), withAnimation: [.slideDown, .effectFade])
      return
    }
    if newIDs.count == oldIDs.count, let from = oldIDs.firstIndex(of: newIDs[0]) {
      var moved = oldIDs
      moved.insert(moved.remove(at: from), at: 0)
      if moved == newIDs {
        table.moveRow(at: from, to: 0)
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let changed = IndexSet(new.indices.filter { oldByID[new[$0].id] != new[$0] })
        if !changed.isEmpty { table.reloadData(forRowIndexes: changed, columnIndexes: [0]) }
        return
      }
    }
    table.reloadData()
  }

  /// Met le clavier dans l'éditeur.
  @discardableResult
  func focusEditor() -> Bool {
    guard let window else { return false }
    return window.makeFirstResponder(textView)
  }

  private func setEditorText(_ text: String) {
    textView.string = text
    styleText()
    textView.scrollToBeginningOfDocument(nil)
    textView.needsDisplay = true
  }

  private func setEditorFocused(_ focused: Bool) {
    editorBackdrop.layer?.springAnimate(keyPath: "opacity", to: Float(focused ? 1 : 0))
  }

  /// Première ligne en titre, le reste en corps. Ne change que les attributs, jamais le texte.
  private func styleText() {
    guard let storage = textView.textStorage, !textView.hasMarkedText() else { return }
    let full = NSRange(location: 0, length: storage.length)
    var contentsEnd = 0
    (storage.string as NSString).getLineStart(
      nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: 0, length: 0))

    storage.beginEditing()
    storage.setAttributes(Self.bodyAttributes, range: full)
    storage.setAttributes(Self.headingAttributes, range: NSRange(location: 0, length: contentsEnd))
    storage.endEditing()
    textView.typingAttributes =
      textView.selectedRange().location <= contentsEnd
      ? Self.headingAttributes : Self.bodyAttributes
  }

  private func isBlank(_ note: Note) -> Bool {
    note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var selectedNote: Note? { notes.first { $0.id == selectedID } }

  // MARK: - Actions

  @objc private func addClicked() {
    // Une note encore vide sert de nouvelle note : on n'en empile pas.
    if let note = selectedNote, isBlank(note) {
      focusEditor()
      return
    }
    onCreate?()
    DispatchQueue.main.async { [weak self] in self?.focusEditor() }
  }

  @objc private func deleteClicked() {
    guard let selectedID else { return }
    delete(id: selectedID)
  }

  /// Supprime une note ; si elle n'était pas vide, « Undo delete » reste proposé quelques secondes.
  private func delete(id: UUID) {
    guard let note = notes.first(where: { $0.id == id }) else { return }
    if !isBlank(note) {
      lastDeleted = note
      showUndo()
    }
    onDelete?(id)
  }

  /// Supprime la note ouverte si elle est vide, sans proposer d'annuler.
  func discardEmptyNote() {
    guard let note = selectedNote, isBlank(note) else { return }
    onDelete?(note.id)
  }

  private func selectNeighbor(_ offset: Int) {
    guard let selectedID, let index = notes.firstIndex(where: { $0.id == selectedID }) else {
      return
    }
    let target = index + offset
    guard notes.indices.contains(target) else { return }
    table.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
    table.scrollRowToVisible(target)
  }

  // MARK: - Annuler la suppression

  private func showUndo() {
    undoTask?.cancel()
    undoPill.isHidden = false
    undoPill.layer?.opacity = 1
    undoPill.layer?.crossfadeIn(delay: 0, duration: 0.2)
    needsLayout = true
    undoTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(6))
      guard !Task.isCancelled else { return }
      self?.hideUndo()
    }
  }

  private func hideUndo() {
    undoTask?.cancel()
    lastDeleted = nil
    undoPill.layer?.springAnimate(keyPath: "opacity", to: Float(0)) { [weak self] in
      guard let self, self.lastDeleted == nil else { return }
      self.undoPill.isHidden = true
    }
  }

  private func undoDelete() {
    guard let note = lastDeleted else { return }
    hideUndo()
    if let current = selectedNote, isBlank(current) {
      onEdit?(current.id, note.text)
    } else {
      onCreate?()
      if let id = selectedID { onEdit?(id, note.text) }
    }
    DispatchQueue.main.async { [weak self] in self?.focusEditor() }
  }

  // MARK: - Indicateur d'enregistrement

  /// Le store écrit à chaque frappe : l'indicateur ne fait que le dire, une fois la frappe calmée.
  private func scheduleSaved() {
    savedTask?.cancel()
    setSaved(visible: false)
    savedTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(600))
      guard !Task.isCancelled else { return }
      self?.setSaved(visible: true)
      try? await Task.sleep(for: .milliseconds(1500))
      guard !Task.isCancelled else { return }
      self?.setSaved(visible: false)
    }
  }

  private func setSaved(visible: Bool) {
    guard let layer = savedView.layer else { return }
    if visible { layer.springReveal(y: -3) }
    layer.springAnimate(keyPath: "opacity", to: Float(visible ? 1 : 0))
  }

  private func revealEditor(x: CGFloat, y: CGFloat = 0) {
    editorScroll.layer?.springReveal(x: x, y: y)
  }

  // MARK: - Clavier

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard window != nil, !isHiddenOrHasHiddenAncestor else { return false }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    switch (flags, event.keyCode) {
    case ([.command], 45):  // N
      addClicked()
    case ([.command, .shift], 51):  // ⌫
      deleteClicked()
    case ([.command, .option], 126):  // ↑
      selectNeighbor(-1)
    case ([.command, .option], 125):  // ↓
      selectNeighbor(1)
    default:
      return super.performKeyEquivalent(with: event)
    }
    return true
  }

  // MARK: - Cycle de vie

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(
      self, name: NSWindow.didResignKeyNotification, object: nil)
    if let window {
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowResignedKey), name: NSWindow.didResignKeyNotification,
        object: window)
    }
  }

  /// Le panneau se replie ou perd le clavier : une note restée vide ne sert à rien.
  @objc private func windowResignedKey() { discardEmptyNote() }

  override func viewDidHide() {
    super.viewDidHide()
    discardEmptyNote()
  }

  // MARK: - NSTableView

  func numberOfRows(in tableView: NSTableView) -> Int { notes.count }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let view =
      tableView.makeView(withIdentifier: Self.rowBackgroundIdentifier, owner: nil)
      as? NoteRowBackground ?? NoteRowBackground()
    view.identifier = Self.rowBackgroundIdentifier
    return view
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let cell =
      tableView.makeView(withIdentifier: Self.rowIdentifier, owner: nil) as? NoteRowView
      ?? NoteRowView()
    cell.identifier = Self.rowIdentifier
    let note = notes[row]
    cell.configure(with: note)
    cell.onDelete = { [weak self] in self?.delete(id: note.id) }
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !isApplying, table.selectedRow >= 0, notes.indices.contains(table.selectedRow) else {
      return
    }
    let row = table.selectedRow
    let previousID = selectedID
    guard notes[row].id != previousID else { return }
    let previousIndex = notes.firstIndex { $0.id == previousID }
    selectedID = notes[row].id
    isApplying = true
    setEditorText(notes[row].text)
    isApplying = false
    revealEditor(x: row > (previousIndex ?? row) ? 8 : -8)
    // La note qu'on quitte reste vide : elle disparaît plutôt que de s'empiler.
    if let previousID, let previous = notes.first(where: { $0.id == previousID }),
      isBlank(previous)
    {
      onDelete?(previousID)
    }
  }

  /// Balayage vers la gauche sur une ligne (trackpad) : « Delete ».
  func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge)
    -> [NSTableViewRowAction]
  {
    guard edge == .trailing, notes.indices.contains(row) else { return [] }
    let id = notes[row].id
    let action = NSTableViewRowAction(style: .destructive, title: "Delete") { [weak self] _, _ in
      self?.delete(id: id)
    }
    action.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
    return [action]
  }

  // Glisser une ligne vers une autre app : le texte de la note.
  func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int)
    -> (any NSPasteboardWriting)?
  {
    guard notes.indices.contains(row), !isBlank(notes[row]) else { return nil }
    return notes[row].text as NSString
  }

  func tableView(
    _ tableView: NSTableView, draggingSession session: NSDraggingSession,
    willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet
  ) {
    // Le panneau se replie dès que le curseur le quitte : on gèle ce suivi pendant le glisser.
    FileShelfStore.shared.isDraggingOut = true
  }

  func tableView(
    _ tableView: NSTableView, draggingSession session: NSDraggingSession,
    endedAt screenPoint: NSPoint, operation: NSDragOperation
  ) {
    FileShelfStore.shared.isDraggingOut = false
  }

  // MARK: - NSTextViewDelegate

  func textDidChange(_ notification: Notification) {
    guard !isApplying else { return }
    styleText()
    if let selectedID {
      onEdit?(selectedID, textView.string)
      scheduleSaved()
    } else {
      createFromTyping()
    }
  }

  /// Rien n'est ouvert et l'on tape : la première frappe crée la note.
  private func createFromTyping() {
    let text = textView.string
    guard !text.isEmpty else { return }
    keepsEditorText = true
    onCreate?()
    keepsEditorText = false
    if let id = selectedID {
      onEdit?(id, text)
      scheduleSaved()
    }
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    guard !isApplying, !textView.hasMarkedText() else { return }
    let end = (textView.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
      .upperBound
    let inFirstLine =
      textView.selectedRange().location < end
      || textView.selectedRange().location == 0
    textView.typingAttributes = inFirstLine ? Self.headingAttributes : Self.bodyAttributes
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()
    let midY = bounds.maxY - headerHeight / 2
    let bodyHeight = max(0, bounds.height - headerHeight)

    titleLabel.sizeToFit()
    titleLabel.frame.origin = CGPoint(x: 0, y: midY - titleLabel.frame.height / 2)
    countLabel.sizeToFit()
    countLabel.frame.origin = CGPoint(
      x: titleLabel.frame.maxX + 6, y: midY - countLabel.frame.height / 2)
    addButton.frame = CGRect(x: listWidth - 26, y: midY - 11, width: 26, height: 22)
    deleteButton.frame = CGRect(x: bounds.maxX - 26, y: midY - 11, width: 26, height: 22)

    let editorX = listWidth + 12
    tableScroll.frame = CGRect(x: 0, y: 0, width: listWidth, height: bodyHeight)
    table.sizeLastColumnToFit()
    divider.frame = CGRect(x: listWidth + 5, y: 0, width: 1, height: bodyHeight)
    let editorFrame = CGRect(
      x: editorX, y: 0, width: max(0, bounds.width - editorX), height: bodyHeight)
    editorBackdrop.frame = editorFrame
    editorScroll.frame = editorFrame

    savedView.frame = CGRect(x: editorX + 10, y: midY - 8, width: 56, height: 16)
    savedIcon.frame = CGRect(x: 0, y: 3, width: 10, height: 10)
    savedLabel.sizeToFit()
    savedLabel.frame.origin = CGPoint(x: 14, y: 8 - savedLabel.frame.height / 2)

    let pillWidth = min(undoPill.fittingWidth, max(0, deleteButton.frame.minX - editorX - 70))
    undoPill.frame = CGRect(
      x: deleteButton.frame.minX - 6 - pillWidth, y: midY - 10, width: pillWidth, height: 20)

    let centerX = listWidth / 2
    let centerY = bodyHeight / 2
    emptyIcon.frame = CGRect(x: centerX - 20, y: centerY - 2, width: 40, height: 32)
    emptyTitle.frame = CGRect(x: 0, y: centerY - 22, width: listWidth, height: 16)
  }
}

// MARK: - Éditeur

/// Éditeur de texte brut : prévient quand il prend ou perd le clavier, et dessine l'invite tant
/// qu'il est vide.
private final class NoteTextView: NSTextView {

  var onFocusChanged: ((Bool) -> Void)?

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { onFocusChanged?(true) }
    return accepted
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { onFocusChanged?(false) }
    return resigned
  }

  override func didChangeText() {
    super.didChangeText()
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard string.isEmpty, !hasMarkedText() else { return }
    var attributes = NotesTabView.headingAttributes
    attributes[.foregroundColor] = NSColor.white.withAlphaComponent(0.28)
    let origin = NSPoint(
      x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
      y: textContainerInset.height)
    NSAttributedString(string: "Start typing…", attributes: attributes).draw(at: origin)
  }
}

// MARK: - Fond de ligne

/// Fond d'une ligne : la sélection est une pastille blanche translucide, comme sur les autres
/// onglets, et non le bleu d'accent du système.
private final class NoteRowBackground: NSTableRowView {

  override var isEmphasized: Bool {
    get { false }
    set {}
  }

  override func drawSelection(in dirtyRect: NSRect) {
    NSColor.white.withAlphaComponent(0.14).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 0), xRadius: 10, yRadius: 10).fill()
  }
}

// MARK: - Ligne de la liste

/// Une ligne de la liste : le titre, puis la date et le début du texte. Au survol, un voile
/// clair et un ✕ pour supprimer la note. Les couleurs sont fixes : la sélection est un fond
/// blanc translucide, pas un fond d'accent.
private final class NoteRowView: NSTableCellView {

  var onDelete: (() -> Void)?

  private let titleField = NSTextField(labelWithString: "")
  private let detailField = NSTextField(labelWithString: "")
  private let deleteButton = ClipboardCardButton(symbol: "xmark", label: "Delete note")
  private let hoverLayer = CALayer()
  private var isHovered = false

  private let inset: CGFloat = 10
  private let buttonSize: CGFloat = 18

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    hoverLayer.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
    hoverLayer.cornerRadius = 10
    hoverLayer.cornerCurve = .continuous
    hoverLayer.opacity = 0
    layer?.addSublayer(hoverLayer)

    titleField.font = .systemFont(ofSize: 12, weight: .semibold)
    titleField.lineBreakMode = .byTruncatingTail
    detailField.font = .systemFont(ofSize: 11)
    detailField.textColor = .white.withAlphaComponent(0.5)
    detailField.lineBreakMode = .byTruncatingTail
    addSubview(titleField)
    addSubview(detailField)

    deleteButton.isHidden = true
    deleteButton.wantsLayer = true
    deleteButton.layer?.opacity = 0
    deleteButton.onClick = { [weak self] in self?.onDelete?() }
    addSubview(deleteButton)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func configure(with note: Note) {
    let blank = note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    titleField.stringValue = note.title
    titleField.textColor = .white.withAlphaComponent(blank ? 0.5 : 1)
    let preview = Self.preview(of: note) ?? "No additional text"
    detailField.stringValue = "\(Self.dateText(for: note.updatedAt))  \(preview)"
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    isHovered = false
    hoverLayer.removeAllAnimations()
    hoverLayer.opacity = 0
    deleteButton.layer?.removeAllAnimations()
    deleteButton.layer?.opacity = 0
    deleteButton.isHidden = true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(
      NSTrackingArea(
        rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self))
  }

  override func mouseEntered(with event: NSEvent) { setHovered(true) }
  override func mouseExited(with event: NSEvent) { setHovered(false) }

  private func setHovered(_ hovered: Bool) {
    guard hovered != isHovered else { return }
    isHovered = hovered
    hoverLayer.springAnimate(keyPath: "opacity", to: Float(hovered ? 1 : 0))
    if hovered { deleteButton.isHidden = false }
    deleteButton.layer?.springAnimate(keyPath: "opacity", to: Float(hovered ? 1 : 0)) {
      [weak self] in
      guard let self, !self.isHovered else { return }
      self.deleteButton.isHidden = true
    }
  }

  override func layout() {
    super.layout()
    hoverLayer.frame = bounds.insetBy(dx: 2, dy: 0)
    let titleWidth = max(0, bounds.width - 2 * inset - buttonSize - 4)
    let width = max(0, bounds.width - 2 * inset)
    titleField.frame = CGRect(x: inset, y: bounds.midY + 1, width: titleWidth, height: 16)
    detailField.frame = CGRect(x: inset, y: bounds.midY - 16, width: width, height: 15)
    deleteButton.frame = CGRect(
      x: bounds.maxX - inset - buttonSize, y: bounds.midY + 1 - 1, width: buttonSize,
      height: buttonSize)
  }

  /// Deuxième ligne non vide du texte : celle qui suit le titre.
  private static func preview(of note: Note) -> String? {
    note.text.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .dropFirst()
      .first
  }

  private static func dateText(for date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    return date.formatted(date: .numeric, time: .omitted)
  }
}
