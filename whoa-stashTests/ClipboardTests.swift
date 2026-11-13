import Foundation
import Testing

@testable import whoa_stash

@MainActor
@Suite("Presse-papiers : classement")
struct ClipboardClassifierTests {

  private func classify(_ snapshot: ClipboardSnapshot) -> ClipboardClassification? {
    ClipboardClassifier.classify(snapshot)
  }

  @Test("un texte simple est classé TEXT")
  func plainText() {
    let result = classify(ClipboardSnapshot(string: "Drag In. Drag Out."))
    #expect(result?.kind == .text)
    #expect(result?.tag == "TEXT")
  }

  @Test("une URL avec schéma est un lien")
  func urlWithScheme() {
    let result = classify(ClipboardSnapshot(string: "https://example.com/page?q=1"))
    #expect(result?.kind == .link)
    #expect(result?.tag == "LINK")
  }

  @Test("une adresse en www. est un lien")
  func wwwAddress() {
    #expect(classify(ClipboardSnapshot(string: "www.mynotchbar.com"))?.kind == .link)
  }

  @Test("une phrase qui contient une URL reste un texte")
  func sentenceWithUrl() {
    #expect(classify(ClipboardSnapshot(string: "voir https://example.com ici"))?.kind == .text)
  }

  @Test("des données d'image sont classées image PNG")
  func imageData() {
    let result = classify(ClipboardSnapshot(imageData: Data([0x89, 0x50, 0x4E, 0x47])))
    #expect(result?.kind == .image)
    #expect(result?.tag == "PNG")
  }

  @Test("un fichier image copié est une image, avec son extension")
  func imageFile() {
    let result = classify(ClipboardSnapshot(fileURLs: [URL(fileURLWithPath: "/tmp/photo.jpg")]))
    #expect(result?.kind == .image)
    #expect(result?.tag == "JPG")
  }

  @Test("un fichier vidéo copié est une vidéo")
  func videoFile() {
    #expect(
      classify(ClipboardSnapshot(fileURLs: [URL(fileURLWithPath: "/tmp/clip.mov")]))?.kind == .video
    )
  }

  @Test("un autre fichier est classé fichier, étiqueté par son extension")
  func otherFile() {
    let result = classify(ClipboardSnapshot(fileURLs: [URL(fileURLWithPath: "/tmp/Archive.zip")]))
    #expect(result?.kind == .file)
    #expect(result?.tag == "ZIP")
  }

  @Test("un fichier l'emporte sur le nom et l'icône que le Finder y joint")
  func fileWinsOverCompanions() {
    let snapshot = ClipboardSnapshot(
      fileURLs: [URL(fileURLWithPath: "/tmp/Archive.zip")], imageData: Data([1]),
      string: "Archive.zip")
    #expect(classify(snapshot)?.kind == .file)
  }

  @Test("un presse-papiers vide ou blanc ne donne rien")
  func emptyContent() {
    #expect(classify(ClipboardSnapshot()) == nil)
    #expect(classify(ClipboardSnapshot(string: "  \n ")) == nil)
  }

  @Test("chaque type est retenu par le bon filtre")
  func filters() {
    #expect(ClipboardFilter.all.matches(.file))
    #expect(ClipboardFilter.links.matches(.link))
    #expect(!ClipboardFilter.text.matches(.link))
    #expect(!ClipboardFilter.images.matches(.file))
  }
}

@MainActor
@Suite("Presse-papiers : historique")
struct ClipboardHistoryStoreTests {

