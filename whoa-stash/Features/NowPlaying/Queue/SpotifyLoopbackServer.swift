import Foundation
import Network

/// Reçoit la redirection de Spotify (`http://127.0.0.1:<port>/callback?code=…&state=…`) sur une
/// socket locale qui n'écoute que le temps de la connexion, et renvoie le code d'autorisation.
nonisolated final class SpotifyLoopbackServer: @unchecked Sendable {

  enum Failure: Error { case timedOut, denied, stateMismatch, portUnavailable }

  private let port: UInt16
  private let lock = NSLock()
  private var continuation: CheckedContinuation<String, Error>?
  private var listener: NWListener?

  init(port: UInt16) { self.port = port }

  /// Écoute, appelle `onReady` (qui ouvre le navigateur), puis attend la redirection.
  func receiveCode(
    expectedState: String, timeout: Duration, onReady: @escaping @Sendable () -> Void
  ) async throws
    -> String
  {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<String, Error>) in
      lock.lock()
      self.continuation = continuation
      lock.unlock()

      guard let nwPort = NWEndpoint.Port(rawValue: port),
        let listener = try? NWListener(using: .tcp, on: nwPort)
      else {
        finish(.failure(Failure.portUnavailable))
        return
      }
      self.listener = listener
      listener.newConnectionHandler = { [weak self] connection in
        self?.handle(connection, expectedState: expectedState)
      }
      listener.stateUpdateHandler = { [weak self] state in
        switch state {
        case .ready: onReady()
        case .failed: self?.finish(.failure(Failure.portUnavailable))
        default: break
        }
      }
      listener.start(queue: .global(qos: .userInitiated))

      Task { [weak self] in
        try? await Task.sleep(for: timeout)
        self?.finish(.failure(Failure.timedOut))
      }
    }
  }

  private func handle(_ connection: NWConnection, expectedState: String) {
    connection.start(queue: .global(qos: .userInitiated))
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
      [weak self] data, _, _, _ in
      guard let self, let data, let request = String(data: data, encoding: .utf8) else {
        connection.cancel()
        return
      }
      let result = Self.code(fromRequest: request, expectedState: expectedState)
      let message: String
      switch result {
      case .success:
        message = "Connected to Spotify. You can close this tab and go back to whoa-stash."
      case .failure: message = "Spotify connection failed. You can close this tab and try again."
      }
      let body =
        "<html><body style=\"font-family:-apple-system;text-align:center;padding-top:20vh\">\(message)</body></html>"
      let response =
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
      connection.send(
        content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
      self.finish(result)
    }
  }

  /// Extrait `code` de la ligne de requête, après avoir vérifié `state` — sans lui, n'importe quelle
  /// page ouverte dans le navigateur pourrait nous faire échanger son propre code.
  static func code(fromRequest request: String, expectedState: String) -> Result<String, Error> {
    guard let line = request.split(separator: "\r\n").first, line.hasPrefix("GET "),
      let target = line.split(separator: " ").dropFirst().first,
      let components = URLComponents(string: "http://127.0.0.1" + target)
    else { return .failure(Failure.denied) }
    let query = Dictionary(
      (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
      uniquingKeysWith: { first, _ in first })
    guard query["state"] == expectedState else { return .failure(Failure.stateMismatch) }
    guard let code = query["code"], query["error"] == nil else { return .failure(Failure.denied) }
    return .success(code)
  }

  private func finish(_ result: Result<String, Error>) {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    listener?.cancel()
    listener = nil
    continuation?.resume(with: result)
  }
}
