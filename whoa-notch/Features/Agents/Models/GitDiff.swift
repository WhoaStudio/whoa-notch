import Foundation

/// Le fichier dont on veut voir le diff : son chemin absolu et le dossier de la session.
nonisolated struct DiffTarget: Hashable, Sendable {
  var path: String
  var cwd: String?
}

/// Une ligne du diff tel que la fenêtre d'aperçu le montre.
nonisolated struct DiffLine: Equatable, Sendable {
  nonisolated enum Kind: Equatable, Sendable {
    /// L'en-tête d'un bloc (`@@ -1,3 +1,4 @@ …`).
    case hunk
    case context
    case added
    case removed
    /// `\ No newline at end of file`.
    case note
  }

  var kind: Kind
  /// Numéro dans l'ancien fichier (absent pour une ligne ajoutée).
  var oldNumber: Int?
  /// Numéro dans le nouveau fichier (absent pour une ligne retirée).
  var newNumber: Int?
  var text: String
}

/// Le diff d'un fichier contre le dernier commit.
nonisolated struct GitDiff: Equatable, Sendable {
  nonisolated enum Change: Equatable, Sendable {
    case modified
    case added
    case deleted
    case renamed(from: String)
  }

  /// Lignes gardées au plus ; au-delà, le diff est tronqué.
  static let lineLimit = 400

  var path: String
  var change: Change = .modified
  var isBinary = false
  var additions = 0
  var deletions = 0
  var lines: [DiffLine] = []
  /// Le diff a plus de lignes que `lineLimit` : seules les premières sont gardées.
  var isTruncated = false
  /// Le texte complet, gardé seulement quand le diff est tronqué (pour « Open full diff »).
  var fullText: String?
}

/// Lit la sortie de `git diff` (format unifié) d'un seul fichier, renommé ou non.
nonisolated enum GitDiffParser {

  /// - Parameters:
  ///   - text: la sortie de `git diff`.
  ///   - path: le chemin affiché quand le diff n'en donne pas (`rename to` l'emporte).
  ///   - lineLimit: lignes gardées au plus ; les compteurs, eux, portent sur tout le diff.
  static func parse(_ text: String, path: String, lineLimit: Int = GitDiff.lineLimit) -> GitDiff {
    var diff = GitDiff(path: path)
    var renameFrom: String?
    var renameTo: String?
    var inHunk = false
    var oldNumber = 0
    var newNumber = 0

    func keep(_ line: DiffLine) {
      if diff.lines.count < lineLimit { diff.lines.append(line) } else { diff.isTruncated = true }
    }

    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(raw)
      if line.hasPrefix("@@") {
        guard let start = hunkStart(line) else { continue }
        inHunk = true
        oldNumber = start.old
        newNumber = start.new
        keep(DiffLine(kind: .hunk, text: line))
        continue
      }
      if !inHunk {
        // L'en-tête du fichier : ce qui change, avant le premier bloc.
        if line.hasPrefix("new file mode") {
          diff.change = .added
        } else if line.hasPrefix("deleted file mode") {
          diff.change = .deleted
        } else if line.hasPrefix("rename from ") {
          renameFrom = String(line.dropFirst("rename from ".count))
        } else if line.hasPrefix("rename to ") {
          renameTo = String(line.dropFirst("rename to ".count))
        } else if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
          diff.isBinary = true
          if line.contains(" /dev/null and ") { diff.change = .added }
          if line.hasSuffix(" and /dev/null differ") { diff.change = .deleted }
        }
        continue
      }
      // Dans un bloc : le premier caractère donne le type de la ligne.
      switch line.first {
      case "+":
        diff.additions += 1
        keep(DiffLine(kind: .added, newNumber: newNumber, text: String(line.dropFirst())))
        newNumber += 1
      case "-":
        diff.deletions += 1
        keep(DiffLine(kind: .removed, oldNumber: oldNumber, text: String(line.dropFirst())))
        oldNumber += 1
      case " ":
        keep(
          DiffLine(
            kind: .context, oldNumber: oldNumber, newNumber: newNumber,
            text: String(line.dropFirst())))
        oldNumber += 1
        newNumber += 1
      case "\\":
        keep(DiffLine(kind: .note, text: String(line.dropFirst(2))))
      default:
        // La ligne vide qui clôt la sortie.
        break
      }
    }

    if let renameFrom, let renameTo {
      diff.change = .renamed(from: renameFrom)
      diff.path = renameTo
    }
    if diff.isTruncated { diff.fullText = text }
    return diff
  }

  /// `@@ -12,3 +14,5 @@` → (12, 14). Une longueur absente vaut un.
  static func hunkStart(_ header: String) -> (old: Int, new: Int)? {
    let parts = header.split(separator: " ")
    guard parts.count >= 3, parts[0] == "@@", parts[1].hasPrefix("-"), parts[2].hasPrefix("+")
    else { return nil }
    func start(_ part: Substring) -> Int? {
      Int(part.dropFirst().split(separator: ",").first ?? "")
    }
    guard let old = start(parts[1]), let new = start(parts[2]) else { return nil }
    return (old, new)
  }
}

/// Ce que l'aperçu a trouvé pour un fichier.
nonisolated enum GitDiffResult: Equatable, Sendable {
  case diff(GitDiff)
  /// Le fichier est suivi par git et n'a pas changé depuis le dernier commit.
  case unchanged
  /// Pas de diff à montrer, avec la raison (« Not a git repository »…).
  case unavailable(String)
}
