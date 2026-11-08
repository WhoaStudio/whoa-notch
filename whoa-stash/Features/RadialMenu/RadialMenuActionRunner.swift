import AppKit
import os

/// Exécute l'élément choisi : lance l'appli, ou lance le raccourci par `/usr/bin/shortcuts`.
@MainActor
enum RadialMenuActionRunner {

  static func run(_ item: RadialMenuItem) {
    switch item.kind {
    case .app: launchApp(item)
    case .shortcut: runShortcut(named: item.name)
    }
  }

  private static func launchApp(_ item: RadialMenuItem) {
    guard let url = AppLauncher.resolveURL(item.pinnedApp) else {
      Log.radialMenu.info("Appli introuvable : \(item.bundleID, privacy: .public)")
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
      if let error {
        Log.radialMenu.error(
          "Lancement impossible : \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private static func runShortcut(named name: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    process.arguments = ["run", name]
    process.terminationHandler = { finished in
      if finished.terminationStatus != 0 {
        Log.radialMenu.error(
          "Raccourci en échec — code \(finished.terminationStatus, privacy: .public)")
      }
    }
    do {
      try process.run()
    } catch {
      Log.radialMenu.error(
        "Raccourci impossible à lancer : \(error.localizedDescription, privacy: .public)")
    }
  }
}

/// Noms des raccourcis de Raccourcis.app, pour les choisir dans les Préférences.
enum ShortcutsCatalog {

  nonisolated static func names() async -> [String] {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return continuation.resume(returning: []) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        continuation.resume(returning: lines.filter { !$0.isEmpty })
      }
    }
  }
}
