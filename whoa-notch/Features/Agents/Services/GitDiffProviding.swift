import Foundation

/// La source des diffs de l'aperçu. Lecture seule : rien n'est jamais écrit dans le dépôt.
protocol GitDiffProviding: Sendable {
  /// Le diff du fichier contre le dernier commit, calculé hors du fil principal.
  nonisolated func diff(for target: DiffTarget) async -> GitDiffResult
}

/// `--git-diff=sample` : des diffs fixes, sans lancer git. Le nom du fichier choisit le cas : `.png`
/// binaire, `new` ajouté, `old` renommé, `gone` supprimé, `big` tronqué, `same` inchangé, le reste modifié.
nonisolated struct MockGitDiffProvider: GitDiffProviding {

  static func fromLaunchArguments() -> MockGitDiffProvider? {
    CommandLine.arguments.contains("--git-diff=sample") ? MockGitDiffProvider() : nil
  }

  func diff(for target: DiffTarget) async -> GitDiffResult {
    try? await Task.sleep(for: .milliseconds(300))
    let name = URL(fileURLWithPath: target.path).lastPathComponent
    if name.hasSuffix(".png") {
      return .diff(GitDiff(path: name, change: .modified, isBinary: true))
    }
    if name.contains("same") { return .unchanged }
    let text: String
    switch true {
    case name.contains("new"): text = Self.added
    case name.contains("gone"): text = Self.deleted
    case name.contains("old"): text = Self.renamed
    case name.contains("big"): text = Self.big
    default: text = Self.modified
    }
    return .diff(GitDiffParser.parse(text, path: name))
  }

  private static let modified = """
    diff --git a/invoice.ts b/invoice.ts
    index 3b18e51..a4c0d2f 100644
    --- a/invoice.ts
    +++ b/invoice.ts
    @@ -8,7 +8,8 @@ import { Item } from './types'

    -const TVA = 0.196
    +const TVA = 0.2

     export function total(items: Item[]) {
       const sum = items.reduce((s, i) => s + i.price, 0)
    -  return sum * (1 + TVA)
    +  const rounded = Math.round(sum * (1 + TVA) * 100) / 100
    +  return rounded
     }
    """

  private static let added = """
    diff --git a/new.ts b/new.ts
    new file mode 100644
    --- /dev/null
    +++ b/new.ts
    @@ -0,0 +1,3 @@
    +export const answer = 42
    +export const question = 'unknown'
    +export default answer
    """

  private static let deleted = """
    diff --git a/gone.ts b/gone.ts
    deleted file mode 100644
    --- a/gone.ts
    +++ /dev/null
    @@ -1,2 +0,0 @@
    -export const legacy = true
    -export default legacy
    """

  private static let renamed = """
    diff --git a/src/old.ts b/src/renamed.ts
    similarity index 80%
    rename from src/old.ts
    rename to src/renamed.ts
    --- a/src/old.ts
    +++ b/src/renamed.ts
    @@ -1,3 +1,3 @@
     export function greet() {
    -  return 'hello'
    +  return 'hello, world'
     }
    """

  private static let big: String = {
    var lines = ["diff --git a/big.ts b/big.ts", "--- a/big.ts", "+++ b/big.ts", "@@ -1,500 +1,500 @@"]
    for index in 1...500 { lines.append("-const value\(index) = \(index)") }
    for index in 1...500 { lines.append("+const value\(index) = \(index * 2)") }
    return lines.joined(separator: "\n")
  }()
}
