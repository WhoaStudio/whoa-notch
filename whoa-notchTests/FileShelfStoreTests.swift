import Foundation
import Testing

@testable import whoa_notch

@MainActor
struct FileShelfStoreTests {

  @Test("un dépôt déplace le fichier dans le dossier du bac")
  func addingFileMovesItIntoTray() throws {
    let fixture = try Fixture()
    let source = fixture.root.appendingPathComponent("note.txt")
    try Data("hello".utf8).write(to: source)
    let store = FileShelfStore(
      defaults: fixture.defaults,
      trayDirectory: fixture.trayDirectory
    )

    let moved = store.add([source])

    #expect(moved.count == 1)
    #expect(!FileManager.default.fileExists(atPath: source.path))
    #expect(FileManager.default.fileExists(atPath: moved[0].path))
    #expect(store.urls == moved)
  }

  @Test("un conflit de nom conserve les deux fichiers")
  func duplicateNamesGetUniqueDestinations() throws {
    let fixture = try Fixture()
    let firstSource = fixture.root.appendingPathComponent("one/note.txt")
    let secondSource = fixture.root.appendingPathComponent("two/note.txt")
    try FileManager.default.createDirectory(
      at: firstSource.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: secondSource.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("one".utf8).write(to: firstSource)
    try Data("two".utf8).write(to: secondSource)
    let store = FileShelfStore(
      defaults: fixture.defaults,
      trayDirectory: fixture.trayDirectory
    )

    let moved = store.add([firstSource, secondSource])

    #expect(moved.map(\.lastPathComponent) == ["note.txt", "note 2.txt"])
    #expect(try String(contentsOf: moved[0], encoding: .utf8) == "one")
    #expect(try String(contentsOf: moved[1], encoding: .utf8) == "two")
  }

  @Test("un fichier absent n'est pas ajouté")
  func missingFileIsNotAdded() throws {
    let fixture = try Fixture()
    let missing = fixture.root.appendingPathComponent("missing.txt")
    let store = FileShelfStore(
      defaults: fixture.defaults,
      trayDirectory: fixture.trayDirectory
    )

    #expect(store.add([missing]).isEmpty)
    #expect(store.urls.isEmpty)
  }

  @Test("les signets du bac survivent à une nouvelle instance")
  func bookmarksSurviveRelaunch() throws {
    let fixture = try Fixture()
    let source = fixture.root.appendingPathComponent("note.txt")
    try Data("hello".utf8).write(to: source)
    let first = FileShelfStore(
      defaults: fixture.defaults,
      trayDirectory: fixture.trayDirectory
    )
    let moved = first.add([source])

    let second = FileShelfStore(
      defaults: fixture.defaults,
      trayDirectory: fixture.trayDirectory
    )

    #expect(second.urls == moved)
  }

  @Test("mettre un fichier à la corbeille le retire du bac et du disque")
  func trashingRemovesFileFromTrayAndDisk() throws {
    let fixture = try Fixture()
    let source = fixture.root.appendingPathComponent("note.txt")
    try Data("hello".utf8).write(to: source)
    let store = FileShelfStore(
      defaults: fixture.defaults,
      trayDirectory: fixture.trayDirectory
    )
    let moved = store.add([source])

    let trashed = store.trash(moved[0])

    #expect(trashed)
    #expect(store.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: moved[0].path))
  }

  @Test("mettre à la corbeille un fichier inconnu ne change rien")
  func trashingUnknownFileIsIgnored() throws {
    let fixture = try Fixture()
    let store = FileShelfStore(
      defaults: fixture.defaults,
      trayDirectory: fixture.trayDirectory
    )

    #expect(!store.trash(fixture.root.appendingPathComponent("absent.txt")))
  }
}

private final class Fixture {
  let root: URL
  let trayDirectory: URL
  let defaultsSuiteName: String
  let defaults: UserDefaults

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("whoa-notch-tests-\(UUID().uuidString)", isDirectory: true)
    trayDirectory = root.appendingPathComponent("Tray", isDirectory: true)
    defaultsSuiteName = "whoa-notch.tests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: defaultsSuiteName)!
    defaults.removePersistentDomain(forName: defaultsSuiteName)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: root)
    defaults.removePersistentDomain(forName: defaultsSuiteName)
  }
}
