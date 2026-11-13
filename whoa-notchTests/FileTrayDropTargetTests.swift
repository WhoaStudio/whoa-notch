import AppKit
import Testing

@testable import whoa_notch

@MainActor
struct FileTrayDropTargetTests {

  private let bounds = NSRect(x: 0, y: 0, width: 200, height: 100)

  @Test("la moitié gauche du bac garde le fichier")
  func leftHalfKeeps() {
    #expect(FileTrayDropTarget.target(at: NSPoint(x: 40, y: 50), in: bounds) == .keep)
  }

  @Test("la moitié droite du bac envoie par AirDrop")
  func rightHalfAirDrops() {
    #expect(FileTrayDropTarget.target(at: NSPoint(x: 160, y: 50), in: bounds) == .airDrop)
  }

  @Test("hors du bac, le fichier est gardé")
  func outsideKeeps() {
    #expect(FileTrayDropTarget.target(at: NSPoint(x: 160, y: 300), in: bounds) == .keep)
  }
}
