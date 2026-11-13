import AppKit
import OSLog

/// Son « pop » joué à chaque clic sur un bouton de l'app, si `General > Enable button sound` est coché.
///
/// Un seul moniteur d'événements couvre tous les `NSButton` : aucun contrôleur n'a besoin de
/// câbler son action. Les contrôles dessinés à la main (icônes du dock, onglets, engrenage)
/// appellent `playClick()` directement. Le son est un `NSSound` partagé — `stop()` avant `play()`
/// redémarre la lecture quand on clique vite, sans empiler les lectures. Un fichier manquant ou
/// illisible est journalisé et n'empêche jamais l'action du bouton, qui s'exécute de toute façon.
@MainActor
final class ButtonSound {

  static let shared = ButtonSound()

  private let sound: NSSound?
  private let storage: SettingsStorage
  private var clickMonitor: Any?

  private init(storage: SettingsStorage = .shared) {
    self.storage = storage
    guard let url = Bundle.main.url(forResource: "pop", withExtension: "mp3") else {
      Log.sound.error("Fichier pop.mp3 introuvable dans le bundle")
      sound = nil
      return
    }
    sound = NSSound(contentsOf: url, byReference: true)
    sound?.volume = 0.35
  }

  /// Écoute les clics de souris de l'app. À appeler une seule fois, au lancement.
  func startClickMonitoring() {
    guard clickMonitor == nil else { return }
    clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      self?.handleClick(event)
      return event
    }
  }

  private func handleClick(_ event: NSEvent) {
    guard let window = event.window, let frameView = window.contentView?.superview else { return }
    let point = frameView.convert(event.locationInWindow, from: nil)
    guard let hit = frameView.hitTest(point), let button = enclosingButton(of: hit),
      button.isEnabled
    else {
      return
    }
    playClick()
  }

  /// Le bouton qui contient `view`, ou `nil` si le clic ne tombe pas sur un bouton.
  private func enclosingButton(of view: NSView) -> NSButton? {
    var current: NSView? = view
    while let candidate = current {
      if let button = candidate as? NSButton { return button }
      current = candidate.superview
    }
    return nil
  }

  /// Joue le son de clic si le réglage le permet. Sans effet sinon.
  func playClick() {
    guard storage.settings.general.enableButtonSound, let sound else { return }
    sound.stop()
    if !sound.play() {
      Log.sound.error("Lecture de pop.mp3 refusée")
    }
  }
}
