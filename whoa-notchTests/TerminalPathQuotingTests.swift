import Testing

@testable import whoa_notch

@Suite("Chemins déposés dans le terminal")
struct TerminalPathQuotingTests {

  @Test("un chemin sans caractère spécial reste tel quel")
  func safePathIsUntouched() {
    #expect(TerminalTabView.shellQuoted("/Users/moi/notes-1.txt") == "/Users/moi/notes-1.txt")
  }

  @Test("un chemin avec espace est mis entre apostrophes")
  func spaceIsQuoted() {
    #expect(TerminalTabView.shellQuoted("/tmp/mon fichier.txt") == "'/tmp/mon fichier.txt'")
  }

  @Test("une apostrophe dans le chemin est protégée")
  func apostropheIsEscaped() {
    #expect(TerminalTabView.shellQuoted("/tmp/l'été") == "'/tmp/l'\\''été'")
  }
}
