import AudioToolbox
import CoreAudio
import Foundation

/// Abstraction du contrôle de volume — permet d'échanger facilement une implémentation
/// factice (développement) contre une implémentation système, au même titre que
/// `BrightnessControlling`.
protocol VolumeControlling: AnyObject {
  func setVolume(_ value: Float)
  func getVolume() -> Float
}

/// Contrôle le volume du device de sortie audio par défaut via CoreAudio.
/// Entièrement basé sur des APIs publiques — fonctionne en sandbox et sur l'App Store.
final class SystemVolumeService: VolumeControlling {

  static let shared = SystemVolumeService()
  private init() {}

  /// Retourne l'AudioDeviceID du device de sortie par défaut.
  private func defaultOutputDevice() -> AudioDeviceID? {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)

    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0, nil,
      &size,
      &deviceID
    )

    return status == noErr ? deviceID : nil
  }

  /// Définit le volume (0.0 à 1.0) sur le device de sortie par défaut.
  func setVolume(_ value: Float) {
    guard let deviceID = defaultOutputDevice() else { return }

    var volume = value
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )

    let size = UInt32(MemoryLayout<Float>.size)
    AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &volume)
  }

  /// Lit le volume actuel (0.0 à 1.0).
  func getVolume() -> Float {
    guard let deviceID = defaultOutputDevice() else { return 0 }

    var volume: Float = 0
    var size = UInt32(MemoryLayout<Float>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )

    AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
    return volume
  }
}
