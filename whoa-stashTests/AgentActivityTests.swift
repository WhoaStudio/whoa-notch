import Foundation
import Testing

@testable import whoa_stash

@Suite struct AgentActivityTests {

    private func decode(_ json: String) -> AgentEvent? {
        AgentEvent.decode(Data(json.utf8))
    }

    private func tool(_ name: String, _ input: String = "{}", session: String = "s") -> AgentEvent {
        decode(#"{"kind":"tool","payload":{"session_id":"\#(session)","cwd":"/p/korus","tool_name":"\#(name)","tool_input":\#(input)}}"#)!
    }

    // MARK: - Correspondance outil → étape

    @Test func lesOutilsDeLectureSontL_etapeRead() {
        #expect(tool("Read", #"{"file_path":"/p/korus/a.ts","offset":10}"#).tool?.step == .read)
        #expect(tool("Grep", #"{"pattern":"TVA"}"#).tool?.step == .read)
        #expect(tool("WebFetch", #"{"url":"https://x.dev"}"#).tool?.filePath == "https://x.dev")
    }

    @Test func uneLectureGardeSonDecalage() {
        let call = tool("Read", #"{"file_path":"/p/korus/a.ts","offset":10}"#).tool
        #expect(call?.startLine == 10)
        #expect(call?.snippet.isEmpty == true)
    }

    @Test func uneEditionMontreLeTexteEcrit() {
        let call = tool("Edit", #"{"file_path":"/p/korus/a.ts","old_string":"x","new_string":"a\nb"}"#).tool
        #expect(call?.step == .edit)
        #expect(call?.snippet == ["a", "b"])
        let write = tool("Write", #"{"file_path":"/p/korus/b.ts","content":"un"}"#).tool
        #expect(write?.snippet == ["un"])
    }

    @Test func bashMontreLaCommande() {
        let call = tool("Bash", #"{"command":"npm test\nnpm run lint"}"#).tool
        #expect(call?.step == .bash)
        #expect(call?.snippet == ["npm test", "npm run lint"])
    }

    @Test func unOutilInconnuNAvancePasLaListe() {
        #expect(tool("mcp__x__y").tool?.step == nil)
    }

    @Test func lesQuestionsNeFontPasAvancerLActivite() {
        #expect(decode(#"{"kind":"tool","payload":{"tool_name":"AskUserQuestion","tool_input":{}}}"#) == nil)
    }

    @Test func lApercuEstLimiteAuxLignesMaximales() {
        let text = (1...30).map(String.init).joined(separator: "\n")
        #expect(ToolCall.lines(of: text).count == ToolCall.previewLines)
        #expect(ToolCall.lines(of: String(repeating: "x", count: 500)).first?.count == 120)
    }

    // MARK: - Aperçu d'un fichier lu

    @Test func apercuDUnFichierDuDossierDeLaSession() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("act-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try (1...20).map { "ligne \($0)" }.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        let call = ToolCall(name: "Read", step: .read, filePath: file.path, startLine: 3, cwd: dir.path)
        let lines = try #require(ToolCall.filePreview(call))
        #expect(lines.first == "ligne 3")
        #expect(lines.count == ToolCall.previewLines)
    }

    @Test func pasDApercuPourUnFichierHorsDuDossier() throws {
        let call = ToolCall(name: "Read", step: .read, filePath: "/etc/hosts", cwd: "/Users/x/projet")
        #expect(ToolCall.filePreview(call) == nil)
    }

    // MARK: - Store

    private let none: (ToolCall) -> [String]? = { _ in nil }

    @Test func lEtapeAvanceEtLesEtapesPasseesRestent() {
        var store = AgentActivityStore()
        store.apply(tool("Read"), preview: none)
        store.apply(tool("Edit", #"{"file_path":"/p/korus/a.ts","new_string":"x"}"#), preview: none)
        #expect(store.current?.step == .edit)
        #expect(store.current?.visited == [.read, .edit])
        #expect(store.current?.project == "korus")
    }

    @Test func stopTermineLeTourEtUnNouveauPromptRepart() {
        var store = AgentActivityStore()
        store.apply(tool("Bash", #"{"command":"ls"}"#), preview: none)
        store.apply(AgentEvent(kind: .finished, project: "korus", sessionID: "s"))
        #expect(store.current?.step == .done)
        store.apply(AgentEvent(kind: .turnStart, project: "korus", sessionID: "s"))
        #expect(store.current?.step == nil)
        #expect(store.current?.visited.isEmpty == true)
    }

    @Test func laFinDeSessionRetireLActivite() {
        var store = AgentActivityStore()
        store.apply(tool("Read"), preview: none)
        store.apply(AgentEvent(kind: .sessionEnd, project: "korus", sessionID: "s"))
        #expect(store.current == nil)
    }

    @Test func lApercuDuDisqueComplete() {
        var store = AgentActivityStore()
        store.apply(tool("Read", #"{"file_path":"/p/korus/a.ts"}"#), preview: { _ in ["ligne"] })
        #expect(store.current?.snippet == ["ligne"])
    }

    @Test func laSessionLaPlusRecenteEstMontree() {
        var store = AgentActivityStore()
        store.apply(tool("Read", session: "a"), preview: none)
        store.apply(tool("Bash", #"{"command":"ls"}"#, session: "b"), preview: none)
        #expect(store.current?.step == .bash)
        store.apply(tool("Read", session: "a"), preview: none)
        #expect(store.current?.step == .read)
    }

    @Test func uneActiviteSansNouvelleExpire() {
        var store = AgentActivityStore()
        let start = Date(timeIntervalSince1970: 1_000)
        store.apply(tool("Read"), now: start, preview: none)
        let early = store.expire(now: start.addingTimeInterval(60))
        #expect(!early)
        let late = store.expire(now: start.addingTimeInterval(AgentActivityStore.workingLifetime + 1))
        #expect(late)
        #expect(store.current == nil)
    }

    @Test func unTourTermineExpireVite() {
        var store = AgentActivityStore()
        let start = Date(timeIntervalSince1970: 1_000)
        store.apply(tool("Read"), now: start, preview: none)
        store.apply(AgentEvent(kind: .finished, project: "korus", sessionID: "s"), now: start)
        let expired = store.expire(now: start.addingTimeInterval(AgentActivityStore.finishedLifetime + 1))
        #expect(expired)
    }

    @Test func unOutilQuiDemarreNeLevePasLaDemandeDeSaSession() {
        var prompts = AgentPromptStore()
        prompts.apply(AgentEvent(kind: .needsInput, project: "p", sessionID: "s", prompt: .message("?"), replyID: "r"))
        let changed = prompts.apply(tool("Read"))
        #expect(!changed)
        #expect(prompts.current != nil)
    }
}
