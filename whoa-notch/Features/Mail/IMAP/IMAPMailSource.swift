import Foundation
import OSLog

/// Lecture des réponses du serveur, sans réseau.
nonisolated enum IMAPParsing {

  /// `[UIDNEXT 4392]` → 4392.
  static func value(of key: String, in responses: [IMAPResponse]) -> Int? {
    for response in responses {
      guard let range = response.line.range(of: "[\(key) ") else { continue }
      if let number = Int(response.line[range.upperBound...].prefix(while: \.isNumber)) {
        return number
      }
    }
    return nil
  }

  /// `* 12 EXISTS` → 12.
  static func exists(in responses: [IMAPResponse]) -> Int? {
    for response in responses where response.line.hasSuffix(" EXISTS") {
      let parts = response.line.split(separator: " ")
      if parts.count == 3, let count = Int(parts[1]) { return count }
    }
    return nil
  }

  static func uid(in line: String) -> Int? {
    guard let range = line.range(of: "UID ") else { return nil }
    return Int(line[range.upperBound...].prefix(while: \.isNumber))
  }

  /// Un `* n FETCH (UID … BODY[HEADER.FIELDS …] {…} BODY[TEXT]<0> {…})` → le message.
  static func message(from response: IMAPResponse, account: String, validity: Int?) -> (
    uid: Int, message: MailMessage
  )? {
    guard response.line.contains("FETCH"), let uid = uid(in: response.line) else { return nil }
    let headerData = response.literals.first { $0.label.contains("HEADER") }?.data ?? Data()
    let bodyData = response.literals.first { !$0.label.contains("HEADER") }?.data ?? Data()
    let headers = MailBodyDecoder.parseHeaders(String(decoding: headerData, as: UTF8.self))

    let sender = MailBodyDecoder.displayName(fromHeader: headers["from"] ?? "")
    let subject = MailBodyDecoder.decodeHeader(headers["subject"] ?? "")
    let messageID = headers["message-id"] ?? ""
    return (
      uid,
      MailMessage(
        id: messageID.isEmpty ? "\(account)/\(validity ?? 0)/\(uid)" : messageID,
        sender: sender.isEmpty ? "Unknown sender" : sender,
        subject: subject.isEmpty ? "(no subject)" : subject,
        preview: MailBodyDecoder.preview(headers: headers, body: bodyData),
        account: account)
    )
  }
}

/// Courrier d'un compte IMAP : connexion TLS, `IDLE` sur la boîte de réception, et un `FETCH` des
/// messages arrivés depuis. Tout reste sur la machine : le Mac parle directement au serveur du
/// fournisseur, comme Mail, et le mot de passe est lu dans le trousseau.
///
/// Rien n'est modifié sur le serveur : la boîte est ouverte en lecture seule (`EXAMINE`) et le texte
/// lu par `BODY.PEEK`, donc aucun message n'est marqué lu. Connexion perdue (veille, réseau) :
/// nouvelle tentative avec un délai croissant, puis rattrapage des messages manqués.
nonisolated struct IMAPMailSource: MailSource {

  let account: IMAPAccount

  /// Combien de messages manqués on remontre au plus après une reconnexion.
  private static let catchUpLimit = 5
  private static let idleDuration: Duration = .seconds(600)
  private static let fetchItems =
    "(UID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT MESSAGE-ID CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] BODY.PEEK[TEXT]<0.6144>)"

  func messages() -> AsyncStream<MailMessage> {
    AsyncStream { continuation in
      let account = account
      let task = Task {
        await Self.run(account: account, continuation: continuation)
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Essai unique, pour le bouton « Test » des Préférences : se connecte, ouvre la boîte et rend
  /// le nombre de messages qu'elle contient.
  static func test(account: IMAPAccount, password: String) async throws -> Int {
    let connection = IMAPConnection(host: account.host, port: account.port)
    do {
      try await connection.open()
      try await connection.readGreeting()
      try await connection.login(username: account.username, password: password)
      let selected = try await connection.run("EXAMINE INBOX")
      await connection.close()
      return IMAPParsing.exists(in: selected) ?? 0
    } catch {
      await connection.close()
      throw error
    }
  }

  // MARK: - Boucle

  /// Ce qui survit d'une connexion à l'autre : où on en était, pour ne rien afficher deux fois.
  private final class SyncState {
    var lastUID: Int?
    var validity: Int?
  }

  private static func run(account: IMAPAccount, continuation: AsyncStream<MailMessage>.Continuation)
    async
  {
    let state = SyncState()
    var delay = 5
    while !Task.isCancelled {
      do {
        try await session(
          account: account, state: state, continuation: continuation, onReady: { delay = 5 })
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        Log.mail.error("IMAP : \(error.localizedDescription, privacy: .private)")
      }
      try? await Task.sleep(for: .seconds(delay))
      delay = min(delay * 2, 300)
    }
  }

  private static func session(
    account: IMAPAccount, state: SyncState, continuation: AsyncStream<MailMessage>.Continuation,
    onReady: () -> Void
  ) async throws {
    guard let password = IMAPCredentialStore.load(for: account), !password.isEmpty else {
      throw IMAPError.missingPassword
    }
    let connection = IMAPConnection(host: account.host, port: account.port)
    do {
      try await withTaskCancellationHandler {
        try await connection.open()
        try await connection.readGreeting()
        try await connection.login(username: account.username, password: password)
        let selected = try await connection.run("EXAMINE INBOX")
        onReady()
        Log.mail.info("IMAP : boîte ouverte")

        let validity = IMAPParsing.value(of: "UIDVALIDITY", in: selected)
        if state.lastUID == nil || state.validity != validity {
          // Premier passage : l'existant n'est pas du nouveau courrier.
          state.lastUID = (IMAPParsing.value(of: "UIDNEXT", in: selected) ?? 1) - 1
          state.validity = validity
        }

        try await fetchNew(connection, account: account, state: state, continuation: continuation)
        while true {
          if try await connection.idle(maxDuration: idleDuration) {
            try await fetchNew(
              connection, account: account, state: state, continuation: continuation)
          }
        }
      } onCancel: {
        Task { await connection.close() }
      }
    } catch {
      await connection.close()
      throw error
    }
  }

  private static func fetchNew(
    _ connection: IMAPConnection, account: IMAPAccount, state: SyncState,
    continuation: AsyncStream<MailMessage>.Continuation
  ) async throws {
    guard let last = state.lastUID else { return }
    let responses: [IMAPResponse]
    do {
      responses = try await connection.run("UID FETCH \(last + 1):* \(fetchItems)")
    } catch IMAPError.commandFailed {
      return  // boîte vide : certains serveurs refusent `1:*`
    }

    let fresh =
      responses
      .compactMap {
        IMAPParsing.message(from: $0, account: account.username, validity: state.validity)
      }
      .filter { $0.uid > last }
      .sorted { $0.uid < $1.uid }
    // `n:*` rend toujours au moins le dernier message ; le filtre ci-dessus l'écarte s'il est déjà vu.
    if let newest = fresh.last { state.lastUID = newest.uid }
    for item in fresh.suffix(catchUpLimit) {
      continuation.yield(item.message)
    }
  }
}
