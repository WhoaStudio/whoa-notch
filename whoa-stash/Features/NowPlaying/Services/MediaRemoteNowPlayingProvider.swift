import Foundation
import OSLog

/// Lit ce qui joue, et pilote le lecteur, pour toutes les applications à la fois.
///
/// Depuis macOS 15.4 MediaRemote ne répond plus qu'aux processus titrés. `/usr/bin/perl` en est
/// un : on lui fait charger `MediaRemoteAdapter.framework` (voir `Vendor/MediaRemoteAdapter`) et
/// on lit ses lignes JSON sur la sortie standard. Les commandes passent par le même script.
/// L'API est privée : si elle casse, la vue ne s'affiche simplement jamais.
final class MediaRemoteNowPlayingProvider: NowPlayingProviding {

  var onUpdate: ((NowPlayingState?) -> Void)?

  private var process: Process?
  private var isRunning = false
  private var retryDelay: Duration = .seconds(2)
  private var retryTask: Task<Void, Never>?

  /// Script perl et bibliothèque embarqués dans les ressources de l'app. Le script exige un
  /// chemin `*.framework/<nom>` : on le fabrique dans les caches avec un lien vers la
  /// bibliothèque, et c'est ce chemin qu'on lui passe. `nil` si quelque chose manque.
  private static var adapterPaths: (script: String, framework: String)? {
    guard
      let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
      let library = Bundle.main.url(forResource: "MediaRemoteAdapter", withExtension: "bin"),
      let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { return nil }

    let framework =
      caches
      .appending(path: Bundle.main.bundleIdentifier ?? "whoa-stash", directoryHint: .isDirectory)
      .appending(path: "MediaRemoteAdapter.framework", directoryHint: .isDirectory)
    let link = framework.appending(path: "MediaRemoteAdapter")
    do {
      try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
      // Recréé à chaque lancement : l'app a pu changer de place depuis le précédent.
      try? FileManager.default.removeItem(at: link)
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: library)
    } catch {
      Log.nowPlaying.error(
        "lien vers l'adaptateur impossible : \(error.localizedDescription, privacy: .public)")
      return nil
    }
    return (script.path, framework.path)
  }

  func start() {
    guard !isRunning else { return }
    isRunning = true
    launch()
  }

  func stop() {
    isRunning = false
    retryTask?.cancel()
    retryTask = nil
    process?.terminationHandler = nil
    process?.terminate()
    process = nil
  }

  func send(_ command: NowPlayingCommand) {
    guard let paths = Self.adapterPaths else { return }
    Task.detached {
      let process = Process()
      process.executableURL = URL(filePath: "/usr/bin/perl")
      process.arguments = [paths.script, paths.framework, "send", String(command.rawValue)]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
      } catch {
        Log.nowPlaying.error(
          "commande \(command.rawValue, privacy: .public) impossible : \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }

  /// L'adaptateur attend la position en microsecondes entières.
  func seek(to seconds: TimeInterval) {
    guard let paths = Self.adapterPaths, seconds.isFinite else { return }
    let microseconds = Int(max(0, seconds) * 1_000_000)
    Task.detached {
      let process = Process()
      process.executableURL = URL(filePath: "/usr/bin/perl")
      process.arguments = [paths.script, paths.framework, "seek", String(microseconds)]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
      } catch {
        Log.nowPlaying.error(
          "déplacement impossible : \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  // MARK: - Flux

  private func launch() {
    guard let paths = Self.adapterPaths else {
      Log.nowPlaying.error("adaptateur MediaRemote absent des ressources")
      return
    }

    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/perl")
    process.arguments = [paths.script, paths.framework, "stream", "--debounce=150", "--micros"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    let reader = StreamReader { [weak self] state in
      Task { @MainActor [weak self] in
        self?.retryDelay = .seconds(2)
        self?.onUpdate?(state)
      }
    }
    pipe.fileHandleForReading.readabilityHandler = { handle in
      reader.feed(handle.availableData)
    }
    process.terminationHandler = { [weak self] _ in
      pipe.fileHandleForReading.readabilityHandler = nil
      Task { @MainActor [weak self] in self?.scheduleRetry() }
    }

    do {
      try process.run()
      self.process = process
      Log.nowPlaying.info("flux MediaRemote démarré")
    } catch {
      Log.nowPlaying.error(
        "flux MediaRemote impossible : \(error.localizedDescription, privacy: .public)")
      scheduleRetry()
    }
  }

  /// Le flux s'est arrêté (perl tué, adaptateur cassé) : on le relance avec un délai croissant,
  /// et plus rien ne joue d'ici là.
  private func scheduleRetry() {
    process = nil
    onUpdate?(nil)
    guard isRunning else { return }
    let delay = retryDelay
    retryDelay = min(retryDelay * 2, .seconds(60))
    retryTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.launch()
    }
  }
}

/// Découpe la sortie du processus en lignes et les passe à `NowPlayingStreamParser`. Appelé depuis
/// la file de lecture du tube, jamais depuis le fil principal : l'état est donc sous verrou.
private nonisolated final class StreamReader: @unchecked Sendable {

  private let lock = NSLock()
  private var buffer = Data()
  private var parser = NowPlayingStreamParser()
  private let onState: @Sendable (NowPlayingState?) -> Void

  init(onState: @escaping @Sendable (NowPlayingState?) -> Void) {
    self.onState = onState
  }

  func feed(_ data: Data) {
    guard !data.isEmpty else { return }
    lock.lock()
    defer { lock.unlock() }

    buffer.append(data)
    while let newline = buffer.firstIndex(of: 0x0A) {
      let line = buffer[buffer.startIndex..<newline]
      buffer.removeSubrange(buffer.startIndex...newline)
      if let state = parser.ingest(line: Data(line)) {
        onState(state)
      }
    }
  }
}
