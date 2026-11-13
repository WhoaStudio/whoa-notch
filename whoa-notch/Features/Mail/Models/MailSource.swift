import Foundation

/// Source de courrier entrant. L'encoche ne sait pas d'où vient un message : chaque fournisseur
/// (IMAP aujourd'hui) se contente de fournir ce flux.
nonisolated protocol MailSource: Sendable {
  /// Les nouveaux messages, au fil de l'eau. Ceux qui étaient déjà là au démarrage n'y figurent
  /// pas. Le flux se ferme, et la source s'arrête, quand la tâche qui le lit est annulée.
  func messages() -> AsyncStream<MailMessage>
}

/// `--mail=sample` : un message fixe environ 2 s après le lancement, sans réseau ni trousseau.
nonisolated struct MockMailSource: MailSource {

  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments) -> MockMailSource?
  {
    arguments.contains("--mail=sample") ? MockMailSource() : nil
  }

  func messages() -> AsyncStream<MailMessage> {
    AsyncStream { continuation in
      let task = Task {
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        continuation.yield(
          MailMessage(
            id: "mock-1",
            sender: "Ada Lovelace",
            subject: "Notes on the Analytical Engine",
            preview:
              "I have finished the translation and added a few notes of my own. Could you read the last section before Friday?",
            account: "sample"))
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
