import AppKit
import Foundation
import Testing

@testable import whoa_notch

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
    let name = "whoa-notch.tests.\(UUID().uuidString)"
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

  @Test("les récentes sont sans doublon, la plus récente d'abord, et bornées à huit")
  func recentIsDeduplicatedAndBounded() {
    let colors = (1...10).map { PickedColor(red: UInt8($0), green: 0, blue: 0) }
    let sampler = ScriptedSampler(colors + [colors[5]])
    let model = ColorPickerViewModel(sampler: sampler, storage: Self.makeStorage())
    for _ in 0..<11 { model.handle(.pick) }
    #expect(
      model.state.recent
        == [colors[5], colors[9], colors[8], colors[7], colors[6], colors[4], colors[3], colors[2]])
  }

  @Test("aucune couleur courante avant le premier prélèvement")
  func noCurrentBeforeFirstPick() {
    let model = ColorPickerViewModel(sampler: ScriptedSampler([]), storage: Self.makeStorage())
    #expect(model.state.current == nil)
  }

  @Test("garder une couleur, la retirer, et l'écriture choisie survivent au relancement")
  func savedAndFormatPersist() {
    let storage = Self.makeStorage()
    let red = Self.color("#FF0000")
    let model = ColorPickerViewModel(sampler: ScriptedSampler([red]), storage: storage)
    model.handle(.pick)
    model.handle(.toggleSaved)
    model.handle(.selectFormat(.hsl))
    #expect(model.state.isCurrentSaved)
    let relaunched = ColorPickerViewModel(sampler: ScriptedSampler([]), storage: storage)
    #expect(relaunched.state.saved == [red])
    #expect(relaunched.state.format == .hsl)
    relaunched.handle(.toggleSaved)
    #expect(relaunched.state.saved.isEmpty)
  }

  @Test("déposer une couleur la garde une seule fois, et la retirer la sort de la liste")
  func dropAndRemoveSaved() {
    let model = ColorPickerViewModel(sampler: ScriptedSampler([]), storage: Self.makeStorage())
    let blue = Self.color("#0000FF")
    model.handle(.save(blue))
    model.handle(.save(blue))
    #expect(model.state.saved == [blue])
    model.handle(.removeSaved(blue))
    #expect(model.state.saved.isEmpty)
  }

  @Test("retirer une récente ne touche pas aux autres")
  func removeRecent() {
    let red = Self.color("#FF0000")
    let green = Self.color("#00FF00")
    let model = ColorPickerViewModel(
      sampler: ScriptedSampler([red, green]), storage: Self.makeStorage())
    model.handle(.pick)
    model.handle(.pick)
    model.handle(.removeRecent(green))
    #expect(model.state.recent == [red])
  }

  @Test("une retouche n'entre dans les récentes qu'à la copie ou au glisser")
  func adjustJoinsRecentOnCommit() {
    let red = Self.color("#FF0000")
    let model = ColorPickerViewModel(sampler: ScriptedSampler([red]), storage: Self.makeStorage())
    model.handle(.pick)
    let darker = Self.color("#800000")
    model.handle(.adjust(darker))
    #expect(model.state.current == darker)
    #expect(model.state.recent == [red])
    model.handle(.commit)
    #expect(model.state.recent == [darker, red])
    model.handle(.commit)
    #expect(model.state.recent == [darker, red])
  }

  @Test("les écritures par format et le code Swift")
  func formatStringsAndCode() {
    let color = Self.color("#0A6FE8")
    #expect(color.string(for: .hex) == "#0A6FE8")
    #expect(color.string(for: .rgb) == "rgb(10, 111, 232)")
    #expect(color.string(for: .hsl) == "hsl(213, 92%, 47%)")
    #expect(color.swiftUICode == "Color(red: 0.039, green: 0.435, blue: 0.910)")
    #expect(
      color.nsColorCode == "NSColor(srgbRed: 0.039, green: 0.435, blue: 0.910, alpha: 1)")
  }

  @Test("le contraste WCAG du blanc et du noir, et de la teinte retouchée")
  func contrastAndHSB() {
    #expect(Self.color("#000000").contrast.ratio > 20.9)
    #expect(Self.color("#000000").contrast.onWhite)
    #expect(Self.color("#FFFFFF").contrast.grade == "AAA")
    #expect(!Self.color("#FFFFFF").contrast.onWhite)
    let hsb = Self.color("#FF0000").hsb
    #expect(hsb.hue == 0 && hsb.saturation == 1 && hsb.brightness == 1)
    #expect(PickedColor(hue: 120, saturation: 1, brightness: 1) == Self.color("#00FF00"))
    #expect(PickedColor(hue: -120, saturation: 1, brightness: 1) == Self.color("#0000FF"))
    #expect(PickedColor(hue: 0, saturation: 1, brightness: 0) == Self.color("#000000"))
  }

  /// Les cadres de l'onglet à 440 pt (largeur de l'onglet) et à 360 pt : rien ne sort ni ne
  /// se chevauche, et la plus longue valeur tient dans le champ.
  @Test("la mise en page tient à 440 et à 360 pt, sans chevauchement ni coupure")
  func layoutFitsAtMinimumWidth() {
    let colors = (1...8).map { PickedColor(red: UInt8($0 * 30), green: 255, blue: 255) }
    var state = ColorPickerState()
    state.current = colors[0]
    state.recent = colors
    state.saved = colors
    state.format = .hsl
    for width: CGFloat in [440, 360] {
      let view = ColorPickerTabView(frame: NSRect(x: 0, y: 0, width: width, height: 150))
      view.apply(state)
      view.layoutSubtreeIfNeeded()
      let parts = view.subviews.filter { !$0.isHidden }
      for part in parts {
        #expect(view.bounds.contains(part.frame), "\(type(of: part)) sort à \(width) pt")
      }
      for (index, a) in parts.enumerated() {
        for b in parts[(index + 1)...] {
          #expect(!a.frame.intersects(b.frame), "\(type(of: a)) chevauche \(type(of: b)) à \(width) pt")
        }
      }
      let longest = "hsl(360, 100%, 100%)" as NSString
      let textWidth = longest.size(
        withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)]).width
      let pill = parts.first { $0 is ColorValuePill }
      #expect((pill?.frame.width ?? 0) >= textWidth + 46)
      for row in parts.compactMap({ $0 as? ColorDropStrip }) {
        for chip in row.subviews.compactMap({ $0 as? ColorChipView }) where !chip.isHidden {
          #expect(row.bounds.contains(chip.frame))
          #expect(chip.frame.maxX <= row.bounds.width - 38 || row.subviews.allSatisfy { !($0 is ColorPickerClickView) || $0.isHidden || !$0.frame.intersects(chip.frame) })
        }
      }
    }
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
