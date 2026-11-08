import AppKit

/// Liste des bagues d'utilisation, une par case déclarée dans `SidePanelGeometry.ringSlots`.
/// Celles qui n'ont pas encore de source restent vides, avec leur marque en teinte neutre —
/// elles ne sont pas alimentées par l'instantané Claude.
///
/// Les bagues sont empilées **verticalement**, de haut en bas : la liste s'allonge du sens dans
/// lequel le panneau est suspendu, et non en travers de sa largeur. Quand elle dépasse la hauteur
/// offerte, c'est `SidePanelStackView` qui la fait défiler — la vue, elle, n'annonce que la
/// hauteur dont elle a besoin (`contentHeight`).
///
/// La vue ne gère pas le survol elle-même : c'est `SidePanelController` qui décide, depuis la
/// position globale du curseur, quelle bague est survolée et le lui dit par
/// `setHighlightedRing(_:)`. La fenêtre reçoit désormais les clics (la capsule de navigation en a
/// besoin), mais le suivi des bagues reste global — il doit aussi fonctionner pendant que le
/// curseur traverse la bulle, qui est une autre fenêtre.
final class ClaudeUsageRingStripView: NSView {

  private let rings: [ClaudeUsageRingView]

  override init(frame frameRect: NSRect) {
    rings = SidePanelGeometry.ringSlots.map { slot in
      ClaudeUsageRingView(
        tileSize: SidePanelGeometry.ringTileSize,
        mark: slot.mark,
        serviceName: slot.serviceName
      )
    }
    super.init(frame: frameRect)
    wantsLayer = true
    rings.forEach(addSubview)

    // Les cases sans source partent — et restent — sur un anneau vide.
    for (position, ring) in rings.enumerated()
    where !SidePanelGeometry.ringSlots[position].isConnected {
      let reason =
        SidePanelGeometry.ringSlots[position].mark == .copilot
        ? "Individual quota unavailable from GitHub"
        : "Usage unavailable"
      ring.apply(.unavailable(reason: reason), animated: false)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(claudeState: ClaudeUsageState, copilotState: CopilotUsageState, animated: Bool) {
    for (position, ring) in rings.enumerated()
    where SidePanelGeometry.ringSlots[position].isConnected {
      switch SidePanelGeometry.ringSlots[position].mark {
      case .claude:
        ring.apply(claudeState, animated: animated)
      case .copilot:
        ring.applyCopilot(copilotState, animated: animated)
      default:
        break
      }
    }
  }

  /// Met en avant la bague survolée et laisse retomber les autres.
  func setHighlightedRing(_ index: Int?) {
    for (position, ring) in rings.enumerated() {
      ring.setHighlighted(position == index)
    }
  }

  /// Cadre d'une bague dans le repère de cette vue, `nil` hors des bornes — c'est ce que le
  /// contrôleur convertit en coordonnées écran pour ancrer la bulle.
  func ringFrame(at index: Int) -> NSRect? {
    guard rings.indices.contains(index) else { return nil }
    return rings[index].frame
  }

  var ringCount: Int { rings.count }

  /// Hauteur réclamée par la pile — ce que `SidePanelStackView` donne à la vue de document de
  /// son défilement.
  var contentHeight: CGFloat { SidePanelGeometry.ringStripHeight }

  override func layout() {
    super.layout()

    let tile = SidePanelGeometry.ringTileSize
    let spacing = SidePanelGeometry.ringSpacing

    // Le groupe est centré dans la largeur comme dans la hauteur offerte, avec un écart fixe
    // entre bagues : les répartir sur toute la hauteur les éloignerait trop les unes des
    // autres, alors qu'elles forment une seule liste à lire d'un coup. Quand la hauteur
    // manque, la pile part du haut et c'est le défilement qui donne accès au reste.
    let total = contentHeight
    let x = bounds.midX - tile / 2
    var y = bounds.height > total ? bounds.midY + total / 2 - tile : bounds.maxY - tile

    for ring in rings {
      ring.frame = NSRect(x: x, y: y, width: tile, height: tile)
      y -= tile + spacing
    }
  }
}
