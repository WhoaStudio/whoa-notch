import Foundation

/// Ce que le presse-papiers contenait à un instant donné, recopié hors de `NSPasteboard` :
/// le classeur ne touche donc jamais au pasteboard réel et se teste avec des valeurs.
struct ClipboardSnapshot: Equatable {
  var fileURLs: [URL] = []
  /// Image brute, déjà encodée en PNG par le moniteur.
  var imageData: Data?
  var string: String?
  /// Vrai pour un contenu que l'app source demande de ne pas conserver (gestionnaire de mots
  /// de passe, mot de passe à usage unique…).
  var isConcealed = false
  /// Application au premier plan au moment de la copie : c'est elle qui a écrit dans le presse-papiers.
  var sourceBundleID: String?
}
