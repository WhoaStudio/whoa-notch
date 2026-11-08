import Foundation

/// Famille d'un appareil audio Bluetooth : elle décide du glyphe affiché dans la pastille.
enum DeviceKind: Equatable {
  case airPodsPro
  case airPodsMax
  case airPods
  case beatsHeadphones
  case headphones
  case speaker

  /// Symbole SF du glyphe.
  var symbolName: String {
    switch self {
    case .airPodsPro: "airpodspro"
    case .airPodsMax: "airpodsmax"
    case .airPods: "airpods"
    case .beatsHeadphones: "beats.headphones"
    case .headphones: "headphones"
    case .speaker: "hifispeaker"
    }
  }

  /// Déduit la famille du nom de l'appareil, puis de la catégorie que `system_profiler` lui
  /// donne (`device_minorType`). Ce qui n'est reconnu nulle part retombe sur un casque.
  static func classify(name: String, minorType: String? = nil) -> DeviceKind {
    let name = name.lowercased()
    if name.contains("airpods") {
      if name.contains("max") { return .airPodsMax }
      if name.contains("pro") { return .airPodsPro }
      return .airPods
    }
    if name.contains("beats") { return .beatsHeadphones }

    let minorType = minorType?.lowercased() ?? ""
    if minorType.contains("speaker") || name.contains("speaker") { return .speaker }
    return .headphones
  }
}

/// Niveaux de batterie relevés pour un appareil. Chaque champ est optionnel : un appareil n'en
/// expose qu'une partie, et aucune valeur n'est jamais inventée.
nonisolated struct DeviceBattery: Equatable {
  var main: Int?
  var left: Int?
  var right: Int?
  var caseLevel: Int?

  /// Forme de l'indicateur. Des écouteurs aux niveaux séparés prennent la bague, sans chiffre,
  /// sur le plus faible des deux ; un niveau unique prend la barre et son pourcentage.
  nonisolated enum Indicator: Equatable {
    case ring(percent: Int)
    case bar(percent: Int)
  }

  var indicator: Indicator? {
    let buds = [left, right].compactMap { $0 }
    if let lowest = buds.min() { return .ring(percent: lowest) }
    if let main { return .bar(percent: main) }
    return nil
  }
}

/// Ce que la pastille affiche : l'appareil, et sa batterie quand elle est connue.
struct DeviceStatus: Equatable {
  var name: String
  var kind: DeviceKind
  var battery: DeviceBattery?

  /// `--simulate-bluetooth-device=airpodsmax,82` (ou `airpodspro,82`, `airpodsmax` sans niveau)
  /// substitue un appareil fixe à la vraie détection, pour vérifier la pastille sans matériel.
  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments) -> DeviceStatus? {
    guard let argument = arguments.first(where: { $0.hasPrefix("--simulate-bluetooth-device=") })
    else {
      return nil
    }
    let parts = argument.dropFirst("--simulate-bluetooth-device=".count).split(separator: ",")
    guard let model = parts.first else { return nil }
    let level = parts.dropFirst().first.flatMap { Int($0) }.map { min(100, max(0, $0)) }

    switch model.lowercased() {
    case "airpodspro":
      return DeviceStatus(
        name: "AirPods Pro", kind: .airPodsPro,
        battery: level.map { DeviceBattery(left: $0, right: $0) })
    case "airpodsmax":
      return DeviceStatus(
        name: "AirPods Max", kind: .airPodsMax,
        battery: level.map { DeviceBattery(main: $0) })
    default:
      return nil
    }
  }
}
