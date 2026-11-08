import Foundation

/// Traduit le geste de drag de `EdgeSliderView` en réglage de volume, en appliquant la
/// sensibilité configurée par l'utilisateur. Miroir de `BrightnessViewModel` : la vue ne
/// connaît ni `VolumeControlling` ni `SettingsStorage`, seulement ce ViewModel.
@MainActor
final class EdgeSliderViewModel {

  private let volumeService: VolumeControlling
  private let settings: SettingsStorage

  init(
    volumeService: VolumeControlling = SystemVolumeService.shared,
    settings: SettingsStorage = .shared
  ) {
    self.volumeService = volumeService
    self.settings = settings
  }

  /// `rawRatio` est la position verticale brute du drag (0...1 avant application de la
  /// sensibilité) — `event.locationInWindow.y / bounds.height` côté vue.
  func adjustVolume(rawRatio: CGFloat) {
    let ratio = max(0, min(1, rawRatio * CGFloat(settings.settings.edgeSlider.sensitivity)))
    volumeService.setVolume(Float(ratio))
  }
}
