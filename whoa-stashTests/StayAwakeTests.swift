import Foundation
import Testing

@testable import whoa_stash

@MainActor
@Suite("Stay Awake")
struct StayAwakeTests {

  private final class Clock {
    var date = Date(timeIntervalSince1970: 1_000)
  }

  private func makeViewModel() -> (StayAwakeViewModel, MockStayAwakeProvider, Clock) {
    let provider = MockStayAwakeProvider()
    let clock = Clock()
    let viewModel = StayAwakeViewModel(provider: provider, now: { clock.date })
    return (viewModel, provider, clock)
  }

  @Test("le temps restant s'écrit en heures, minutes puis secondes")
  func remainingText() {
    #expect(StayAwakeState.remainingText(2 * 3600) == "2 hr left")
    #expect(StayAwakeState.remainingText(2 * 3600 - 1) == "2 hr left")
    #expect(StayAwakeState.remainingText(3600 + 30 * 60) == "1 hr 30 min left")
    #expect(StayAwakeState.remainingText(45 * 60) == "45 min left")
    #expect(StayAwakeState.remainingText(59) == "59 sec left")
  }

  @Test("sans échéance, l'état dit qu'il dure jusqu'à l'arrêt")
  func statusTextWithoutDeadline() {
    #expect(StayAwakeState().statusText == "Off")
    var state = StayAwakeState()
    state.duration = .forever
    #expect(state.statusText == "Until turned off")
  }

  @Test("démarrer tient le Mac éveillé avec la portée choisie")
  func startHoldsScope() {
    let (viewModel, provider, _) = makeViewModel()
    viewModel.start(.hour1)
    #expect(provider.heldScope == .macAndDisplay)
    #expect(viewModel.state.duration == .hour1)
    #expect(viewModel.state.remaining == 3600)
  }

  @Test("changer la portée à chaud refait la prise")
  func scopeChangeWhileActive() {
    let (viewModel, provider, _) = makeViewModel()
    viewModel.start(.hour1)
    viewModel.setScope(.macOnly)
    #expect(provider.heldScope == .macOnly)
    #expect(viewModel.state.scope == .macOnly)
  }

  @Test("changer la portée à l'arrêt ne tient rien")
  func scopeChangeWhileInactive() {
    let (viewModel, provider, _) = makeViewModel()
    viewModel.setScope(.macOnly)
    #expect(provider.heldScope == nil)
    viewModel.start(.minutes15)
    #expect(provider.heldScope == .macOnly)
  }

  @Test("« Turn Off » relâche la prise")
  func turnOffReleases() {
    let (viewModel, provider, _) = makeViewModel()
    viewModel.start(.hours2)
    viewModel.turnOff()
    #expect(provider.heldScope == nil)
    #expect(!viewModel.state.isActive)
    #expect(viewModel.state.remaining == nil)
  }

  @Test("à l'échéance, la prise est relâchée")
  func expiryReleases() {
    let (viewModel, provider, clock) = makeViewModel()
    viewModel.start(.minutes15)

    clock.date.addTimeInterval(14 * 60)
    viewModel.tick()
    #expect(provider.heldScope != nil)
    #expect(viewModel.state.remaining == 60)

    clock.date.addTimeInterval(60)
    viewModel.tick()
    #expect(provider.heldScope == nil)
    #expect(!viewModel.state.isActive)
  }

  @Test("sans échéance, rien ne s'arrête tout seul")
  func foreverNeverExpires() {
    let (viewModel, provider, clock) = makeViewModel()
    viewModel.start(.forever)
    clock.date.addTimeInterval(10 * 24 * 3600)
    viewModel.tick()
    #expect(provider.heldScope != nil)
    #expect(viewModel.state.remaining == nil)
  }

  @Test("une prise refusée laisse l'état inactif")
  func refusedHold() {
    let (viewModel, provider, _) = makeViewModel()
    provider.refusesToHold = true
    viewModel.start(.hour1)
    #expect(!viewModel.state.isActive)
  }

  @Test("le balayage ne mène ni à Stay Awake ni à Analytics, ni n'en part")
  func swipeSkipsStayAwake() {
    #expect(NotchTab.colorPicker.neighbor(.next) == nil)
    for headerTab in [NotchTab.stayAwake, .analytics] {
      #expect(headerTab.neighbor(.next) == nil)
      #expect(headerTab.neighbor(.previous) == nil)
      #expect(!NotchTab.barTabs.contains(headerTab))
    }
  }
}
