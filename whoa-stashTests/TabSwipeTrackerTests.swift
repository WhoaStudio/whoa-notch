import Testing

@testable import whoa_stash

/// Balayage d'onglets : un geste surtout horizontal et assez long change d'onglet, tout le reste
/// (clic, petit mouvement, défilement vertical) ne change rien.
@MainActor
struct TabSwipeTrackerTests {

    @Test func balayageVersLaGaucheVaAuOngletSuivant() {
        var tracker = TabSwipeTracker()
        let moved = tracker.move(dx: -80, dy: 2)
        #expect(moved)
        let result = tracker.end()
        #expect(result == .next)
    }

    @Test func balayageVersLaDroiteVaAuOngletPrecedent() {
        var tracker = TabSwipeTracker()
        tracker.move(dx: 80, dy: 0)
        let result = tracker.end()
        #expect(result == .previous)
    }

    @Test func unClicSansMouvementNeChangeRien() {
        var tracker = TabSwipeTracker()
        let result = tracker.end()
        #expect(result == nil)
    }

    @Test func unPetitMouvementResteUnClic() {
        var tracker = TabSwipeTracker()
        let moved = tracker.move(dx: -3, dy: 1)
        #expect(!moved)
        let result = tracker.end()
        #expect(result == nil)
    }

    @Test func unBalayageTropCourtNeChangePasDOnglet() {
        var tracker = TabSwipeTracker()
        let moved = tracker.move(dx: -30, dy: 0)
        #expect(moved)
        let result = tracker.end()
        #expect(result == nil)
    }

    @Test func unDefilementVerticalEstAbandonne() {
        var tracker = TabSwipeTracker()
        let moved = tracker.move(dx: -4, dy: 40)
        #expect(!moved)
        // Même si le doigt dérive ensuite vers le côté, le geste reste un défilement.
        let movedAgain = tracker.move(dx: -200, dy: 0)
        #expect(!movedAgain)
        let result = tracker.end()
        #expect(result == nil)
    }

    @Test func leSuiveurEstRemisAZeroApresLeRelache() {
        var tracker = TabSwipeTracker()
        tracker.move(dx: -80, dy: 0)
        _ = tracker.end()
        let result = tracker.end()
        #expect(result == nil)
        #expect(tracker.offset == 0)
    }

    @Test func lOngletVoisinNeReboucleJamais() {
        #expect(NotchTab.global.neighbor(.previous) == nil)
        #expect(NotchTab.terminal.neighbor(.next) == nil)
        #expect(NotchTab.ai.neighbor(.next) == .terminal)
        #expect(NotchTab.global.neighbor(.next) == .calendar)
        #expect(NotchTab.ai.neighbor(.previous) == .mirror)
        #expect(NotchTab.terminal.neighbor(.previous) == .ai)
    }
}
