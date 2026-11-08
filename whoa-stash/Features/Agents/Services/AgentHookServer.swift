import Foundation
import OSLog

/// Écoute le socket Unix local sur lequel le script de hook envoie ses événements.
///
/// Aucun réseau : le socket vit dans `Application Support/whoa-stash/`, en 0600. Un message est une
/// ligne JSON ; il est lu sur une file de fond et remis au main actor décodé.
nonisolated final class AgentHookServer: @unchecked Sendable {

  static var supportDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/whoa-stash", isDirectory: true)
  }

  static var socketPath: String { supportDirectory.appendingPathComponent("agent.sock").path }

  /// Posé avant `start()`, appelé sur le main actor.
  var onEvent: (@MainActor (AgentEvent) -> Void)?

  /// Posé avant `start()`, appelé sur le main actor quand un hook qui attendait une réponse est
  /// annulé : l'utilisateur a répondu dans le terminal, ou la session a été tuée.
  var onCancel: (@MainActor (String) -> Void)?

  private var source: DispatchSourceRead?
  /// Connexions de hooks qui attendent une réponse, par `replyID`. Touché seulement sur `queue`.
  private var waiting: [String: DispatchSourceRead] = [:]
  private let queue = DispatchQueue(label: "ugolin-olle.whoa-stash.agent-hook-server")

  func start() {
    guard source == nil else { return }
    let path = Self.socketPath
    try? FileManager.default.createDirectory(
      at: Self.supportDirectory, withIntermediateDirectories: true)
    unlink(path)

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return Log.agents.error("socket() a échoué : \(errno, privacy: .public)") }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard path.utf8.count < capacity else {
      close(fd)
      return Log.agents.error("Chemin du socket trop long")
    }
    withUnsafeMutablePointer(to: &address.sun_path) {
      $0.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strlcpy($0, path, capacity) }
    }
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bound == 0, listen(fd, 8) == 0 else {
      close(fd)
      return Log.agents.error("bind/listen a échoué : \(errno, privacy: .public)")
    }
    chmod(path, 0o600)

    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in
      let client = accept(fd, nil, nil)
      guard client >= 0 else { return }
      self?.read(client)
    }
    source.setCancelHandler {
      close(fd)
      unlink(path)
    }
    source.resume()
    self.source = source
  }

  func stop() {
    source?.cancel()
    source = nil
    queue.async { [weak self] in
      self?.waiting.values.forEach { $0.cancel() }
      self?.waiting.removeAll()
    }
  }

  /// Écrit la réponse sur la connexion du hook, qui la rend à Claude Code, puis la ferme. Sans
  /// effet si le hook a déjà été annulé.
  func reply(to replyID: String, json: String) {
    queue.async { [weak self] in
      guard let source = self?.waiting.removeValue(forKey: replyID) else { return }
      let fd = Int32(source.handle)
      let bytes = Array((json + "\n").utf8)
      var sent = 0
      while sent < bytes.count {
        let count = bytes[sent...].withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        if count <= 0 { break }
        sent += count
      }
      source.cancel()
    }
  }

  /// Lit jusqu'au premier `\n` (ou la fin du flux), avec un délai d'une seconde et 64 Ko au plus.
  /// La connexion se ferme ensuite, sauf pour une demande à laquelle on peut répondre : elle reste
  /// ouverte, surveillée, jusqu'à `reply` ou jusqu'à ce que le hook la ferme.
  private func read(_ client: Int32) {
    var timeout = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while data.count < 65_536 {
      let count = recv(client, &buffer, buffer.count, 0)
      if count <= 0 { break }
      data.append(buffer, count: count)
      if buffer[..<count].contains(0x0A) { break }
    }

    guard let event = AgentEvent.decode(data) else {
      close(client)
      return Log.agents.debug(
        "Message ignoré sur le socket (\(data.count, privacy: .public) octets)")
    }
    if let replyID = event.replyID {
      hold(client, replyID: replyID)
    } else {
      close(client)
    }
    Log.agents.info("Événement reçu : \(event.kind.rawValue, privacy: .public)")
    Task { @MainActor [weak self] in self?.onEvent?(event) }
  }

  /// Garde la connexion ouverte et guette sa fermeture : `nc` ne ferme que si Claude Code a tué le
  /// hook, c'est-à-dire quand la demande a trouvé sa réponse ailleurs.
  private func hold(_ client: Int32, replyID: String) {
    // La lecture d'un délai d'une seconde a servi à la ligne d'entrée ; l'attente est sans limite.
    var none = timeval(tv_sec: 0, tv_usec: 0)
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
    let watcher = DispatchSource.makeReadSource(fileDescriptor: client, queue: queue)
    watcher.setEventHandler { [weak self, weak watcher] in
      var byte: UInt8 = 0
      let count = recv(client, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
      guard count == 0 || (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK) else { return }
      guard let self, let watcher, self.waiting.removeValue(forKey: replyID) != nil else { return }
      watcher.cancel()
      Log.agents.info("Hook annulé : la connexion s'est fermée")
      Task { @MainActor [weak self] in self?.onCancel?(replyID) }
    }
    watcher.setCancelHandler { close(client) }
    waiting[replyID] = watcher
    watcher.resume()
  }
}
