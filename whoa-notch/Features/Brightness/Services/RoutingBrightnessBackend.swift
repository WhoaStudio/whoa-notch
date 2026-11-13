import CoreGraphics
import Foundation

/// Choisit, écran par écran, par où passer pour régler la luminosité.
///
/// - **écran interne** : DisplayServices, la seule route fiable pour la dalle d'un Mac.
/// - **écran externe avec une ligne I2C** : DDC/CI, le protocole que comprennent les moniteurs
///   du commerce.
/// - **écran externe sans ligne I2C** : DisplayServices à nouveau, en dernier recours. C'est ce
///   qui fait fonctionner les écrans Apple (Studio Display, Pro Display XDR), que macOS pilote
///   lui-même et qui n'exposent pas de DDC.
///
/// Le choix est refait à chaque accès : l'écran visé change dès que le widget change d'écran.
final class RoutingBrightnessBackend: DisplayBrightnessBackend {

  private let builtIn: DisplayBrightnessBackend
  private let ddc: DDCBrightnessBackend

  init(
    builtIn: DisplayBrightnessBackend = DisplayServicesBackend(),
    ddc: DDCBrightnessBackend = DDCBrightnessBackend()
  ) {
    self.builtIn = builtIn
    self.ddc = ddc
  }

  private func backend(for displayID: CGDirectDisplayID) -> DisplayBrightnessBackend {
    guard CGDisplayIsBuiltin(displayID) == 0, ddc.canDrive(displayID) else { return builtIn }
    return ddc
  }

  func brightness(for displayID: CGDirectDisplayID) -> Float? {
    backend(for: displayID).brightness(for: displayID)
  }

  @discardableResult
  func setBrightness(_ value: Float, for displayID: CGDirectDisplayID) -> Bool {
    backend(for: displayID).setBrightness(value, for: displayID)
  }
}
