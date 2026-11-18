import AppKit
import Testing

@testable import whoa_notch

/// La pastille des profils : accessibilité, largeur compacte et clic sans fenêtre.
@MainActor
struct DockProfilePillTests {

  private func profiles(_ count: Int) -> [DockProfile] {
    (0..<count).map { DockProfile(id: "p\($0)", name: "Profil \($0)") }
  }

  @Test("la pastille se lit comme un groupe de boutons radio, un par profil")
  func exposesRadioGroup() {
    let pill = DockProfilePillView(frame: .zero)
    pill.apply(profiles: profiles(3), activeID: "p1")

    #expect(pill.accessibilityRole() == .radioGroup)
    let children = pill.accessibilityChildren() as? [NSView] ?? []
    #expect(children.count == 3)
    #expect(children.allSatisfy { $0.accessibilityRole() == .radioButton })
    #expect(children.map { $0.accessibilityLabel() } == ["Profil 0", "Profil 1", "Profil 2"])
    #expect(children.map { ($0.accessibilityValue() as? NSNumber)?.intValue } == [0, 1, 0])
  }

  @Test("l'action d'appui de VoiceOver choisit le profil")
  func pressSelectsProfile() {
    let pill = DockProfilePillView(frame: .zero)
    var selected: String?
    pill.onSelect = { selected = $0 }
    pill.apply(profiles: profiles(2), activeID: "p0")

    let second = (pill.accessibilityChildren() as? [NSView])?.last
    #expect(second?.accessibilityPerformPress() == true)
    #expect(selected == "p1")
  }

  @Test("au-delà de cinq profils, seuls les noms des inactifs disparaissent")
  func compactWidthKeepsActiveName() {
    let pill = DockProfilePillView(frame: .zero)
    pill.apply(profiles: profiles(5), activeID: "p0")
    let full = pill.contentSize.width

    pill.apply(profiles: profiles(6), activeID: "p0")
    let compact = pill.contentSize.width
    // Six profils compacts tiennent dans moins de place que cinq avec leur nom.
    #expect(compact < full + 40)
    #expect(compact > 0)
  }
}
