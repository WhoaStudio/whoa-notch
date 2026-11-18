import Foundation
import Testing
import os

@testable import whoa_notch

/// Lance le vrai `git` dans un dépôt jetable : les cas que l'analyse seule ne couvre pas (fichier
/// pas encore suivi, supprimé, renommé, binaire, ignoré).
@Suite struct GitDiffServiceTests {

  private static let hasGit = GitDiffService.gitExecutable != nil

  /// Un dépôt avec un commit initial, qui disparaît avec l'objet.
  private final class Repo {
    let root: String
    private let git: String

    init() throws {
      git = GitDiffService.gitExecutable ?? ""
      // Résolu : `/var` est un lien vers `/private/var`, et git compare les chemins résolus.
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "whoa-notch-git-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      root = directory.resolvingSymlinksInPath().path
      try run(["init", "-q"])
      try write("a.txt", "one\ntwo\nthree\n")
      try write("old-name.txt", "alpha\nbeta\ngamma\ndelta\nepsilon\n")
      try write("pic.bin", Data([0, 1, 2, 3, 0, 255]))
      try write("gone.txt", "bye\n")
      try write(".gitignore", "secret.env\n")
      try run(["add", "-A"])
      try run(["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-q", "--no-verify", "-m", "init"])
    }

    deinit { try? FileManager.default.removeItem(atPath: root) }

    func path(_ name: String) -> String { root + "/" + name }

    func write(_ name: String, _ text: String) throws {
      try text.write(toFile: path(name), atomically: true, encoding: .utf8)
    }

    func write(_ name: String, _ data: Data) throws {
      try data.write(to: URL(fileURLWithPath: path(name)))
    }

    func run(_ arguments: [String]) throws {
      let result = GitDiffService.run(git, arguments, in: root)
      #expect(result?.status == 0, "git \(arguments.joined(separator: " ")) → \(String(describing: result?.status))")
    }

    func diff(_ name: String) -> GitDiffResult {
      GitDiffService.compute(DiffTarget(path: path(name), cwd: root))
    }
  }

  private func parsed(_ result: GitDiffResult) -> GitDiff? {
    if case .diff(let diff) = result { return diff }
    return nil
  }

  @Test("un fichier modifié montre ses lignes", .enabled(if: hasGit))
  func modified() throws {
    let repo = try Repo()
    try repo.write("a.txt", "one\nTWO\nthree\nfour\n")
    let diff = parsed(repo.diff("a.txt"))
    #expect(diff?.change == .modified)
    #expect(diff?.additions == 2 && diff?.deletions == 1)
  }

  @Test("un fichier suivi et inchangé n'a pas de diff", .enabled(if: hasGit))
  func unchanged() throws {
    let repo = try Repo()
    #expect(repo.diff("a.txt") == .unchanged)
  }

  @Test("un fichier pas encore suivi est tout ajouté", .enabled(if: hasGit))
  func untracked() throws {
    let repo = try Repo()
    try repo.write("fresh.txt", "x\ny\n")
    let diff = parsed(repo.diff("fresh.txt"))
    #expect(diff?.change == .added)
    #expect(diff?.additions == 2)
  }

  @Test("un fichier supprimé est tout retiré", .enabled(if: hasGit))
  func deleted() throws {
    let repo = try Repo()
    try FileManager.default.removeItem(atPath: repo.path("gone.txt"))
    let diff = parsed(repo.diff("gone.txt"))
    #expect(diff?.change == .deleted)
    #expect(diff?.deletions == 1)
  }

  @Test("un fichier renommé avec git mv est reconnu", .enabled(if: hasGit))
  func renamed() throws {
    let repo = try Repo()
    try repo.run(["mv", "old-name.txt", "new-name.txt"])
    try repo.write("new-name.txt", "alpha\nbeta\nGAMMA\ndelta\nepsilon\n")
    let diff = parsed(repo.diff("new-name.txt"))
    #expect(diff?.change == .renamed(from: "old-name.txt"))
    #expect(diff?.additions == 1 && diff?.deletions == 1)
  }

  @Test("un fichier binaire modifié est signalé sans ligne", .enabled(if: hasGit))
  func binary() throws {
    let repo = try Repo()
    try repo.write("pic.bin", Data([9, 8, 7, 0, 1, 2]))
    let diff = parsed(repo.diff("pic.bin"))
    #expect(diff?.isBinary == true)
    #expect(diff?.lines.isEmpty == true)
  }

  @Test("un fichier ignoré par git n'est pas montré", .enabled(if: hasGit))
  func ignored() throws {
    let repo = try Repo()
    try repo.write("secret.env", "TOKEN=1\n")
    #expect(repo.diff("secret.env") == .unavailable("Ignored by git"))
  }

  @Test("hors d'un dépôt, la raison est donnée", .enabled(if: hasGit))
  func outsideRepository() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "whoa-notch-plain-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("f.txt")
    try "x".write(to: file, atomically: true, encoding: .utf8)
    let result = GitDiffService.compute(DiffTarget(path: file.path, cwd: directory.path))
    #expect(result == .unavailable("Not in a git repository"))
  }

  @Test("l'ancien chemin d'un renommage est lu dans la liste des noms")
  func renameListing() {
    let listing = "M\ta.txt\nR087\told.txt\tnew.txt\nA\tb.txt\n"
    #expect(GitDiffService.renamedFrom(listing, to: "new.txt") == "old.txt")
    #expect(GitDiffService.renamedFrom(listing, to: "b.txt") == nil)
  }

  @Test("le cache ne lance le calcul qu'une fois par fichier")
  @MainActor func cacheComputesOnce() async {
    nonisolated final class Counter: GitDiffProviding, Sendable {
      let calls = OSAllocatedUnfairLock(initialState: 0)
      func diff(for target: DiffTarget) async -> GitDiffResult {
        calls.withLock { $0 += 1 }
        try? await Task.sleep(for: .milliseconds(50))
        return .unchanged
      }
    }
    let counter = Counter()
    let store = GitDiffStore(provider: counter)
    let target = DiffTarget(path: "/nonexistent/file.txt", cwd: nil)
    async let first = store.diff(for: target)
    async let second = store.diff(for: target)
    _ = await (first, second)
    _ = await store.diff(for: target)
    #expect(counter.calls.withLock { $0 } == 1)
    #expect(store.cached(for: target) == .unchanged)
  }
}
