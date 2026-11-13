import CoreGraphics
import Foundation

/// Une case de la rangée d'icônes du dock.
enum DockRowEntry: Equatable {
  case app(DockItem)
  case widget(DockWidgetPlacement)
}

/// La rangée d'icônes : les applis du profil actif avec les widgets glissés à leur place. Pur,
/// pour que les règles de placement se testent sans fenêtre.
enum DockRow {

  /// Les widgets s'insèrent par indice croissant ; deux widgets au même indice gardent leur ordre.
  /// Un indice trop grand colle le widget au bout de la rangée.
  static func entries(items: [DockItem], widgets: [DockWidgetPlacement]) -> [DockRowEntry] {
    var row = items.map(DockRowEntry.app)
    var next = 0
    for widget in widgets.enumerated().sorted(by: {
      ($0.element.index, $0.offset) < ($1.element.index, $1.offset)
    }).map(\.element) {
      let position = min(max(widget.index, next), row.count)
      row.insert(.widget(widget), at: position)
      next = position + 1
    }
    return row
  }

  /// Les widgets de `row`, chacun avec sa position réelle dans la rangée.
  static func placements(of row: [DockRowEntry]) -> [DockWidgetPlacement] {
    row.enumerated().compactMap { position, entry in
      guard case .widget(var widget) = entry else { return nil }
      widget.index = position
      return widget
    }
  }

  /// Les widgets une fois `moved` lâché à `index` (position dans la rangée d'avant le déplacement).
  /// Un widget déjà dans le dock est déplacé, sinon il est ajouté.
  static func placements(placing moved: DockWidgetPlacement, at index: Int, in row: [DockRowEntry])
    -> [DockWidgetPlacement]
  {
    var row = row
    var target = index
    if let existing = row.firstIndex(where: {
      if case .widget(let widget) = $0 { return widget.id == moved.id }
      return false
    }) {
      row.remove(at: existing)
      if existing < target { target -= 1 }
    }
    row.insert(.widget(moved), at: max(0, min(target, row.count)))
    return placements(of: row)
  }

  /// Les widgets une fois `id` retiré : les autres gardent leur place dans la rangée.
  static func placements(removing id: String, from row: [DockRowEntry]) -> [DockWidgetPlacement] {
    placements(
      of: row.filter {
        if case .widget(let widget) = $0 { return widget.id != id }
        return true
      })
  }

  /// Rang parmi les épinglées d'une insertion à `position` dans la rangée.
  static func pinnedIndex(beforeRowIndex position: Int, in row: [DockRowEntry]) -> Int {
    row.prefix(position).filter {
      if case .app(let item) = $0 { return item.isPinned }
      return false
    }.count
  }

  /// Position la plus à droite où une appli peut tomber : juste après la dernière épinglée — les
  /// applis seulement lancées restent après.
  static func lastAppDropPosition(in row: [DockRowEntry]) -> Int {
    let last = row.lastIndex {
      if case .app(let item) = $0 { return item.isPinned }
      return false
    }
    return last.map { $0 + 1 } ?? 0
  }
}

/// Les zones où un glisser peut tomber.
enum DockDropZone {

  /// L'indice d'insertion dans la rangée sous le pointeur, ou `nil` s'il est sur le groupe de
  /// gauche (les profils), où rien ne se dépose. `rowStart` est le bord gauche de la
  /// première case au repos, `profileEnd` le bord droit de la zone des profils.
  static func rowIndex(
    x: CGFloat, profileEnd: CGFloat, rowStart: CGFloat, iconSize: CGFloat, pitch: CGFloat,
    count: Int
  ) -> Int? {
    guard x >= profileEnd else { return nil }
    let before = (0..<count).filter { rowStart + CGFloat($0) * pitch + iconSize / 2 < x }.count
    return before
  }
}
