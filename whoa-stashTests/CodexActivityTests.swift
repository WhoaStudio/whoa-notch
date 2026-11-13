import Foundation
import Testing

@testable import whoa_stash

/// Journaux de session Codex : jetons, modèle et projet lus sur une entrée fixe.
@Suite struct CodexActivityTests {

  private func tokenCount(
    at stamp: String, input: Int, cached: Int, output: Int, total: Int
  ) -> String {
    """
    {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"token_count","info":{\
    "total_token_usage":{"total_tokens":\(total)},\
    "last_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),\
    "output_tokens":\(output)}}}}
    """
  }

  private var rollout: Data {
    let lines = [
      #"{"timestamp":"2026-11-10T09:00:00.000Z","type":"session_meta","payload":{"cwd":"/Users/x/whoa-stash"}}"#,
      #"{"timestamp":"2026-11-10T09:00:01.000Z","type":"turn_context","payload":{"model":"gpt-6.1-sol"}}"#,
      tokenCount(at: "2026-11-10T09:00:02.000Z", input: 1_000, cached: 400, output: 200, total: 1_200),
      // Même total : Codex répète l'événement quand seules les limites changent.
      tokenCount(at: "2026-11-10T09:00:03.000Z", input: 1_000, cached: 400, output: 200, total: 1_200),
      tokenCount(at: "2026-11-10T09:00:09.000Z", input: 500, cached: 0, output: 50, total: 1_750),
    ]
    return Data(lines.joined(separator: "\n").utf8)
  }

  @Test func `les jetons en cache sortent de l'entrée et les doublons sont ignorés`() {
    let records = ActivityLogParser.parseCodex(rollout, fileKey: "f", fallbackProject: "?")

    #expect(records.count == 2)
    #expect(records[0].tokens == TokenCounts(input: 600, output: 200, cacheRead: 400))
    #expect(records[1].tokens == TokenCounts(input: 500, output: 50, cacheRead: 0))
  }

  @Test func `le modèle et le projet viennent de la session`() {
    let records = ActivityLogParser.parseCodex(rollout, fileKey: "f", fallbackProject: "?")

    #expect(records.allSatisfy { $0.agent == .codex })
    #expect(records.allSatisfy { $0.model == "gpt-6.1-sol" })
    #expect(records.allSatisfy { $0.project == "whoa-stash" })
  }
}
