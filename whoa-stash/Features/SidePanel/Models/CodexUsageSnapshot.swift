import Foundation

/// Les deux fenêtres de quota de Codex : la session glissante de 5 h et le quota hebdomadaire.
/// Chacune peut manquer — certains forfaits n'exposent que l'hebdomadaire.
struct CodexUsageSnapshot: Equatable, Sendable {
    let fiveHour: ClaudeUsageWindow?
    let weekly: ClaudeUsageWindow?
}

enum CodexUsageState: Equatable {
    case loading
    case loaded(CodexUsageSnapshot)
    case unavailable(reason: String)
    /// Connexion ChatGPT absente ou refusée : seule une reconnexion dans Codex y remédie.
    case expired(reason: String)

    var snapshot: CodexUsageSnapshot? {
        if case let .loaded(snapshot) = self { return snapshot }
        return nil
    }

    /// Connexion absente ou refusée par le serveur, par opposition à une panne passagère.
    static func requiresLogin(_ error: Error) -> Bool {
        if case CodexUsageCredentialError.notSignedIn = error { return true }
        if case let CodexUsageServiceError.badStatus(code) = error { return code == 401 || code == 403 }
        return false
    }
}
