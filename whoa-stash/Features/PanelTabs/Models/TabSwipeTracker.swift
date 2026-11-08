import CoreGraphics

/// Suit un geste horizontal (balayage à deux doigts ou glisser à la souris) sur le corps du
/// panneau et dit s'il s'agit d'un balayage d'onglet.
///
/// Pur et sans AppKit pour pouvoir se tester : la vue lui passe les déplacements, il répond par
/// l'état du geste. Rien ne démarre avant `engageThreshold` — en deçà, un appui reste un clic — et
/// un geste surtout vertical est abandonné pour de bon, afin de laisser défiler les listes.
struct TabSwipeTracker {

  /// Sens du balayage, du point de vue de la rangée d'onglets.
  enum Direction: Equatable {
    case previous
    case next
  }

  /// Déplacement horizontal à partir duquel le geste devient un balayage (et non un clic).
  static let engageThreshold: CGFloat = 6

  /// Déplacement horizontal total à partir duquel le relâché change d'onglet.
  static let commitThreshold: CGFloat = 60

  /// Déplacement horizontal cumulé : négatif quand le doigt va vers la gauche.
  private(set) var offset: CGFloat = 0
  private(set) var isSwiping = false

  private var vertical: CGFloat = 0
  private var isAbandoned = false

  /// Ajoute un déplacement. Renvoie `true` tant que le geste est un balayage en cours, c'est-à-dire
  /// quand la vue doit suivre le doigt (et garder l'événement pour elle).
  @discardableResult
  mutating func move(dx: CGFloat, dy: CGFloat) -> Bool {
    guard !isAbandoned else { return false }
    offset += dx
    vertical += dy

    if !isSwiping {
      // Le geste se décide une fois : surtout vertical, c'est du défilement.
      if abs(vertical) > Self.engageThreshold, abs(vertical) > abs(offset) {
        isAbandoned = true
        return false
      }
      guard abs(offset) > Self.engageThreshold, abs(offset) > abs(vertical) else { return false }
      isSwiping = true
    }
    return true
  }

  /// Termine le geste. Renvoie le sens à suivre, ou `nil` si c'était un clic, un défilement ou un
  /// balayage trop court. Le suiveur est remis à zéro.
  mutating func end() -> Direction? {
    defer { self = TabSwipeTracker() }
    guard isSwiping, abs(offset) >= Self.commitThreshold else { return nil }
    return offset < 0 ? .next : .previous
  }

  /// Abandonne le geste sans rien décider (fenêtre qui perd la souris, repli du panneau).
  mutating func cancel() {
    self = TabSwipeTracker()
  }
}
