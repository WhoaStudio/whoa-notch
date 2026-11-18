import Foundation
import Testing

@testable import whoa_notch

@Suite struct GitDiffParserTests {

  private let modified = """
    diff --git a/a.ts b/a.ts
    index 1111111..2222222 100644
    --- a/a.ts
    +++ b/a.ts
    @@ -3,4 +3,5 @@ function f() {
     keep
    -old
    +new
    +extra
     tail
    \\ No newline at end of file
    """

  @Test("un fichier modifié donne ses blocs, ses compteurs et ses numéros de ligne")
  func modifiedFile() {
    let diff = GitDiffParser.parse(modified, path: "a.ts")
    #expect(diff.change == .modified)
    #expect(diff.additions == 2)
    #expect(diff.deletions == 1)
    #expect(diff.lines.first?.kind == .hunk)
    let removed = diff.lines.first { $0.kind == .removed }
    #expect(removed?.text == "old")
    #expect(removed?.oldNumber == 4)
    #expect(removed?.newNumber == nil)
    let extra = diff.lines.first { $0.text == "extra" }
    #expect(extra?.kind == .added)
    #expect(extra?.newNumber == 5)
    #expect(extra?.oldNumber == nil)
    let tail = diff.lines.first { $0.text == "tail" }
    #expect(tail?.oldNumber == 5 && tail?.newNumber == 6)
    #expect(diff.lines.last?.kind == .note)
    #expect(!diff.isTruncated)
  }

  @Test("un fichier ajouté n'a que des lignes ajoutées")
  func addedFile() {
    let text = """
      diff --git a/n.ts b/n.ts
      new file mode 100644
      --- /dev/null
      +++ b/n.ts
      @@ -0,0 +1,2 @@
      +one
      +two
      """
    let diff = GitDiffParser.parse(text, path: "n.ts")
    #expect(diff.change == .added)
    #expect(diff.additions == 2 && diff.deletions == 0)
    #expect(diff.lines.filter { $0.kind == .added }.map(\.newNumber) == [1, 2])
  }

  @Test("un fichier supprimé n'a que des lignes retirées")
  func deletedFile() {
    let text = """
      diff --git a/g.ts b/g.ts
      deleted file mode 100644
      --- a/g.ts
      +++ /dev/null
      @@ -1,2 +0,0 @@
      -one
      -two
      """
    let diff = GitDiffParser.parse(text, path: "g.ts")
    #expect(diff.change == .deleted)
    #expect(diff.deletions == 2 && diff.additions == 0)
  }

  @Test("un renommage garde l'ancien chemin et affiche le nouveau")
  func renamedFile() {
    let text = """
      diff --git a/src/old.ts b/src/new.ts
      similarity index 80%
      rename from src/old.ts
      rename to src/new.ts
      --- a/src/old.ts
      +++ b/src/new.ts
      @@ -1,2 +1,2 @@
       same
      -before
      +after
      """
    let diff = GitDiffParser.parse(text, path: "new.ts")
    #expect(diff.change == .renamed(from: "src/old.ts"))
    #expect(diff.path == "src/new.ts")
    #expect(diff.additions == 1 && diff.deletions == 1)
  }

  @Test("un renommage pur n'a aucune ligne")
  func pureRename() {
    let text = """
      diff --git a/x.ts b/y.ts
      similarity index 100%
      rename from x.ts
      rename to y.ts
      """
    let diff = GitDiffParser.parse(text, path: "y.ts")
    #expect(diff.change == .renamed(from: "x.ts"))
    #expect(diff.lines.isEmpty && !diff.isBinary)
  }

  @Test("un fichier binaire est reconnu, sans ligne")
  func binaryFile() {
    let changed = GitDiffParser.parse(
      "diff --git a/i.png b/i.png\nindex 1..2 100644\nBinary files a/i.png and b/i.png differ\n",
      path: "i.png")
    #expect(changed.isBinary && changed.lines.isEmpty && changed.change == .modified)

    let added = GitDiffParser.parse(
      "diff --git a/i.png b/i.png\nnew file mode 100644\nBinary files /dev/null and b/i.png differ\n",
      path: "i.png")
    #expect(added.isBinary && added.change == .added)

    let deleted = GitDiffParser.parse(
      "diff --git a/i.png b/i.png\ndeleted file mode 100644\nBinary files a/i.png and /dev/null differ\n",
      path: "i.png")
    #expect(deleted.isBinary && deleted.change == .deleted)
  }

  @Test("un gros diff est tronqué, les compteurs restent justes et le texte complet est gardé")
  func truncation() {
    var lines = ["diff --git a/b b/b", "--- a/b", "+++ b/b", "@@ -1,100 +1,100 @@"]
    for index in 0..<100 { lines.append("-old\(index)") }
    for index in 0..<100 { lines.append("+new\(index)") }
    let text = lines.joined(separator: "\n")
    let diff = GitDiffParser.parse(text, path: "b", lineLimit: 50)
    #expect(diff.isTruncated)
    #expect(diff.lines.count == 50)
    #expect(diff.additions == 100 && diff.deletions == 100)
    #expect(diff.fullText == text)

    let small = GitDiffParser.parse(modified, path: "a.ts")
    #expect(small.fullText == nil)
  }

  @Test("l'en-tête d'un bloc donne ses numéros de départ, longueur absente comprise")
  func hunkHeader() {
    #expect(GitDiffParser.hunkStart("@@ -12,3 +14,5 @@ func")?.old == 12)
    #expect(GitDiffParser.hunkStart("@@ -12,3 +14,5 @@ func")?.new == 14)
    #expect(GitDiffParser.hunkStart("@@ -1 +1 @@")?.new == 1)
    #expect(GitDiffParser.hunkStart("not a header") == nil)
  }
}
