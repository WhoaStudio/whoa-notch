import Darwin
import Foundation
import os

/// Les processus lancés depuis les actions.
///
/// Chaque commande tourne dans un shell de connexion (`$SHELL -l -c`, pour retrouver le `PATH`
/// de l'utilisateur) et dans son propre groupe de processus : arrêter un serveur envoie le signal
/// au groupe entier, donc aussi aux enfants (`pnpm` lance `node`, qui lance le serveur).
final class DevProcessManager: DevProcessProviding {

  private(set) var servers: [DevServer] = []
  var onChange: (() -> Void)?

  /// Nombre de lignes de sortie gardées par serveur.
  private static let outputLimit = 200
  /// Délai laissé à `SIGTERM` avant `SIGKILL`.
  private static let killDelay: Duration = .seconds(3)

  private var sources: [UUID: DispatchSourceProcess] = [:]
  /// Le côté lecture du tube : sans cette référence, le `FileHandle` est libéré et la lecture s'arrête.
  private var readers: [UUID: FileHandle] = [:]
  private var partialLines: [UUID: String] = [:]
  private var pendingRestarts: [UUID: DevAction] = [:]

  // MARK: - DevProcessProviding

  func start(_ action: DevAction) {
    guard servers.first(where: { $0.id == action.id })?.isRunning != true else { return }
    guard let spawned = Self.spawn(command: action.command, directory: action.directory) else {
      Log.devServers.error("lancement impossible")
      var failed = DevServer(
        id: action.id, name: action.name, command: action.command, directory: action.directory,
        pid: nil, startedAt: Date())
      failed.exitCode = 127
      failed.output = ["Impossible de lancer la commande."]
      upsert(failed)
      return
    }
    let pid = spawned.pid
    Log.devServers.info("serveur démarré, pid \(pid, privacy: .public)")
    partialLines[action.id] = ""
    upsert(
      DevServer(
        id: action.id, name: action.name, command: action.command, directory: action.directory,
        pid: pid, startedAt: Date()))

    let id = action.id
    readers[id] = spawned.output
    Self.pump(spawned.output) { [weak self] text in
      Task { @MainActor in self?.append(text, to: id) }
    }
    let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
    source.setEventHandler { [weak self] in self?.reap(id: id, pid: pid) }
    sources[id] = source
    source.resume()
  }

  func stop(_ id: UUID) {
    guard let index = servers.firstIndex(where: { $0.id == id }), let pid = servers[index].pid
    else { return }
    servers[index].isStopping = true
    onChange?()
    kill(-pid, SIGTERM)
    Task { [weak self] in
      try? await Task.sleep(for: Self.killDelay)
      // Le processus a pu s'arrêter, et son pid être réattribué : on ne vise que le même serveur.
      guard let self, servers.first(where: { $0.id == id })?.pid == pid else { return }
      kill(-pid, SIGKILL)
    }
  }

  func restart(_ action: DevAction) {
    if servers.first(where: { $0.id == action.id })?.isRunning == true {
      pendingRestarts[action.id] = action
      stop(action.id)
    } else {
      start(action)
    }
  }

  func remove(_ id: UUID) {
    guard servers.first(where: { $0.id == id })?.isRunning != true else { return }
    servers.removeAll { $0.id == id }
    partialLines[id] = nil
    readers[id] = nil
    onChange?()
  }

  func stopAll() {
    let pids = servers.compactMap(\.pid)
    pids.forEach { kill(-$0, SIGTERM) }
    guard !pids.isEmpty else { return }
    // L'app se ferme : on laisse un instant aux serveurs, puis on achève ceux qui restent.
    usleep(300_000)
    for pid in pids where kill(-pid, 0) == 0 { kill(-pid, SIGKILL) }
  }

  // MARK: - Suivi

  private func upsert(_ server: DevServer) {
    if let index = servers.firstIndex(where: { $0.id == server.id }) {
      servers[index] = server
    } else {
      servers.append(server)
    }
    onChange?()
  }

  private func append(_ text: String, to id: UUID) {
    guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
    let cleaned = Self.stripEscapes(text)
    var lines = (partialLines[id] ?? "") + cleaned
    var complete = lines.components(separatedBy: "\n")
    lines = complete.removeLast()
    partialLines[id] = lines
    let fresh = complete.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard !fresh.isEmpty else { return }
    servers[index].output.append(contentsOf: fresh)
    if servers[index].output.count > Self.outputLimit {
      servers[index].output.removeFirst(servers[index].output.count - Self.outputLimit)
    }
    onChange?()
  }

  private func reap(id: UUID, pid: Int32) {
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    sources[id]?.cancel()
    sources[id] = nil
    // Le processus est parti ; ses éventuels enfants restés dans le groupe sont achevés.
    kill(-pid, SIGKILL)
    let signal = status & 0x7f
    let code: Int32 = signal == 0 ? (status >> 8) & 0xff : 128 + signal
    Log.devServers.info("serveur terminé, code \(code, privacy: .public)")
    if let index = servers.firstIndex(where: { $0.id == id }) {
      servers[index].pid = nil
      servers[index].exitCode = code
      servers[index].isStopping = false
    }
    onChange?()
    if let action = pendingRestarts.removeValue(forKey: id) { start(action) }
  }

  // MARK: - Lancement

  nonisolated private static func stripEscapes(_ text: String) -> String {
    text.replacingOccurrences(
      of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
  }

  /// Lit un tube sur son fil d'arrière-plan et transmet chaque morceau de texte.
  nonisolated private static func pump(
    _ handle: FileHandle, sink: @escaping @Sendable (String) -> Void
  ) {
    handle.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
        try? handle.close()
        return
      }
      sink(String(decoding: data, as: UTF8.self))
    }
  }

  /// Démarre `$SHELL -l -c command` dans un nouveau groupe de processus, sa sortie (stdout et
  /// stderr) dans un tube. `nil` si le lancement échoue.
  private static func spawn(command: String, directory: String?) -> (
    pid: Int32, output: FileHandle
  )? {
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let pipe = Pipe()

    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
    posix_spawnattr_setpgroup(&attributes, 0)

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    let writeEnd = pipe.fileHandleForWriting.fileDescriptor
    posix_spawn_file_actions_adddup2(&actions, writeEnd, 1)
    posix_spawn_file_actions_adddup2(&actions, writeEnd, 2)
    let workingDirectory = directory ?? NSHomeDirectory()
    posix_spawn_file_actions_addchdir(&actions, workingDirectory)

    let arguments = [shell, "-l", "-c", command]
    let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
    let environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
    let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) } + [nil]
    defer {
      argv.forEach { free($0) }
      envp.forEach { free($0) }
    }

    var pid: pid_t = 0
    let result = posix_spawn(&pid, shell, &actions, &attributes, argv, envp)
    // Le fils a sa copie du côté écriture : sans cette fermeture, la lecture ne finirait jamais.
    try? pipe.fileHandleForWriting.close()
    guard result == 0 else { return nil }
    return (pid, pipe.fileHandleForReading)
  }
}
