import Foundation

/// `--agent-sessions=sample` : six sessions fixes dans la liste de l'onglet AI (en cours, bloquée,
/// en attente, close), pour vérifier la liste, son défilement et le balayage sans lancer Claude
/// Code. Elles ne passent que par la liste : aucune carte de demande, et répondre n'envoie rien.
nonisolated enum AgentSessionSample {

  /// Un événement et son âge en secondes.
  typealias Step = (event: AgentEvent, secondsAgo: TimeInterval)

  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments) -> [Step]? {
    guard arguments.contains("--agent-sessions=sample") else { return nil }
    return steps
  }

  /// `--diff-popover=<fichier>` : la session « whoa-notch » est choisie et l'aperçu du diff de ce
  /// fichier s'ouvre seul, pour le voir sans survoler à la main.
  static var selectedSessionID: String? {
    CommandLine.arguments.contains { $0.hasPrefix("--diff-popover=") } ? "whoa-notch" : nil
  }

  private static func event(
    _ kind: AgentEvent.Kind, _ session: String, text: String? = nil, tool: ToolCall? = nil,
    prompt: AgentEvent.Prompt? = nil, replyID: String? = nil
  ) -> AgentEvent {
    AgentEvent(
      kind: kind, project: session, sessionID: session, prompt: prompt, replyID: replyID,
      tool: tool, text: text)
  }

  /// La racine du dépôt, déduite de l'emplacement de ce fichier : les éditions de l'exemple portent
  /// sur de vrais fichiers modifiés, pour que l'aperçu du diff montre un vrai diff.
  private static let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().path

  private static func repoEdit(_ file: String) -> ToolCall {
    ToolCall(
      name: "Edit", step: .edit, filePath: repositoryRoot + "/" + file, cwd: repositoryRoot)
  }

  private static var steps: [Step] {
    let edit = ToolCall(
      name: "Edit", step: .edit, filePath: "src/invoice.ts",
      snippet: ["const TVA = 0.2", "return sum * (1 + TVA)"],
      removed: ["const TVA = 0.196"])
    return [
      (event(.turnStart, "checkout-api", text: "Fix the VAT rounding"), 312),
      (event(.toolStart, "checkout-api", tool: ToolCall(name: "Read", step: .read, filePath: "src/invoice.ts")), 300),
      (event(.toolStart, "checkout-api", tool: edit), 240),
      (event(.toolStart, "checkout-api", tool: ToolCall(name: "Bash", step: .bash, snippet: ["npm test -- invoice"])), 20),

      (event(.turnStart, "docs-site", text: "Publish the changelog"), 190),
      (event(.toolStart, "docs-site", tool: ToolCall(name: "Read", step: .read, filePath: "CHANGELOG.md")), 170),
      (event(.needsInput, "docs-site", prompt: .tool(name: "Bash", detail: "git push origin main"), replyID: "sample-docs"), 60),

      (event(.turnStart, "whoa-notch", text: "Loosen the log spacing"), 4000),
      (event(.toolStart, "whoa-notch", tool: ToolCall(name: "Read", step: .read, filePath: repositoryRoot + "/whoa-notch/Features/Agents/Views/AgentActivityCardView.swift", cwd: repositoryRoot)), 3900),
      (event(.toolStart, "whoa-notch", tool: repoEdit("whoa-notch/Features/Agents/Models/AgentSession.swift")), 3850),
      (event(.toolStart, "whoa-notch", tool: repoEdit("whoa-notch/Features/Agents/Views/AgentSessionsView.swift")), 3820),
      (event(.toolStart, "whoa-notch", tool: repoEdit("whoa-notch/Features/Agents/Models/AgentSessionSample.swift")), 3800),
      (event(.toolStart, "whoa-notch", tool: repoEdit("whoa-notch/Resources/Assets.xcassets/MenuBarIcon.imageset/menubar-18.png")), 3780),
      (event(.finished, "whoa-notch", text: "Spacing loosened; tests pass."), 3700),

      (event(.turnStart, "design-tokens", text: "Rename the grey scale"), 900),
      (event(.toolStart, "design-tokens", tool: ToolCall(name: "Read", step: .read, filePath: "tokens/colors.json")), 880),
      (event(.sessionEnd, "design-tokens"), 820),

      (event(.turnStart, "infra", text: "Plan the staging change"), 140),
      (event(.toolStart, "infra", tool: ToolCall(name: "Bash", step: .bash, snippet: ["terraform plan"])), 90),

      (event(.turnStart, "mobile-app", text: "Bump the SDK"), 700),
      (event(.toolStart, "mobile-app", tool: ToolCall(name: "Read", step: .read, filePath: "package.json")), 690),
      (event(.sessionEnd, "mobile-app"), 650),
    ]
  }
}
