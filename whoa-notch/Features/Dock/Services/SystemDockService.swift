import Foundation
import os

/// Accès aux réglages du Dock macOS, derrière un protocole pour que les tests ne touchent jamais
/// au vrai Dock.
@MainActor
protocol DockDefaultsAccessing: AnyObject {
  func bool(_ key: String) -> Bool?
  func double(_ key: String) -> Double?
  /// `nil` supprime la clé.
  func set(_ key: String, bool: Bool?)
  func set(_ key: String, double: Double?)
  func restartDock()
  /// Lance un veilleur indépendant qui remet `saved` si l'app disparaît sans passer par `restore()`
  /// (arrêt depuis Xcode, plantage, `kill -9`) — cas où `applicationWillTerminate` n'est pas appelé.
  func armRestoreWatcher(saved: SavedSystemDock)
  func disarmRestoreWatcher()
}

extension DockDefaultsAccessing {
  func armRestoreWatcher(saved: SavedSystemDock) {}
  func disarmRestoreWatcher() {}
}

@MainActor
final class SystemDockDefaults: DockDefaultsAccessing {
  private let domain = "com.apple.dock" as CFString

  func bool(_ key: String) -> Bool? {
    (CFPreferencesCopyAppValue(key as CFString, domain) as? NSNumber)?.boolValue
  }

  func double(_ key: String) -> Double? {
    (CFPreferencesCopyAppValue(key as CFString, domain) as? NSNumber)?.doubleValue
  }

  func set(_ key: String, bool: Bool?) { write(key, bool.map { NSNumber(value: $0) }) }
  func set(_ key: String, double: Double?) { write(key, double.map { NSNumber(value: $0) }) }

  private func write(_ key: String, _ value: CFPropertyList?) {
    CFPreferencesSetAppValue(key as CFString, value, domain)
    CFPreferencesAppSynchronize(domain)
  }

  private var watcherSentinel: URL?

  func armRestoreWatcher(saved: SavedSystemDock) {
    disarmRestoreWatcher()
    let pid = ProcessInfo.processInfo.processIdentifier
    let sentinel = FileManager.default.temporaryDirectory.appendingPathComponent(
      "whoa-notch-dock-restore-\(pid)")
    guard FileManager.default.createFile(atPath: sentinel.path, contents: nil) else { return }
    watcherSentinel = sentinel

    func command(_ key: String, bool: Bool?) -> String {
      bool.map { "/usr/bin/defaults write com.apple.dock \(key) -bool \($0)" }
        ?? "/usr/bin/defaults delete com.apple.dock \(key) 2>/dev/null"
    }
    func command(_ key: String, double: Double?) -> String {
      double.map { "/usr/bin/defaults write com.apple.dock \(key) -float \($0)" }
        ?? "/usr/bin/defaults delete com.apple.dock \(key) 2>/dev/null"
    }
    // Tant que l'app tourne et que le fichier témoin existe, on attend. Le fichier a disparu : arrêt
    // normal, `restore()` a tout fait. L'app a disparu avec le fichier encore là : on restaure.
    let script = """
      while kill -0 \(pid) 2>/dev/null && [ -e '\(sentinel.path)' ]; do sleep 1; done
      if [ -e '\(sentinel.path)' ]; then
        \(command("autohide", bool: saved.autohide))
        \(command("autohide-delay", double: saved.autohideDelay))
        /usr/bin/killall Dock
        rm -f '\(sentinel.path)'
      fi
      """
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    // Le sous-shell en arrière-plan est adopté par launchd : il survit à l'app.
    process.arguments = ["-c", "(\(script)) >/dev/null 2>&1 &"]
    do { try process.run() } catch {
      Log.dock.error(
        "veilleur de restauration impossible : \(error.localizedDescription, privacy: .public)")
    }
  }

  func disarmRestoreWatcher() {
    guard let sentinel = watcherSentinel else { return }
    try? FileManager.default.removeItem(at: sentinel)
    watcherSentinel = nil
  }

  func restartDock() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = ["Dock"]
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      Log.dock.error("killall Dock a échoué : \(error.localizedDescription, privacy: .public)")
    }
  }
}

/// Masque le Dock macOS (masquage auto + très long délai) et le remet **exactement** comme il
/// était. Les valeurs d'origine sont enregistrées avant toute écriture ; une clé absente est
/// supprimée à la restauration plutôt que réécrite.
@MainActor
final class SystemDockService {

  static let hiddenDelay: Double = 1000
  private static let autohideKey = "autohide"
  private static let delayKey = "autohide-delay"

  private let storage: SettingsStorage
  private let defaults: DockDefaultsAccessing

  init(storage: SettingsStorage = .shared, defaults: DockDefaultsAccessing = SystemDockDefaults()) {
    self.storage = storage
    self.defaults = defaults
  }

  /// Aligne le Dock système sur le réglage : masqué si demandé, restauré sinon (y compris après
  /// un plantage qui aurait laissé une sauvegarde derrière lui).
  func sync(hidden: Bool) {
    if hidden { hide() } else { restore() }
  }

  private func hide() {
    // Une sauvegarde existante vient d'un lancement précédent : la garder, elle seule
    // contient les vraies valeurs de l'utilisateur.
    if storage.settings.dock.savedSystemDock == nil {
      // Déjà masqué par nous (une autre instance ou une sortie sans restauration) : ces valeurs
      // ne sont pas celles de l'utilisateur. On garde des clés absentes plutôt que de les figer.
      let alreadyHidden = isHiddenByUs()
      storage.settings.dock.savedSystemDock = SavedSystemDock(
        autohide: alreadyHidden ? nil : defaults.bool(Self.autohideKey),
        autohideDelay: alreadyHidden ? nil : defaults.double(Self.delayKey))
    }
    // Armé avant le garde : après un plantage le Dock est déjà masqué, et ce lancement doit quand même le surveiller.
    if let saved = storage.settings.dock.savedSystemDock {
      defaults.armRestoreWatcher(saved: saved)
    }
    guard !isHiddenByUs() else { return }
    defaults.set(Self.autohideKey, bool: true)
    defaults.set(Self.delayKey, double: Self.hiddenDelay)
    defaults.restartDock()
    Log.dock.info("Dock macOS masqué")
  }

  private func isHiddenByUs() -> Bool {
    defaults.bool(Self.autohideKey) == true && defaults.double(Self.delayKey) == Self.hiddenDelay
  }

  func restore() {
    guard let saved = storage.settings.dock.savedSystemDock else { return }
    defaults.disarmRestoreWatcher()
    defaults.set(Self.autohideKey, bool: saved.autohide)
    defaults.set(Self.delayKey, double: saved.autohideDelay)
    defaults.restartDock()
    storage.settings.dock.savedSystemDock = nil
    Log.dock.info("Dock macOS restauré")
  }
}
