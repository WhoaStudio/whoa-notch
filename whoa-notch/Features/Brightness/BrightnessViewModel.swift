import Foundation

/// Expose l'état de luminosité et de visibilité de l'overlay via des callbacks simples
/// (pas de SwiftUI/Combine ici : les vues AppKit s'abonnent directement).
/// Déclenche le retour sonore/haptique uniquement lorsqu'une graduation est réellement franchie.
@MainActor
final class BrightnessViewModel {

  static let tickCount = 36

  private(set) var brightness: Float
  private(set) var isVisible = false

  var onBrightnessChanged: ((Float) -> Void)?
  var onVisibilityChanged: ((Bool) -> Void)?

  private let controller: BrightnessControlling
  private let feedback: OverlayFeedback
  private let storage: SettingsStorage
  /// Sensibilité de base au scroll, multipliée par `Brightness > Scroll sensitivity`.
  private let baseScrollSensitivity: Float = 0.0035

  /// `feedback` et `storage` ont des valeurs par défaut indépendantes : un appelant qui
  /// injecte un `storage` de test doit aussi passer le `feedback` correspondant
  /// (`NoOpOverlayFeedback`), sans quoi le retour sensoriel lirait encore `.shared`.
  /// `BrightnessOverlayController` fait ce câblage explicitement.
  init(
    controller: BrightnessControlling,
    feedback: OverlayFeedback = SystemOverlayFeedback(),
    storage: SettingsStorage = .shared
  ) {
    self.controller = controller
    self.feedback = feedback
    self.storage = storage
    self.brightness = controller.brightness
  }

  func setVisible(_ visible: Bool) {
    guard isVisible != visible else { return }
    isVisible = visible
    onVisibilityChanged?(visible)
  }

  /// Relit la luminosité réelle depuis le contrôleur (le système a pu la changer pendant
  /// que le widget était fermé — touches clavier, Réglages Système…) sans jouer de retour
  /// sonore/haptique : ce n'est pas une action de l'utilisateur sur le widget.
  func syncWithSystem() {
    let current = controller.brightness
    guard current != brightness else { return }
    brightness = current
    onBrightnessChanged?(current)
  }

  /// `delta > 0` = scroll vers le haut (scrolling naturel) → augmente la luminosité.
  func adjust(byScrollDelta delta: CGFloat) {
    let multiplier = Float(storage.settings.brightness.scrollSensitivity)
    setBrightness(brightness + Float(delta) * baseScrollSensitivity * multiplier)
  }

  func setBrightness(_ value: Float) {
    let clamped = min(max(value, 0), 1)
    guard clamped != brightness else { return }

    let previousTick = activeTickCount(for: brightness)
    brightness = clamped
    controller.brightness = clamped
    onBrightnessChanged?(clamped)

    if activeTickCount(for: clamped) != previousTick {
      feedback.tickCrossed()
    }
  }

  var activeTickCount: Int { activeTickCount(for: brightness) }

  var percent: Int { Int((brightness * 100).rounded()) }

  private func activeTickCount(for value: Float) -> Int {
    Int((value * Float(Self.tickCount)).rounded())
  }
}
