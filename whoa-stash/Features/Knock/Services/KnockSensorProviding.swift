import Foundation

/// Source des échantillons de l'accéléromètre. Derrière un protocole pour vérifier l'UI sans
/// capteur (`MockKnockSensor`).
nonisolated protocol KnockSensorProviding: AnyObject {
  /// `onSamples` est appelé sur le main thread, par lots, dans l'ordre.
  func start(onSamples: @escaping @MainActor @Sendable ([AccelSample]) -> Void)
  func stop()
}

/// Simule un coup au lancement : `--knock=single|double`.
nonisolated final class MockKnockSensor: KnockSensorProviding, @unchecked Sendable {

  private let knocksAt: [TimeInterval]

  init(double: Bool) {
    knocksAt = double ? [2.0, 2.25] : [2.0]
  }

  static func fromLaunchArguments() -> MockKnockSensor? {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--knock=") }) else {
      return nil
    }
    switch arg.dropFirst("--knock=".count) {
    case "single": return MockKnockSensor(double: false)
    case "double": return MockKnockSensor(double: true)
    default: return nil
    }
  }

  func start(onSamples: @escaping @MainActor @Sendable ([AccelSample]) -> Void) {
    let origin = ProcessInfo.processInfo.systemUptime
    let signal = KnockSignal.samples(knocksAt: knocksAt, duration: 4, start: origin)
    // Un lot toutes les 20 ms, comme le vrai capteur.
    for batch in stride(from: 0, to: signal.count, by: 16) {
      let chunk = Array(signal[batch..<min(batch + 16, signal.count)])
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(batch) / 800) {
        MainActor.assumeIsolated { onSamples(chunk) }
      }
    }
  }

  func stop() {}
}
