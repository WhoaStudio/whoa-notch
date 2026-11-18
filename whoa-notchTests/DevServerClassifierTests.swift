import Foundation
import Testing

@testable import whoa_notch

/// Détection des serveurs de développement : lecture de `lsof`, racine de projet, framework,
/// groupes. Les dossiers de projet sont créés dans un « dossier personnel » temporaire.
struct DevServerClassifierTests {

  /// Un faux dossier personnel avec `portfolio` (dépôt git, monorepo : `apps/web` a son
  /// `package.json` avec Next.js) et `api` (`package.json` avec NestJS, sans git).
  private static func makeHome() throws -> String {
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("whoa-notch-tests-\(UUID().uuidString)").path
    let manager = FileManager.default
    try manager.createDirectory(atPath: home + "/portfolio/.git", withIntermediateDirectories: true)
    try manager.createDirectory(atPath: home + "/portfolio/apps/web", withIntermediateDirectories: true)
    try Data(#"{"dependencies":{"next":"15.0.0","react":"19"}}"#.utf8)
      .write(to: URL(fileURLWithPath: home + "/portfolio/apps/web/package.json"))
    try manager.createDirectory(atPath: home + "/api", withIntermediateDirectories: true)
    try Data(#"{"dependencies":{"@nestjs/core":"11"}}"#.utf8)
      .write(to: URL(fileURLWithPath: home + "/api/package.json"))
    return home
  }

  private func process(
    _ pid: Int32, _ name: String, port: Int, cwd: String?, arguments: [String] = [],
    leader: Int32? = nil
  ) -> ListeningProcess {
    ListeningProcess(
      pid: pid, name: name, ports: [port], cwd: cwd, arguments: arguments.isEmpty ? [name] : arguments,
      groupLeader: leader)
  }

  @Test("lsof : un processus, ses ports sans doublon, IPv4 et IPv6")
  func parsesLsofOutput() {
    let output = "p100\ncnode\nf20\nn*:3000\nf21\nn[::1]:3000\nf22\nn127.0.0.1:3001\np200\ncpostgres\nn127.0.0.1:5432\np300\ncidle\n"
    let parsed = DevServerClassifier.parseLsof(output)
    #expect(parsed.map(\.pid) == [100, 200])
    #expect(parsed[0].ports == [3000, 3001])
    #expect(parsed[1].name == "postgres")
  }

  @Test("la racine est celle du dépôt git, le framework vient du package.json le plus proche")
  func monorepoRootIsTheGitRoot() throws {
    let home = try Self.makeHome()
    let found = DevServerClassifier.projectRoot(
      for: process(1, "node", port: 3000, cwd: home + "/portfolio/apps/web"), home: home)
    #expect(found?.root == home + "/portfolio")
    #expect(found?.packageDirectory == home + "/portfolio/apps/web")
  }

  @Test("sans dépôt git, le dossier du package.json est la racine")
  func packageDirectoryIsTheRootWithoutGit() throws {
    let home = try Self.makeHome()
    let found = DevServerClassifier.projectRoot(
      for: process(1, "node", port: 3001, cwd: home + "/api"), home: home)
    #expect(found?.root == home + "/api")
  }

  @Test("un dossier hors du dossier personnel n'est jamais un projet")
  func foldersOutsideHomeAreNotProjects() throws {
    let home = try Self.makeHome()
    let found = DevServerClassifier.projectRoot(
      for: process(1, "postgres", port: 5432, cwd: "/opt/homebrew/var/postgresql@18"), home: home)
    #expect(found == nil)
  }

  @Test("le framework se lit d'abord dans la commande, puis dans les dépendances")
  func frameworkRules() {
    #expect(
      DevServerClassifier.framework(
        name: "node", arguments: ["node", "/p/node_modules/next/dist/bin/next", "dev"],
        dependencies: []) == .nextjs)
    #expect(
      DevServerClassifier.framework(
        name: "node", arguments: ["node", "server.js"], dependencies: ["@nestjs/core", "express"])
        == .nestjs)
    #expect(
      DevServerClassifier.framework(
        name: "bun", arguments: ["bun", "run", "src/index.ts"], dependencies: ["hono"]) == .hono)
    #expect(
      DevServerClassifier.framework(
        name: "postgres", arguments: ["/opt/homebrew/bin/postgres", "-D", "/x"], dependencies: [])
        == .postgres)
    #expect(DevServerClassifier.framework(name: "node", arguments: ["node"], dependencies: []) == .node)
    #expect(DevServerClassifier.framework(name: "Raycast", arguments: ["Raycast"], dependencies: []) == nil)
  }

  @Test("les serveurs se groupent par projet ; Postgres sans projet va dans Other / System")
  func groupsByProject() throws {
    let home = try Self.makeHome()
    let groups = DevServerClassifier.group(
      [
        process(10, "node", port: 3000, cwd: home + "/portfolio/apps/web"),
        process(11, "node", port: 3001, cwd: home + "/api"),
        process(12, "postgres", port: 5432, cwd: "/opt/homebrew/var/postgresql@18"),
        process(13, "ControlCenter", port: 7000, cwd: "/"),
        // Un outil dont le dossier est un projet, mais qui n'est pas un serveur de développement.
        process(14, "claude", port: 56684, cwd: home + "/portfolio"),
      ], home: home)

    #expect(groups.map(\.name) == ["api", "portfolio", DetectedServerGroup.systemName])
    #expect(groups[1].servers.map(\.framework) == [.nextjs])
    #expect(groups[1].servers.first?.ports == [3000])
    #expect(groups[2].path == nil)
    #expect(groups[2].servers.map(\.framework) == [.postgres])
  }

  @Test("un serveur lancé depuis l'app porte le nom de son action")
  func actionServersAreLabelled() throws {
    let home = try Self.makeHome()
    let groups = DevServerClassifier.group(
      [process(10, "node", port: 3000, cwd: home + "/portfolio/apps/web", leader: 99)],
      home: home, actionGroups: [99: "Start dev server"])
    #expect(groups.first?.servers.first?.actionName == "Start dev server")
  }
}
