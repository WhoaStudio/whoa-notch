import AppKit
import CoreGraphics
import os

/// Suit l'appui, le déplacement et le relâché d'un bouton « autre » de la souris (milieu, retour,
/// avance) par un `CGEventTap` actif : les événements du bouton choisi sont avalés, sinon l'appli
/// sous le curseur recevrait aussi le clic. Exige l'autorisation Accessibilité ; sans elle le tap
/// n'est pas créé et le service retente toutes les 2 s, jusqu'à ce qu'elle soit accordée.
@MainActor
final class MouseButtonHoldService {

  var onPress: (() -> Void)?
  var onDrag: (() -> Void)?
  var onRelease: (() -> Void)?

  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var retryTimer: Timer?
  private(set) var button: RadialMouseButton = .middle
  private var wantsTap = false
  private var isHeld = false

  func apply(enabled: Bool, button: RadialMouseButton) {
    self.button = button
    wantsTap = enabled
    guard enabled else {
      stop()
      return
    }
    guard tap == nil else { return }
    if !install() { startRetrying() }
  }

  private func install() -> Bool {
    let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged]
    let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
    let callback: CGEventTapCallBack = { _, type, event, userData in
      guard let userData else { return Unmanaged.passUnretained(event) }
      let service = Unmanaged<MouseButtonHoldService>.fromOpaque(userData).takeUnretainedValue()
      // Le tap est posé sur la boucle principale : ce rappel y tourne.
      let swallow = MainActor.assumeIsolated { service.handle(type: type, event: event) }
      return swallow ? nil : Unmanaged.passUnretained(event)
    }
    guard
      let port = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask, callback: callback,
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else { return false }
    let runLoopSource = CFMachPortCreateRunLoopSource(nil, port, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    tap = port
    source = runLoopSource
    retryTimer?.invalidate()
    retryTimer = nil
    Log.radialMenu.info("tap de souris installé")
    return true
  }

  private func startRetrying() {
    guard retryTimer == nil else { return }
    Log.radialMenu.info("Accessibilité refusée : nouvelle tentative toutes les 2 s")
    retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.wantsTap, self.tap == nil else { return }
        _ = self.install()
      }
    }
  }

  private func stop() {
    retryTimer?.invalidate()
    retryTimer = nil
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil
    source = nil
    isHeld = false
  }

  /// Vrai si l'événement doit être avalé (c'est celui du bouton suivi).
  private func handle(type: CGEventType, event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return false
    }
    let number = event.getIntegerValueField(.mouseEventButtonNumber)
    if type == .otherMouseDown {
      Log.radialMenu.info(
        "bouton \(number, privacy: .public) enfoncé (suivi : \(self.button.rawValue, privacy: .public))"
      )
    }
    guard number == Int64(button.rawValue) else { return false }
    switch type {
    case .otherMouseDown:
      isHeld = true
      onPress?()
    case .otherMouseDragged:
      if isHeld { onDrag?() }
    case .otherMouseUp:
      // Un relâché sans appui vu (tap installé bouton déjà enfoncé) passe tel quel.
      guard isHeld else { return false }
      isHeld = false
      onRelease?()
    default:
      return false
    }
    return true
  }
}
