import AVFoundation

/// Ce que montre l'onglet Mirror.
nonisolated enum CameraMirrorState: Equatable {
  /// Caméra éteinte : l'onglet n'est pas à l'écran.
  case idle
  case running
  /// Autorisation refusée ou restreinte : l'écriteau renvoie vers les Réglages Système.
  case denied
  /// Autorisée, mais la machine n'a pas de caméra qui s'ouvre.
  case unavailable
}

/// Décide quand la caméra tourne. Elle ne doit être allumée que pendant que l'onglet est à
/// l'écran — panneau déplié **et** onglet Mirror choisi — : c'est ce qui éteint le voyant au repli.
///
/// Pousse son état par `onStateChanged`, sans tenir la vue.
@MainActor
final class CameraMirrorViewModel {

  private(set) var state: CameraMirrorState = .idle {
    didSet {
      guard state != oldValue else { return }
      onStateChanged?(state)
    }
  }

  var onStateChanged: ((CameraMirrorState) -> Void)?

  private let provider: any CameraMirrorProviding
  private var wantsRunning = false
  private var startTask: Task<Void, Never>?

  init(provider: any CameraMirrorProviding) {
    self.provider = provider
  }

  var session: AVCaptureSession? { provider.session }

  /// Allume ou éteint la caméra. Sans effet si l'état voulu est déjà celui du moment.
  func setActive(_ active: Bool) {
    guard active != wantsRunning else { return }
    wantsRunning = active
    startTask?.cancel()

    guard active else {
      startTask = nil
      provider.stopCapture()
      state = .idle
      return
    }
    startTask = Task { await start() }
  }

  /// La demande d'autorisation peut rester ouverte longtemps : le panneau a pu se replier
  /// entre-temps, et la caméra ne doit alors pas s'allumer au retour de la réponse.
  private func start() async {
    var access = provider.accessStatus
    if access == .notDetermined {
      access = await provider.requestAccess()
    }
    guard wantsRunning, !Task.isCancelled else { return }

    guard access == .granted else {
      state = .denied
      return
    }
    state = provider.startCapture() ? .running : .unavailable
  }
}
