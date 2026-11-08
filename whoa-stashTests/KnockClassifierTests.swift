import Foundation
import Testing

@testable import whoa_stash

/// Classement des coups sur le châssis, sur des échantillons simulés (`KnockSignal`) : le temps
/// vient des échantillons, aucun capteur ni minuteur réel.
struct KnockClassifierTests {

  private static func run(
    _ samples: [AccelSample], hasDouble: Bool = false,
    recentInput: @escaping () -> Bool = { false },
    flushAt: TimeInterval? = nil
  ) -> [Knock] {
    var classifier = KnockClassifier()
    classifier.hasDoubleAction = hasDouble
    var knocks: [Knock] = []
    for sample in samples { knocks += classifier.ingest(sample, recentInput: recentInput) }
    if let flushAt { knocks += classifier.advance(to: flushAt) }
    return knocks
  }

  @Test("le silence ne donne aucun coup")
  func silenceGivesNothing() {
    #expect(Self.run(KnockSignal.samples(knocksAt: [], duration: 3)).isEmpty)
  }

  @Test("un coup donne un coup simple")
  func singleKnock() {
    #expect(Self.run(KnockSignal.samples(knocksAt: [1.5], duration: 3)) == [Knock(count: 1)])
  }

  @Test("un coup trop léger, sous le seuil, est ignoré")
  func tooSoftIsIgnored() {
    #expect(Self.run(KnockSignal.samples(knocksAt: [1.5], amplitude: 0.02, duration: 3)).isEmpty)
  }

  @Test("la gravité seule, même inclinée, ne déclenche rien")
  func steadyTiltIsIgnored() {
    let tilted = (0..<2400).map { AccelSample(x: 0.5, y: 0, z: -0.87, time: Double($0) / 800) }
    #expect(Self.run(tilted).isEmpty)
  }

  @Test("deux coups rapprochés donnent un double coup et annulent le coup simple")
  func doubleKnockCancelsSingle() {
    let samples = KnockSignal.samples(knocksAt: [1.5, 1.8], duration: 4)
    #expect(Self.run(samples, hasDouble: true, flushAt: 10) == [Knock(count: 2)])
  }

  @Test("sans action de double coup, chaque coup part tout de suite")
  func withoutDoubleActionEachKnockIsSingle() {
    let samples = KnockSignal.samples(knocksAt: [1.5, 1.8], duration: 4)
    #expect(Self.run(samples) == [Knock(count: 1), Knock(count: 1)])
  }

  @Test("le coup simple en attente part après le délai de groupement")
  func pendingSingleFlushes() {
    let samples = KnockSignal.samples(knocksAt: [1.5], duration: 1.8)
    #expect(Self.run(samples, hasDouble: true).isEmpty)
    #expect(Self.run(samples, hasDouble: true, flushAt: 5) == [Knock(count: 1)])
  }

  @Test("deux coups trop espacés ne font pas un double coup")
  func farApartAreTwoSingles() {
    let samples = KnockSignal.samples(knocksAt: [1.5, 2.8], duration: 4)
    #expect(Self.run(samples, hasDouble: true, flushAt: 10) == [Knock(count: 1), Knock(count: 1)])
  }

  @Test("les rebonds d'un même coup ne comptent pas deux fois")
  func ringingCountsOnce() {
    // 0,06 s d'écart : sous le délai mort, c'est la résonance du premier coup.
    let samples = KnockSignal.samples(knocksAt: [1.5, 1.56], duration: 3)
    #expect(Self.run(samples) == [Knock(count: 1)])
  }

  @Test("un pic accompagné d'une frappe ou d'un clic récent est ignoré")
  func typingIsIgnored() {
    let samples = KnockSignal.samples(knocksAt: [1.5], duration: 3)
    #expect(Self.run(samples, recentInput: { true }).isEmpty)
  }

  @Test("un échantillon isolé, même fort, n'est pas un coup")
  func singleSpikeIsIgnored() {
    var samples = KnockSignal.samples(knocksAt: [], duration: 3)
    samples[1600].z += 0.8
    #expect(Self.run(samples).isEmpty)
  }

  @Test("un échantillon nul du capteur n'est pas un coup")
  func zeroReportIsIgnored() {
    var samples = KnockSignal.samples(knocksAt: [], duration: 3)
    samples[1600].z = 0
    #expect(Self.run(samples).isEmpty)
  }

