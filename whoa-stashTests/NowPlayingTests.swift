import Foundation
import Testing

@testable import whoa_stash

@MainActor
struct NowPlayingParserTests {

    private func line(_ json: String) -> Data { Data(json.utf8) }

    @Test("une ligne complète donne l'état de lecture")
    func parsesFullPayload() {
        var parser = NowPlayingStreamParser()
        let state = parser.ingest(line: line("""
            {"type":"data","diff":false,"payload":{"title":"Titre","artist":"Artiste","playing":true,\
            "bundleIdentifier":"com.spotify.client","artworkData":"aGVsbG8="}}
            """))
        #expect(state == .some(NowPlayingState(
            title: "Titre", artist: "Artiste", artwork: Data("hello".utf8), isPlaying: true,
            bundleIdentifier: "com.spotify.client")))
    }

    @Test("une différence fusionne ses clés dans l'état précédent")
    func mergesDiff() {
        var parser = NowPlayingStreamParser()
        _ = parser.ingest(line: line("""
            {"diff":false,"payload":{"title":"T","artist":"A","playing":true,"bundleIdentifier":"b"}}
            """))
        let paused = parser.ingest(line: line(#"{"diff":true,"payload":{"playing":false}}"#))
        #expect(paused??.isPlaying == false)
        #expect(paused??.title == "T")
    }

    @Test("une clé à null est retirée de l'état")
    func nullRemovesKey() {
        var parser = NowPlayingStreamParser()
        _ = parser.ingest(line: line("""
            {"diff":false,"payload":{"title":"T","artist":"A","playing":true,"bundleIdentifier":"b"}}
            """))
        let state = parser.ingest(line: line(#"{"diff":true,"payload":{"artist":null}}"#))
        #expect(state??.artist == "")
    }

    @Test("sans titre, sans lecteur ou sans clé, il n'y a rien à montrer")
    func missingMandatoryKeys() {
        var parser = NowPlayingStreamParser()
        #expect(parser.ingest(line: line(#"{"diff":false,"payload":{}}"#)) == .some(nil))
        #expect(parser.ingest(line: line(#"{"diff":false,"payload":{"title":"T","playing":true}}"#)) == .some(nil))
    }

    @Test("une ligne illisible ne change rien")
    func ignoresGarbage() {
        var parser = NowPlayingStreamParser()
        #expect(parser.ingest(line: line("pas du json")) == nil)
    }
}

@MainActor
struct NowPlayingPositionTests {

    private let start = Date(timeIntervalSince1970: 1_000)

    private func state(playing: Bool, elapsed: TimeInterval?, duration: TimeInterval? = 200) -> NowPlayingState {
        NowPlayingState(
            title: "T", artist: "A", isPlaying: playing, bundleIdentifier: "b",
            duration: duration, elapsed: elapsed, timestamp: start)
    }

    @Test("la position avance depuis l'instant du relevé tant que ça joue")
    func advancesWhilePlaying() {
        #expect(state(playing: true, elapsed: 20).position(at: start.addingTimeInterval(10)) == 30)
    }

    @Test("en pause la position ne bouge pas")
    func frozenWhenPaused() {
        #expect(state(playing: false, elapsed: 20).position(at: start.addingTimeInterval(10)) == 20)
    }

    @Test("la position ne dépasse pas la durée et reste inconnue sans relevé")
    func clampedAndOptional() {
        #expect(state(playing: true, elapsed: 195).position(at: start.addingTimeInterval(60)) == 200)
        #expect(state(playing: true, elapsed: nil).position(at: start) == nil)
    }

    @Test("les microsecondes de l'adaptateur sont converties en secondes")
    func parsesMicros() {
        var parser = NowPlayingStreamParser()
        let parsed = parser.ingest(line: Data("""
            {"diff":false,"payload":{"title":"T","playing":true,"bundleIdentifier":"b",\
            "durationMicros":200000000,"elapsedTimeMicros":20500000,"timestampEpochMicros":1000000000}}
            """.utf8))
        #expect(parsed??.duration == 200)
        #expect(parsed??.elapsed == 20.5)
        #expect(parsed??.timestamp == Date(timeIntervalSince1970: 1_000))
    }
}

@MainActor
struct NowPlayingViewModelTests {

    private func state(playing: Bool, title: String = "T") -> NowPlayingState {
        NowPlayingState(title: title, artist: "A", artwork: nil, isPlaying: playing, bundleIdentifier: "b")
    }

    private final class RecordingProvider: NowPlayingProviding {
        var onUpdate: ((NowPlayingState?) -> Void)?
        var sent: [NowPlayingCommand] = []
        init() {}
        func start() {}
        func stop() {}
        func send(_ command: NowPlayingCommand) { sent.append(command) }
    }

    @Test("la vue apparaît dès que ça joue et se masque après le délai d'arrêt")
    func hidesAfterDelay() async throws {
        let model = NowPlayingViewModel(provider: RecordingProvider(), hideDelay: .milliseconds(50))
        var emitted: [NowPlayingState?] = []
        model.onStateChanged = { emitted.append($0) }

        model.receive(state(playing: true))
        #expect(emitted == [state(playing: true)])

        model.receive(nil)
        #expect(emitted.count == 1)
        // Attente bornée plutôt qu'un délai fixe : un runner CI chargé peut dépasser 100 ms.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while emitted.count < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(emitted.count == 2)
        #expect(emitted.last == .some(nil))
    }

    @Test("une pause garde le titre affiché le temps du délai, et reprendre annule le masquage")
    func resumeCancelsHide() async throws {
        let model = NowPlayingViewModel(provider: RecordingProvider(), hideDelay: .milliseconds(80))
        var emitted: [NowPlayingState?] = []
        model.onStateChanged = { emitted.append($0) }

        model.receive(state(playing: true))
        model.receive(state(playing: false))
        #expect(emitted.last == .some(state(playing: false)))

        model.receive(state(playing: true))
        try await Task.sleep(for: .milliseconds(200))
        #expect(emitted.last == .some(state(playing: true)))
    }

    @Test("le lecteur garde le dernier morceau, en pause, quand les ailes se masquent")
    func playerKeepsLastTrack() async throws {
        let model = NowPlayingViewModel(provider: RecordingProvider(), hideDelay: .milliseconds(30))
        var wings: [NowPlayingState?] = []
        var player: [NowPlayingState?] = []
        model.onStateChanged = { wings.append($0) }
        model.onPlayerChanged = { player.append($0) }

        model.receive(state(playing: true))
        model.receive(nil)
        try await Task.sleep(for: .milliseconds(120))

        #expect(wings.last == .some(nil))
        #expect(player.last == .some(state(playing: false)))
    }

    @Test("les commandes passent au fournisseur")
    func forwardsCommands() {
        let provider = RecordingProvider()
        let model = NowPlayingViewModel(provider: provider)
        model.send(.nextTrack)
        #expect(provider.sent == [.nextTrack])
    }
}
