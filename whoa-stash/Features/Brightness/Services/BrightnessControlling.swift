import CoreGraphics
import Foundation

/// Abstraction du contrôle de luminosité — permet d'échanger facilement
/// une implémentation factice (développement) contre une implémentation système.
protocol BrightnessControlling: AnyObject {
  var brightness: Float { get set }

  /// Écran que les lectures/écritures visent. Posé par l'overlay, seul à savoir sur quel
  /// écran il est affiché ; `nil` (ou non posé) retombe sur l'écran par défaut de
  /// l'implémentation.
  var targetDisplay: (() -> CGDirectDisplayID?)? { get set }
}

/// Implémentation factice pour le développement et les previews SwiftUI.
/// Ne pilote aucun matériel : garde simplement la valeur en mémoire.
final class FakeBrightnessService: BrightnessControlling {
  var brightness: Float
  /// Gardé pour satisfaire le protocole : rien ici ne pilote d'écran.
  var targetDisplay: (() -> CGDirectDisplayID?)?

  init(initialBrightness: Float = 0.6) {
    self.brightness = initialBrightness
  }
}
