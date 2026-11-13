import Foundation
import os

/// Ce que l'onglet Color affiche : la couleur courante (aucune avant le premier prélèvement), les
/// dernières prélevées, celles gardées, l'écriture choisie et l'état du prélèvement.
struct ColorPickerState: Equatable {
  var current: PickedColor?
  var recent: [PickedColor] = []
  var saved: [PickedColor] = []
  var format: ColorFormat = .hex
  /// Vrai entre « Pick » et la couleur choisie (ou Échap) : le panneau reste replié.
  var isSampling = false

  var isCurrentSaved: Bool { current.map(saved.contains) ?? false }
}

enum ColorPickerAction {
  case pick
  case select(PickedColor)
  case clearRecent
  case selectFormat(ColorFormat)
  /// Garde la couleur courante, ou la retire si elle l'est déjà.
  case toggleSaved
  /// Garde cette couleur (déposée sur la rangée « Saved »).
  case save(PickedColor)
  case removeRecent(PickedColor)
  case removeSaved(PickedColor)
  /// La couleur courante, teinte ou luminosité retouchée : elle n'entre pas dans les récentes
  /// tant qu'on ne la copie, ne la garde ou ne l'emporte pas (`commit`).
  case adjust(PickedColor)
  case commit
}

/// Relie le prélèvement à l'interface et garde les couleurs dans les préférences. Ne tient aucun
/// contrôleur : c'est `AppDelegate` qui branche `onStateChanged`.
@MainActor
final class ColorPickerViewModel {

  static let recentLimit = 8
  static let savedLimit = 8

  var onStateChanged: ((ColorPickerState) -> Void)?

  private(set) var state = ColorPickerState()

  private let sampler: any ColorSampling
  private let storage: SettingsStorage
  /// Vrai quand la couleur courante vient d'une retouche, pas encore dans les récentes.
  private var hasUncommittedAdjustment = false

  init(sampler: any ColorSampling, storage: SettingsStorage = .shared) {
    self.sampler = sampler
    self.storage = storage
    let settings = storage.settings.colorPicker
    state.recent = settings.recent.compactMap(PickedColor.init(hex:))
    state.saved = settings.saved.compactMap(PickedColor.init(hex:))
    state.format = settings.format
    state.current = state.recent.first
  }

  func activate() {
    onStateChanged?(state)
  }

  func handle(_ action: ColorPickerAction) {
    switch action {
    case .pick:
      startPicking()
      return
    case .select(let color):
      hasUncommittedAdjustment = false
      state.current = color
    case .clearRecent:
      state.recent = []
      persist()
    case .selectFormat(let format):
      state.format = format
      persist()
    case .toggleSaved:
      guard let current = state.current else { return }
      if state.saved.contains(current) {
        state.saved.removeAll { $0 == current }
      } else {
        insertSaved(current)
      }
      persist()
    case .save(let color):
      guard !state.saved.contains(color) else { return }
      insertSaved(color)
      persist()
    case .removeRecent(let color):
      state.recent.removeAll { $0 == color }
      persist()
    case .removeSaved(let color):
      state.saved.removeAll { $0 == color }
      persist()
    case .adjust(let color):
      hasUncommittedAdjustment = true
      state.current = color
    case .commit:
      guard hasUncommittedAdjustment, let current = state.current else { return }
      hasUncommittedAdjustment = false
      insertRecent(current)
      persist()
    }
    onStateChanged?(state)
  }

  private func insertSaved(_ color: PickedColor) {
    state.saved.insert(color, at: 0)
    state.saved = Array(state.saved.prefix(Self.savedLimit))
  }

  private func insertRecent(_ color: PickedColor) {
    state.recent.removeAll { $0 == color }
    state.recent.insert(color, at: 0)
    state.recent = Array(state.recent.prefix(Self.recentLimit))
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
      hasUncommittedAdjustment = false
      state.current = color
      insertRecent(color)
      persist()
    } else {
      Log.colorPicker.info("prélèvement annulé")
    }
    onStateChanged?(state)
  }

  private func persist() {
    storage.settings.colorPicker = ColorPickerSettings(
      recent: state.recent.map(\.hexString), saved: state.saved.map(\.hexString),
      format: state.format)
  }
}
