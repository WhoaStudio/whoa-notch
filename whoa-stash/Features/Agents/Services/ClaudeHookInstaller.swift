import Foundation

/// Installe et retire les hooks de Claude Code (`Stop`, `Notification`, `PermissionRequest`, `PreToolUse` sur `AskUserQuestion`, et ceux qui lèvent une demande) dans `~/.claude/settings.json`.
///
/// La fusion ne touche qu'aux entrées dont la commande désigne notre script : les autres clés et les
/// autres hooks restent tels quels. Avant toute écriture, le fichier d'origine est copié dans
/// `settings.json.whoa-stash.bak` ; à la désinstallation, si le résultat est équivalent à cette copie,
/// ses octets d'origine sont réécrits (`JSONSerialization` ne conserve pas l'ordre des clés).
nonisolated struct ClaudeHookInstaller {

    enum Status: Equatable {
        case notInstalled
        case partiallyInstalled
        case installed

        var text: String {
            switch self {
            case .notInstalled: "Not installed"
            case .partiallyInstalled: "Partly installed"
            case .installed: "Installed"
            }
        }
    }

    enum InstallError: LocalizedError {
        case unreadableSettings

        var errorDescription: String? {
            "settings.json is not a valid JSON object. It was left untouched."
        }
    }

    /// Événement Claude Code → argument passé au script.
    private static let events: [(name: String, argument: String, matcher: String?)] = [
        ("Stop", "stop", nil),
        ("Notification", "notify", "permission_prompt|idle_prompt|elicitation_dialog"),
        ("PermissionRequest", "permission", nil),
        ("PreToolUse", "question", "AskUserQuestion"),
        // Chaque outil qui démarre fait avancer la carte d'activité de l'onglet AI.
        ("PreToolUse", "tool", nil),
        // La demande se lève au premier événement suivant de la session : aucun hook ne signale la réponse.
        ("PostToolUse", "clear", nil),
        ("PostToolUseFailure", "clear", nil),
        ("UserPromptSubmit", "turn", nil),
        ("SessionEnd", "end", nil),
    ]

    let settingsURL: URL
    let scriptURL: URL

    static var standard: ClaudeHookInstaller {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ClaudeHookInstaller(
            settingsURL: home.appendingPathComponent(".claude/settings.json"),
            scriptURL: AgentHookServer.supportDirectory.appendingPathComponent("whoa-hook"))
    }

    private var backupURL: URL { settingsURL.appendingPathExtension("whoa-stash.bak") }

    // MARK: - État

    func status() -> Status {
        guard let root = try? readRoot() else { return .notInstalled }
        let present = Self.events.filter { hasEntry(in: root, event: $0.name, argument: $0.argument) }.count
        let scriptExists = FileManager.default.isExecutableFile(atPath: scriptURL.path)
        if present == Self.events.count && scriptExists { return .installed }
        return present == 0 && !scriptExists ? .notInstalled : .partiallyInstalled
    }

    // MARK: - Installation

    /// Remplace nos entrées par celles d'aujourd'hui : une installation plus ancienne, aux arguments
    /// différents, ne laisse pas de doublon. Les hooks des autres ne bougent pas.
    func install() throws {
        var root = try readRoot()
        let original = try? Data(contentsOf: settingsURL)

        try writeScript()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (name, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = withoutOurs(groups)
            hooks[name] = kept.isEmpty ? nil : kept
        }
        for event in Self.events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command(event.argument)]]]
            if let matcher = event.matcher { group["matcher"] = matcher }
            hooks[event.name] = (hooks[event.name] as? [Any] ?? []) + [group]
        }
        var updated = root
        updated["hooks"] = hooks
        guard !NSDictionary(dictionary: updated).isEqual(to: root) else { return }

        // Un seul `.bak` : le premier, celui du fichier d'avant nous. Une seconde installation
        // qui ne change rien n'arrive pas jusqu'ici.
        if let original, !FileManager.default.fileExists(atPath: backupURL.path) {
            try original.write(to: backupURL, options: .atomic)
        }
        root = updated
        try write(root)
    }

    func uninstall() throws {
        var root = try readRoot()
        if var hooks = root["hooks"] as? [String: Any] {
            for event in Self.events {
                guard let groups = hooks[event.name] as? [[String: Any]] else { continue }
                let kept = withoutOurs(groups)
                hooks[event.name] = kept.isEmpty ? nil : kept
            }
            root["hooks"] = hooks.isEmpty ? nil : hooks
        }

        if let backup = try? Data(contentsOf: backupURL),
            let saved = try? JSONSerialization.jsonObject(with: backup) as? [String: Any],
            NSDictionary(dictionary: saved).isEqual(to: root)
        {
            try backup.write(to: settingsURL, options: .atomic)
            try? FileManager.default.removeItem(at: backupURL)
        } else if root.isEmpty && !FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.removeItem(at: settingsURL)
        } else {
            try write(root)
        }
        try? FileManager.default.removeItem(at: scriptURL)
    }

    // MARK: - Fichier

    private func readRoot() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadableSettings
        }
        return root
    }

    private func write(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }

    private func writeScript() throws {
        try FileManager.default.createDirectory(
            at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.scriptContents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    // MARK: - Entrées

    /// Le chemin est entre apostrophes : il contient « Application Support ».
    private func command(_ argument: String) -> String {
        "'\(scriptURL.path)' \(argument)"
    }

    /// Les groupes de hooks sans nos entrées ; un groupe qui n'avait que les nôtres disparaît.
    private func withoutOurs(_ groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            var group = group
            let remaining = (group["hooks"] as? [[String: Any]] ?? []).filter { !isOurs($0) }
            if remaining.isEmpty { return nil }
            group["hooks"] = remaining
            return group
        }
    }

    private func isOurs(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains(scriptURL.path) == true
    }

    private func hasEntry(in root: [String: Any], event: String, argument: String) -> Bool {
        let groups = (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.contains { group in
            (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String) == command(argument) }
        }
    }

    /// Le script ne bloque jamais Claude Code : il sort toujours en 0, et sans l'app il ne fait rien.
    /// Il met le JSON du hook sur une ligne, que le serveur lit jusqu'au `\n`.
    ///
    /// Les événements d'activité (`tool`, `clear`, `stop`…) sont réduits aux champs utiles et à
    /// 3 000 caractères par valeur : le serveur lit 64 Ko au plus, et un `Write` ou un résultat de
    /// lecture dépasse vite. `permission` garde l'entrée entière : la réponse la renvoie.
    ///
    /// Pour `permission`, il reste connecté et attend la réponse de l'encoche, qu'il rend telle quelle
    /// sur sa sortie : Claude Code l'applique et ferme sa boîte de dialogue. La boîte s'ouvre sans
    /// attendre le hook ; si on y répond dans le terminal, Claude Code tue le script et le serveur voit
    /// la connexion se fermer. Perl plutôt que `nc`, qui se ferme dès la fin de son entrée.
    static let scriptContents = #"""
        #!/bin/sh
        # Installé par Whoa Stash : prévient l'encoche qu'une session Claude Code se termine, demande ou reprend.
        SOCK="$HOME/Library/Application Support/whoa-stash/agent.sock"
        [ -S "$SOCK" ] || exit 0
        WAIT=0
        [ "$1" = permission ] && WAIT=590
        exec /usr/bin/perl -MSocket -e '
        my ($kind, $path, $wait) = @ARGV;
        local $/;
        my $in = <STDIN>;
        $in = "{}" unless defined $in && length $in;
        if ($kind ne "permission" && $kind ne "question") {
            require JSON::PP;
            my $d = eval { JSON::PP::decode_json($in) };
            if (ref $d eq "HASH") {
                my %o = map { $_ => $d->{$_} } grep { defined $d->{$_} && !ref $d->{$_} } qw(session_id cwd tool_name);
                if (ref $d->{tool_input} eq "HASH") {
                    my $i = $d->{tool_input};
                    $o{tool_input} = { map { my $v = $i->{$_}; ($_ => (defined $v && !ref $v && length $v > 3000 ? substr($v, 0, 3000) : $v)) } keys %$i };
                }
                $in = JSON::PP->new->utf8->canonical->encode(\%o);
            }
        }
        $in =~ s/\n//g;
        socket(my $s, PF_UNIX, SOCK_STREAM, 0) or exit 0;
        connect($s, pack_sockaddr_un($path)) or exit 0;
        syswrite($s, "{\"kind\":\"$kind\",\"payload\":$in}\n");
        exit 0 unless $wait;
        my $rin = "";
        vec($rin, fileno($s), 1) = 1;
        if (select(my $rout = $rin, undef, undef, $wait)) {
            $/ = "\n";
            my $line = <$s>;
            print $line if defined $line;
        }
        exit 0;
        ' "$1" "$SOCK" "$WAIT" 2>/dev/null
        exit 0

        """#
}
