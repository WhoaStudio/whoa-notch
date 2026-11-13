import Foundation

/// Relie la détection d'une connexion Bluetooth à la lecture de sa batterie, puis remet un
/// `DeviceStatus` prêt à afficher.
final class DeviceStatusCoordinator {

  var onStatus: ((DeviceStatus) -> Void)?

  private let monitor = BluetoothAudioMonitor()

  func activate() {
    // `--simulate-bluetooth-device=airpodsmax,82` : voir `DeviceStatus.fromLaunchArguments`.
    if let simulated = DeviceStatus.fromLaunchArguments() {
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(1))
        self?.onStatus?(simulated)
      }
      return
    }

    monitor.onConnect = { [weak self] name in
      Task { @MainActor [weak self] in
        // Le niveau peut se faire attendre ou manquer : passé le délai, la pastille
        // s'affiche sans indicateur plutôt qu'avec une valeur inventée.
        let battery = await SystemProfilerBatteryReader.read(deviceName: name)
        let status = DeviceStatus(
          name: name, kind: DeviceKind.classify(name: name), battery: battery)
        self?.onStatus?(status)
      }
    }
    monitor.start()
  }
}
