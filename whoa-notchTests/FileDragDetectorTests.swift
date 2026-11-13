import Testing

@testable import whoa_notch

@MainActor
struct FileDragDetectorTests {

  @Test("un clic sur un presse-papiers de glisser resté plein n'est pas un glisser")
  func clickWithStalePasteboardIsNotADrag() {
    var detector = FileDragDetector()
    // Un glisser précédent a laissé des fichiers ; aucun nouveau glisser depuis le relâchement.
    _ = detector.isDragging(buttonDown: false, changeCount: 7, carriesFiles: true)

    let dragging = detector.isDragging(buttonDown: true, changeCount: 7, carriesFiles: true)

    #expect(!dragging)
  }

  @Test("un glisser de fichiers qui démarre bouton enfoncé est détecté")
  func dragStartingWhileButtonHeldIsADrag() {
    var detector = FileDragDetector()
    _ = detector.isDragging(buttonDown: false, changeCount: 7, carriesFiles: true)

    let dragging = detector.isDragging(buttonDown: true, changeCount: 8, carriesFiles: true)

    #expect(dragging)
  }

  @Test("un glisser qui se termine redevient un état de repos au relâchement")
  func releasingTheButtonEndsTheDrag() {
    var detector = FileDragDetector()
    _ = detector.isDragging(buttonDown: false, changeCount: 7, carriesFiles: true)
    _ = detector.isDragging(buttonDown: true, changeCount: 8, carriesFiles: true)

    let afterRelease = detector.isDragging(buttonDown: false, changeCount: 8, carriesFiles: true)
    let nextClick = detector.isDragging(buttonDown: true, changeCount: 8, carriesFiles: true)

    #expect(!afterRelease)
    #expect(!nextClick)
  }

  @Test("un glisser sans fichiers n'est pas un glisser de fichiers")
  func dragWithoutFilesIsNotAFileDrag() {
    var detector = FileDragDetector()
    _ = detector.isDragging(buttonDown: false, changeCount: 7, carriesFiles: false)

    let dragging = detector.isDragging(buttonDown: true, changeCount: 8, carriesFiles: false)

    #expect(!dragging)
  }
}
