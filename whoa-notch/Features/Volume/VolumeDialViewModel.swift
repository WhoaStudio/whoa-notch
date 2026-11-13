import Foundation

/// Expose le niveau de volume et la visibilité du cadran via des callbacks simples — miroir de
/// `BrightnessViewModel`, dont il reprend la course (0…1), le grain (`tickCount`) et la façon
/// de traduire la molette en réglage.
///
/// Il ne connaît que `VolumeControlling` : c'est le même service CoreAudio que le slider de
/// bord (`SystemVolumeService`), qui pilote le volume du périphérique de sortie par défaut —
/// donc tout ce qui sort des haut-parleurs, et pas le volume d'une application en particulier.
///
/// Comme la luminosité, il ne déclenche le retour sonore/haptique que lorsqu'une graduation est
/// réellement franchie : c'est le cran qu'on entend, pas la molette.
@MainActor
final class VolumeDialViewModel {

  static let tickCount = VolumeDialGeometry.tickCount

  private(set) var volume: Float
  private(set) var isVisible = false

  private let service: VolumeControlling
  private let feedback: OverlayFeedback

  /// Sensibilité de la molette. Le cadran n'a pas de réglage dans les Préférences,
  /// contrairement à la luminosité : cette valeur est celle de la luminosité au réglage par
  /// défaut, pour que les deux cadrans répondent pareil sous le même geste.
  private let scrollSensitivity: Float = 0.0035

  init(
    service: VolumeControlling = SystemVolumeService.shared,
    feedback: OverlayFeedback = SystemOverlayFeedback()
  ) {
    self.service = service
    self.feedback = feedback
    volume = min(max(service.getVolume(), 0), 1)
  }

  func setVisible(_ visible: Bool) {
    guard isVisible != visible else { return }
    isVisible = visible
  }

  /// Relit le volume réel avant chaque apparition : il a pu changer pendant que le cadran
  /// était fermé — touches du clavier, Réglages Système, un autre contrôleur de volume. Sans
  /// jouer de retour sonore/haptique : ce n'est pas une action de l'utilisateur sur le cadran.
  func syncWithSystem() {
    let current = min(max(service.getVolume(), 0), 1)
    guard current != volume else { return }
    volume = current
  }

  /// `delta > 0` = molette vers le haut (défilement naturel) → monte le volume.
  func adjust(byScrollDelta delta: CGFloat) {
    setVolume(volume + Float(delta) * scrollSensitivity)
  }

  /// Seule porte d'écriture : la course est bornée ici, donc le cadran ne peut ni descendre
  /// sous zéro ni dépasser cent, quel que soit l'élan de la molette.
  func setVolume(_ value: Float) {
    let clamped = min(max(value, 0), 1)
    guard clamped != volume else { return }

    let previousTick = activeTickCount(for: volume)
    volume = clamped
    service.setVolume(clamped)

    if activeTickCount(for: clamped) != previousTick {
      feedback.tickCrossed()
    }
  }

  var fraction: CGFloat { CGFloat(volume) }

  var percent: Int { Int((volume * 100).rounded()) }

  var activeTickCount: Int { activeTickCount(for: volume) }

  private func activeTickCount(for value: Float) -> Int {
    Int((value * Float(Self.tickCount)).rounded())
  }
}
