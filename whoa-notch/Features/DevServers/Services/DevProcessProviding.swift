import Foundation

/// Lance et suit les processus des actions. `DevProcessManager` les démarre pour de vrai ;
/// `MockDevProcessManager` simule leur état, pour vérifier l'interface sans rien lancer.
protocol DevProcessProviding: AnyObject {
  var servers: [DevServer] { get }
  /// Appelé à chaque changement (démarrage, sortie, fin).
  var onChange: (() -> Void)? { get set }
  func start(_ action: DevAction)
  func stop(_ id: UUID)
  func restart(_ action: DevAction)
  /// Oublie un serveur arrêté.
  func remove(_ id: UUID)
  /// Arrête tout, avant la sortie de l'app.
  func stopAll()
}
