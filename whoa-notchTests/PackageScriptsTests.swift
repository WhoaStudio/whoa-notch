import Foundation
import Testing

@testable import whoa_notch

/// Scripts du `package.json` d'un projet et commande qui les lance.
struct PackageScriptsTests {

  private static func makeProject(_ packageJSON: String, files: [String] = []) throws -> String {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("whoa-notch-scripts-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    try Data(packageJSON.utf8).write(to: URL(fileURLWithPath: path + "/package.json"))
    for file in files { FileManager.default.createFile(atPath: path + "/" + file, contents: Data()) }
    return path
  }

  @Test("les scripts se lisent, les plus utiles d'abord")
  func readsScriptsInPriorityOrder() throws {
    let path = try Self.makeProject(
      #"{"scripts":{"zeta":"echo z","build":"next build","dev":"next dev","alpha":"echo a"}}"#)
    let scripts = PackageScripts.read(in: path)
    #expect(scripts.map(\.name) == ["dev", "build", "alpha", "zeta"])
    #expect(scripts.first?.body == "next dev")
  }

  @Test("sans package.json ni scripts, la liste est vide")
  func missingFileOrScriptsGivesNothing() throws {
    #expect(PackageScripts.read(in: "/nonexistent-\(UUID().uuidString)").isEmpty)
    #expect(PackageScripts.read(in: try Self.makeProject(#"{"name":"x"}"#)).isEmpty)
  }

  @Test("le gestionnaire vient du champ packageManager, sinon du fichier de verrouillage")
  func packageManagerDetection() throws {
    let declared = try Self.makeProject(#"{"packageManager":"pnpm@9.1.0"}"#, files: ["yarn.lock"])
    #expect(PackageScripts.packageManager(in: declared) == "pnpm")
    let locked = try Self.makeProject("{}", files: ["yarn.lock"])
    #expect(PackageScripts.packageManager(in: locked) == "yarn")
    let bun = try Self.makeProject("{}", files: ["bun.lock"])
    #expect(PackageScripts.packageManager(in: bun) == "bun")
    #expect(PackageScripts.packageManager(in: try Self.makeProject("{}")) == "npm")
  }

  @Test("la commande suit le gestionnaire ; un nom de commande réservée passe par run")
  func commandForScript() throws {
    let pnpm = try Self.makeProject("{}", files: ["pnpm-lock.yaml"])
    #expect(PackageScripts.command(for: "dev", in: pnpm) == "pnpm dev")
    #expect(PackageScripts.command(for: "install", in: pnpm) == "pnpm run install")
    let npm = try Self.makeProject("{}", files: ["package-lock.json"])
    #expect(PackageScripts.command(for: "dev", in: npm) == "npm run dev")
    let bun = try Self.makeProject("{}", files: ["bun.lockb"])
    #expect(PackageScripts.command(for: "dev", in: bun) == "bun run dev")
  }
}
