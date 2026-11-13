import AVFoundation
import CoreGraphics
import Testing

@testable import whoa_stash

/// Le tracé du curseur courbe et le réglage de l'aperçu : des fonctions pures, vérifiées sans vue.
@Suite("Curseur de luminosité de l'aperçu")
struct ArcSliderGeometryTests {

  private let arc = ArcSliderGeometry(center: CGPoint(x: 100, y: 100), radius: 80)

  @Test("la valeur 0 est au pied de l'arc et la valeur 1 à son sommet")
  func endpointsAreBottomAndTop() {
    #expect(arc.point(for: 0).y < arc.center.y)
    #expect(arc.point(for: 1).y > arc.center.y)
    // Les deux bouts sont à gauche du centre : l'arc longe le bord gauche du cercle.
    #expect(arc.point(for: 0).x < arc.center.x)
    #expect(arc.point(for: 1).x < arc.center.x)
  }

  @Test("un point de l'arc redonne la valeur dont il vient")
  func pointAndValueRoundTrip() {
    for value in stride(from: 0.0, through: 1.0, by: 0.25) {
      #expect(abs(arc.value(at: arc.point(for: value)) - value) < 0.0001)
    }
  }

  @Test("au-delà des extrémités, la valeur reste bornée à 0 et à 1")
  func valueIsClamped() {
    #expect(arc.value(at: CGPoint(x: 100, y: 0)) == 0)
    #expect(arc.value(at: CGPoint(x: 100, y: 200)) == 1)
    // Sous-droite, en deçà de l'extrémité basse : collé à 0 ; au-dessus à droite : collé à 1.
    #expect(arc.value(at: CGPoint(x: 180, y: 30)) == 0)
    #expect(arc.value(at: CGPoint(x: 180, y: 170)) == 1)
  }

  @Test("seule la piste peut être saisie")
  func onlyTheTrackIsGrabbable() {
    #expect(arc.isNear(arc.point(for: 0.5), tolerance: 10))
    #expect(!arc.isNear(arc.center, tolerance: 10))
    #expect(!arc.isNear(CGPoint(x: 180, y: 100), tolerance: 10))
  }
}

@Suite("Réglage de luminosité de l'aperçu")
struct CameraBrightnessTests {

  @Test("au repos l'aperçu n'est pas retouché")
  func neutralLeavesPreviewUntouched() {
    let overlay = CameraBrightness.overlay(for: CameraBrightness.neutral)
    #expect(overlay.darkness == 0)
    #expect(overlay.lightness == 0)
  }

  @Test("sous le repos le voile noir apparaît, au-dessus c'est le blanc")
  func darkensBelowAndLightensAbove() {
    let dark = CameraBrightness.overlay(for: 0)
    let light = CameraBrightness.overlay(for: 1)
    #expect(dark.darkness > 0 && dark.lightness == 0)
    #expect(light.lightness > 0 && light.darkness == 0)
  }

  @Test("à 0 comme à 1 il reste de l'image")
  func extremesKeepSomeImage() {
    #expect(CameraBrightness.overlay(for: 0).darkness < 1)
    #expect(CameraBrightness.overlay(for: 1).lightness < 1)
  }
}

/// Le modèle de vue de l'onglet Mirror, vu à travers une fausse caméra qui note ses allumages.
@MainActor
@Suite("Onglet Mirror")
struct CameraMirrorViewModelTests {

  private final class SpyProvider: CameraMirrorProviding {
    var accessStatus: CameraAccess
    let session: AVCaptureSession? = nil
    let hasCamera: Bool
    private(set) var starts = 0
    private(set) var stops = 0

    init(access: CameraAccess, hasCamera: Bool = true) {
      accessStatus = access
      self.hasCamera = hasCamera
    }

    func requestAccess() async -> CameraAccess {
      if accessStatus == .notDetermined { accessStatus = .granted }
      return accessStatus
    }

    func startCapture() -> Bool {
      starts += 1
      return hasCamera
    }

    func stopCapture() { stops += 1 }
  }

  /// Laisse la tâche de démarrage du modèle de vue aller au bout.
  private func settle() async {
    for _ in 0..<5 { await Task.yield() }
  }

  @Test("autorisée, la caméra démarre quand l'onglet s'affiche")
  func startsWhenActivated() async {
    let provider = SpyProvider(access: .granted)
    let model = CameraMirrorViewModel(provider: provider)

    model.setActive(true)
    await settle()

    #expect(model.state == .running)
    #expect(provider.starts == 1)
  }

  @Test("la caméra s'éteint quand l'onglet n'est plus à l'écran")
  func stopsWhenDeactivated() async {
    let provider = SpyProvider(access: .granted)
    let model = CameraMirrorViewModel(provider: provider)

    model.setActive(true)
    await settle()
    model.setActive(false)

    #expect(model.state == .idle)
    #expect(provider.stops == 1)
  }

