import CoreGraphics
import Foundation
import Testing

@testable import whoa_notch

@Suite("Menu radial")
@MainActor
struct RadialMenuTests {

  private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

  @Test("le disque suit le curseur quand il tient à l'écran")
  func centerFollowsCursor() {
    let center = RadialMenuGeometry.center(forCursor: CGPoint(x: 500, y: 400), in: screen)
    #expect(center == CGPoint(x: 500, y: 400))
  }

  @Test("le disque reste entièrement à l'écran près des bords et des coins")
  func centerIsClampedAtEdges() {
    let radius = RadialMenuGeometry.diameter / 2
    let corner = RadialMenuGeometry.center(forCursor: CGPoint(x: 2, y: 799), in: screen)
    #expect(corner == CGPoint(x: radius, y: 800 - radius))
    let right = RadialMenuGeometry.center(forCursor: CGPoint(x: 999, y: 400), in: screen)
    #expect(right == CGPoint(x: 1000 - radius, y: 400))
  }

  @Test("un écran plus petit que le disque le centre")
  func tinyScreenCentersDisk() {
    let tiny = CGRect(x: 0, y: 0, width: 100, height: 100)
    #expect(RadialMenuGeometry.center(forCursor: .zero, in: tiny) == CGPoint(x: 50, y: 50))
  }

  @Test("le premier élément est en haut, les suivants dans le sens horaire")
  func sectorsRunClockwiseFromTop() {
    #expect(RadialMenuGeometry.index(forOffset: CGVector(dx: 0, dy: 80), count: 8) == 0)
    #expect(RadialMenuGeometry.index(forOffset: CGVector(dx: 80, dy: 0), count: 8) == 2)
    #expect(RadialMenuGeometry.index(forOffset: CGVector(dx: 0, dy: -80), count: 8) == 4)
    #expect(RadialMenuGeometry.index(forOffset: CGVector(dx: -80, dy: 0), count: 8) == 6)
  }

  @Test("la zone morte et la liste vide ne visent rien")
  func deadZoneAndEmptyList() {
    #expect(RadialMenuGeometry.index(forOffset: CGVector(dx: 5, dy: 5), count: 8) == nil)
    #expect(RadialMenuGeometry.index(forOffset: CGVector(dx: 0, dy: 80), count: 0) == nil)
  }

  @Test("un seul élément est visé dans toutes les directions")
  func singleItem() {
    #expect(RadialMenuGeometry.index(forOffset: CGVector(dx: -60, dy: -60), count: 1) == 0)
  }

  @Test("les éléments survivent à un relancement, dans l'ordre")
  func itemsPersist() {
    let name = "whoa-notch.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }

    let first = SettingsStorage(defaults: defaults)
    first.settings.radialMenu.enabled = true
    first.settings.radialMenu.button = .back
    first.settings.radialMenu.items = [
      RadialMenuItem(
        kind: .app, name: "Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app"),
      .shortcut(named: "Lampe"),
    ]

    let second = SettingsStorage(defaults: defaults)
    #expect(second.settings.radialMenu == first.settings.radialMenu)
    #expect(second.settings.radialMenu.items.map(\.name) == ["Safari", "Lampe"])
  }

  @Test("un type d'élément inconnu est écarté sans perdre les autres")
  func unknownItemKindIsDropped() throws {
    let json = """
      {"enabled": true, "button": 99, "items": [
        {"id": "a", "kind": "futur", "name": "?"},
        {"id": "b", "kind": "shortcut", "name": "Lampe"}]}
      """
    let decoded = try JSONDecoder().decode(RadialMenuSettings.self, from: Data(json.utf8))
    #expect(decoded.enabled)
    #expect(decoded.button == .middle)
    #expect(decoded.items.map(\.name) == ["Lampe"])
  }

  @Test("le clic à trois doigts se relit après un relancement")
  func threeFingerClickPersists() throws {
    var settings = RadialMenuSettings()
    settings.button = .threeFingerClick
    let data = try JSONEncoder().encode(settings)
    #expect(
      try JSONDecoder().decode(RadialMenuSettings.self, from: data).button == .threeFingerClick)
  }

  @Test("un ancien blob sans menu radial garde ses autres réglages")
  func oldBlobWithoutRadialMenu() throws {
    let decoded = try JSONDecoder().decode(
      AppSettings.self, from: Data(#"{"general": {"panelOpacity": 0.5}}"#.utf8))
    #expect(decoded.general.panelOpacity == 0.5)
    #expect(decoded.radialMenu == RadialMenuSettings())
  }
}
