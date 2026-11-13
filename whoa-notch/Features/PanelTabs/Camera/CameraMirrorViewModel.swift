import AVFoundation

/// Ce que montre l'onglet Mirror.
nonisolated enum CameraMirrorState: Equatable {
  /// Caméra éteinte : l'onglet n'est pas à l'écran.
  case idle
  case running
  /// L'autorisation n'a jamais été demandée : l'onglet propose un bouton qui la demande.
  case needsAccess
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
  private let accessPollInterval: Duration
  private var wantsRunning = false
  private var requestTask: Task<Void, Never>?
  private var accessWatch: Task<Void, Never>?

  init(provider: any CameraMirrorProviding, accessPollInterval: Duration = .seconds(1)) {
    self.provider = provider
    self.accessPollInterval = accessPollInterval
  }

  var session: AVCaptureSession? { provider.session }

  /// Dernière image reçue de la caméra, pour la copier.
  func snapshot() -> CGImage? { provider.snapshot() }

  /// Allume ou éteint la caméra. Sans effet si l'état voulu est déjà celui du moment.
  func setActive(_ active: Bool) {
    guard active != wantsRunning else { return }
    wantsRunning = active
    requestTask?.cancel()
    requestTask = nil
    accessWatch?.cancel()
    accessWatch = nil

    guard active else {
      provider.stopCapture()
      state = .idle
      return
    }

    // L'onglet ne déclenche plus l'invite du système de lui-même : sans réponse encore, il
    // l'explique et laisse le bouton la demander.
    switch provider.accessStatus {
    case .granted:
      begin()
    case .notDetermined:
      state = .needsAccess
      watchAccess()
    case .denied:
      state = .denied
      watchAccess()
    }
  }

  /// Le bouton « Allow camera » : ouvre la fenêtre d'autorisation du système. Le panneau a pu
  /// se replier pendant qu'elle était ouverte : la caméra ne doit alors pas s'allumer au retour.
  func requestAccess() {
    guard wantsRunning, state == .needsAccess else { return }
    requestTask?.cancel()
    requestTask = Task {
      let access = await provider.requestAccess()
      guard wantsRunning, !Task.isCancelled, state != .running else { return }
      if access == .granted {
        begin()
      } else {
        state = .denied
        watchAccess()
      }
    }
  }

  private func begin() {
    accessWatch?.cancel()
    accessWatch = nil
    state = provider.startCapture() ? .running : .unavailable
  }

  /// Tant que l'écriteau est affiché, l'autorisation est relue chaque seconde : l'app n'est
  /// pas activée en revenant de Réglages Système (le panneau ne prend pas le focus), et une
  /// autorisation accordée là-bas doit faire démarrer l'aperçu sans rouvrir l'onglet.
  private func watchAccess() {
    accessWatch?.cancel()
    let interval = accessPollInterval
    accessWatch = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: interval)
        guard let self, wantsRunning, !Task.isCancelled else { return }
        if provider.accessStatus == .granted, state != .running {
          begin()
          return
        }
      }
    }
  }
}
