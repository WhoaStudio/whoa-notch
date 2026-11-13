import AVFoundation
import CoreImage
import OSLog

/// Où en est l'autorisation d'accès à la caméra, réduite à ce que l'onglet Mirror distingue.
/// `restricted` (contrôle parental, profil de gestion) se range avec `denied` : dans les deux cas
/// la demande ne peut plus aboutir, et l'écriteau est le même.
nonisolated enum CameraAccess: Equatable {
  case notDetermined
  case granted
  case denied
}

/// La source d'image de l'onglet Mirror. Derrière un protocole, comme les autres sources
/// externes, pour que le panneau se vérifie sans caméra ni autorisation
/// (`MockCameraMirrorProvider`).
protocol CameraMirrorProviding: AnyObject {

  var accessStatus: CameraAccess { get }

  /// Session à brancher sur la couche d'aperçu. `nil` tant que rien n'a démarré, et pour la
  /// fausse source, qui n'a pas d'image à fournir.
  var session: AVCaptureSession? { get }

  /// Ouvre la fenêtre d'autorisation du système si la réponse n'est pas encore connue.
  func requestAccess() async -> CameraAccess

  /// Allume la caméra. `false` quand la machine n'en a aucune, ou qu'elle ne s'ouvre pas.
  func startCapture() -> Bool

  /// Éteint la caméra : c'est ce qui fait retomber le voyant vert.
  func stopCapture()

  /// Dernière image reçue, pour la copier. `nil` sans image (fausse source, caméra éteinte).
  func snapshot() -> CGImage?
}

extension CameraMirrorProviding {
  func snapshot() -> CGImage? { nil }
}

/// Garde la dernière image de la caméra. Le délégué tourne sur la file de capture : l'image
/// passe par un verrou, et seule la référence est conservée (la conversion en `CGImage` se fait
/// à la demande, jamais à chaque image).
nonisolated final class MirrorFrameGrabber: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  private let lock = NSLock()
  nonisolated(unsafe) private var latest: CVPixelBuffer?
  private let context = CIContext()

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    lock.lock()
    latest = buffer
    lock.unlock()
  }

  func image() -> CGImage? {
    lock.lock()
    let buffer = latest
    lock.unlock()
    guard let buffer else { return nil }
    let image = CIImage(cvPixelBuffer: buffer)
    return context.createCGImage(image, from: image.extent)
  }

  func clear() {
    lock.lock()
    latest = nil
    lock.unlock()
  }
}

/// La vraie caméra, via une `AVCaptureSession`. `startRunning()` et `stopRunning()` bloquent
/// jusqu'à l'ouverture du matériel : ils passent par une file série à eux, qui garde aussi un
/// arrêt demandé juste après un démarrage dans le bon ordre.
final class AVCameraMirrorService: CameraMirrorProviding {

  private(set) var session: AVCaptureSession?
  private let queue = DispatchQueue(label: "ugolin-olle.whoa-stash.camera-mirror")
  private let frameQueue = DispatchQueue(label: "ugolin-olle.whoa-stash.camera-mirror.frames")
  private let grabber = MirrorFrameGrabber()

  var accessStatus: CameraAccess {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: .granted
    case .notDetermined: .notDetermined
    default: .denied
    }
  }

  func requestAccess() async -> CameraAccess {
    let granted = await AVCaptureDevice.requestAccess(for: .video)
    return granted ? .granted : .denied
  }

  func startCapture() -> Bool {
    if session == nil {
      guard let device = AVCaptureDevice.default(for: .video) else {
        Log.camera.info("Aucune caméra disponible")
        return false
      }
      do {
        let input = try AVCaptureDeviceInput(device: device)
        let newSession = AVCaptureSession()
        // Un cercle de 240 pt fait 480 px sur un écran Retina : `.medium` (480×360) était étiré,
        // `.high` suffit sans demander la pleine résolution du capteur.
        newSession.sessionPreset = .high
        guard newSession.canAddInput(input) else { return false }
        newSession.addInput(input)
        // Sortie d'images, pour copier l'image figée.
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(grabber, queue: frameQueue)
        if newSession.canAddOutput(output) { newSession.addOutput(output) }
        session = newSession
      } catch {
        Log.camera.error(
          "Ouverture de la caméra impossible : \(error.localizedDescription, privacy: .public)")
        return false
      }
    }

    guard let session else { return false }
    nonisolated(unsafe) let running = session
    queue.async {
      if !running.isRunning { running.startRunning() }
    }
    Log.camera.info("Caméra démarrée")
    return true
  }

  func stopCapture() {
    guard let session else { return }
    nonisolated(unsafe) let running = session
    queue.async {
      if running.isRunning { running.stopRunning() }
    }
    grabber.clear()
    Log.camera.info("Caméra arrêtée")
  }

  func snapshot() -> CGImage? { grabber.image() }
}

// MARK: - Source de développement

/// Fausse caméra injectée par `--camera-mirror=<granted|denied|notDetermined>`, dans le même
/// esprit que `--calendar-agenda=` : c'est le seul moyen d'atteindre l'écriteau d'accès refusé
/// sans révoquer l'autorisation de l'app dans les Réglages Système. Elle ne fournit pas d'image,
/// la vue montre alors un dégradé à la place.
final class MockCameraMirrorProvider: CameraMirrorProviding {

  private(set) var accessStatus: CameraAccess
  let session: AVCaptureSession? = nil

  init(accessStatus: CameraAccess) {
    self.accessStatus = accessStatus
  }

  /// Une demande « sans réponse » est accordée, comme le ferait un clic sur Autoriser.
  func requestAccess() async -> CameraAccess {
    if accessStatus == .notDetermined { accessStatus = .granted }
    return accessStatus
  }

  func startCapture() -> Bool { true }

  func stopCapture() {}

  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments)
    -> MockCameraMirrorProvider?
  {
    guard let argument = arguments.first(where: { $0.hasPrefix("--camera-mirror=") }) else {
      return nil
    }

    return switch argument.dropFirst("--camera-mirror=".count) {
    case "granted": MockCameraMirrorProvider(accessStatus: .granted)
    case "denied": MockCameraMirrorProvider(accessStatus: .denied)
    case "notDetermined": MockCameraMirrorProvider(accessStatus: .notDetermined)
    default: nil
    }
  }
}
