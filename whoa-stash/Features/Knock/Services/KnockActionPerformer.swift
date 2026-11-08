import AppKit
import OSLog

/// Exécute l'action associée à un coup.
final class KnockActionPerformer {

  var onNowPlayingCommand: ((NowPlayingCommand) -> Void)?

  func perform(_ action: KnockAction) {
    switch action {
    case .none:
      break
    case .displayOff:
      run("/usr/bin/pmset", ["displaysleepnow"])
    case .lockScreen:
      guard AccessibilityPermissionService.shared.isTrusted else {
        AccessibilityPermissionService.shared.requestAccess()
        return
      }
      sendKey(code: 12, flags: [.maskControl, .maskCommand])  // ⌃⌘Q
    case .startScreenSaver:
      openApp("/System/Library/CoreServices/ScreenSaverEngine.app")
    case .missionControl:
      openApp("/System/Applications/Mission Control.app")
    case .playPause:
      onNowPlayingCommand?(.togglePlayPause)
    case .nextTrack:
      onNowPlayingCommand?(.nextTrack)
    }
  }

  private func run(_ path: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    do { try process.run() } catch {
      Log.knock.error(
        "Échec de \(path, privacy: .public) : \(error.localizedDescription, privacy: .public)")
    }
  }

  private func openApp(_ path: String) {
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
  }

  private func sendKey(code: CGKeyCode, flags: CGEventFlags) {
    for down in [true, false] {
      let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
      event?.flags = flags
      event?.post(tap: .cghidEventTap)
    }
  }
}
