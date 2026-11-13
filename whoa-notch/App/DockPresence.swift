import AppKit

/// Présence de l'app dans le Dock. La cible est `LSUIElement`, donc la politique d'activation
/// au lancement est `.accessory` : pas d'icône, pas de menu bar, et c'est l'état de repos.
///
/// La fenêtre de Préférences est la seule qui en demande une. Sans icône, une fenêtre de
/// réglages passée à l'arrière-plan n'est plus rappelable — ni par le Dock, ni par un menu
/// d'app qui n'existe pas tant qu'on est `.accessory`. On bascule donc sur `.regular` le temps
/// qu'elle soit ouverte, et on redevient `.accessory` dès sa fermeture.
///
/// Les deux fonctions sont idempotentes : les appeler deux fois de suite ne fait rien la
/// seconde fois, ce qui évite un clignotement de l'icône sur une réouverture.
@MainActor
enum DockPresence {

  static func showIcon() {
    guard NSApp.activationPolicy() != .regular else { return }
    NSApp.setActivationPolicy(.regular)
  }

  static func hideIcon() {
    guard NSApp.activationPolicy() != .accessory else { return }
    NSApp.setActivationPolicy(.accessory)
  }
}
