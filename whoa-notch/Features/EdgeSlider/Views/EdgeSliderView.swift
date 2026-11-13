import AppKit

/// Vue custom qui dessine le slider et gère le drag pour ajuster le volume. Ne connaît que
/// son `EdgeSliderViewModel` — jamais un service ou une préférence système directement.
final class EdgeSliderView: NSView {

  var viewModel: EdgeSliderViewModel?

  private var isDragging = false

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach { removeTrackingArea($0) }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
  }

  override func mouseEntered(with event: NSEvent) {
    // TODO: animer l'élargissement de la fenêtre pour révéler le slider complet
  }

  override func mouseExited(with event: NSEvent) {
    // TODO: animer le retour à l'état "fin trait" au bord de l'écran
  }

  override func mouseDragged(with event: NSEvent) {
    isDragging = true
    viewModel?.adjustVolume(rawRatio: event.locationInWindow.y / bounds.height)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    isDragging = false
  }

  override func draw(_ dirtyRect: NSRect) {
    // TODO: dessiner le niveau actuel, les "detents" (crans), etc.
  }
}
