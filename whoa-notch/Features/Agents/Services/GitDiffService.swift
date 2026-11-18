import Foundation
import os

/// Calcule le diff d'un fichier avec `git`, en lecture seule (`GIT_OPTIONAL_LOCKS=0`, aucune
/// commande qui écrit). Tout se passe hors du fil principal, avec une limite de temps et de taille.
nonisolated struct GitDiffService: GitDiffProviding {

  /// Temps laissé à une commande git.
  private static let timeout: TimeInterval = 6
  /// Sortie gardée au plus : au-delà, la commande est arrêtée et le diff compté comme tronqué.
  private static let outputLimit = 4 * 1024 * 1024

  func diff(for target: DiffTarget) async -> GitDiffResult {
    await Task.detached(priority: .userInitiated) { Self.compute(target) }.value
  }

  // MARK: - Calcul

  static func compute(_ target: DiffTarget) -> GitDiffResult {
    guard let git = gitExecutable else { return .unavailable("git is not installed") }
    guard let directory = nearestExistingDirectory(of: target) else {
      return .unavailable("The folder no longer exists")
    }
    guard
      let top = run(git, ["rev-parse", "--show-toplevel"], in: directory), top.status == 0,
      let root = String(data: top.output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !root.isEmpty
    else { return .unavailable("Not in a git repository") }

    let literal = ":(literal)" + target.path
    let exists = FileManager.default.fileExists(atPath: target.path)

    // Un fichier ignoré par git (`.env`…) n'est pas montré : son contenu n'a pas à s'afficher au survol.
    if let ignored = run(git, ["check-ignore", "-q", "--", target.path], in: root), ignored.status == 0 {
      return .unavailable("Ignored by git")
    }

    let base = ["diff", "--no-color", "--no-ext-diff", "-M", "--unified=3"]
    guard let tracked = run(git, base + ["HEAD", "--", literal], in: root) else {
      return .unavailable("git did not answer in time")
    }
    // Statut 128 : pas encore de commit, tout est nouveau.
    if tracked.status == 0, !tracked.output.isEmpty {
      return parsed(tracked, target: target, git: git, root: root, base: base, literal: literal)
    }
    if tracked.status == 0 {
      // Rien contre HEAD : suivi et inchangé, ou pas suivi du tout.
      if isTracked(git, literal, root: root) { return .unchanged }
    } else if tracked.status != 128 {
      return .unavailable("git could not compare this file")
    }
    guard exists else { return .unavailable("File not found") }
    // Un fichier pas encore suivi : tout y est ajouté. `--no-index` rend 1 quand il y a une différence.
    guard let fresh = run(git, base + ["--no-index", "--", "/dev/null", target.path], in: root),
      fresh.status == 1 || fresh.status == 0
    else { return .unavailable("git could not read this file") }
    guard !fresh.output.isEmpty else { return .unchanged }
    return parsed(fresh, target: target, git: git, root: root, base: base, literal: literal)
  }

  private static func parsed(
    _ result: (status: Int32, output: Data, isCut: Bool), target: DiffTarget, git: String,
    root: String, base: [String], literal: String
  ) -> GitDiffResult {
    let name = URL(fileURLWithPath: target.path).lastPathComponent
    var text = String(decoding: result.output, as: UTF8.self)
    var diff = GitDiffParser.parse(text, path: name)

    // Un fichier ajouté peut être un renommage dont l'ancien chemin n'était pas dans le filtre.
    if diff.change == .added, !diff.isBinary, !result.isCut,
      let listed = run(git, ["diff", "--no-color", "-M", "--name-status", "HEAD"], in: root),
      let relative = relativePath(of: target.path, root: root),
      let from = renamedFrom(String(decoding: listed.output, as: UTF8.self), to: relative),
      let again = run(
        git, base + ["HEAD", "--", ":(literal)" + root + "/" + from, literal], in: root),
      !again.output.isEmpty
    {
      text = String(decoding: again.output, as: UTF8.self)
      diff = GitDiffParser.parse(text, path: name)
    }
    if result.isCut {
      diff.isTruncated = true
      diff.fullText = text
    }
    return .diff(diff)
  }

  /// `R087\told\tnew` → l'ancien chemin du fichier `to`.
  static func renamedFrom(_ nameStatus: String, to relative: String) -> String? {
    for line in nameStatus.split(separator: "\n") {
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      if fields.count == 3, fields[0].hasPrefix("R"), String(fields[2]) == relative {
        return String(fields[1])
      }
    }
    return nil
  }

  private static func relativePath(of path: String, root: String) -> String? {
    // `/var` et `/private/var` désignent le même dossier : on compare les chemins résolus.
    let resolvedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
    let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    guard resolved.hasPrefix(resolvedRoot + "/") else { return nil }
    return String(resolved.dropFirst(resolvedRoot.count + 1))
  }

  private static func isTracked(_ git: String, _ literal: String, root: String) -> Bool {
    run(git, ["ls-files", "--error-unmatch", "--", literal], in: root)?.status == 0
  }

  /// Le dossier du fichier, ou le plus proche qui existe encore (fichier supprimé), ou celui de la session.
  private static func nearestExistingDirectory(of target: DiffTarget) -> String? {
    var url = URL(fileURLWithPath: target.path).deletingLastPathComponent()
    var isDirectory: ObjCBool = false
    while url.path != "/" {
      if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
        return url.path
      }
      url.deleteLastPathComponent()
    }
    if let cwd = target.cwd, FileManager.default.fileExists(atPath: cwd) { return cwd }
    return nil
  }

  // MARK: - git

  /// Le premier `git` trouvé. `/usr/bin/git` n'est pas essayé : sans les outils de ligne de
  /// commande, il ouvrirait la fenêtre d'installation de macOS.
  static let gitExecutable: String? = [
    "/opt/homebrew/bin/git", "/usr/local/bin/git",
    "/Library/Developer/CommandLineTools/usr/bin/git",
    "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
  ].first { FileManager.default.isExecutableFile(atPath: $0) }

  /// Lance git dans `directory`. `nil` : impossible à lancer ou trop long ; `isCut` : sortie coupée.
  static func run(_ git: String, _ arguments: [String], in directory: String)
    -> (status: Int32, output: Data, isCut: Bool)?
  {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: git)
    process.arguments = ["-C", directory, "-c", "core.quotepath=off"] + arguments
    process.environment = [
      "GIT_OPTIONAL_LOCKS": "0", "LC_ALL": "C", "HOME": NSHomeDirectory(),
      "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      Log.agents.error("git impossible à lancer : \(error.localizedDescription, privacy: .public)")
      return nil
    }

    // Trop long : on arrête git, la lecture en bas se termine alors d'elle-même.
    let timedOut = TimeoutFlag()
    let watchdog = DispatchWorkItem {
      timedOut.set()
      if process.isRunning { process.terminate() }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

    var output = Data()
    var isCut = false
    while let chunk = try? pipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
      output.append(chunk)
      if output.count > outputLimit {
        isCut = true
        if process.isRunning { process.terminate() }
        break
      }
    }
    process.waitUntilExit()
    watchdog.cancel()
    if timedOut.isSet { return nil }
    return (process.terminationStatus, output, isCut)
  }
}

/// Un drapeau levé depuis une autre file que celle qui le lit.
private nonisolated final class TimeoutFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  var isSet: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set() {
    lock.lock()
    value = true
    lock.unlock()
  }
}
