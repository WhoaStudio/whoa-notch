import CoreAudio
import Foundation

/// Signale quand la sortie audio par défaut devient un appareil Bluetooth — AirPods qui se
/// connectent, enceinte qui prend le relais. Même API publique que `SystemVolumeService`, sans
/// permission : un clavier ou une souris Bluetooth, qui n'ont pas de sortie audio, ne déclenchent
/// rien.
final class BluetoothAudioMonitor {

  /// Appelé avec le nom de l'appareil, sur le fil principal.
  var onConnect: ((String) -> Void)?

  private var lastDeviceID: AudioDeviceID?
  private var listener: AudioObjectPropertyListenerBlock?

  private var defaultOutputAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  func start() {
    guard listener == nil else { return }
    // L'appareil déjà branché au lancement n'est pas une connexion : on le retient seulement.
    lastDeviceID = Self.defaultOutputDevice()

    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      MainActor.assumeIsolated { self?.defaultOutputDidChange() }
    }
    listener = block
    AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, .main, block)
  }

  func stop() {
    guard let listener else { return }
    AudioObjectRemovePropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, .main, listener)
    self.listener = nil
  }

  private func defaultOutputDidChange() {
    guard let device = Self.defaultOutputDevice(), device != lastDeviceID else { return }
    lastDeviceID = device
    guard Self.isBluetooth(device), let name = Self.name(of: device) else { return }
    onConnect?(name)
  }

  private static func defaultOutputDevice() -> AudioDeviceID? {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
    return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
  }

  private static func isBluetooth(_ device: AudioDeviceID) -> Bool {
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else {
      return false
    }
    return transport == kAudioDeviceTransportTypeBluetooth
      || transport == kAudioDeviceTransportTypeBluetoothLE
  }

  private static func name(of device: AudioDeviceID) -> String? {
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else {
      return nil
    }
    return name?.takeRetainedValue() as String?
  }
}
