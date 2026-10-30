import Foundation
import Testing
@testable import whoa_stash

@Suite struct ClaudeHookInstallerTests {

    private func makeInstaller(settings: String?) throws -> (ClaudeHookInstaller, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let settingsURL = dir.appendingPathComponent("settings.json")
        if let settings { try settings.write(to: settingsURL, atomically: true, encoding: .utf8) }
        let installer = ClaudeHookInstaller(
            settingsURL: settingsURL, scriptURL: dir.appendingPathComponent("support dir/whoa-hook"))
        return (installer, dir)
    }

    private func readRoot(_ installer: ClaudeHookInstaller) throws -> [String: Any] {
        let data = try Data(contentsOf: installer.settingsURL)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let existing = """
        {
          "model": "opus",
          "hooks": {
            "Stop": [{"hooks": [{"type": "command", "command": "echo autre"}]}],
            "PostToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": "fmt"}]}]
          }
        }
        """

    @Test func installeEnGardantLesAutresHooksEtCles() throws {
        let (installer, _) = try makeInstaller(settings: existing)
        try installer.install()
        let root = try readRoot(installer)
        #expect(root["model"] as? String == "opus")
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect((hooks["PostToolUse"] as? [Any])?.count == 2)
        #expect((hooks["Stop"] as? [Any])?.count == 2)
        #expect((hooks["Notification"] as? [Any])?.count == 1)
        #expect(installer.status() == .installed)
    }

    @Test func installerDeuxFoisNeCreePasDeDoublon() throws {
        let (installer, _) = try makeInstaller(settings: existing)
        try installer.install()
        let once = try Data(contentsOf: installer.settingsURL)
        try installer.install()
        #expect(try Data(contentsOf: installer.settingsURL) == once)
    }

    @Test func ecritUneSauvegardeAvantDeModifier() throws {
        let (installer, _) = try makeInstaller(settings: existing)
        try installer.install()
        let backup = installer.settingsURL.appendingPathExtension("whoa-stash.bak")
        #expect(try String(contentsOf: backup, encoding: .utf8) == existing)
    }

    @Test func desinstallerRestitueLeContenuDOrigine() throws {
        let (installer, _) = try makeInstaller(settings: existing)
        try installer.install()
        try installer.uninstall()
        #expect(try String(contentsOf: installer.settingsURL, encoding: .utf8) == existing)
        #expect(installer.status() == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: installer.scriptURL.path))
    }

    @Test func desinstallerNeRetireQueNosEntreesSiLeFichierADejaChange() throws {
        let (installer, _) = try makeInstaller(settings: existing)
        try installer.install()
        var root = try readRoot(installer)
        root["theme"] = "dark"
        try JSONSerialization.data(withJSONObject: root).write(to: installer.settingsURL)
        try installer.uninstall()
        let after = try readRoot(installer)
        #expect(after["theme"] as? String == "dark")
        let hooks = try #require(after["hooks"] as? [String: Any])
        #expect((hooks["Stop"] as? [Any])?.count == 1)
        #expect(hooks["Notification"] == nil)
    }

    @Test func fichierAbsentEstCreeEtSupprimeALaDesinstallation() throws {
        let (installer, _) = try makeInstaller(settings: nil)
        try installer.install()
        #expect(installer.status() == .installed)
        try installer.uninstall()
        #expect(!FileManager.default.fileExists(atPath: installer.settingsURL.path))
    }

    @Test func unFichierIllisibleResteIntact() throws {
        let (installer, _) = try makeInstaller(settings: "pas du json")
        #expect(throws: ClaudeHookInstaller.InstallError.self) { try installer.install() }
        #expect(try String(contentsOf: installer.settingsURL, encoding: .utf8) == "pas du json")
    }

    @Test func decodeLeNomDuProjetDepuisLeCwd() throws {
        let line = #"{"kind":"stop","payload":{"cwd":"/Users/x/Dev/mon-projet","session_id":"1"}}"#
        let event = try #require(AgentEvent.decode(Data(line.utf8)))
        #expect(event == AgentEvent(kind: .finished, project: "mon-projet", sessionID: "1"))
        #expect(AgentEvent.decode(Data(#"{"kind":"autre"}"#.utf8)) == nil)
    }

    @Test func uneInstallationAncienneEstRemplaceeSansDoublon() throws {
        let legacy = """
            {"hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": "'LEGACY' clear"}]}]}}
            """
        let (installer, _) = try makeInstaller(settings: legacy)
        var root = try readRoot(installer)
        var hooks = try #require(root["hooks"] as? [String: Any])
        hooks["UserPromptSubmit"] = [["hooks": [["type": "command", "command": "'\(installer.scriptURL.path)' clear"]]]]
        root["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: root).write(to: installer.settingsURL)

        try installer.install()
        let after = try #require(try readRoot(installer)["hooks"] as? [String: Any])
        let groups = try #require(after["UserPromptSubmit"] as? [[String: Any]])
        #expect(groups.count == 1)
        let command = ((groups[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String) ?? ""
        #expect(command.hasSuffix(" turn"))
    }
}
