import Foundation
import Testing

@testable import whoa_stash

/// Couleur prélevée : écritures HEX, RGB et HSL, couleurs récentes et leur persistance.
@MainActor
struct ColorPickerTests {

  /// Source qui rend les couleurs données, tout de suite ; `nil` pour une annulation.
  private final class ScriptedSampler: ColorSampling {
    var results: [PickedColor?]
    var completion: ((PickedColor?) -> Void)?
    var hold = false
    init(_ results: [PickedColor?]) { self.results = results }
    func pick(_ completion: @escaping (PickedColor?) -> Void) {
      if hold { self.completion = completion } else { completion(results.removeFirst()) }
    }
  }

  private static func makeStorage() -> SettingsStorage {
    let name = "whoa-stash.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return SettingsStorage(defaults: defaults)
  }

  private static func color(_ hex: String) -> PickedColor { PickedColor(hex: hex)! }

  @Test("les trois écritures de la maquette")
  func formatsMatchMockup() {
    let color = Self.color("#0A6FE8")
    #expect(color.hexString == "#0A6FE8")
    #expect(color.rgbString == "rgb(10, 111, 232)")
    #expect(color.hslString == "hsl(213, 92%, 47%)")
  }

  @Test("le gris et les extrêmes n'ont pas de teinte")
  func hslOfGraysAndExtremes() {
    #expect(Self.color("#000000").hslString == "hsl(0, 0%, 0%)")
    #expect(Self.color("#FFFFFF").hslString == "hsl(0, 0%, 100%)")
    #expect(Self.color("#808080").hslString == "hsl(0, 0%, 50%)")
    #expect(Self.color("#FF0000").hslString == "hsl(0, 100%, 50%)")
  }

  @Test("un hexadécimal invalide est refusé")
  func invalidHexIsRejected() {
    #expect(PickedColor(hex: "#12345") == nil)
    #expect(PickedColor(hex: "zzzzzz") == nil)
    #expect(PickedColor(hex: "0A6FE8") == Self.color("#0A6FE8"))
  }

  @Test("une couleur prélevée devient la courante et la première des récentes")
  func pickedColorIsCurrentAndRecent() {
    let red = Self.color("#FF0000")
    let model = ColorPickerViewModel(sampler: ScriptedSampler([red]), storage: Self.makeStorage())
    model.handle(.pick)
    #expect(model.state.current == red)
    #expect(model.state.recent == [red])
    #expect(!model.state.isSampling)
  }

  @Test("Échap garde la couleur et les récentes, et sort du prélèvement")
  func cancelKeepsState() {
    let red = Self.color("#FF0000")
    let model = ColorPickerViewModel(
      sampler: ScriptedSampler([red, nil]), storage: Self.makeStorage())
    model.handle(.pick)
    model.handle(.pick)
    #expect(model.state.current == red)
    #expect(model.state.recent == [red])
    #expect(!model.state.isSampling)
  }

  @Test("le prélèvement est signalé tant qu'il dure")
  func samplingFlagWhileWaiting() {
    let sampler = ScriptedSampler([])
    sampler.hold = true
    let model = ColorPickerViewModel(sampler: sampler, storage: Self.makeStorage())
    model.handle(.pick)
    #expect(model.state.isSampling)
    sampler.completion?(nil)
    #expect(!model.state.isSampling)
  }

  @Test("les récentes sont sans doublon, la plus récente d'abord, et bornées à cinq")
  func recentIsDeduplicatedAndBounded() {
    let colors = (1...6).map { PickedColor(red: UInt8($0), green: 0, blue: 0) }
    let sampler = ScriptedSampler(colors + [colors[3]])
    let model = ColorPickerViewModel(sampler: sampler, storage: Self.makeStorage())
    for _ in 0..<7 { model.handle(.pick) }
    #expect(model.state.recent == [colors[3], colors[5], colors[4], colors[2], colors[1]])
  }

  @Test("Clear vide les récentes mais garde la couleur courante")
  func clearEmptiesRecent() {
    let red = Self.color("#FF0000")
    let model = ColorPickerViewModel(sampler: ScriptedSampler([red]), storage: Self.makeStorage())
    model.handle(.pick)
    model.handle(.clearRecent)
    #expect(model.state.recent.isEmpty)
    #expect(model.state.current == red)
  }

  @Test("les récentes survivent à une nouvelle instance")
  func recentSurvivesRelaunch() {
    let storage = Self.makeStorage()
    let red = Self.color("#FF0000")
    ColorPickerViewModel(sampler: ScriptedSampler([red]), storage: storage).handle(.pick)
    let relaunched = ColorPickerViewModel(sampler: ScriptedSampler([]), storage: storage)
    #expect(relaunched.state.recent == [red])
    #expect(relaunched.state.current == red)
  }
}