  @Test("un mouvement prolongé n'est pas un coup")
  func sustainedMotionIsIgnored() {
    let samples = (0..<2400).map { i -> AccelSample in
      let t = Double(i) / 800
      let bump = (1.5..<2.0).contains(t) ? 0.15 : 0
      return AccelSample(x: 0, y: 0, z: -1 + bump, time: t)
    }
    #expect(Self.run(samples).isEmpty)
  }

  @Test("un trou dans le flux relance le filtre de gravité sans coup")
  func gapRestartsFilter() {
    let before = KnockSignal.samples(knocksAt: [], duration: 1.5)
    let after = (0..<1600).map { AccelSample(x: 0.4, y: 0, z: -0.9, time: 2.5 + Double($0) / 800) }
    #expect(Self.run(before + after).isEmpty)
  }

  // MARK: - Enregistrement réel

  private static func run(
    recording: [AccelSample], hasDouble: Bool = false, flushAfter: TimeInterval = 2
  ) -> [Knock] {
    var classifier = KnockClassifier()
    classifier.threshold = KnockClassifier.threshold(forSensitivity: 0.7)  // sensibilité par défaut de `KnockSettings`
    classifier.hasDoubleAction = hasDouble
    var knocks: [Knock] = []
    for sample in recording { knocks += classifier.ingest(sample, recentInput: { false }) }
    if let last = recording.last { knocks += classifier.advance(to: last.time + flushAfter) }
    return knocks
  }

  @Test("enregistrement réel : un coup ferme donne un coup simple")
  func recordedSingle() {
    #expect(Self.run(recording: KnockRecordings.single) == [Knock(count: 1)])
  }

  @Test("enregistrement réel : deux coups à 0,28 s donnent un double coup")
  func recordedDouble() {
    #expect(Self.run(recording: KnockRecordings.double, hasDouble: true) == [Knock(count: 2)])
  }

  @Test("enregistrement réel : machine posée, aucun coup")
  func recordedQuiet() {
    #expect(Self.run(recording: KnockRecordings.quiet).isEmpty)
  }

  @Test("enregistrement réel : la saisie au clavier ne donne aucun coup")
  func recordedTyping() {
    #expect(Self.run(recording: KnockRecordings.typing).isEmpty)
  }

  @Test("la sensibilité abaisse le seuil")
  func sensitivityLowersThreshold() {
    #expect(
      KnockClassifier.threshold(forSensitivity: 1) < KnockClassifier.threshold(forSensitivity: 0.5))
    #expect(
      KnockClassifier.threshold(forSensitivity: 0.5) < KnockClassifier.threshold(forSensitivity: 0))
  }
}

@MainActor
struct KnockSettingsStorageTests {

  private static func makeDefaults() -> UserDefaults {
    let name = "whoa-stash.tests.knock.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  @Test("par défaut, un coup simple éteint l'écran et le double verrouille")
  func defaultMapping() {
    let settings = KnockSettings()
    #expect(settings.enabled)
    #expect(settings.action(taps: 1) == .displayOff)
    #expect(settings.action(taps: 2) == .lockScreen)
    #expect(settings.hasDoubleAction)
  }

  @Test("les choix de coups survivent à un relancement")
  func choicesSurviveRelaunch() {
    let defaults = Self.makeDefaults()
    let first = SettingsStorage(defaults: defaults)
    first.settings.knock.double = .playPause
    first.settings.knock.single = .lockScreen
    first.settings.knock.sensitivity = 0.8
    first.settings.knock.enabled = false

    let second = SettingsStorage(defaults: defaults)
    #expect(second.settings.knock.double == .playPause)
    #expect(second.settings.knock.single == .lockScreen)
    #expect(second.settings.knock.sensitivity == 0.8)
    #expect(!second.settings.knock.enabled)
  }

  @Test("une action inconnue ou une clé absente retombe sur la valeur par défaut")
  func toleratesUnknownAction() throws {
    let json = #"{"double":"teleport"}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(KnockSettings.self, from: json)
    #expect(decoded.double == .lockScreen)
    #expect(decoded.single == .displayOff)
  }
}
