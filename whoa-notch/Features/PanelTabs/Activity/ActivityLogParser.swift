import Foundation

/// Lit les journaux de session locaux des agents : un fichier `.jsonl` par session, une requête
/// par ligne. Ne garde que les nombres et les noms utiles aux mesures — jamais le texte des
/// conversations.
nonisolated enum ActivityLogParser {

  // MARK: - Claude Code

  private struct ClaudeLine: Decodable {
    struct Message: Decodable {
      struct Usage: Decodable {
        struct CacheCreation: Decodable {
          let ephemeral5mInputTokens: Int?
          let ephemeral1hInputTokens: Int?
          enum CodingKeys: String, CodingKey {
            case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
            case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
          }
        }
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheCreation: CacheCreation?
        enum CodingKeys: String, CodingKey {
          case inputTokens = "input_tokens"
          case outputTokens = "output_tokens"
          case cacheReadInputTokens = "cache_read_input_tokens"
          case cacheCreationInputTokens = "cache_creation_input_tokens"
          case cacheCreation = "cache_creation"
        }
      }
      let id: String?
      let model: String?
      let usage: Usage?
    }
    let timestamp: String?
    let cwd: String?
    let requestId: String?
    let message: Message?
  }

  private static let usageMarker = Data("\"usage\"".utf8)

  /// `fallbackProject` sert quand une ligne ne porte pas son dossier de travail.
  static func parseClaude(_ data: Data, fallbackProject: String) -> [ActivityRecord] {
    let decoder = JSONDecoder()
    let formatter = makeDateFormatter()
    var records: [ActivityRecord] = []

    for (index, line) in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
      .enumerated()
    {
      // Tri à bas coût : la plupart des lignes (messages utilisateur, outils) n'ont pas d'usage.
      guard line.range(of: usageMarker) != nil,
        let entry = try? decoder.decode(ClaudeLine.self, from: Data(line)),
        let message = entry.message,
        let usage = message.usage,
        let model = message.model, !model.hasPrefix("<"),
        let stamp = entry.timestamp, let date = formatter(stamp)
      else { continue }

      var tokens = TokenCounts(
        input: usage.inputTokens ?? 0,
        output: usage.outputTokens ?? 0,
        cacheRead: usage.cacheReadInputTokens ?? 0
      )
      if let split = usage.cacheCreation {
        tokens.cacheWrite5m = split.ephemeral5mInputTokens ?? 0
        tokens.cacheWrite1h = split.ephemeral1hInputTokens ?? 0
      } else {
        tokens.cacheWrite5m = usage.cacheCreationInputTokens ?? 0
      }

      let key = message.id.map { "\($0)|\(entry.requestId ?? "")" } ?? "\(stamp)#\(index)"
      records.append(
        ActivityRecord(
          key: key, date: date, agent: .claudeCode, model: model,
          project: projectName(entry.cwd) ?? fallbackProject, tokens: tokens))
    }
    return records
  }

  // MARK: - Codex

  /// Les sessions de Codex (`rollout-*.jsonl`) : le dossier et le modèle sont annoncés par
  /// `session_meta` et `turn_context`, les jetons par les événements `token_count`.
  static func parseCodex(_ data: Data, fileKey: String, fallbackProject: String) -> [ActivityRecord]
  {
    let formatter = makeDateFormatter()
    var records: [ActivityRecord] = []
    var project = fallbackProject
    var model = "codex"
    var lastTotal = -1

    for (index, line) in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
      .enumerated()
    {
      guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
        let type = object["type"] as? String,
        let payload = object["payload"] as? [String: Any]
      else { continue }

      switch type {
      case "session_meta", "turn_context":
        if let name = projectName(payload["cwd"] as? String) { project = name }
        if let name = payload["model"] as? String, !name.isEmpty { model = name }
      case "event_msg":
        guard payload["type"] as? String == "token_count",
          let info = payload["info"] as? [String: Any],
          let last = info["last_token_usage"] as? [String: Any],
          let stamp = object["timestamp"] as? String, let date = formatter(stamp)
        else { continue }
        // Codex répète le même événement quand seules les limites changent.
        let total = (info["total_token_usage"] as? [String: Any])?["total_tokens"] as? Int ?? -1
        if total >= 0 {
          guard total != lastTotal else { continue }
          lastTotal = total
        }
        let cached = last["cached_input_tokens"] as? Int ?? 0
        let tokens = TokenCounts(
          input: max(0, (last["input_tokens"] as? Int ?? 0) - cached),
          output: last["output_tokens"] as? Int ?? 0,
          cacheRead: cached
        )
        records.append(
          ActivityRecord(
            key: "codex|\(fileKey)|\(index)", date: date, agent: .codex,
            model: model, project: project, tokens: tokens))
      default:
        continue
      }
    }
    return records
  }

  // MARK: - Commun

  private static func projectName(_ cwd: String?) -> String? {
    guard let cwd, !cwd.isEmpty else { return nil }
    let name = URL(fileURLWithPath: cwd).lastPathComponent
    return name.isEmpty ? nil : name
  }

  /// Les horodatages portent des fractions de seconde ; certains non.
  private static func makeDateFormatter() -> (String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    return { fractional.date(from: $0) ?? plain.date(from: $0) }
  }
}
