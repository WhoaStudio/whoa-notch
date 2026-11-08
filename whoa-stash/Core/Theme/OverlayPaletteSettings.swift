import AppKit
import Combine

/// Pont entre `SettingsStorage` et les statiques partagées de l'overlay : accent et
/// translucidité pour `OverlayPalette`, interrupteur du mouvement pour `OverlayAnimation`.
/// Prévient ensuite l'overlay qu'il doit se repeindre.
///
/// Sans lui, ces deux types devraient connaître les préférences — alors que ce sont un type de
/// thème et un interrupteur, sans dépendance. Il est leur seul écrivain.
@MainActor
final class OverlayPaletteSettings {

  private var cancellable: AnyCancellable?

  init(storage: SettingsStorage) {
    // Première application avant tout affichage : les vues résolvent la palette dès leur
    // construction, donc les statiques doivent déjà porter les valeurs de l'utilisateur.
    apply(storage.settings.general)

    cancellable = storage.$settings
      .map { ($0.general.accentColor, $0.general.panelOpacity, $0.general.enableAnimations) }
      .removeDuplicates { $0 == $1 }
      .dropFirst()
      .sink { [weak self] _ in self?.apply(storage.settings.general) }
  }

  private func apply(_ general: GeneralSettings) {
    OverlayPalette.accent = general.accentColor
    OverlayPalette.panelOpacity = general.panelOpacity
    OverlayAnimation.isEnabled = general.enableAnimations
    NotificationCenter.default.post(name: OverlayPalette.didChangeNotification, object: nil)
  }
}

extension NSView {
  /// Repeint la vue et tout son sous-arbre depuis la palette courante.
  ///
  /// Emprunte `viewDidChangeEffectiveAppearance()`, que chaque vue de l'overlay surcharge
  /// déjà pour rappeler son `applyPalette()` : un changement d'accent ou de translucidité
  /// demande exactement le même travail qu'un passage clair/sombre, et passer par ce chemin
  /// évite d'abonner chaque vue imbriquée une à une.
  func refreshOverlayPalette() {
    viewDidChangeEffectiveAppearance()
    subviews.forEach { $0.refreshOverlayPalette() }
  }
}
