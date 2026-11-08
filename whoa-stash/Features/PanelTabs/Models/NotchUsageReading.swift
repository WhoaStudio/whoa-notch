import Foundation

/// Les fournisseurs de l'onglet AI, dans l'ordre où l'en-tête les présente.
enum NotchUsageProvider: Int, CaseIterable {
  case claude
  case codex
  case copilot

  var name: String {
    switch self {
    case .claude: "Claude Code"
    case .codex: "Codex"
    case .copilot: "GitHub Copilot"
    }
  }

  /// Commande qui rouvre la connexion de l'agent.
  var loginCommand: String {
    switch self {
    case .claude: "claude"
    case .codex: "codex"
    case .copilot: "gh auth login"
    }
  }

  var windowLabel: String {
    switch self {
    case .claude: "5H"
    case .codex: "7D"
    case .copilot: "MO"
    }
  }

  var mark: UsageMarkPath {
    switch self {
    case .claude: .claude
    case .codex: .codex
    case .copilot: .copilot
    }
  }
}

/// Ce que l'onglet AI montre d'un fournisseur : une seule fenêtre de quota, celle que porte son
/// onglet d'en-tête, plus ce que la carte en dit. Calculé une fois ici pour que l'onglet et la
/// carte ne puissent pas afficher deux pourcentages différents du même instantané.
struct NotchUsageReading: Equatable {

  enum Status: Equatable {
    case loading
    case loaded
    case unavailable(reason: String)
  }

  /// Étiquette de la fenêtre : « 5H », « 7D », « MO ».
  let windowLabel: String
  let status: Status
  /// Fraction **restante**, `0…1` — c'est elle que montrent l'onglet, le titre de la carte et
  /// la barre.
  let remaining: Double?
  let resetsAt: Date?
  /// Ligne sous la barre, quand la source en fournit une vraie.
  let secondaryLine: String?
  /// Vrai quand seule une reconnexion répare l'état : la carte propose alors de la lancer.
  var needsReauth = false

  var remainingPercentage: Int? { remaining.map { Int(($0 * 100).rounded()) } }

  static func loading(windowLabel: String) -> NotchUsageReading {
    NotchUsageReading(
      windowLabel: windowLabel, status: .loading, remaining: nil, resetsAt: nil, secondaryLine: nil)
  }

  static func unavailable(windowLabel: String, reason: String) -> NotchUsageReading {
    NotchUsageReading(
      windowLabel: windowLabel, status: .unavailable(reason: reason),
      remaining: nil, resetsAt: nil, secondaryLine: nil)
  }

  private static func loaded(
    windowLabel: String, window: ClaudeUsageWindow, secondaryLine: String? = nil
  ) -> NotchUsageReading {
    NotchUsageReading(
      windowLabel: windowLabel, status: .loaded,
      remaining: 1 - window.utilization, resetsAt: window.resetsAt, secondaryLine: secondaryLine)
  }

  /// Claude : la session de 5 h porte l'onglet ; le quota hebdomadaire passe sous la barre.
  static func claude(_ state: ClaudeUsageState) -> NotchUsageReading {
    switch state {
    case .loading:
      return .loading(windowLabel: "5H")
    case .unavailable(let reason):
      return .unavailable(windowLabel: "5H", reason: reason)
    case .expired(let reason):
      var reading = NotchUsageReading.unavailable(windowLabel: "5H", reason: reason)
      reading.needsReauth = true
      return reading
    case .loaded(let snapshot):
      let weekly = Int(((1 - snapshot.allModels.utilization) * 100).rounded())
      return .loaded(
        windowLabel: "5H", window: snapshot.session, secondaryLine: "7D \(weekly)% remaining")
    }
  }

  /// Copilot : le quota mensuel d'interactions premium. La source ne donne rien d'autre.
  static func copilot(_ state: CopilotUsageState) -> NotchUsageReading {
    switch state {
    case .loading:
      return .loading(windowLabel: "MO")
    case .unavailable(let reason):
      return .unavailable(windowLabel: "MO", reason: reason)
    case .loaded(let snapshot):
      return .loaded(windowLabel: "MO", window: snapshot.premiumInteractions)
    }
  }

  /// Codex : la fenêtre hebdomadaire porte l'onglet, la session de 5 h passe sous la barre. Un
  /// forfait qui n'expose que la session de 5 h la montre à la place.
  static func codex(_ state: CodexUsageState) -> NotchUsageReading {
    switch state {
    case .loading:
      return .loading(windowLabel: "7D")
    case .unavailable(let reason):
      return .unavailable(windowLabel: "7D", reason: reason)
    case .expired(let reason):
      var reading = NotchUsageReading.unavailable(windowLabel: "7D", reason: reason)
      reading.needsReauth = true
      return reading
    case .loaded(let snapshot):
      if let weekly = snapshot.weekly {
        let session = snapshot.fiveHour.map {
          "5H \(Int(((1 - $0.utilization) * 100).rounded()))% remaining"
        }
        return .loaded(windowLabel: "7D", window: weekly, secondaryLine: session)
      }
      if let fiveHour = snapshot.fiveHour {
        return .loaded(windowLabel: "5H", window: fiveHour)
      }
      return .unavailable(windowLabel: "7D", reason: "Codex n'a renvoyé aucun quota.")
    }
  }

  /// Un fournisseur en échec garde son propre état d'erreur, avec la raison réelle et, quand
  /// seule une reconnexion y remédie, l'action qui la propose.
  static func failure(of provider: NotchUsageProvider, error: Error) -> NotchUsageReading {
    var reading = NotchUsageReading.unavailable(
      windowLabel: provider.windowLabel, reason: error.localizedDescription)
    switch provider {
    case .claude:
      if case ClaudeUsageCredentialError.expired = error { reading.needsReauth = true }
    case .codex:
      reading.needsReauth = CodexUsageState.requiresLogin(error)
    case .copilot:
      break
    }
    return reading
  }
}
