import Testing

@testable import whoa_notch

struct NowPlayingClockTests {

  @Test("sous une heure, le format reste m:ss")
  func shortTrack() {
    #expect(NowPlayingClock.format(0) == "0:00")
    #expect(NowPlayingClock.format(243) == "4:03")
    #expect(NowPlayingClock.format(3599) == "59:59")
  }

  @Test("à partir d'une heure, le format passe à h:mm:ss")
  func longTrack() {
    #expect(NowPlayingClock.format(3600) == "1:00:00")
    #expect(NowPlayingClock.format(10_482) == "2:54:42")
  }

  @Test("une valeur négative ou non finie donne zéro")
  func invalidValues() {
    #expect(NowPlayingClock.format(-5) == "0:00")
    #expect(NowPlayingClock.format(.nan) == "0:00")
    #expect(NowPlayingClock.format(.infinity) == "0:00")
  }

  @Test("le temps restant porte un signe moins, sauf à zéro")
  func remaining() {
    #expect(NowPlayingClock.formatRemaining(633) == "-10:33")
    #expect(NowPlayingClock.formatRemaining(10_482) == "-2:54:42")
    #expect(NowPlayingClock.formatRemaining(0) == "0:00")
  }
}
