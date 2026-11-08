import Foundation
import Testing

@testable import whoa_stash

/// Le cadran de volume, pris par son view model : la course bornée, et le retour sensoriel qui
/// ne se déclenche qu'au franchissement d'une graduation. Les deux sont exercés avec un service
/// audio et un retour factices, donc sans toucher au volume de la machine ni faire de bruit.
@MainActor
struct VolumeDialViewModelTests {

  private final class FakeVolumeService: VolumeControlling {
    var volume: Float
    private(set) var writes: [Float] = []

    init(volume: Float) {
      self.volume = volume
    }

    func setVolume(_ value: Float) {
      volume = value
      writes.append(value)
    }

    func getVolume() -> Float { volume }
  }

  private final class CountingFeedback: OverlayFeedback {
    private(set) var ticks = 0
    func tickCrossed() { ticks += 1 }
  }

  private static func make(volume: Float) -> (
    VolumeDialViewModel, FakeVolumeService, CountingFeedback
  ) {
    let service = FakeVolumeService(volume: volume)
    let feedback = CountingFeedback()
    return (VolumeDialViewModel(service: service, feedback: feedback), service, feedback)
  }

  @Test("la course est bornée aux deux bouts, quel que soit l'élan de la molette")
  func courseIsClamped() {
    let (viewModel, service, _) = Self.make(volume: 0.5)

    viewModel.adjust(byScrollDelta: 10_000)
    #expect(viewModel.volume == 1)
    #expect(viewModel.percent == 100)
    #expect(service.getVolume() == 1)

    viewModel.adjust(byScrollDelta: -10_000)
    #expect(viewModel.volume == 0)
    #expect(viewModel.percent == 0)
    #expect(service.getVolume() == 0)
  }

  @Test("le retour ne se joue qu'au franchissement d'une graduation")
  func feedbackFollowsTicks() {
    let (viewModel, _, feedback) = Self.make(volume: 0)

    // Un pas assez petit pour rester dans la même graduation : le volume bouge, pas le cran.
    viewModel.setVolume(1 / Float(VolumeDialViewModel.tickCount) / 4)
    #expect(viewModel.volume > 0)
    #expect(feedback.ticks == 0)

    // Un pas qui change de graduation : un tick, et un seul.
    viewModel.setVolume(1 / Float(VolumeDialViewModel.tickCount))
    #expect(feedback.ticks == 1)

    // Une valeur déjà posée ne rejoue rien.
    viewModel.setVolume(1 / Float(VolumeDialViewModel.tickCount))
    #expect(feedback.ticks == 1)
  }

  @Test("se resynchroniser sur le système ne joue aucun retour")
  func syncIsSilent() {
    let (viewModel, service, feedback) = Self.make(volume: 0)

    // Le volume a changé ailleurs pendant que le cadran était fermé.
    service.volume = 0.8
    viewModel.syncWithSystem()

    #expect(viewModel.percent == 80)
    #expect(feedback.ticks == 0)
    // Et rien n'a été réécrit vers le système : on l'a lu, pas piloté.
    #expect(service.writes.isEmpty)
  }
}