  @Test("sans réponse encore, l'onglet propose le bouton et n'ouvre pas l'invite de lui-même")
  func needsAccessDoesNotPrompt() async {
    let provider = SpyProvider(access: .notDetermined)
    let model = CameraMirrorViewModel(provider: provider)

    model.setActive(true)
    await settle()

    #expect(model.state == .needsAccess)
    #expect(provider.starts == 0)
  }

  @Test("le bouton demande l'autorisation puis la caméra démarre")
  func buttonRequestsAccessThenStarts() async {
    let provider = SpyProvider(access: .notDetermined)
    let model = CameraMirrorViewModel(provider: provider)

    model.setActive(true)
    model.requestAccess()
    await settle()

    #expect(model.state == .running)
    #expect(provider.starts == 1)
  }

  @Test("une autorisation accordée dans Réglages Système fait démarrer l'aperçu")
  func grantedElsewhereStarts() async throws {
    let provider = SpyProvider(access: .denied)
    let model = CameraMirrorViewModel(
      provider: provider, accessPollInterval: .milliseconds(5))

    model.setActive(true)
    #expect(model.state == .denied)
    provider.accessStatus = .granted
    for _ in 0..<200 where model.state != .running { try await Task.sleep(for: .milliseconds(5)) }

    #expect(model.state == .running)
    #expect(provider.starts == 1)
  }

  @Test("replié, l'onglet ne surveille plus l'autorisation")
  func collapsedStopsWatching() async throws {
    let provider = SpyProvider(access: .denied)
    let model = CameraMirrorViewModel(
      provider: provider, accessPollInterval: .milliseconds(5))

    model.setActive(true)
    model.setActive(false)
    provider.accessStatus = .granted
    try await Task.sleep(for: .milliseconds(60))

    #expect(provider.starts == 0)
    #expect(model.state == .idle)
  }

  @Test("refusée, l'onglet montre l'écriteau et la caméra ne s'allume jamais")
  func deniedNeverStarts() async {
    let provider = SpyProvider(access: .denied)
    let model = CameraMirrorViewModel(provider: provider)

    model.setActive(true)
    await settle()

    #expect(model.state == .denied)
    #expect(provider.starts == 0)
  }

  @Test("sans caméra, l'état est indisponible")
  func noCameraIsUnavailable() async {
    let model = CameraMirrorViewModel(provider: SpyProvider(access: .granted, hasCamera: false))

    model.setActive(true)
    await settle()

    #expect(model.state == .unavailable)
  }

  @Test("un repli avant la réponse du système n'allume pas la caméra")
  func collapseBeforeAnswerDoesNotStart() async {
    let provider = SpyProvider(access: .notDetermined)
    let model = CameraMirrorViewModel(provider: provider)

    model.setActive(true)
    model.requestAccess()
    model.setActive(false)
    await settle()

    #expect(provider.starts == 0)
    #expect(model.state == .idle)
  }
}

@Suite("Zoom de l'aperçu")
struct MirrorZoomTests {

  @Test("au repos l'aperçu n'est pas zoomé")
  func startsAtOne() {
    let zoom = MirrorZoom()
    #expect(zoom.displayed == 1)
    #expect(!zoom.isZoomed)
  }

  @Test("un pincement agrandit, dans les bornes")
  func magnifyWithinRange() {
    var zoom = MirrorZoom()
    zoom.magnify(by: 0.5)
    #expect(zoom.displayed == 1.5)
    #expect(zoom.isZoomed)
    #expect(!zoom.isOutOfRange)
  }

  @Test("au-delà de 3×, l'image résiste puis revient sur la borne")
  func rubberBandAndSettle() {
    var zoom = MirrorZoom()
    zoom.magnify(by: 4)
    #expect(zoom.isOutOfRange)
    #expect(zoom.displayed > 3)
    #expect(zoom.displayed < 3.3)
    zoom.settle()
    #expect(zoom.displayed == 3)
  }

  @Test("sous 1×, le dépassement reste minime")
  func belowOneBarelyMoves() {
    var zoom = MirrorZoom()
    zoom.magnify(by: -0.6)
    #expect(zoom.displayed < 1)
    #expect(zoom.displayed > 0.94)
    zoom.settle()
    #expect(zoom.displayed == 1)
  }

  @Test("la molette zoome vers le haut et dézoome vers le bas")
  func scrollDirection() {
    var zoom = MirrorZoom()
    zoom.scroll(by: 20)
    let zoomedIn = zoom.displayed
    #expect(zoomedIn > 1)
    zoom.scroll(by: -20)
    #expect(abs(zoom.displayed - 1) < 1e-9)
  }

  @Test("le rectangle visible est un carré centré, plus petit quand on zoome")
  func visibleRect() {
    let size = CGSize(width: 1280, height: 720)
    #expect(
      MirrorZoom.visibleRect(imageSize: size, zoom: 1)
        == CGRect(x: 280, y: 0, width: 720, height: 720))
    #expect(
      MirrorZoom.visibleRect(imageSize: size, zoom: 2)
        == CGRect(x: 460, y: 180, width: 360, height: 360))
  }
}
