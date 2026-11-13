import AppKit
import SwiftUI

/// Clavier et balayage à deux doigts du parcours d'accueil. Un moniteur local suffit : le panneau
/// est le seul à recevoir ces événements tant qu'il est la fenêtre clé. Flèches pour changer
/// d'étape, Retour pour continuer, Échap pour passer ; le balayage suit le doigt 1:1
/// (`TabSwipeTracker`, le même que les onglets de l'encoche).
@MainActor
final class OnboardingInput {

  private let model: OnboardingModel
  private weak var window: NSWindow?
  private var monitor: Any?
  private var swipe = TabSwipeTracker()
  var onSkip: (() -> Void)?

  init(model: OnboardingModel, window: NSWindow) {
    self.model = model
    self.window = window
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) {
      [weak self] event in
      guard let self, event.window === self.window else { return event }
      return self.handle(event) ? nil : event
    }
  }

  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }

  private func handle(_ event: NSEvent) -> Bool {
    switch event.type {
    case .keyDown: return handleKey(event)
    case .scrollWheel: return handleScroll(event)
    default: return false
    }
  }

  private func handleKey(_ event: NSEvent) -> Bool {
    switch event.keyCode {
    case 123: model.go(-1)  // ←
    case 124, 36, 76: model.go(1)  // →, Retour, Entrée
    case 53: onSkip?()  // Échap
    default: return false
    }
    return true
  }

  private func handleScroll(_ event: NSEvent) -> Bool {
    // La molette d'une souris n'a pas de phase : ce n'est pas un balayage.
    guard event.hasPreciseScrollingDeltas, !event.phase.isEmpty else { return false }
    if event.phase.contains(.began) { swipe.cancel() }
    if event.phase.contains(.cancelled) {
      swipe.cancel()
      settle(nil)
      return true
    }
    let tracking = swipe.move(
      dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, timestamp: event.timestamp)
    if tracking {
      model.dragOffset = OnboardingFlow.trackedOffset(swipe.offset, at: model.step)
    }
    if event.phase.contains(.ended) {
      let velocity = swipe.releaseVelocity(at: event.timestamp)
      settle(swipe.end(velocity: velocity))
      return true
    }
    return tracking
  }

  private func settle(_ direction: TabSwipeTracker.Direction?) {
    let animation = OverlayAnimation.allowsMotion ? SpringPreset.snappy.swiftUIAnimation : nil
    // Le contenu revient en place avec le même ressort que la glissade d'étape.
    switch direction {
    case .next?: stepAfterSwipe(+1)
    case .previous?: stepAfterSwipe(-1)
    case nil: break
    }
    withAnimation(animation) { model.dragOffset = 0 }
  }

  /// Au bord, un balayage trop long ne termine pas le parcours : seule la flèche ou le bouton le font.
  private func stepAfterSwipe(_ delta: Int) {
    guard model.step.moved(by: delta) != nil else { return }
    model.go(delta)
  }
}
