import AppKit
import OSLog

/// Rouvre la session d'un agent : lance sa commande (`claude`, `codex`) dans Terminal, qui
/// renouvelle la connexion au démarrage. L'app n'écrit jamais ces jetons elle-même.
///
/// Un fichier `.command` plutôt qu'un script Apple Events : Terminal l'ouvre directement, sans
/// demander l'autorisation d'automatisation.
enum AgentLoginLauncher {

  static func open(command: String) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "whoa-stash-\(command)-login.command")
    let script = "#!/bin/zsh -l\n\(command)\n"
    do {
      try script.write(to: url, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
      NSWorkspace.shared.open(url)
    } catch {
      Log.sidePanel.error(
        "ouverture de \(command) dans Terminal échouée — \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
