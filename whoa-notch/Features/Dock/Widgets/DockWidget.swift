import AppKit

/// Un widget du dock : une tuile carrée de la taille d'une icône. Il reçoit ses données de sa
/// propre source ; le dock ne fait que le placer, le démarrer et l'arrêter.
@MainActor
protocol DockWidget: AnyObject {
  var view: NSView { get }
  /// Commence à écouter la source de données ; appelé quand le widget entre dans le dock.
  func start()
  /// Cesse d'écouter ; appelé quand il en sort.
  func stop()
}

/// Un type de widget enregistré : de quoi le proposer dans les Préférences et en fabriquer un.
struct DockWidgetKind {
  /// Clé stable, sauvegardée dans `DockWidgetPlacement.kind`.
  let id: String
  let title: String
  /// Symbole SF de la tuile dans la galerie.
  let symbol: String
  let make: @MainActor () -> DockWidget
}

/// Ajouter un widget = écrire son fichier puis l'ajouter à `all`. Le dock n'est pas touché.
@MainActor
enum DockWidgetRegistry {
  static let all: [DockWidgetKind] = [BatteryWidget.kind, StorageWidget.kind]

  static func kind(for id: String) -> DockWidgetKind? { all.first { $0.id == id } }
}
