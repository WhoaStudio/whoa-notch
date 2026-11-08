import Foundation
import os

/// Ce que l'onglet Color affiche : la couleur courante, les dernières prélevées et l'état du
/// prélèvement.
struct ColorPickerState: Equatable {
  var current: PickedColor = .placeholder
  var recent: [PickedColor] = []
  /// Vrai entre « Pick » et la couleur choisie (ou Échap) : le panneau reste replié.
  var isSampling = false
}

enum ColorPickerAction {
  case pick
  case select(PickedColor)
  case clearRecent
}

/// Relie le prélèvement à l'interface et garde les couleurs récentes dans les préférences. Ne
/// tient aucun contrôleur : c'est `AppDelegate` qui branche `onStateChanged`.
@MainActor
final class ColorPickerViewModel {

  static let recentLimit = 5

  var onStateChanged: ((ColorPickerState) -> Void)?

  private(set) var state = ColorPickerState()

  private let sampler: any ColorSampling
  private let storage: SettingsStorage

  init(sampler: any ColorSampling, storage: SettingsStorage = .shared) {
    self.sampler = sampler
    self.storage = storage
    state.recent = storage.settings.colorPicker.recent.compactMap(PickedColor.init(hex:))
    if let latest = state.recent.first { state.current = latest }
  }

  func activate() {
    onStateChanged?(state)
  }

  func handle(_ action: ColorPickerAction) {
    switch action {
    case .pick: startPicking()
    case .select(let color):
      state.current = color
      onStateChanged?(state)
    case .clearRecent:
      state.recent = []
      persistRecent()
      onStateChanged?(state)
    }
  }

  private func startPicking() {
    guard !state.isSampling else { return }
    state.isSampling = true
    onStateChanged?(state)
    sampler.pick { [weak self] color in self?.finishPicking(color) }
  }

  private func finishPicking(_ color: PickedColor?) {
    state.isSampling = false
    if let color {
      Log.colorPicker.info("couleur prélevée")
      state.current = color
      state.recent.removeAll { $0 == color }
      state.recent.insert(color, at: 0)
      state.recent = Array(state.recent.prefix(Self.recentLimit))
      persistRecent()
    } else {
      Log.colorPicker.info("prélèvement annulé")
    }
    onStateChanged?(state)
  }

  private func persistRecent() {
    storage.settings.colorPicker.recent = state.recent.map(\.hexString)
  }
}
