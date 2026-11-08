import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import whoa_stash

@MainActor
struct ImageFormatConverterTests {

  @Test("le format se lit dans l'extension, et un fichier texte n'en a pas")
  func formatFromExtension() {
    #expect(ImageFormat(url: URL(fileURLWithPath: "/a/photo.JPG")) == .jpeg)
    #expect(ImageFormat(url: URL(fileURLWithPath: "/a/photo.jpeg")) == .jpeg)
    #expect(ImageFormat(url: URL(fileURLWithPath: "/a/photo.png")) == .png)
    #expect(ImageFormat(url: URL(fileURLWithPath: "/a/photo.heic")) == .heic)
    #expect(ImageFormat(url: URL(fileURLWithPath: "/a/note.txt")) == nil)
  }

  @Test("les cibles excluent le format de la source")
  func targetsExcludeSource() {
    #expect(!ImageFormat.png.conversionTargets.contains(.png))
    #expect(ImageFormat.png.conversionTargets.contains(.jpeg))
    #expect(!ImageFormat.jpeg.conversionTargets.contains(.jpeg))
  }

  @Test("PNG vers JPG produit un JPEG lisible sans toucher à l'original")
  func pngToJpeg() throws {
    let fixture = try Fixture()
    let source = try fixture.writePNG(named: "image.png")
    let before = try Data(contentsOf: source)
    let store = FileShelfStore(defaults: fixture.defaults, trayDirectory: fixture.tray)

    let converted = try #require(store.addConverted(from: source, to: .jpeg))

    #expect(converted.pathExtension == "jpg")
    #expect(try Data(contentsOf: source) == before)
    let imageSource = try #require(CGImageSourceCreateWithURL(converted as CFURL, nil))
    #expect(CGImageSourceGetType(imageSource) as String? == UTType.jpeg.identifier)
    #expect(store.urls.last == converted)
  }

  @Test("une conversion ne remplace jamais un fichier existant")
  func neverOverwrites() throws {
    let fixture = try Fixture()
    let source = try fixture.writePNG(named: "image.png")
    let store = FileShelfStore(defaults: fixture.defaults, trayDirectory: fixture.tray)

    let first = try #require(store.addConverted(from: source, to: .jpeg))
    let second = try #require(store.addConverted(from: source, to: .jpeg))

    #expect(first != second)
    #expect(FileManager.default.fileExists(atPath: first.path))
  }

  @Test("un fichier illisible échoue sans rien ajouter au bac")
  func unreadableFails() throws {
    let fixture = try Fixture()
    let source = fixture.root.appendingPathComponent("fake.png")
    try Data("pas une image".utf8).write(to: source)
    let store = FileShelfStore(defaults: fixture.defaults, trayDirectory: fixture.tray)

    #expect(store.addConverted(from: source, to: .jpeg) == nil)
    #expect(store.urls.isEmpty)
  }

  private func pixelSize(of url: URL) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let properties = try #require(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    return (
      try #require(properties[kCGImagePropertyPixelWidth] as? Int),
      try #require(properties[kCGImagePropertyPixelHeight] as? Int)
    )
  }

  @Test("Resize à 50 % divise les deux dimensions par deux")
  func resizeHalvesDimensions() throws {
    let fixture = try Fixture()
    let source = try fixture.writePNG(named: "image.png")
    let store = FileShelfStore(defaults: fixture.defaults, trayDirectory: fixture.tray)

    let resized = try #require(
      store.addTransformed(
        from: source, options: ImageTransformOptions(format: .png, scale: 0.5), suffix: " resized"))

    #expect(try pixelSize(of: resized) == (4, 4))
    #expect(resized.lastPathComponent == "image resized.png")
  }

  @Test("Rotate à 90° échange largeur et hauteur")
  func rotateSwapsDimensions() throws {
    let fixture = try Fixture()
    let source = try fixture.writePNG(named: "wide.png", size: NSSize(width: 12, height: 6))
    let store = FileShelfStore(defaults: fixture.defaults, trayDirectory: fixture.tray)

    let rotated = try #require(
      store.addTransformed(
        from: source, options: ImageTransformOptions(format: .png, rotationDegrees: 90),
        suffix: " rotated"))

    #expect(try pixelSize(of: rotated) == (6, 12))
  }

  @Test("une sortie vers un autre dossier n'entre pas dans le bac")
  func outputInOtherDirectoryStaysOutOfTray() throws {
    let fixture = try Fixture()
    let source = try fixture.writePNG(named: "image.png")
    let store = FileShelfStore(defaults: fixture.defaults, trayDirectory: fixture.tray)
    let elsewhere = fixture.root.appendingPathComponent("Downloads")

    let written = try #require(
      store.addTransformed(
        from: source, options: ImageTransformOptions(format: .jpeg), suffix: "", in: elsewhere))

    #expect(
      written.deletingLastPathComponent().standardizedFileURL == elsewhere.standardizedFileURL)
    #expect(store.urls.isEmpty)
  }

  private struct Fixture {
    let root: URL
    let tray: URL
    let defaults: UserDefaults

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      tray = root.appendingPathComponent("Tray")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defaults = UserDefaults(suiteName: UUID().uuidString)!
    }

    func writePNG(named name: String, size: NSSize = NSSize(width: 8, height: 8)) throws -> URL {
      let image = NSImage(size: size, flipped: false) { rect in
        NSColor.red.setFill()
        rect.fill()
        return true
      }
      let tiff = try #require(image.tiffRepresentation)
      let rep = try #require(NSBitmapImageRep(data: tiff))
      let data = try #require(rep.representation(using: .png, properties: [:]))
      let url = root.appendingPathComponent(name)
      try data.write(to: url)
      return url
    }
  }
}
