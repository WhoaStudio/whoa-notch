import AVFoundation
import EventKit
import Foundation
import Testing

@testable import whoa_notch

/// Conversions des états système des autorisations vers l'état affiché.
@MainActor
@Suite("Autorisations système")
struct PrivacyPermissionTests {

  @Test(
    "Un accès complet aux calendriers est autorisé, le refus et l'écriture seule ne le sont pas")
  func calendarMapping() {
    #expect(PrivacyPermissionService.calendarState(.fullAccess) == .allowed)
    #expect(PrivacyPermissionService.calendarState(.notDetermined) == .notDetermined)
    #expect(PrivacyPermissionService.calendarState(.denied) == .denied)
    #expect(PrivacyPermissionService.calendarState(.writeOnly) == .denied)
  }

  @Test("La caméra suit son statut AVFoundation")
  func cameraMapping() {
    #expect(PrivacyPermissionService.captureState(.authorized) == .allowed)
    #expect(PrivacyPermissionService.captureState(.notDetermined) == .notDetermined)
    #expect(PrivacyPermissionService.captureState(.denied) == .denied)
    #expect(PrivacyPermissionService.captureState(.restricted) == .denied)
  }

  @Test("L'automatisation : noErr autorisé, consentement jamais demandé, tout autre code refusé")
  func automationMapping() {
    #expect(PrivacyPermissionService.automationState(osStatus: noErr) == .allowed)
    #expect(
      PrivacyPermissionService.automationState(
        osStatus: OSStatus(errAEEventWouldRequireUserConsent)) == .notDetermined)
    #expect(
      PrivacyPermissionService.automationState(osStatus: OSStatus(errAEEventNotPermitted))
        == .denied)
  }

  @Test("Contacts, localisation, photos et micro suivent leurs statuts système")
  func otherStatusMappings() {
    #expect(PrivacyPermissionService.contactsState(.authorized) == .allowed)
    #expect(PrivacyPermissionService.contactsState(.denied) == .denied)
    #expect(PrivacyPermissionService.locationState(.authorizedAlways) == .allowed)
    #expect(PrivacyPermissionService.locationState(.notDetermined) == .notDetermined)
    #expect(PrivacyPermissionService.photosState(.limited) == .allowed)
    #expect(PrivacyPermissionService.photosState(.restricted) == .denied)
    #expect(PrivacyPermissionService.captureState(.authorized) == .allowed)
    #expect(PrivacyPermissionService.captureState(.notDetermined) == .notDetermined)
  }

  @Test("Chaque autorisation affichée a un volet des Réglages système")
  func everyPermissionHasSettingsPane() {
    for permission in PrivacyPermission.allCases {
      #expect(permission.settingsURL != nil)
    }
  }
}
