/// Dit si un glisser de fichiers vient de commencer, à partir de l'état du bouton et du
/// presse-papiers de glisser.
///
/// Ce presse-papiers garde le contenu du dernier glisser une fois celui-ci terminé : lire ses URL
/// seules dirait donc « glisser en cours » pour n'importe quel clic. Un vrai glisser se reconnaît
/// à un `changeCount` qui bouge bouton enfoncé ; on retient donc le compteur à chaque relâchement.
@MainActor
struct FileDragDetector {

  private var idleChangeCount: Int?

  mutating func isDragging(buttonDown: Bool, changeCount: Int, carriesFiles: Bool) -> Bool {
    guard buttonDown else {
      idleChangeCount = changeCount
      return false
    }
    guard carriesFiles, let idleChangeCount else { return false }
    return changeCount != idleChangeCount
  }
}
