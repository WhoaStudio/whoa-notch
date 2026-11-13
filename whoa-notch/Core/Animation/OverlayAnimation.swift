import AppKit

/// Interrupteur unique du mouvement de l'overlay, piloté par `General > Enable animations`.
///
/// Il est consulté par les deux primitives que tout l'overlay partage — `PanelFold` et
/// `CALayer.springAnimate` — plutôt que par chaque appelant : chaque `animated: true` dispersé
/// dans les panneaux passe par l'une des deux, donc les couper ici suffit à couper le mouvement
/// partout, sans retoucher un seul site d'appel.
enum OverlayAnimation {

  /// `nonisolated(unsafe)` et non `@MainActor` : les primitives qui le lisent ne sont pas
  /// isolées, et les annoter se propagerait à toutes les vues de l'overlay. L'accès est de
  /// fait confiné à la boucle principale — c'est du code AppKit, écrit par
  /// `OverlayAnimationSettings` et lu au moment de poser une animation.
  nonisolated(unsafe) static var isEnabled = GeneralSettings().enableAnimations

  /// Le réglage système prime sur le réglage de l’overlay.
  nonisolated static var allowsMotion: Bool {
    isEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }
}
