import AppKit

/// Onglet Notes : la liste des notes à gauche, l'éditeur de texte brut à droite, à la manière de
/// Notes.app. La vue n'est qu'une lecture des notes : `apply(notes:)` la repeint, et chaque action
/// remonte par callback.
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
  private let editorScroll = NSScrollView()
  private let textView = NSTextView()
  private let emptyIcon = NSImageView()
  private let emptyTitle = NSTextField(labelWithString: "No Notes")
  private let emptyHint = NSTextField(labelWithString: "Click the compose button to create one.")

  private var notes: [Note] = []
  private var selectedID: UUID?
  /// Levé pendant qu'on repeint : les callbacks AppKit qui en résultent ne sont pas des actions.
  private var isApplying = false

  private let headerHeight: CGFloat = 28
  private let listWidth: CGFloat = 190
  private let rowHeight: CGFloat = 46

  private static let rowIdentifier = NSUserInterfaceItemIdentifier("noteRow")

  private static let bodyFont = NSFont.systemFont(ofSize: 13)
  private static let headingFont = NSFont.systemFont(ofSize: 17, weight: .semibold)

  private static let bodyAttributes: [NSAttributedString.Key: Any] = [
    .font: bodyFont,
    .foregroundColor: NSColor.labelColor,
  ]

  private static let headingAttributes: [NSAttributedString.Key: Any] = {
    let paragraph = NSMutableParagraphStyle()
    paragraph.paragraphSpacing = 6
    return [
      .font: headingFont,
      .foregroundColor: NSColor.labelColor,
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
    titleLabel.textColor = .labelColor
    addSubview(titleLabel)

    countLabel.wantsLayer = true
    countLabel.font = .systemFont(ofSize: 13)
    countLabel.textColor = .tertiaryLabelColor
    addSubview(countLabel)

    configure(
      addButton, symbol: "square.and.pencil", description: "New note", action: #selector(addClicked)
    )
    configure(
      deleteButton, symbol: "trash", description: "Delete note", action: #selector(deleteClicked))

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
    column.resizingMask = .autoresizingMask
    table.addTableColumn(column)
    table.headerView = nil
    table.backgroundColor = .clear
    table.rowHeight = rowHeight
    table.style = .plain
    table.selectionHighlightStyle = .regular
    table.intercellSpacing = NSSize(width: 0, height: 2)
    table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    table.dataSource = self
    table.delegate = self
    tableScroll.documentView = table
    tableScroll.drawsBackground = false
    tableScroll.hasVerticalScroller = false
    tableScroll.hasHorizontalScroller = false
    addSubview(tableScroll)

    divider.boxType = .separator
    addSubview(divider)

    textView.isRichText = false
    textView.allowsUndo = true
    textView.font = Self.bodyFont
    textView.textColor = .labelColor
    textView.typingAttributes = Self.bodyAttributes
    textView.insertionPointColor = .controlAccentColor
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 12, height: 8)
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.delegate = self
    editorScroll.documentView = textView
    editorScroll.drawsBackground = false
    editorScroll.hasVerticalScroller = false
    addSubview(editorScroll)

    emptyIcon.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 28, weight: .light))
    emptyIcon.contentTintColor = .tertiaryLabelColor
    addSubview(emptyIcon)

    emptyTitle.font = .systemFont(ofSize: 13, weight: .semibold)
    emptyTitle.textColor = .secondaryLabelColor
    emptyTitle.alignment = .center
    addSubview(emptyTitle)

    emptyHint.font = .systemFont(ofSize: 11)
    emptyHint.textColor = .tertiaryLabelColor
    emptyHint.alignment = .center
    addSubview(emptyHint)
  }

  private func configure(_ button: NSButton, symbol: String, description: String, action: Selector)
  {
    button.isBordered = false
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    button.contentTintColor = .secondaryLabelColor
    button.toolTip = description
    button.target = self
    button.action = action
    addSubview(button)
  }

  // MARK: - État

  func apply(notes newNotes: [Note]) {
    isApplying = true
    defer { isApplying = false }

    let previousID = selectedID
    let hadNotes = !notes.isEmpty
    notes = newNotes
    if selectedID == nil || !notes.contains(where: { $0.id == selectedID }) {
      selectedID = notes.first?.id
    }
    table.reloadData()
    if let index = notes.firstIndex(where: { $0.id == selectedID }) {
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }

    // Le texte n'est réécrit que s'il diffère : celui qu'on tape ici revient identique, et
    // le réécrire ferait sauter le curseur.
    let text = notes.first { $0.id == selectedID }?.text ?? ""
    if textView.string != text || previousID != selectedID {
      textView.string = text
      styleText()
    }

    let hasNotes = !notes.isEmpty
    textView.isEditable = hasNotes
    deleteButton.isEnabled = hasNotes
    let count = hasNotes ? "\(notes.count)" : ""
    if countLabel.stringValue != count {
      countLabel.stringValue = count
      countLabel.layer?.springReveal(y: -4)
    }
    if hadNotes, hasNotes, previousID != selectedID {
      revealEditor()
    }
    for view in [emptyIcon, emptyTitle, emptyHint] { view.isHidden = hasNotes }
    editorScroll.isHidden = !hasNotes
    if hadNotes != hasNotes {
      let revealed: [NSView] = hasNotes ? [editorScroll] : [emptyIcon, emptyTitle, emptyHint]
      for view in revealed {
        view.wantsLayer = true
        view.layer?.springReveal()
      }
    }
    needsLayout = true
  }

  /// Met le clavier dans l'éditeur.
  @discardableResult
  func focusEditor() -> Bool {
    guard notes.isEmpty == false, let window else { return false }
    return window.makeFirstResponder(textView)
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

  @objc private func addClicked() {
    onCreate?()
    DispatchQueue.main.async { [weak self] in self?.focusEditor() }
  }

  @objc private func deleteClicked() {
    guard let selectedID else { return }
    onDelete?(selectedID)
  }

  // MARK: - NSTableView

  func numberOfRows(in tableView: NSTableView) -> Int { notes.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let cell =
      tableView.makeView(withIdentifier: Self.rowIdentifier, owner: nil) as? NoteRowView
      ?? NoteRowView()
    cell.identifier = Self.rowIdentifier
    cell.configure(with: notes[row])
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !isApplying, table.selectedRow >= 0 else { return }
    selectedID = notes[table.selectedRow].id
    isApplying = true
    textView.string = notes[table.selectedRow].text
    styleText()
    isApplying = false
    revealEditor()
  }

  private func revealEditor() {
    editorScroll.wantsLayer = true
    editorScroll.layer?.springReveal(x: 6, y: 0)
  }

  // MARK: - NSTextViewDelegate

  func textDidChange(_ notification: Notification) {
    guard !isApplying, let selectedID else { return }
    styleText()
    onEdit?(selectedID, textView.string)
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
    let headerY = bounds.maxY - headerHeight
    let bodyHeight = max(0, headerY)

    titleLabel.sizeToFit()
    titleLabel.frame.origin = CGPoint(x: 0, y: bounds.maxY - titleLabel.frame.height)
    countLabel.sizeToFit()
    countLabel.frame.origin = CGPoint(
      x: titleLabel.frame.maxX + 6,
      y: bounds.maxY - countLabel.frame.height)
    addButton.frame = CGRect(x: listWidth - 26, y: bounds.maxY - 22, width: 26, height: 22)
    deleteButton.frame = CGRect(x: bounds.maxX - 26, y: bounds.maxY - 22, width: 26, height: 22)

    tableScroll.frame = CGRect(x: 0, y: 0, width: listWidth, height: bodyHeight)
    table.sizeLastColumnToFit()
    divider.frame = CGRect(x: listWidth, y: 0, width: 1, height: bounds.height)
    let editorX = listWidth + 1
    editorScroll.frame = CGRect(
      x: editorX, y: 0, width: max(0, bounds.width - editorX), height: bodyHeight)

    let centerX = editorX + max(0, bounds.width - editorX) / 2
    let centerY = bodyHeight / 2
    emptyIcon.frame = CGRect(x: centerX - 20, y: centerY + 4, width: 40, height: 36)
    emptyTitle.frame = CGRect(
      x: editorX, y: centerY - 16, width: bounds.width - editorX, height: 16)
    emptyHint.frame = CGRect(x: editorX, y: centerY - 34, width: bounds.width - editorX, height: 14)
  }
}

