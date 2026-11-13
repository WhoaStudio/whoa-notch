import Testing

@testable import whoa_stash

@MainActor
struct TrayNameFitterTests {

  @Test("un nom qui tient reste tel quel")
  func shortNameIsUnchanged() {
    let result = TrayNameFitter.fit("note.txt", tailLength: 4) { $0.count <= 12 }

    #expect(result == "note.txt")
  }

  @Test("un nom trop long est coupé au milieu et garde son extension")
  func longNameKeepsExtension() {
    let name = "rapport-trimestriel-final-v12.pdf"

    let result = TrayNameFitter.fit(name, tailLength: 4) { $0.count <= 14 }

    #expect(result.count <= 14)
    #expect(result.contains("…"))
    #expect(result.hasSuffix(".pdf"))
    #expect(result.hasPrefix("rap"))
  }

  @Test("plus la place est étroite, plus la coupe est courte, sans jamais déborder")
  func narrowerWidthCutsMore() {
    let name = "une-tres-longue-capture-ecran-2026-11-12.png"

    let wide = TrayNameFitter.fit(name, tailLength: 4) { $0.count <= 24 }
    let narrow = TrayNameFitter.fit(name, tailLength: 4) { $0.count <= 12 }

    #expect(wide.count <= 24)
    #expect(narrow.count <= 12)
    #expect(narrow.count < wide.count)
    #expect(narrow.hasSuffix(".png"))
  }
}
