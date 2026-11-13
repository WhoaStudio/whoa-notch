import CoreGraphics
import Foundation
import OSLog

/// Bas niveau : lit/écrit la luminosité d'un écran précis. `SystemBrightnessService`
/// choisit le bon backend selon l'écran ciblé — aujourd'hui uniquement l'écran interne
/// via `DisplayServicesBackend`. Un futur `DDCBackend` (I2C/DDC via IOKit) pourrait
/// implémenter ce même protocole pour les écrans externes, sans toucher au reste de
/// l'architecture (`BrightnessControlling`, `BrightnessViewModel`).
protocol DisplayBrightnessBackend {
  func brightness(for displayID: CGDirectDisplayID) -> Float?
  @discardableResult func setBrightness(_ value: Float, for displayID: CGDirectDisplayID) -> Bool
}

/// Pilote la luminosité via l'API privée DisplayServices
/// (`/System/Library/PrivateFrameworks/DisplayServices.framework`).
///
/// Il n'existe pas d'API publique pour régler la luminosité native d'un Mac
/// (en particulier sur Apple Silicon, où l'ancienne route IODisplay ne fonctionne plus).
/// DisplayServices est l'API utilisée en interne par le Centre de contrôle et par des
/// outils open-source connus (ex. `nriley/brightness`). C'est la route la plus fiable
/// pour l'écran interne d'un Mac ; elle ne fonctionne en revanche pas de façon fiable
/// pour la plupart des écrans externes tiers, qui nécessitent du DDC/CI (I2C) — hors
/// scope ici, voir `DisplayBrightnessBackend`.
final class DisplayServicesBackend: DisplayBrightnessBackend {

  private typealias GetBrightnessFn =
    @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
  private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

  private let getBrightnessFn: GetBrightnessFn?
  private let setBrightnessFn: SetBrightnessFn?

  init() {
    guard
      let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_NOW
      )
    else {
      Log.brightness.error(
        "impossible de charger DisplayServices.framework — la luminosité ne sera pas pilotable")
      getBrightnessFn = nil
      setBrightnessFn = nil
      return
    }

    if let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
      getBrightnessFn = unsafeBitCast(symbol, to: GetBrightnessFn.self)
    } else {
      getBrightnessFn = nil
    }

    if let symbol = dlsym(handle, "DisplayServicesSetBrightness") {
      setBrightnessFn = unsafeBitCast(symbol, to: SetBrightnessFn.self)
    } else {
      setBrightnessFn = nil
    }
  }

  func brightness(for displayID: CGDirectDisplayID) -> Float? {
    guard let getBrightnessFn else { return nil }
    var value: Float = 0
    guard getBrightnessFn(displayID, &value) == 0 else { return nil }
    return value
  }

  @discardableResult
  func setBrightness(_ value: Float, for displayID: CGDirectDisplayID) -> Bool {
    guard let setBrightnessFn else { return false }
    return setBrightnessFn(displayID, max(0, min(1, value))) == 0
  }
}

/// Implémentation concrète de `BrightnessControlling` exposée à l'app, via
/// `DisplayServicesBackend`. Cible l'écran désigné par `targetDisplay` — l'overlay y branche
/// l'écran qui le porte — et retombe sur `fallbackDisplayID` (l'écran principal) quand
/// personne ne l'a posé ou que l'écran n'a pas pu être identifié.
///
/// L'écran est résolu à *chaque* accès et jamais mémorisé : entre deux apparitions du widget
/// le curseur a pu changer d'écran, et un écran a pu être branché ou débranché.
///
/// Le backend par défaut est `RoutingBrightnessBackend`, qui choisit la route selon l'écran :
/// DisplayServices pour la dalle interne, DDC/CI pour les moniteurs externes.
final class SystemBrightnessService: BrightnessControlling {

  private let backend: DisplayBrightnessBackend
  private let fallbackDisplayID: () -> CGDirectDisplayID

  var targetDisplay: (() -> CGDirectDisplayID?)?

  init(
    backend: DisplayBrightnessBackend = RoutingBrightnessBackend(),
    fallbackDisplayID: @escaping () -> CGDirectDisplayID = CGMainDisplayID
  ) {
    self.backend = backend
    self.fallbackDisplayID = fallbackDisplayID
  }

  private var resolvedDisplayID: CGDirectDisplayID {
    targetDisplay?() ?? fallbackDisplayID()
  }

  var brightness: Float {
    get { backend.brightness(for: resolvedDisplayID) ?? 0.5 }
    set { backend.setBrightness(newValue, for: resolvedDisplayID) }
  }
}
