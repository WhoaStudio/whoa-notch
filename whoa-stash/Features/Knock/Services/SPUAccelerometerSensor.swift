import Foundation
import IOKit
import IOKit.hid
import OSLog

/// Accéléromètre du châssis (Apple silicon) lu via `AppleSPUHIDDevice`, page d'usage
/// constructeur 0xFF00, usage 3. Capteur non documenté : absent ou modifié, l'app dégrade sans
/// planter. Rapports de 22 octets, x/y/z en int32 petit-boutiste aux décalages 6/10/14, en 1/65536 g.
///
/// Le capteur ne parle qu'une fois réveillé : `ReportingState`, `PowerState` et `ReportInterval`
/// se posent sur le *pilote* (`AppleSPUHIDDriver`), pas sur le device, et sans droits root.
/// Lu à ~800 Hz sur une file dédiée ; les échantillons repartent par lots d'une vingtaine de ms.
nonisolated final class SPUAccelerometerSensor: KnockSensorProviding, @unchecked Sendable {

  private static let reportLength = 22
  private static let payloadOffset = 6
  private static let scale = 65536.0
  private static let bufferSize = 4096
  private static let batchSize = 16

  private static let reportCallback: IOHIDReportWithTimeStampCallback = {
    context, _, _, _, _, report, length, _ in
    guard let context else { return }
    Unmanaged<SPUAccelerometerSensor>.fromOpaque(context).takeUnretainedValue().handle(
      report, length: length)
  }

  private let queue = DispatchQueue(label: "ugolin-olle.whoa-stash.knock", qos: .userInteractive)
  private let lock = NSLock()
  private var handler: (@MainActor @Sendable ([AccelSample]) -> Void)?
  private var pendingBatch: [AccelSample] = []
  private var devices: [(device: IOHIDDevice, buffer: UnsafeMutablePointer<UInt8>)] = []

  func start(onSamples: @escaping @MainActor @Sendable ([AccelSample]) -> Void) {
    guard devices.isEmpty else { return }
    wakeDrivers()
    let services = accelerometerServices()
    guard !services.isEmpty else {
      Log.knock.error("Accéléromètre introuvable : détection de coups désactivée")
      return
    }
    lock.withLock { handler = onSamples }

    let context = Unmanaged.passUnretained(self).toOpaque()
    for service in services {
      defer { IOObjectRelease(service) }
      guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service),
        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
      else { continue }
      let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.bufferSize)
      IOHIDDeviceSetDispatchQueue(device, queue)
      IOHIDDeviceRegisterInputReportWithTimeStampCallback(
        device, buffer, Self.bufferSize, Self.reportCallback, context)
      IOHIDDeviceActivate(device)
      devices.append((device, buffer))
    }
    Log.knock.info("Accéléromètre actif : \(self.devices.count, privacy: .public) device(s)")
  }

  func stop() {
    for entry in devices {
      IOHIDDeviceCancel(entry.device)
      IOHIDDeviceClose(entry.device, IOOptionBits(kIOHIDOptionsTypeNone))
      // Le tampon reste alloué : un rapport en vol peut encore l'écrire après l'annulation.
    }
    devices.removeAll()
    lock.withLock {
      handler = nil
      pendingBatch.removeAll()
    }
  }

  // MARK: - File du capteur

  private func handle(_ report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
    guard length == Self.reportLength else { return }
    let sample = AccelSample(
      x: Double(Self.int32(report, Self.payloadOffset)) / Self.scale,
      y: Double(Self.int32(report, Self.payloadOffset + 4)) / Self.scale,
      z: Double(Self.int32(report, Self.payloadOffset + 8)) / Self.scale,
      time: ProcessInfo.processInfo.systemUptime)

    let delivery: (batch: [AccelSample], handler: @MainActor @Sendable ([AccelSample]) -> Void)? =
      lock.withLock {
        pendingBatch.append(sample)
        guard pendingBatch.count >= Self.batchSize, let handler else { return nil }
        defer { pendingBatch.removeAll(keepingCapacity: true) }
        return (pendingBatch, handler)
      }
    if let delivery {
      DispatchQueue.main.async { MainActor.assumeIsolated { delivery.handler(delivery.batch) } }
    }
  }

  private static func int32(_ report: UnsafeMutablePointer<UInt8>, _ offset: Int) -> Int32 {
    Int32(
      bitPattern: UInt32(report[offset]) | UInt32(report[offset + 1]) << 8
        | UInt32(report[offset + 2]) << 16 | UInt32(report[offset + 3]) << 24)
  }

  // MARK: - Registre IOKit

  private func wakeDrivers() {
    var iterator: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iterator) == KERN_SUCCESS
    else { return }
    defer { IOObjectRelease(iterator) }
    while case let driver = IOIteratorNext(iterator), driver != 0 {
      IORegistryEntrySetCFProperty(
        driver, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
      IORegistryEntrySetCFProperty(driver, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
      IORegistryEntrySetCFProperty(driver, "ReportInterval" as CFString, 1000 as CFNumber)
      IOObjectRelease(driver)
    }
  }

  private func accelerometerServices() -> [io_service_t] {
    var iterator: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDevice"), &iterator) == KERN_SUCCESS
    else { return [] }
    defer { IOObjectRelease(iterator) }
    var matches: [io_service_t] = []
    while case let service = IOIteratorNext(iterator), service != 0 {
      if property(service, "PrimaryUsagePage") == 0xFF00, property(service, "PrimaryUsage") == 3 {
        matches.append(service)
      } else {
        IOObjectRelease(service)
      }
    }
    return matches
  }

  private func property(_ service: io_service_t, _ key: String) -> Int? {
    (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue() as? NSNumber)?.intValue
  }
}
