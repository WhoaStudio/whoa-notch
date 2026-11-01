import CoreGraphics
import Foundation

/// La pose du couvercle du logo de l'encoche dépliée : fermé, entrouvert au survol, grand ouvert
/// au clic. Pur calcul, séparé de la vue pour se tester sans fenêtre.
nonisolated enum ChestLidPose: String, Equatable {
    case closed, peek, open

    /// Ouverture visée : 0 fermé, 1 comme dans l'œuvre.
    var openness: Double {
        switch self {
        case .closed: 0
        case .peek: 0.35
        case .open: 1
        }
    }

    /// Le curseur entre sur le logo : le couvercle s'entrouvre, sans toucher à un coffre déjà ouvert.
    func afterEntering() -> ChestLidPose { self == .closed ? .peek : self }

    /// Le curseur quitte le logo : tout se referme.
    func afterExiting() -> ChestLidPose { .closed }

    /// Un clic ouvre en grand ; un second clic, le curseur étant toujours dessus, revient à la
    /// pose du survol.
    func afterClick() -> ChestLidPose { self == .open ? .peek : .open }
}

/// Le regard du logo : de combien les yeux se décalent vers le curseur.
nonisolated enum ChestGaze {
    /// Demi-axes de l'ellipse où le centre des yeux reste, pour un coffre de côté `side`
    /// (grille 256 de l'œuvre : 36 unités de marge de chaque côté des yeux, moins sous le museau).
    static func limit(forChestSide side: CGFloat) -> CGSize {
        CGSize(width: side * 12 / 256, height: side * 8 / 256)
    }

    /// Décalage des yeux pour un curseur donné, dans le repère du coffre.
    ///
    /// Nul si le curseur est hors de l'encoche, ou pile sur les yeux. Sinon dirigé vers le curseur
    /// et toujours dans l'ellipse `limit` : la force croît avec la distance jusqu'à
    /// `reach`, puis reste à 1.
    static func offset(
        cursor: CGPoint, eyesCenter: CGPoint, insideNotch: Bool, limit: CGSize, reach: CGFloat
    ) -> CGVector {
        guard insideNotch else { return .zero }
        let dx = cursor.x - eyesCenter.x
        let dy = cursor.y - eyesCenter.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return .zero }
        let strength = reach > 0 ? min(distance / reach, 1) : 1
        return CGVector(
            dx: dx / distance * limit.width * strength,
            dy: dy / distance * limit.height * strength)
    }
}

/// Le rythme des clignements : aléatoire, rapide, parfois double. Les tirages (`unit`, de 0 à 1)
/// viennent de l'appelant, pour que le calcul reste déterministe en test.
nonisolated enum ChestBlink {
    /// Attente entre deux clignements.
    static let intervals: ClosedRange<TimeInterval> = 2.5...6
    /// Durée d'un clignement, paupières fermées puis rouvertes.
    static let duration: TimeInterval = 0.12
    /// Écart entre les deux clignements d'une paire, mesuré depuis le début du premier.
    static let doubleGap: TimeInterval = 0.2
    /// Part des clignements qui viennent par deux.
    static let doubleChance = 0.2
    /// Échelle verticale des yeux, fermés.
    static let closedScale: CGFloat = 0.08

    static func interval(unit: Double) -> TimeInterval {
        intervals.lowerBound + min(max(unit, 0), 1) * (intervals.upperBound - intervals.lowerBound)
    }

    static func isDouble(unit: Double) -> Bool { unit < doubleChance }
}
