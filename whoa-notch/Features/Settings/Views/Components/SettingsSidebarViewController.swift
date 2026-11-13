import AppKit
import Combine

/// Sidebar des Préférences : champ de recherche puis une ligne par `SettingsCategory` (icône
/// colorée + titre), avec un espace entre les groupes (base, fonctions, About). La recherche filtre
/// les titres ; la sélection est partagée via `SettingsViewModel`.
final class SettingsSidebarViewController: NSViewController {

  /// Une ligne de la table : une catégorie, ou un espace qui sépare deux groupes.
  private enum Row {
    case category(SettingsCategory)
    case heading(String)
  }

  private let viewModel: SettingsViewModel
  private let searchField = NSSearchField()
  private let tableView = NSTableView()
  private var categories = SettingsCategory.allCases
  private var rows: [Row] = []
  private var cancellable: AnyCancellable?

  init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    view = NSView(
      frame: NSRect(
        x: 0, y: 0, width: SettingsMetrics.sidebarWidth, height: SettingsMetrics.windowSize.height))
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    searchField.placeholderString = "Search"
    searchField.delegate = self
    searchField.translatesAutoresizingMaskIntoConstraints = false

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("category"))
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.style = .plain
    tableView.selectionHighlightStyle = .regular
    tableView.intercellSpacing = NSSize(width: 0, height: 2)
    tableView.rowHeight = SettingsMetrics.sidebarRowHeight
    tableView.backgroundColor = .clear
    tableView.dataSource = self
    tableView.delegate = self
    rebuildRows()

    let scrollView = NSScrollView()
    scrollView.documentView = tableView
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(searchField)
    view.addSubview(scrollView)
    NSLayoutConstraint.activate([
      searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 52),
      searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

      scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    cancellable = viewModel.$selectedCategory.sink { [weak self] in self?.select($0) }
  }

  /// Sans recherche, un titre de section ouvre chaque groupe ; pendant une recherche, la liste
  /// reste plate.
  private func rebuildRows() {
    rows = []
    for category in categories {
      if let last = categories.firstIndex(of: category), last > 0,
        categories[last - 1].sidebarGroup != category.sidebarGroup, searchField.stringValue.isEmpty
      {
        rows.append(.heading(Self.headings[category.sidebarGroup] ?? ""))
      }
      rows.append(.category(category))
    }
  }

  private static let headings = [1: "Features", 2: "Whoa Notch"]

  private func select(_ category: SettingsCategory) {
    guard
      let row = rows.firstIndex(where: {
        if case .category(category) = $0 { return true } else { return false }
      }),
      tableView.selectedRow != row
    else { return }
    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
  }
}

extension SettingsSidebarViewController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    SettingsMetrics.sidebarRowHeight
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    if case .category = rows[row] { return true }
    return false
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    if case .heading(let title) = rows[row] {
      let label = NSTextField(labelWithString: title)
      label.font = .systemFont(ofSize: 13, weight: .semibold)
      label.textColor = .secondaryLabelColor
      let container = NSView()
      label.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(label)
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
        label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
      ])
      return container
    }
    guard case .category(let category) = rows[row] else { return nil }
    let icon = SettingsSymbolTile(
      symbolName: category.symbolName, tint: category.tint, size: SettingsMetrics.sidebarIconSize)
    let label = NSTextField(labelWithString: category.title)
    label.font = .systemFont(ofSize: 13)
    let stack = NSStackView(views: [icon, label])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 8
    stack.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 12)
    return stack
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    SettingsSidebarRowView()
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    guard rows.indices.contains(row), case .category(let category) = rows[row] else { return }
    viewModel.selectedCategory = category
  }
}

extension SettingsSidebarViewController: NSSearchFieldDelegate {
  func controlTextDidChange(_ notification: Notification) {
    let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
    categories =
      query.isEmpty
      ? SettingsCategory.allCases
      : SettingsCategory.allCases.filter { $0.title.localizedCaseInsensitiveContains(query) }
    rebuildRows()
    tableView.reloadData()
    select(viewModel.selectedCategory)
  }
}

/// Ligne de la sidebar : pastille arrondie de 12 pt pour la sélection, avec 12 pt de marge.
private final class SettingsSidebarRowView: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    guard isSelected else { return }
    SettingsPalette.sidebarSelection.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 12, dy: 0), xRadius: 12, yRadius: 12).fill()
  }

  override var isEmphasized: Bool {
    get { false }
    set {}
  }
}