  private func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "clipboard-tests-\(UUID().uuidString)")
  }

  private func text(_ value: String) -> ClipboardClassification {
    ClipboardClassifier.classify(ClipboardSnapshot(string: value))!
  }

  @Test("le plus récent est en tête")
  func newestFirst() {
    let store = ClipboardHistoryStore(directory: makeDirectory())
    store.add(text("un"))
    store.add(text("deux"))
    #expect(store.items.map(\.text) == ["deux", "un"])
  }

  @Test("recopier la même chose la fait remonter sans doublon")
  func duplicateMovesToFront() {
    let store = ClipboardHistoryStore(directory: makeDirectory())
    store.add(text("un"))
    store.add(text("deux"))
    store.add(text("un"))
    #expect(store.items.map(\.text) == ["un", "deux"])
  }

  @Test("au-delà de la limite, les plus anciens sont chassés")
  func limit() {
    let store = ClipboardHistoryStore(directory: makeDirectory(), limit: 2)
    store.add(text("un"))
    store.add(text("deux"))
    store.add(text("trois"))
    #expect(store.items.map(\.text) == ["trois", "deux"])
  }

  @Test("Clear vide la liste et supprime les images")
  func clear() throws {
    let directory = makeDirectory()
    let store = ClipboardHistoryStore(directory: directory)
    store.add(ClipboardClassifier.classify(ClipboardSnapshot(imageData: Data([1, 2, 3])))!)
    let imageURL = try #require(store.items.first.flatMap(store.imageURL(for:)))
    #expect(FileManager.default.fileExists(atPath: imageURL.path))

    store.clear()

    #expect(store.items.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: imageURL.path))
  }

  @Test("retirer un élément supprime aussi son image")
  func removeDeletesImage() throws {
    let store = ClipboardHistoryStore(directory: makeDirectory())
    store.add(ClipboardClassifier.classify(ClipboardSnapshot(imageData: Data([1, 2, 3])))!)
    let item = try #require(store.items.first)
    let imageURL = try #require(store.imageURL(for: item))

    store.remove(id: item.id)

    #expect(store.items.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: imageURL.path))
  }

  @Test("Clear garde les éléments épinglés")
  func clearKeepsPinned() throws {
    let store = ClipboardHistoryStore(directory: makeDirectory())
    store.add(text("un"))
    store.add(text("deux"))
    store.setPinned(true, id: try #require(store.items.last).id)

    store.clear()

    #expect(store.items.map(\.text) == ["un"])
  }

  @Test("la limite ne chasse jamais un élément épinglé")
  func limitSkipsPinned() throws {
    let store = ClipboardHistoryStore(directory: makeDirectory(), limit: 2)
    store.add(text("un"))
    store.setPinned(true, id: try #require(store.items.first).id)
    store.add(text("deux"))
    store.add(text("trois"))
    #expect(store.items.map(\.text) == ["trois", "un"])
  }

  @Test("un historique écrit avant les épingles se relit, sans épingle")
  func legacyHistoryDecodes() throws {
    let json = """
      [{"id":"\(UUID().uuidString)","kind":"text","tag":"TEXT","text":"vieux","fingerprint":"t:vieux",\
      "date":0}]
      """
    let items = try JSONDecoder().decode([ClipboardItem].self, from: Data(json.utf8))
    #expect(items.first?.isPinned == false)
  }

  @Test("une épingle survit à un nouveau lancement")
  func pinPersists() throws {
    let directory = makeDirectory()
    let store = ClipboardHistoryStore(directory: directory)
    store.add(text("un"))
    store.setPinned(true, id: try #require(store.items.first).id)
    #expect(ClipboardHistoryStore(directory: directory).items.first?.isPinned == true)
  }

  @Test("l'historique survit à un nouveau lancement")
  func persistence() {
    let directory = makeDirectory()
    ClipboardHistoryStore(directory: directory).add(text("un"))
    #expect(ClipboardHistoryStore(directory: directory).items.map(\.text) == ["un"])
  }
}

@MainActor
@Suite("Presse-papiers : âge")
struct ClipboardAgeTests {

  @Test("l'âge s'écrit en minutes, heures puis jours")
  func ageText() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func age(_ seconds: TimeInterval) -> String {
      ClipboardItem.ageText(since: now.addingTimeInterval(-seconds), now: now)
    }
    #expect(age(5) == "now")
    #expect(age(23 * 60) == "23 min ago")
    #expect(age(3 * 3600) == "3 h ago")
    #expect(age(2 * 86_400) == "2 d ago")
  }
}

@MainActor
@Suite("Presse-papiers : aperçu")
struct ClipboardPreviewTests {

  @Test("l'aperçu retire lignes vides, retrait commun et tabulations")
  func displayText() {
    let raw = "\n\n    func a() {\r\n\n\t\t  return 1\n    }\n\n"
    #expect(ClipboardPreview.displayText(raw) == "func a() {\n  return 1\n}")
  }

  @Test("un texte énorme est borné")
  func displayTextIsBounded() {
    let raw = String(repeating: "mot ", count: 50_000)
    #expect(ClipboardPreview.displayText(raw).count <= ClipboardPreview.maxDisplayLength)
  }

  @Test("les couleurs hexadécimales et rgb() sont reconnues")
  func colors() {
    #expect(ClipboardPreview.colorValue(in: "#fa0")?.label == "#FFAA00")
    #expect(ClipboardPreview.colorValue(in: " #3B82F6 ")?.label == "#3B82F6")
    #expect(ClipboardPreview.colorValue(in: "rgb(10, 20, 30)")?.label == "rgb(10, 20, 30)")
  }

  @Test("un texte qui contient une couleur n'est pas une couleur")
  func notColors() {
    #expect(ClipboardPreview.colorValue(in: "fond #fff") == nil)
    #expect(ClipboardPreview.colorValue(in: "#12345") == nil)
    #expect(ClipboardPreview.colorValue(in: "rgb(300, 0, 0)") == nil)
  }

  @Test("un lien se coupe en domaine et reste")
  func linkParts() {
    let parts = ClipboardPreview.linkParts("https://www.example.com/a/b?q=1#top")
    #expect(parts.host == "example.com")
    #expect(parts.rest == "/a/b?q=1#top")
    #expect(ClipboardPreview.linkParts("www.example.com").host == "example.com")
  }
}
