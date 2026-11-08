import Foundation

/// Lit la batterie d'un appareil Bluetooth connecté via `system_profiler`. CoreAudio dit qu'un
/// appareil est là mais pas son niveau, et les appels privés d'`IOBluetooth` n'ont pas leur place
/// dans l'app : on passe donc par l'outil système, qui ne demande aucune permission.
enum SystemProfilerBatteryReader {

  /// Niveau de l'appareil nommé, ou `nil` s'il est introuvable, sans batterie, ou si la lecture
  /// dépasse `timeout`. La pastille s'affiche alors sans indicateur.
  static func read(deviceName: String, timeout: Duration = .seconds(2)) async -> DeviceBattery? {
    await withTaskGroup(of: DeviceBattery?.self) { group in
      group.addTask {
        guard let data = await profile() else { return nil }
        return parse(data, deviceName: deviceName)
      }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }

  /// Extrait le niveau de l'appareil du JSON de `system_profiler SPBluetoothDataType -json`.
  nonisolated static func parse(_ data: Data, deviceName: String) -> DeviceBattery? {
    guard
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let sections = root["SPBluetoothDataType"] as? [[String: Any]]
    else { return nil }

    for section in sections {
      let connected = section["device_connected"] as? [[String: Any]] ?? []
      for entry in connected {
        guard
          let properties = entry[deviceName] as? [String: Any]
        else { continue }

        let battery = DeviceBattery(
          main: percent(properties["device_batteryLevelMain"]),
          left: percent(properties["device_batteryLevelLeft"]),
          right: percent(properties["device_batteryLevelRight"]),
          caseLevel: percent(properties["device_batteryLevelCase"])
        )
        return battery.indicator == nil ? nil : battery
      }
    }
    return nil
  }

  /// « 85% » → 85.
  private nonisolated static func percent(_ value: Any?) -> Int? {
    guard let text = value as? String else { return nil }
    return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
  }

  /// Lance l'outil hors du fil principal : il met de l'ordre de la seconde à répondre.
  private nonisolated static func profile() async -> Data? {
    await Task.detached {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
      process.arguments = ["SPBluetoothDataType", "-json"]
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
      } catch {
        return nil
      }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      return process.terminationStatus == 0 ? data : nil
    }.value
  }
}
