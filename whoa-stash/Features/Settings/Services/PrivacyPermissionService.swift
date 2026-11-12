import AVFoundation
import AppKit
import Contacts
import CoreLocation
import CoreServices
import EventKit
import Photos

/// Une autorisation système de la fenêtre « Privacy & Permissions ». Les lignes sans fonction qui la
/// consomme sont marquées « Not used yet » dans leur légende : leur statut est lu, mais l'app ne le demande
/// pour aucune fonction encore.
enum PrivacyPermission: CaseIterable, Identifiable {
  case calendars
  case reminders
  case contacts
  case location
  case photos
  case microphone
  case accessibility
  case systemAudio
  case musicAutomation

  var id: Self { self }

  var title: String {
    switch self {
    case .calendars: return "Calendars"
    case .reminders: return "Reminders"
    case .contacts: return "Contacts"
    case .location: return "Location"
    case .photos: return "Photos"
    case .microphone: return "Microphone"
    case .accessibility: return "Accessibility"
    case .systemAudio: return "System Audio Recording"
    case .musicAutomation: return "Automation (Music)"
    }
  }

  var caption: String {
    switch self {
    case .calendars: return "Agenda and meetings in the notch panel"
    case .reminders: return "Reserved for a reminders widget. Not used yet"
    case .contacts: return "Reserved for a contacts widget. Not used yet"
    case .location: return "Reserved for local weather. Not used yet"
    case .photos: return "Reserved for a recent photo widget. Not used yet"
    case .microphone: return "Reserved for a voice memo. Not used yet"
    case .accessibility: return "Bring back minimised windows in the dock"
    case .systemAudio:
      return
        "Reserved for App Volume. Not used yet. macOS doesn't expose this status, so it can't be read"
    case .musicAutomation: return "Playing Next: the Apple Music queue"
    }
  }

  /// Volet de Réglages système où l'utilisateur change cette autorisation.
  var settingsURL: URL? {
    let pane: String
    switch self {
    case .calendars: pane = "Privacy_Calendars"
    case .reminders: pane = "Privacy_Reminders"
    case .contacts: pane = "Privacy_Contacts"
    case .location: pane = "Privacy_LocationServices"
    case .photos: pane = "Privacy_Photos"
    case .microphone: pane = "Privacy_Microphone"
    case .accessibility: pane = "Privacy_Accessibility"
    case .systemAudio: pane = "Privacy_ScreenCapture"
    case .musicAutomation: pane = "Privacy_Automation"
    }
    return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
  }
}

/// État d'une autorisation, réduit à ce que l'interface doit montrer.
enum PermissionState: Equatable {
  /// macOS n'a pas encore demandé : une demande ouvrira l'invite.
  case notDetermined
  case allowed
  /// Refusée ou restreinte : seul le réglage système peut la changer.
  case denied
  /// macOS ne donne pas cet état à lire : on ne peut que renvoyer vers le réglage.
  case unknown
}

/// Lit l'état réel de chaque autorisation auprès du système, et la demande quand c'est encore possible.
/// Les conversions d'états sont des fonctions pures, testées à part.
enum PrivacyPermissionService {

  /// Gardé vivant : `CLLocationManager` doit survivre à la demande d'autorisation.
  private static let locationManager = CLLocationManager()

  static func state(for permission: PrivacyPermission) -> PermissionState {
    switch permission {
    case .calendars:
      return calendarState(EKEventStore.authorizationStatus(for: .event))
    case .reminders:
      return calendarState(EKEventStore.authorizationStatus(for: .reminder))
    case .contacts:
      return contactsState(CNContactStore.authorizationStatus(for: .contacts))
    case .location:
      return locationState(locationManager.authorizationStatus)
    case .photos:
      return photosState(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    case .microphone:
      return captureState(AVCaptureDevice.authorizationStatus(for: .audio))
    case .accessibility:
      return AXIsProcessTrusted() ? .allowed : .denied
    case .systemAudio:
      return .unknown
    case .musicAutomation:
      return automationState(osStatus: determineAutomation(bundleID: Self.musicBundleID))
    }
  }

  /// Demande l'autorisation tant que macOS peut encore la poser ; sans effet sinon.
  static func request(_ permission: PrivacyPermission) async {
    switch permission {
    case .calendars:
      _ = try? await EKEventStore().requestFullAccessToEvents()
    case .reminders:
      _ = try? await EKEventStore().requestFullAccessToReminders()
    case .contacts:
      _ = try? await CNContactStore().requestAccess(for: .contacts)
    case .location:
      locationManager.requestWhenInUseAuthorization()
    case .photos:
      _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    case .microphone:
      _ = await AVCaptureDevice.requestAccess(for: .audio)
    case .accessibility:
      AccessibilityPermissionService.shared.requestAccess()
    case .systemAudio:
      // Aucune demande possible : seul le réglage système la donne.
      break
    case .musicAutomation:
      // Une lecture AppleScript anodine : c'est elle qui fait apparaître l'invite Apple Events.
      await Task.detached {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Music\" to name"]
        try? process.run()
        process.waitUntilExit()
      }.value
    }
  }

  static func openSettings(_ permission: PrivacyPermission) {
    guard let url = permission.settingsURL else { return }
    NSWorkspace.shared.open(url)
  }

  // MARK: - Conversions

  /// Calendriers et rappels partagent le même statut EventKit.
  static func calendarState(_ status: EKAuthorizationStatus) -> PermissionState {
    switch status {
    case .fullAccess: return .allowed
    case .notDetermined: return .notDetermined
    // Écriture seule, refus ou restriction : l'app ne peut pas lire.
    default: return .denied
    }
  }

  static func contactsState(_ status: CNAuthorizationStatus) -> PermissionState {
    switch status {
    case .authorized: return .allowed
    case .notDetermined: return .notDetermined
    default: return .denied
    }
  }

  static func locationState(_ status: CLAuthorizationStatus) -> PermissionState {
    switch status {
    case .authorizedAlways: return .allowed
    case .notDetermined: return .notDetermined
    default: return .denied
    }
  }

  static func photosState(_ status: PHAuthorizationStatus) -> PermissionState {
    switch status {
    case .authorized, .limited: return .allowed
    case .notDetermined: return .notDetermined
    default: return .denied
    }
  }

  /// Caméra et micro partagent le statut AVFoundation de capture.
  static func captureState(_ status: AVAuthorizationStatus) -> PermissionState {
    switch status {
    case .authorized: return .allowed
    case .notDetermined: return .notDetermined
    default: return .denied
    }
  }

  /// `AEDeterminePermissionToAutomateTarget` : `noErr` autorisé, `errAEEventWouldRequireUserConsent`
  /// jamais demandé, tout autre code (dont `errAEEventNotPermitted`) refusé.
  static func automationState(osStatus: OSStatus) -> PermissionState {
    switch osStatus {
    case noErr: return .allowed
    case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
    default: return .denied
    }
  }

  // MARK: - Automation

  private static let musicBundleID = "com.apple.Music"

  /// Interroge sans rien afficher (`askUserIfNeeded` faux) : pas d'invite pendant la lecture de l'état.
  private static func determineAutomation(bundleID: String) -> OSStatus {
    let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
    return AEDeterminePermissionToAutomateTarget(
      target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
  }
}
