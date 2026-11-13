import CoreGraphics
import Testing

@testable import whoa_notch

/// Le logo de l'encoche : poses du couvercle, limite du regard et rythme des clignements.
@Suite struct ChestLogoModelTests {
  @Test func survolEntrouvreEtSortieReferme() {
    #expect(ChestLidPose.closed.afterEntering() == .peek)
    #expect(ChestLidPose.open.afterEntering() == .open)
    #expect(ChestLidPose.open.afterExiting() == .closed)
    #expect(ChestLidPose.peek.afterExiting() == .closed)
  }

  @Test func clicOuvreEnGrandPuisRevientALaPoseDuSurvol() {
    #expect(ChestLidPose.peek.afterClick() == .open)
    #expect(ChestLidPose.open.afterClick() == .peek)
    #expect(ChestLidPose.closed.openness < ChestLidPose.peek.openness)
    #expect(ChestLidPose.peek.openness < ChestLidPose.open.openness)
  }

  private func offset(cursor: CGPoint, inside: Bool = true) -> CGVector {
    ChestGaze.offset(
      cursor: cursor, eyesCenter: .zero, insideNotch: inside,
      limit: ChestGaze.limit(forChestSide: 56), reach: 168)
  }

  @Test func regardAuCentreHorsDeLEncocheOuSurLesYeux() {
    #expect(offset(cursor: CGPoint(x: 500, y: 40), inside: false) == .zero)
    #expect(offset(cursor: .zero) == .zero)
  }

  @Test func regardResteDansLEllipse() {
    let limit = ChestGaze.limit(forChestSide: 56)
    for angle in stride(from: 0.0, to: 6.28, by: 0.3) {
      for distance in [1.0, 20, 168, 900] {
        let o = offset(cursor: CGPoint(x: cos(angle) * distance, y: sin(angle) * distance))
        let ratio =
          (o.dx / limit.width) * (o.dx / limit.width) + (o.dy / limit.height)
          * (o.dy / limit.height)
        #expect(ratio <= 1.0001)
      }
    }
  }

  @Test func regardSuitLaDirectionDuCurseur() {
    let o = offset(cursor: CGPoint(x: 400, y: 0))
    #expect(o.dx > 0 && o.dy == 0)
    #expect(offset(cursor: CGPoint(x: 0, y: -400)).dy < 0)
  }

  @Test func clignementsAleatoiresBornes() {
    #expect(ChestBlink.interval(unit: 0) == 2.5)
    #expect(ChestBlink.interval(unit: 1) == 6)
    #expect(ChestBlink.interval(unit: 7) == 6)
    #expect(ChestBlink.isDouble(unit: 0.1))
    #expect(!ChestBlink.isDouble(unit: 0.5))
    #expect(ChestBlink.duration < ChestBlink.doubleGap)
  }
}
