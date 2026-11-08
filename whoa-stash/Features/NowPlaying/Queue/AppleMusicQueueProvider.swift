import Foundation
import OSLog

/// Les titres qui suivent dans la liste de lecture d'Apple Musique, lus par AppleScript.
///
/// Passe par `osascript` plutôt que par `NSAppleScript` : l'événement part d'un binaire système, sans
/// titre particulier à porter pour l'app, et un Musique qui ne répond pas ne bloque qu'un processus
/// qu'on abandonne au bout de `timeout`. macOS demande l'autorisation de piloter Musique à la
/// première lecture (texte : `NSAppleEventsUsageDescription`).
///
/// En lecture aléatoire la suite réelle n'est pas lisible : la liste reste vide plutôt que fausse.
nonisolated struct AppleMusicQueueProvider: PlayingNextProviding {

  static let bundleIdentifier = "com.apple.Music"
  private let timeout: Duration = .seconds(5)

  /// Trois chaînes par titre — nom, artiste, pochette brute — lues ensuite par `parse`. La
  /// pochette est une donnée binaire : `-ss` l'écrit en hexadécimal (`«data tdta…»`).
  private static func script(limit: Int) -> String {
    """
    tell application "Music"
        if player state is not playing and player state is not paused then return {}
        if shuffle enabled then return {}
        set out to {}
        try
            set pl to current playlist
            set idx to index of current track
            set total to count of tracks of pl
            repeat with i from (idx + 1) to (idx + \(limit))
                if i > total then exit repeat
                set t to track i of pl
                set art to ""
                try
                    set art to raw data of artwork 1 of t
                end try
                set end of out to {name of t, artist of t, art}
            end repeat
        end try
        return out
    end tell
    """
  }

  func supports(bundleIdentifier: String) -> Bool { bundleIdentifier == Self.bundleIdentifier }

  func upcoming(limit: Int) async -> [QueueItem] {
    guard let output = await runScript(Self.script(limit: limit)) else { return [] }
    return Self.parse(output, limit: limit)
  }

  private func runScript(_ source: String) async -> String? {
    let timeout = timeout
    return await Task.detached { () -> String? in
      let process = Process()
      process.executableURL = URL(filePath: "/usr/bin/osascript")
      process.arguments = ["-ss", "-e", source]
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      do { try process.run() } catch {
        Log.nowPlaying.error(
          "osascript impossible : \(error.localizedDescription, privacy: .public)")
        return nil
      }

      // Un Musique qui n'a pas encore reçu l'autorisation attend un clic : on n'attend pas avec lui.
      let watchdog = Task {
        try? await Task.sleep(for: timeout)
        if process.isRunning { process.terminate() }
      }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      watchdog.cancel()
      guard process.terminationStatus == 0 else { return nil }
      return String(data: data, encoding: .utf8)
    }.value
  }

  /// Lit la liste imprimée par `osascript -ss` : `{{"Titre", "Artiste", «data tdtaFFD8…»}, …}`.
  /// Seuls comptent les littéraux — chaînes entre guillemets et données hexadécimales —, lus dans
  /// l'ordre, trois par titre ; une pochette absente arrive comme une chaîne vide.
  static func parse(_ output: String, limit: Int) -> [QueueItem] {
    let pattern = #""((?:[^"\\]|\\.)*)"|«data tdta([0-9A-Fa-f]*)»"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let text = output as NSString
    var tokens: [(text: String?, data: Data?)] = []
    for match in regex.matches(in: output, range: NSRange(location: 0, length: text.length)) {
      if match.range(at: 1).location != NSNotFound {
        tokens.append((unescape(text.substring(with: match.range(at: 1))), nil))
      } else {
        tokens.append((nil, hexData(text.substring(with: match.range(at: 2)))))
      }
    }

    var items: [QueueItem] = []
    var index = 0
    while index + 2 < tokens.count, items.count < limit {
      let title = tokens[index].text ?? ""
      let artist = tokens[index + 1].text ?? ""
      let artwork = tokens[index + 2].data
      if !title.isEmpty { items.append(QueueItem(title: title, artist: artist, artwork: artwork)) }
      index += 3
    }
    return items
  }

  private static func unescape(_ string: String) -> String {
    string.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
  }

  private static func hexData(_ hex: String) -> Data? {
    guard !hex.isEmpty, hex.count.isMultiple(of: 2) else { return nil }
    var data = Data(capacity: hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
      data.append(byte)
      index = next
    }
    return data
  }
}
