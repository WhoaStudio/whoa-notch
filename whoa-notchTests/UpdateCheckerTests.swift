import Foundation
import Testing

@testable import whoa_notch

@Suite("Vérification des mises à jour")
struct UpdateCheckerTests {

  @Test("les versions se comparent composante par composante, avec ou sans « v »")
  func versionComparison() {
    #expect(AppVersion.isNewer("v1.2", than: "1.1"))
    #expect(AppVersion.isNewer("1.10", than: "1.9"))
    #expect(AppVersion.isNewer("2", than: "1.9.9"))
    #expect(!AppVersion.isNewer("v1.2", than: "1.2.0"))
    #expect(!AppVersion.isNewer("1.1", than: "1.2"))
  }

  @MainActor private static func makeStorage(autoCheck: Bool) -> SettingsStorage {
    let suite = UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let storage = SettingsStorage(defaults: defaults)
    storage.settings.general.autoCheckForUpdates = autoCheck
    return storage
  }

  @Test("réglage actif : une vérification part au lancement")
  @MainActor
  func checksAtLaunchWhenEnabled() async throws {
    let checker = UpdateChecker(
      provider: MockReleaseProvider(outcome: "available"),
      storage: Self.makeStorage(autoCheck: true), currentVersion: "1.0")
    checker.start()
    try await Task.sleep(for: .milliseconds(300))
    if case .available = checker.status {
    } else {
      Issue.record("statut inattendu : \(checker.status)")
    }
  }

  @Test("réglage désactivé : aucune vérification automatique")
  @MainActor
  func noCheckWhenDisabled() async throws {
    let checker = UpdateChecker(
      provider: MockReleaseProvider(outcome: "available"),
      storage: Self.makeStorage(autoCheck: false), currentVersion: "1.0")
    checker.start()
    try await Task.sleep(for: .milliseconds(300))
    #expect(checker.status == .idle)
  }

  @Test("la vérification manuelle fonctionne réglage désactivé")
  @MainActor
  func manualCheckStillWorks() async throws {
    let checker = UpdateChecker(
      provider: MockReleaseProvider(outcome: "current"),
      storage: Self.makeStorage(autoCheck: false), currentVersion: "1.0")
    checker.start()
    checker.checkNow()
    try await Task.sleep(for: .milliseconds(300))
    #expect(checker.status == .upToDate)
  }
}
