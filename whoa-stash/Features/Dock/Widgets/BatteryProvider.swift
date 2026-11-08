import Foundation
import IOKit.ps
import os

/// Source du niveau de batterie du Mac. `nil` = pas de batterie interne (Mac de bureau).
@MainActor
protocol BatteryProviding: AnyObject {
  var onChange: ((Int?) -> Void)? { get set }
  /// `true` quand le Mac est sur secteur.
  var onPluggedChange: ((Bool) -> Void)? { get set }
  /// Envoie tout de suite le niveau courant, puis à chaque changement.
  func start()
  func stop()
}

/// Lit la batterie interne par IOKit et se réveille quand le système signale un changement de
/// source d'alimentation : aucun sondage.
@MainActor
final class IOKitBatteryProvider: BatteryProviding {

  var onChange: ((Int?) -> Void)?
  var onPluggedChange: ((Bool) -> Void)?
  private var source: CFRunLoopSource?
  private var context: Unmanaged<Box>?

  /// Relie le callback C au fournisseur sans le retenir.
  private final class Box {
    weak var provider: IOKitBatteryProvider?
  }

  func start() {
    if source == nil {
      let box = Box()
      box.provider = self
      let retained = Unmanaged.passRetained(box)
      if let created = IOPSNotificationCreateRunLoopSource(Self.callback, retained.toOpaque())?
        .takeRetainedValue()
      {
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .defaultMode)
        source = created
        context = retained
      } else {
        retained.release()
        Log.dock.error("Notifications d'alimentation indisponibles")
      }
    }
    notify()
  }

  private func notify() {
    onChange?(Self.readPercent())
    onPluggedChange?(Self.isPluggedIn())
  }

  func stop() {
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
    source = nil
    context?.release()
    context = nil
  }

  /// Appelé par le système sur le thread principal.
  nonisolated private static let callback: IOPowerSourceCallbackType = { context in
    guard let context else { return }
    let box = Unmanaged<Box>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { box.provider?.notify() }
  }

  /// `true` si la source d'alimentation courante est le secteur.
  static func isPluggedIn() -> Bool {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
    return IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
      == kIOPSACPowerValue
  }

  /// Niveau de la batterie interne en pourcentage, ou `nil` s'il n'y en a pas.
  static func readPercent() -> Int? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
          as? [String: Any],
        description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
        let current = description[kIOPSCurrentCapacityKey] as? Int,
        let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
      else { continue }
      return min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
    }
    return nil
  }
}

/// Niveau fixe, pour `--battery=<0-100>`.
@MainActor
final class MockBatteryProvider: BatteryProviding {

  var onChange: ((Int?) -> Void)?
  var onPluggedChange: ((Bool) -> Void)?
  var percent: Int?

  init(percent: Int?) { self.percent = percent }

  func start() {
    onChange?(percent)
    onPluggedChange?(CommandLine.arguments.contains("--battery-plugged"))
  }
  func stop() {}

  static func fromLaunchArguments() -> MockBatteryProvider? {
    guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--battery=") }),
      let value = Int(argument.dropFirst("--battery=".count))
    else { return nil }
    return MockBatteryProvider(percent: min(100, max(0, value)))
  }
}
