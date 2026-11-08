import AppKit
import Combine

/// Sidebar des Préférences : champ de recherche puis une ligne par `SettingsCategory` (icône
/// colorée + titre), avec un espace entre les groupes (base, fonctions, About). La recherche filtre
/// les titres ; la sélection est partagée via `SettingsViewModel`.
final class SettingsSidebarViewController: NSViewController {

  /// Une ligne de la table : une catégorie, ou un espace qui sépare deux groupes.
  private enum Row {
    case category(SettingsCategory)
    case gap
  }

  private static let gapHeight: CGFloat = 14

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
    tableView.style = .sourceList
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
      searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 56),
      searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

      scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    cancellable = viewModel.$selectedCategory.sink { [weak self] in self?.select($0) }
  }

  /// Sans recherche, un espace sépare chaque groupe ; pendant une recherche, la liste reste plate.
  private func rebuildRows() {
    rows = []
    for category in categories {
      if let last = categories.firstIndex(of: category), last > 0,
        categories[last - 1].sidebarGroup != category.sidebarGroup, searchField.stringValue.isEmpty
      {
        rows.append(.gap)
      }
      rows.append(.category(category))
    }
  }

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
    if case .gap = rows[row] { return Self.gapHeight }
    return SettingsMetrics.sidebarRowHeight
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    if case .category = rows[row] { return true }
    return false
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard case .category(let category) = rows[row] else { return NSView() }
    let icon = SettingsSymbolTile(
      symbolName: category.symbolName, tint: category.tint, size: SettingsMetrics.sidebarIconSize)
    let label = NSTextField(labelWithString: category.title)
    label.font = .systemFont(ofSize: 14)
    let stack = NSStackView(views: [icon, label])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 10
    return stack
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
