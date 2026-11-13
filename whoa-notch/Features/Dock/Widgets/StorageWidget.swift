import AppKit
import Foundation

/// Espace du volume de démarrage : part utilisée et espace libre en Go.
struct StorageReading: Equatable {
  let usedFraction: Double
  let freeGB: Int
}

/// Source de l'espace disque. `nil` = lecture impossible.
@MainActor
protocol StorageProviding: AnyObject {
  var onChange: ((StorageReading?) -> Void)? { get set }
  func start()
  func stop()
}

/// Lit le volume de démarrage et relit chaque minute (le système n'envoie pas de notification).
@MainActor
final class VolumeStorageProvider: StorageProviding {

  var onChange: ((StorageReading?) -> Void)?
  private var timer: Timer?

  func start() {
    onChange?(Self.read())
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.onChange?(Self.read()) }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  static func read() -> StorageReading? {
    let keys: Set<URLResourceKey> = [
      .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
    ]
    guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
      let total = values.volumeTotalCapacity, total > 0,
      let free = values.volumeAvailableCapacityForImportantUsage
    else { return nil }
    let used = min(1, max(0, 1 - Double(free) / Double(total)))
    return StorageReading(usedFraction: used, freeGB: Int(Double(free) / 1_000_000_000))
  }
}

/// Valeur fixe, pour `--storage=<% utilisé>,<Go libres>`.
@MainActor
final class MockStorageProvider: StorageProviding {

  var onChange: ((StorageReading?) -> Void)?
  var reading: StorageReading?

  init(reading: StorageReading?) { self.reading = reading }

  func start() { onChange?(reading) }
  func stop() {}

  static func fromLaunchArguments() -> MockStorageProvider? {
    guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--storage=") }) else {
      return nil
    }
    let parts = argument.dropFirst("--storage=".count).split(separator: ",").compactMap { Int($0) }
    guard parts.count == 2 else { return nil }
    return MockStorageProvider(
      reading: StorageReading(
        usedFraction: Double(min(100, max(0, parts[0]))) / 100, freeGB: max(0, parts[1])))
  }
}

/// Tuile « stockage » : même anneau que la batterie, orange, rempli de la part utilisée, avec
/// l'espace libre en Go au centre.
@MainActor
final class StorageWidget: DockWidget {

  static let kind = DockWidgetKind(id: "storage", title: "Storage", symbol: "internaldrive") {
    StorageWidget(provider: MockStorageProvider.fromLaunchArguments() ?? VolumeStorageProvider())
  }

  private let provider: StorageProviding
  private let tile = BatteryTileView()
  var view: NSView { tile }

  init(provider: StorageProviding) {
    self.provider = provider
    tile.symbolName = "internaldrive.fill"
    tile.tint = NSColor(hex: "#FF9F0A")
    provider.onChange = { [weak tile] reading in
      tile?.percent = reading.map { Int(($0.usedFraction * 100).rounded()) }
      tile?.labelOverride = reading.map { String($0.freeGB) }
    }
  }

  func start() { provider.start() }
  func stop() { provider.stop() }
}
