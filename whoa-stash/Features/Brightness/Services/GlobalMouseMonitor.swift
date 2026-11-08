import AppKit

/// Émet la position globale du curseur à chaque déplacement, en combinant un moniteur
/// global (autres apps) et local (notre app) — aucune permission d'accessibilité requise.
@MainActor
final class GlobalMouseMonitor {

  var onMove: ((NSPoint) -> Void)?

  /// Appelé à chaque appui du bouton gauche, avec la position globale du curseur.
  var onClick: ((NSPoint) -> Void)?

  /// Suivre aussi le curseur **bouton gauche enfoncé**. Un glisser — de fichiers depuis le
  /// Finder, par exemple — n'émet pas de `.mouseMoved` : sans cela, un panneau qui se déplie
  /// au survol resterait replié tout au long du glisser, et n'aurait jamais l'occasion de
  /// recevoir le dépôt. Hors de ce cas, les surcoûts d'un événement par image de glisser ne
  /// servent à rien, d'où le défaut. Le relâchement (`.leftMouseUp`) en fait partie : c'est
  /// lui qui dit que le glisser est fini et que tout peut reprendre son état de repos.
  private let tracksDrags: Bool

  private var globalMonitor: Any?
  private var localMonitor: Any?

  init(tracksDrags: Bool = false) {
    self.tracksDrags = tracksDrags
  }

  func start() {
    stop()

    var mask: NSEvent.EventTypeMask =
      tracksDrags ? [.mouseMoved, .leftMouseDragged, .leftMouseUp] : [.mouseMoved]
    if onClick != nil { mask.insert(.leftMouseDown) }

    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
      self?.dispatch(event)
    }

    localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
      self?.dispatch(event)
      return event
    }
  }

  private func dispatch(_ event: NSEvent) {
    if event.type == .leftMouseDown {
      onClick?(NSEvent.mouseLocation)
    } else {
      onMove?(NSEvent.mouseLocation)
    }
  }

  func stop() {
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
    }
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
    }
    globalMonitor = nil
    localMonitor = nil
  }
}
