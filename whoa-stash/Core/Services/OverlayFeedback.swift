import AppKit

/// Retour sensoriel joué à chaque graduation franchie, partagé par les réglages de l'overlay —
/// la barre de luminosité et le cadran de volume. Abstraction au même titre que
/// `BrightnessControlling`, pour pouvoir couper le bruit/haptique en tests ou en preview.
///
/// Il vit dans `Core` et non dans une feature : l'interrupteur qu'il lit est dans *General*, pas
/// dans *Brightness*, et le son d'un cran franchi n'a aucune raison d'être celui d'un réglage
/// plutôt que d'un autre.
@MainActor
protocol OverlayFeedback {
  func tickCrossed()
}

/// Un tick sonore très court (son système "Pop") et un tick haptique `.levelChange`,
/// le même vocabulaire que les réglages système (volume, luminosité au clavier) — chacun
/// désactivable indépendamment via `General > Enable haptic/sound feedback`.
///
/// `playsSound: false` pour les surfaces qui ne veulent que le tic sous le doigt, comme la bande
/// de la semaine : l'interrupteur du son ne la concerne alors pas.
final class SystemOverlayFeedback: OverlayFeedback {
  private let sound: NSSound?
  private let storage: SettingsStorage

  init(storage: SettingsStorage = .shared, playsSound: Bool = true) {
    self.storage = storage
    sound = playsSound ? NSSound(named: "Pop") : nil
    sound?.volume = 0.35
  }

  func tickCrossed() {
    let general = storage.settings.general
    if general.enableHapticFeedback {
      NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    if general.enableSoundFeedback {
      sound?.stop()
      sound?.play()
    }
  }
}

/// Aucun retour — développement, previews, tests.
final class NoOpOverlayFeedback: OverlayFeedback {
  func tickCrossed() {}
}