// MARK: - Ligne de la liste

/// Une ligne de la liste : le titre, puis la date et le début du texte. Les couleurs suivent la
/// sélection pour rester lisibles sur le fond d'accent.
private final class NoteRowView: NSTableCellView {

  private let titleField = NSTextField(labelWithString: "")
  private let detailField = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    titleField.font = .systemFont(ofSize: 13, weight: .semibold)
    titleField.lineBreakMode = .byTruncatingTail
    detailField.font = .systemFont(ofSize: 11)
    detailField.lineBreakMode = .byTruncatingTail
    addSubview(titleField)
    addSubview(detailField)
    applyColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func configure(with note: Note) {
    titleField.stringValue = note.title
    let preview = Self.preview(of: note) ?? "No additional text"
    detailField.stringValue = "\(Self.dateText(for: note.updatedAt))  \(preview)"
  }

  override var backgroundStyle: NSView.BackgroundStyle {
    didSet { applyColors() }
  }

  private func applyColors() {
    let emphasized = backgroundStyle == .emphasized
    titleField.textColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
    detailField.textColor =
      emphasized
      ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.75) : .secondaryLabelColor
  }

  override func layout() {
    super.layout()
    let inset: CGFloat = 8
    let width = max(0, bounds.width - 2 * inset)
    titleField.frame = CGRect(x: inset, y: bounds.midY + 1, width: width, height: 16)
    detailField.frame = CGRect(x: inset, y: bounds.midY - 16, width: width, height: 15)
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
