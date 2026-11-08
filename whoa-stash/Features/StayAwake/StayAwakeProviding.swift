import IOKit.pwr_mgt
import OSLog

/// La source qui garde le Mac éveillé. Derrière un protocole, comme les autres sources externes,
/// pour que l'onglet se vérifie sans toucher à la gestion d'énergie (`MockStayAwakeProvider`).
protocol StayAwakeProviding: AnyObject {

  /// Garde le Mac éveillé selon `scope`, en remplaçant la prise précédente. `false` si le
  /// système refuse.
  func hold(_ scope: StayAwakeScope) -> Bool

  /// Rend la main au système. Sans effet quand rien n'est tenu.
  func release()
}

/// Les vraies assertions IOKit : `PreventUserIdleDisplaySleep` garde l'écran (et donc le Mac)
/// éveillé, `PreventUserIdleSystemSleep` garde le Mac seul. Visibles dans `pmset -g assertions`.
final class IOKitStayAwakeProvider: StayAwakeProviding {

  private var assertionID = IOPMAssertionID(kIOPMNullAssertionID)

  func hold(_ scope: StayAwakeScope) -> Bool {
    release()
    let type =
      switch scope {
      case .macAndDisplay: kIOPMAssertPreventUserIdleDisplaySleep
      case .macOnly: kIOPMAssertPreventUserIdleSystemSleep
      }
    let result = IOPMAssertionCreateWithName(
      type as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "whoa-stash : Stay Awake" as CFString,
      &assertionID
    )
    guard result == kIOReturnSuccess else {
      assertionID = IOPMAssertionID(kIOPMNullAssertionID)
      Log.stayAwake.error("Assertion refusée, code \(result, privacy: .public)")
      return false
    }
    Log.stayAwake.info(
      "Mac gardé éveillé, \(scope == .macAndDisplay ? "écran compris" : "système seul", privacy: .public)"
    )
    return true
  }

  func release() {
    guard assertionID != IOPMAssertionID(kIOPMNullAssertionID) else { return }
    IOPMAssertionRelease(assertionID)
    assertionID = IOPMAssertionID(kIOPMNullAssertionID)
    Log.stayAwake.info("Assertion relâchée")
  }
}

/// Fausse source : retient seulement ce qu'on lui demande, sans toucher au système.
/// `--stay-awake=mock` la branche à la place de la vraie.
final class MockStayAwakeProvider: StayAwakeProviding {

  private(set) var heldScope: StayAwakeScope?
  var refusesToHold = false

  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments)
    -> MockStayAwakeProvider?
  {
    arguments.contains("--stay-awake=mock") ? MockStayAwakeProvider() : nil
  }

  func hold(_ scope: StayAwakeScope) -> Bool {
    guard !refusesToHold else { return false }
    heldScope = scope
    return true
  }

  func release() {
    heldScope = nil
  }
}
