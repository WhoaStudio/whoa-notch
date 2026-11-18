import Foundation

extension DockRowEntry {
  /// L'identifiant de la case : le bundle d'une appli, l'identifiant de placement d'un widget.
  var id: String {
    switch self {
    case .app(let item): item.bundleID
    case .widget(let placement): placement.id
    }
  }
}

extension DockPinnedApp {
  /// L'appli telle que la rangée du dock la compose : épinglée, jamais en cours d'exécution.
  var dockItem: DockItem {
    DockItem(
      bundleID: bundleID, path: path, name: DockModel.displayName(path: path), isRunning: false,
      isWebApp: false, isPinned: true)
  }
}

/// Le profil vu comme le dock le montre : une seule rangée où applis et widgets se mêlent. Les
/// opérations de la maquette de Préférences passent toutes par elle, pour que les positions des
/// widgets suivent les applis qu'on déplace, ajoute ou retire.
extension DockProfile {

  /// La rangée du profil, dans l'ordre d'affichage.
  var row: [DockRowEntry] {
    DockRow.entries(items: apps.map(\.dockItem), widgets: widgets)
  }

  private mutating func setRow(_ row: [DockRowEntry]) {
    apps = row.compactMap {
      guard case .app(let item) = $0 else { return nil }
      return DockPinnedApp(bundleID: item.bundleID, path: item.path)
    }
    widgets = DockRow.placements(of: row)
  }

  /// Déplace la case `id` ; `index` est compté dans la rangée une fois la case retirée, comme la
  /// maquette la voit quand l'icône est levée. Renvoie `false` si la case n'y est pas.
  @discardableResult
  mutating func moveEntry(_ id: String, toRemainingIndex index: Int) -> Bool {
    var row = row
    guard let existing = row.firstIndex(where: { $0.id == id }) else { return false }
    let entry = row.remove(at: existing)
    row.insert(entry, at: max(0, min(index, row.count)))
    setRow(row)
    return true
  }

  /// Insère l'appli à `index` de la rangée (borné) ; ne fait rien si le profil l'a déjà.
  @discardableResult
  mutating func insertApp(_ app: DockPinnedApp, atRowIndex index: Int) -> Bool {
    guard !apps.contains(where: { $0.bundleID == app.bundleID }) else { return false }
    var row = row
    row.insert(.app(app.dockItem), at: max(0, min(index, row.count)))
    setRow(row)
    return true
  }

  /// Insère un nouveau widget de ce type à `index` de la rangée (borné).
  mutating func insertWidget(kind: String, atRowIndex index: Int) {
    var row = row
    let position = max(0, min(index, row.count))
    row.insert(.widget(DockWidgetPlacement(kind: kind, index: position)), at: position)
    setRow(row)
  }

  /// Retire la case `id` ; les autres gardent leur place dans la rangée. Renvoie `false` si elle
  /// n'y était pas.
  @discardableResult
  mutating func removeEntry(_ id: String) -> Bool {
    let row = row
    guard row.contains(where: { $0.id == id }) else { return false }
    setRow(row.filter { $0.id != id })
    return true
  }
}
