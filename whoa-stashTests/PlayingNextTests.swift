import Foundation
import Testing

@testable import whoa_stash

@MainActor
struct PlayingNextParsingTests {

  @Test("la sortie d'osascript donne titre, artiste et pochette de chaque titre")
  func parsesAppleMusicOutput() {
    let output = #"{{"Titre A", "Artiste A", «data tdtaFFD8FF»}, {"Titre \"B\"", "Artiste B", ""}}"#
    let items = AppleMusicQueueProvider.parse(output, limit: 3)
    #expect(
      items == [
        QueueItem(title: "Titre A", artist: "Artiste A", artwork: Data([0xFF, 0xD8, 0xFF])),
        QueueItem(title: "Titre \"B\"", artist: "Artiste B", artwork: nil),
      ])
  }

  @Test("une liste vide ou illisible ne donne aucun titre, et la limite est respectée")
  func appleMusicEdgeCases() {
    #expect(AppleMusicQueueProvider.parse("{}", limit: 3).isEmpty)
    #expect(AppleMusicQueueProvider.parse("n'importe quoi", limit: 3).isEmpty)
    let two = #"{{"A", "x", ""}, {"B", "y", ""}}"#
    #expect(AppleMusicQueueProvider.parse(two, limit: 1).map(\.title) == ["A"])
  }

  @Test("la file Spotify donne titre, artistes et la plus petite pochette d'au moins 64 px")
  func parsesSpotifyQueue() {
    let json = """
      {"currently_playing": {"name": "Now"}, "queue": [
        {"name": "The Temple", "artists": [{"name": "Phuture Noize"}, {"name": "X"}],
         "album": {"images": [{"url": "https://i/640", "width": 640}, {"url": "https://i/300", "width": 300},
                              {"url": "https://i/64", "width": 64}]}},
        {"name": "", "artists": []},
        {"name": "Sans image", "artists": [{"name": "Y"}], "album": {"images": []}}
      ]}
      """
    let entries = SpotifyQueueProvider.parse(Data(json.utf8), limit: 3)
    #expect(
      entries == [
        SpotifyQueueProvider.Entry(
          title: "The Temple", artist: "Phuture Noize, X", artworkURL: URL(string: "https://i/64")),
        SpotifyQueueProvider.Entry(title: "Sans image", artist: "Y", artworkURL: nil),
      ])
  }

  @Test(
    "la réponse du point d'accès token garde l'ancien jeton de renouvellement s'il n'en vient pas de neuf"
  )
  func parsesTokenResponse() {
    let now = Date(timeIntervalSince1970: 1_000)
    let fresh = SpotifyAuthorizer.tokens(
      fromTokenResponse: Data(#"{"access_token":"a","refresh_token":"r","expires_in":3600}"#.utf8),
      previousRefreshToken: nil, now: now)
    #expect(
      fresh
        == SpotifyTokens(
          accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(3600)))

    let renewed = SpotifyAuthorizer.tokens(
      fromTokenResponse: Data(#"{"access_token":"b","expires_in":60}"#.utf8),
      previousRefreshToken: "old", now: now)
    #expect(renewed?.refreshToken == "old")
    #expect(
      SpotifyAuthorizer.tokens(fromTokenResponse: Data("{}".utf8), previousRefreshToken: nil) == nil
    )
  }

  @Test("la redirection n'est acceptée qu'avec le bon state")
  func loopbackChecksState() throws {
    let good = "GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
    #expect(try SpotifyLoopbackServer.code(fromRequest: good, expectedState: "xyz").get() == "abc")
    #expect(throws: (any Error).self) {
      try SpotifyLoopbackServer.code(fromRequest: good, expectedState: "autre").get()
    }
    let denied = "GET /callback?error=access_denied&state=xyz HTTP/1.1\r\n\r\n"
    #expect(throws: (any Error).self) {
      try SpotifyLoopbackServer.code(fromRequest: denied, expectedState: "xyz").get()
    }
  }

  @Test("des préférences sans la clé spotify se décodent avec un identifiant vide")
  func settingsDecodeWithoutSpotify() throws {
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    #expect(decoded.spotify.clientID.isEmpty)
  }
}

@MainActor
struct PlayingNextViewModelTests {

  private struct FakeProvider: PlayingNextProviding {
    let items: [QueueItem]
    func supports(bundleIdentifier: String) -> Bool { bundleIdentifier == "b" }
    func upcoming(limit: Int) async -> [QueueItem] { items }
  }

  private func state(title: String = "T", bundle: String = "b", playing: Bool = true)
    -> NowPlayingState
  {
    NowPlayingState(title: title, artist: "A", isPlaying: playing, bundleIdentifier: bundle)
  }

  private let item = QueueItem(title: "Suivant", artist: "Z", artwork: nil)

  /// Attend que `condition` soit vraie, sans dépasser `timeout` : un délai fixe échoue sur une
  /// machine chargée (CI), alors que la file n'arrive qu'après le délai de stabilisation.
  private func waitUntil(attempts: Int = 300, _ condition: () -> Bool) async throws {
    // Nombre de tentatives borné plutôt qu'une échéance horloge : sur un runner figé, l'échéance
    // peut passer avant que la tâche en attente (son propre délai de 10 ms) ait tourné.
    var tries = 0
    while !condition(), tries < attempts {
      tries += 1
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test("un nouveau morceau relit la file, et en changer la vide d'abord")
  func fetchesOnTrackChange() async throws {
    let model = PlayingNextViewModel(
      providers: [FakeProvider(items: [item])], settleDelay: .milliseconds(10),
      minimumRefreshInterval: 0)
    var published: [[QueueItem]] = []
    model.onItemsChanged = { published.append($0) }

    model.update(for: state())
    // Attente de la vraie relecture de la file, pas d'une simple publication (un runner chargé est lent).
    try await waitUntil { published.last == [item] }
    #expect(published == [[item]])

    model.update(for: state(title: "Autre"))
    #expect(published.last == [])
    try await waitUntil { published.last == [item] }
    #expect(published.last == [item])
  }

  @Test("une application sans source, ou plus aucun morceau, laisse la colonne vide")
  func emptyWithoutSourceOrTrack() async throws {
    let model = PlayingNextViewModel(
      providers: [FakeProvider(items: [item])], settleDelay: .milliseconds(10),
      minimumRefreshInterval: 0)
    var published: [[QueueItem]] = []
    model.onItemsChanged = { published.append($0) }

    model.update(for: state(bundle: "inconnue"))
    try await Task.sleep(for: .milliseconds(60))
    #expect(model.items.isEmpty)

    model.update(for: state())
    try await waitUntil { model.items == [item] }
    #expect(model.items == [item])

    model.update(for: nil)
    #expect(model.items.isEmpty)
  }

  @Test("la relecture au dépliage respecte l'intervalle minimal")
  func refreshIsThrottled() async throws {
    let model = PlayingNextViewModel(
      providers: [FakeProvider(items: [item])], settleDelay: .milliseconds(10),
      minimumRefreshInterval: 60)
    model.update(for: state())
    // Attendre la première lecture : elle fixe l'horodatage de la dernière relecture.
    try await waitUntil { model.items == [item] }
    model.onItemsChanged = { _ in Issue.record("aucune relecture attendue") }
    model.refresh()
    try await Task.sleep(for: .milliseconds(60))
  }
}
