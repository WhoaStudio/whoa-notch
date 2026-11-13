import CoreGraphics

/// Les étapes de l'accueil, dans l'ordre. Pur et sans interface : la hauteur du panneau et le
/// passage d'une étape à l'autre se testent sans afficher quoi que ce soit.
enum OnboardingStep: Int, CaseIterable, Identifiable {
  case hello
  case notch
  case tabs
  case permissions
  case done

  var id: Int { rawValue }

  /// Hauteur du contenu, hors encoche matérielle et hors indicateur de progression.
  var contentHeight: CGFloat {
    switch self {
    case .hello: 256
    case .notch: 190
    case .tabs: 196
    case .permissions: 306
    case .done: 192
    }
  }

  /// Nom court, utilisé par `--onboarding-step=`.
  var launchName: String {
    switch self {
    case .hello: "hello"
    case .notch: "notch"
    case .tabs: "tabs"
    case .permissions: "permissions"
    case .done: "done"
    }
  }

  init?(launchName: String) {
    guard let step = Self.allCases.first(where: { $0.launchName == launchName }) else {
      return nil
    }
    self = step
  }

  /// L'étape voisine, ou `nil` au bord : on ne boucle pas.
  func moved(by delta: Int) -> OnboardingStep? {
    Self(rawValue: rawValue + delta)
  }
}

enum OnboardingFlow {

  /// Place de l'indicateur de progression sous le contenu.
  static let progressHeight: CGFloat = 34

  /// Hauteur du panneau pour une étape : encoche, contenu, indicateur.
  static func panelHeight(for step: OnboardingStep, topInset: CGFloat) -> CGFloat {
    topInset + step.contentHeight + progressHeight
  }

  /// La plus haute des étapes : la fenêtre a cette hauteur, la silhouette n'en peint que la part utile.
  static func maxPanelHeight(topInset: CGFloat) -> CGFloat {
    OnboardingStep.allCases.map { panelHeight(for: $0, topInset: topInset) }.max() ?? 0
  }

  /// Déplacement montré pendant un balayage : 1:1 s'il y a une étape de ce côté, sinon le doigt
  /// rencontre une résistance (le quart du déplacement).
  static func trackedOffset(_ offset: CGFloat, at step: OnboardingStep) -> CGFloat {
    let hasPrevious = step.moved(by: -1) != nil
    let hasNext = step.moved(by: 1) != nil
    if offset > 0 && !hasPrevious { return offset * 0.25 }
    if offset < 0 && !hasNext { return offset * 0.25 }
    return offset
  }
}
