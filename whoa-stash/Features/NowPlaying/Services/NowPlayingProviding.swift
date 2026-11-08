import Foundation

/// Source de ce qui joue. Derrière un protocole, comme les autres sources externes : l'interface
/// se vérifie ainsi sans lecteur ni MediaRemote (`MockNowPlayingProvider`).
protocol NowPlayingProviding: AnyObject {
  /// Appelé sur le fil principal à chaque changement ; `nil` quand plus rien ne joue.
  var onUpdate: ((NowPlayingState?) -> Void)? { get set }
  func start()
  func stop()
  func send(_ command: NowPlayingCommand)
}

/// `--now-playing=playing|paused` : un morceau fixe, sans MediaRemote, pour vérifier la vue.
final class MockNowPlayingProvider: NowPlayingProviding {

  var onUpdate: ((NowPlayingState?) -> Void)?

  private var state: NowPlayingState

  init(isPlaying: Bool) {
    state = NowPlayingState(
      title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming", artwork: nil,
      isPlaying: isPlaying, bundleIdentifier: "com.apple.Music", duration: 243, elapsed: 20,
      timestamp: .now)
  }

  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments)
    -> MockNowPlayingProvider?
  {
    guard let argument = arguments.first(where: { $0.hasPrefix("--now-playing=") }) else {
      return nil
    }
    switch argument.dropFirst("--now-playing=".count) {
    case "playing": return MockNowPlayingProvider(isPlaying: true)
    case "paused": return MockNowPlayingProvider(isPlaying: false)
    default: return nil
    }
  }

  func start() {
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(1))
      guard let self else { return }
      onUpdate?(state)
    }
  }

  func stop() {}

  func send(_ command: NowPlayingCommand) {
    switch command {
    case .togglePlayPause:
      state.isPlaying.toggle()
      onUpdate?(state)
    case .nextTrack, .previousTrack:
      break
    }
  }
}
