import Foundation
import OSLog
import os

/// Écoute le socket Unix local sur lequel le script de hook envoie ses événements.
///
/// Aucun réseau : le socket vit dans `Application Support/whoa-stash/`, en 0600. Un message est une
/// ligne JSON ; il est lu sur une file de fond et remis au main actor décodé.
nonisolated final class AgentHookServer: @unchecked Sendable {

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/whoa-stash",
                isDirectory: true
            )
    }

    static var socketPath: String {
        supportDirectory.appendingPathComponent("agent.sock").path
    }

    private let socketPath: String
    /// Combien de temps une question ou un formulaire reste ouvert avant d'être rendu à Claude Code.
    var questionWait: TimeInterval = AgentHookServer.defaultQuestionWait
    /// Combien de temps une fin de tour attend une réponse libre.
    var stopReplyWait: TimeInterval = AgentHookServer.defaultStopReplyWait
    /// Les délais par défaut, lus aussi par l'encoche pour le compte à rebours de la pastille.
    nonisolated static let defaultQuestionWait: TimeInterval = 120
    nonisolated static let defaultStopReplyWait: TimeInterval = 25

    init(socketPath: String = AgentHookServer.socketPath) {
        self.socketPath = socketPath
    }

    /// Posé avant `start()`, appelé sur le main actor.
    var onEvent: (@MainActor (AgentEvent) -> Void)?

    /// Posé avant `start()`, appelé sur le main actor quand un hook qui attendait une réponse est
    /// annulé : l'utilisateur a répondu dans le terminal, ou la session a été tuée.
    var onCancel: (@MainActor (String) -> Void)?

    /// La réponse libre après un tour est activée (Préférences ▸ AI). Lu sur `queue`, posé depuis le
    /// main actor : d'où le verrou.
    private let holdsStopReplies = OSAllocatedUnfairLock(initialState: false)

    func setStopReplyEnabled(_ enabled: Bool) {
        holdsStopReplies.withLock { $0 = enabled }
    }

    /// Combien de temps une demande reste ouverte avant d'être rendue à Claude Code (`{}`). Une
    /// permission n'en a pas : sa boîte de dialogue s'ouvre en parallèle, et le script a sa propre limite.
    private func holdDuration(for response: AgentEvent.Response)
        -> TimeInterval?
    {
        switch response {
        case .permission: nil
        case .question, .elicitation: questionWait
        case .stopReply: stopReplyWait
        }
    }

    private var source: DispatchSourceRead?
    /// Consignes en attente, par session : chacune ne sort que par le hook de sa propre session.
    /// Touché seulement sur `queue`.
    private var steers: [String: [String]] = [:]

    /// Posé avant `start()`, appelé sur le main actor quand une consigne est remise à l'agent
    /// (session, texte).
    var onSteerDelivered: (@MainActor (String, String) -> Void)?

    /// Garde une consigne pour la prochaine fin d'outil de cette session, et d'elle seule.
    func steer(sessionID: String, text: String) {
        queue.async { [weak self] in
            self?.steers[sessionID, default: []].append(text)
        }
    }

    /// La consigne en attente de cette session, rendue au hook `PostToolUse` sous la forme que Claude
    /// Code ajoute à son contexte. Sur `queue`.
    private func takeSteers(for sessionID: String) -> (
        json: String, texts: [String]
    )? {
        guard let texts = steers.removeValue(forKey: sessionID), !texts.isEmpty
        else { return nil }
        let note =
            "The user sent this instruction from the Whoa Stash notch while you were working. "
            + "Take it into account now: " + texts.joined(separator: " | ")
        let root: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PostToolUse", "additionalContext": note,
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root),
            let json = String(data: data, encoding: .utf8)
        else { return nil }
        return (json, texts)
    }
    /// Connexions de hooks qui attendent une réponse, par `replyID`. Touché seulement sur `queue`.
    private var waiting: [String: DispatchSourceRead] = [:]
    private let queue = DispatchQueue(
        label: "ugolin-olle.whoa-stash.agent-hook-server"
    )

    func start() {
        guard source == nil else { return }
        let path = socketPath
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return Log.agents.error(
                "socket() a échoué : \(errno, privacy: .public)"
            )
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            close(fd)
            return Log.agents.error("Chemin du socket trop long")
        }
        withUnsafeMutablePointer(to: &address.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
                _ = strlcpy($0, path, capacity)
            }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            return Log.agents.error(
                "bind/listen a échoué : \(errno, privacy: .public)"
            )
        }
        chmod(path, 0o600)

        let source = DispatchSource.makeReadSource(
            fileDescriptor: fd,
            queue: queue
        )
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
            guard let source = self?.waiting.removeValue(forKey: replyID) else {
                return
            }
            Self.write(json, to: Int32(source.handle))
            source.cancel()
        }
    }

    /// Écrit une ligne sur la connexion d'un hook.
    private nonisolated static func write(_ line: String, to fd: Int32) {
        let bytes = Array((line + "\n").utf8)
        var sent = 0
        while sent < bytes.count {
            let count = bytes[sent...].withUnsafeBytes {
                send(fd, $0.baseAddress, $0.count, 0)
            }
            if count <= 0 { break }
            sent += count
        }
    }

    /// Lit jusqu'au premier `\n` (ou la fin du flux), avec un délai d'une seconde et 64 Ko au plus.
    /// La connexion se ferme ensuite, sauf pour une demande à laquelle on peut répondre : elle reste
    /// ouverte, surveillée, jusqu'à `reply` ou jusqu'à ce que le hook la ferme.
    private func read(_ client: Int32) {
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(
            client,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 65_536 {
            let count = recv(client, &buffer, buffer.count, 0)
            if count <= 0 { break }
            data.append(buffer, count: count)
            if buffer[..<count].contains(0x0A) { break }
        }

        let holdStopReply = holdsStopReplies.withLock { $0 }
        guard let event = AgentEvent.decode(data, holdStopReply: holdStopReply)
        else {
            close(client)
            return Log.agents.debug(
                "Message ignoré sur le socket (\(data.count, privacy: .public) octets)"
            )
        }
        if let replyID = event.replyID {
            // Le script d'un `Stop` n'attend qu'un instant, sauf si on lui dit que le tour est retenu.
            if event.response == .stopReply {
                Self.write(#"{"pending":true}"#, to: client)
            }
            hold(
                client,
                replyID: replyID,
                timeout: holdDuration(for: event.response)
            )
        } else if event.acceptsSteer, let sessionID = event.sessionID,
            let steer = takeSteers(for: sessionID)
        {
            Self.write(steer.json, to: client)
            close(client)
            Task { @MainActor [weak self] in
                steer.texts.forEach { self?.onSteerDelivered?(sessionID, $0) }
            }
        } else {
            close(client)
        }
        Log.agents.info(
            "Événement reçu : \(event.kind.rawValue, privacy: .public)"
        )
        Task { @MainActor [weak self] in self?.onEvent?(event) }
    }

    /// Garde la connexion ouverte et guette sa fermeture : `nc` ne ferme que si Claude Code a tué le
    /// hook, c'est-à-dire quand la demande a trouvé sa réponse ailleurs.
    private func hold(_ client: Int32, replyID: String, timeout: TimeInterval?)
    {
        // La lecture d'un délai d'une seconde a servi à la ligne d'entrée ; l'attente est sans limite.
        var none = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(
            client,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &none,
            socklen_t(MemoryLayout<timeval>.size)
        )
        let watcher = DispatchSource.makeReadSource(
            fileDescriptor: client,
            queue: queue
        )
        watcher.setEventHandler { [weak self, weak watcher] in
            var byte: UInt8 = 0
            let count = recv(client, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
            guard
                count == 0
                    || (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK)
            else { return }
            guard let self, let watcher,
                self.waiting.removeValue(forKey: replyID) != nil
            else { return }
            watcher.cancel()
            Log.agents.info("Hook annulé : la connexion s'est fermée")
            Task { @MainActor [weak self] in self?.onCancel?(replyID) }
        }
        watcher.setCancelHandler { close(client) }
        waiting[replyID] = watcher
        watcher.resume()

        // Sans réponse à temps, la demande est rendue à Claude Code : il demande lui-même, ou s'arrête.
        guard let timeout else { return }
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self,
                let watcher = self.waiting.removeValue(forKey: replyID)
            else { return }
            Self.write("{}", to: Int32(watcher.handle))
            watcher.cancel()
            Log.agents.info("Demande rendue à Claude Code : délai écoulé")
            Task { @MainActor [weak self] in self?.onCancel?(replyID) }
        }
    }
}
