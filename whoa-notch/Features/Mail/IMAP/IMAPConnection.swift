import Foundation
import Network

/// Un morceau envoyé en « literal » (`{n}` suivi de n octets), avec le texte qui le précède sur sa
/// ligne — c'est ce texte (`BODY[HEADER.FIELDS …]`, `BODY[TEXT]<0>`) qui dit de quoi il s'agit.
nonisolated struct IMAPLiteral: Sendable {
  var label: String
  var data: Data
}

/// Une réponse du serveur, reconstituée : la ligne sans ses literals, et les literals à part.
nonisolated struct IMAPResponse: Sendable {
  var line: String
  var literals: [IMAPLiteral]
}

nonisolated enum IMAPError: Error, LocalizedError {
  case connectionClosed
  case commandFailed(String)
  case protocolViolation
  case missingPassword
  case invalidCharacters

  var errorDescription: String? {
    switch self {
    case .connectionClosed: "The server closed the connection."
    case .commandFailed(let status): "The server refused the request: \(status)"
    case .protocolViolation: "Unexpected reply from the server."
    case .missingPassword: "No password saved for this account."
    case .invalidCharacters: "The user name or password contains a line break."
    }
  }
}

/// Une connexion IMAP en TLS (port 993 en général), au-dessus de Network.framework. Un acteur : il
/// sérialise les lectures et les écritures, et c'est lui qui garde le tampon de réception.
///
/// Les réponses sont lues dans l'ordre. Une seule lecture est en cours à la fois : l'attente
/// maximale de `idle` envoie `DONE` au lieu d'annuler la lecture, parce qu'un `receive` de
/// Network.framework ne s'annule pas.
actor IMAPConnection {

  /// Au-delà, un literal n'est pas ce qu'on a demandé (les corps sont tronqués à la demande).
  private static let maximumLiteral = 1_000_000

  private let connection: NWConnection
  private let queue = DispatchQueue(label: "ugolin-olle.whoa-notch.imap")
  private var buffer = Data()
  private var nextTag = 1
  private var doneSent = false

  init(host: String, port: UInt16) {
    let tcp = NWProtocolTCP.Options()
    tcp.enableKeepalive = true
    tcp.keepaliveIdle = 60
    // Le certificat du serveur est vérifié par les réglages TLS par défaut.
    let parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: tcp)
    connection = NWConnection(
      host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 993, using: parameters)
  }

  // MARK: - Connexion

  func open() async throws {
    let once = Once()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
          once.run { continuation.resume() }
        case .failed(let error), .waiting(let error):
          once.run { continuation.resume(throwing: error) }
        case .cancelled:
          once.run { continuation.resume(throwing: IMAPError.connectionClosed) }
        default:
          break
        }
      }
      connection.start(queue: queue)
    }
    connection.stateUpdateHandler = nil
  }

  func close() {
    connection.cancel()
  }

  // MARK: - Commandes

  /// Envoie `command` et rend les réponses non étiquetées, une fois la réponse étiquetée `OK` reçue.
  @discardableResult
  func run(_ command: String) async throws -> [IMAPResponse] {
    let tag = makeTag()
    try await write("\(tag) \(command)")
    return try await collect(tag: tag)
  }

  func readGreeting() async throws {
    let greeting = try await readResponse()
    guard greeting.line.hasPrefix("* OK") || greeting.line.hasPrefix("* PREAUTH") else {
      throw IMAPError.protocolViolation
    }
  }

  func login(username: String, password: String) async throws {
    try await run("LOGIN \(try Self.quote(username)) \(try Self.quote(password))")
  }

  /// Attend l'arrivée d'un message (`* n EXISTS`) au plus `maxDuration`. Renvoie `true` si le
  /// serveur en a annoncé un, `false` si le délai est écoulé. Si le serveur ne répond pas à `DONE`
  /// dans les 30 s, la connexion est fermée — c'est ce qui détecte une liaison morte après une veille.
  func idle(maxDuration: Duration) async throws -> Bool {
    let tag = makeTag()
    doneSent = false
    try await write("\(tag) IDLE")
    guard try await readLine().hasPrefix("+") else { throw IMAPError.commandFailed("IDLE") }

    let timer = Task { [weak self] in
      try? await Task.sleep(for: maxDuration)
      guard !Task.isCancelled else { return }
      try? await self?.sendDoneOnce()
      try? await Task.sleep(for: .seconds(30))
      guard !Task.isCancelled else { return }
      await self?.close()
    }
    defer { timer.cancel() }

    var arrived = false
    while true {
      let response = try await readResponse()
      if response.line.hasPrefix(tag + " ") {
        guard response.line.dropFirst(tag.count + 1).hasPrefix("OK") else {
          throw IMAPError.commandFailed("IDLE")
        }
        return arrived
      }
      if !arrived, response.line.hasSuffix(" EXISTS") {
        arrived = true
        try await sendDoneOnce()
      }
    }
  }

  private func sendDoneOnce() async throws {
    guard !doneSent else { return }
    doneSent = true
    try await write("DONE")
  }

  // MARK: - Lecture et écriture

  private func makeTag() -> String {
    defer { nextTag += 1 }
    return "W\(nextTag)"
  }

  private func collect(tag: String) async throws -> [IMAPResponse] {
    var untagged: [IMAPResponse] = []
    while true {
      let response = try await readResponse()
      if response.line.hasPrefix(tag + " ") {
        let status = response.line.dropFirst(tag.count + 1)
        guard status.hasPrefix("OK") else {
          throw IMAPError.commandFailed(String(status.prefix(100)))
        }
        return untagged
      }
      untagged.append(response)
    }
  }

  /// Une réponse entière, literals compris.
  private func readResponse() async throws -> IMAPResponse {
    var line = ""
    var literals: [IMAPLiteral] = []
    var chunk = try await readLine()
    while let literal = Self.literal(in: chunk) {
      guard literal.size <= Self.maximumLiteral else { throw IMAPError.protocolViolation }
      line += literal.prefix
      literals.append(IMAPLiteral(label: literal.prefix, data: try await readBytes(literal.size)))
      chunk = try await readLine()
    }
    line += chunk
    return IMAPResponse(line: line, literals: literals)
  }

  /// `* 4 FETCH (BODY[TEXT]<0> {312}` → taille 312 et le texte avant l'accolade.
  nonisolated static func literal(in chunk: String) -> (size: Int, prefix: String)? {
    guard chunk.hasSuffix("}"), let open = chunk.lastIndex(of: "{") else { return nil }
    let digits = chunk[chunk.index(after: open)..<chunk.index(before: chunk.endIndex)]
    guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let size = Int(digits) else { return nil }
    return (size, String(chunk[..<open]))
  }

  private func readLine() async throws -> String {
    while true {
      if let newline = buffer.firstIndex(of: 0x0A) {
        var line = Data(buffer[buffer.startIndex..<newline])
        buffer.removeSubrange(buffer.startIndex...newline)
        if line.last == 0x0D { line.removeLast() }
        return String(decoding: line, as: UTF8.self)
      }
      try await fill()
    }
  }

  private func readBytes(_ count: Int) async throws -> Data {
    while buffer.count < count { try await fill() }
    let chunk = Data(buffer.prefix(count))
    buffer.removeFirst(count)
    return chunk
  }

  private func fill() async throws {
    let data: Data = try await withCheckedThrowingContinuation { continuation in
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let data, !data.isEmpty {
          continuation.resume(returning: data)
        } else {
          continuation.resume(throwing: IMAPError.connectionClosed)
        }
      }
    }
    buffer.append(data)
  }

  private func write(_ text: String) async throws {
    let data = Data((text + "\r\n").utf8)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.send(
        content: data,
        completion: .contentProcessed { error in
          if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        })
    }
  }

  /// Chaîne entre guillemets IMAP ; un saut de ligne ne s'y écrit pas.
  nonisolated static func quote(_ value: String) throws -> String {
    guard !value.contains("\r"), !value.contains("\n") else { throw IMAPError.invalidCharacters }
    let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
      of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}

/// Exécute une action au plus une fois, d'où qu'elle soit appelée : le gestionnaire d'état de
/// `NWConnection` peut signaler plusieurs fois, la continuation ne se reprend qu'une.
nonisolated private final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var done = false

  func run(_ body: () -> Void) {
    lock.lock()
    defer { lock.unlock() }
    guard !done else { return }
    done = true
    body()
  }
}
