import Foundation
import Testing

@testable import whoa_notch

/// Persistance des préférences. `SettingsStorage` accepte un `UserDefaults` injecté, donc
/// chaque test travaille dans sa propre suite nommée, jamais dans `.standard` : rien ne fuit
/// d'un test à l'autre ni dans les réglages réels de la machine.
@MainActor
struct SettingsStorageTests {

  /// Un `UserDefaults` vierge, isolé par test, effacé en fin de portée.
  private static func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "whoa-notch.tests.\(name)")!
    defaults.removePersistentDomain(forName: "whoa-notch.tests.\(name)")
    return defaults
  }

  @Test("une suite vide rend les valeurs par défaut")
  func emptyDefaultsYieldDefaultSettings() {
    let storage = SettingsStorage(defaults: Self.makeDefaults())
    #expect(storage.settings == .default)
  }

  @Test("une écriture survit à une nouvelle instance — le cas du relancement")
  func writesSurviveRelaunch() {
    let defaults = Self.makeDefaults()

    let first = SettingsStorage(defaults: defaults)
    first.settings.general.panelOpacity = 0.6
    first.settings.general.accentColor = .purple
    first.settings.brightness.glowIntensity = 1.6
    first.settings.notchPanel.enabled = false
    first.settings.notchPanel.notchlessStyle = .notch

    // Deuxième instance sur la même suite : c'est ce que fait un relancement de l'app.
    let second = SettingsStorage(defaults: defaults)
    #expect(second.settings.general.panelOpacity == 0.6)
    #expect(second.settings.general.accentColor == .purple)
    #expect(second.settings.brightness.glowIntensity == 1.6)
    #expect(second.settings.notchPanel.enabled == false)
    #expect(second.settings.notchPanel.notchlessStyle == .notch)
  }

  @Test("le drapeau de bienvenue est faux par défaut, absent d'un ancien blob, et persiste")
  func onboardingFlagDefaultsAndPersists() {
    let defaults = Self.makeDefaults()
    defaults.set(Data(#"{"general":{}}"#.utf8), forKey: "com.whoastudio.whoa-notch.appSettings")

    let first = SettingsStorage(defaults: defaults)
    #expect(first.settings.hasSeenOnboarding == false)

    first.settings.hasSeenOnboarding = true
    #expect(SettingsStorage(defaults: defaults).settings.hasSeenOnboarding == true)
  }

  @Test("une forme d'encoche inconnue ou absente retombe sur la valeur par défaut")
  func unknownNotchlessStyleFallsBack() {
    let defaults = Self.makeDefaults()
    let blob = #"{"notchPanel":{"enabled":false,"notchlessStyle":"capsule"}}"#
    defaults.set(Data(blob.utf8), forKey: "com.whoastudio.whoa-notch.appSettings")

    let storage = SettingsStorage(defaults: defaults)
    #expect(storage.settings.notchPanel.notchlessStyle == NotchPanelSettings().notchlessStyle)
    #expect(storage.settings.notchPanel.enabled == false)
  }

  @Test("le thème du dock est Dark par défaut, inconnu ou absent, et survit au relancement")
  func dockThemePersistsAndFallsBack() {
    let key = "com.whoastudio.whoa-notch.appSettings"
    let missing = Self.makeDefaults()
    missing.set(Data(#"{"dock":{"autoHide":false}}"#.utf8), forKey: key)
    #expect(SettingsStorage(defaults: missing).settings.dock.theme == .dark)

    let unknown = Self.makeDefaults()
    unknown.set(Data(#"{"dock":{"theme":"neon","autoHide":false}}"#.utf8), forKey: key)
    let fallback = SettingsStorage(defaults: unknown)
    #expect(fallback.settings.dock.theme == .dark)
    #expect(fallback.settings.dock.autoHide == false)

    let defaults = Self.makeDefaults()
    SettingsStorage(defaults: defaults).settings.dock.theme = .liquidGlass
    #expect(SettingsStorage(defaults: defaults).settings.dock.theme == .liquidGlass)
  }

  @Test("un blob illisible retombe sur les valeurs par défaut au lieu de planter")
  func corruptBlobFallsBackToDefaults() {
    let defaults = Self.makeDefaults()
    defaults.set(Data("pas du JSON".utf8), forKey: "com.whoastudio.whoa-notch.appSettings")

    let storage = SettingsStorage(defaults: defaults)
    #expect(storage.settings == .default)
  }

  @Test("un réglage absent du blob garde sa valeur par défaut")
  func missingKeysKeepTheirDefaults() throws {
    let defaults = Self.makeDefaults()
    // Un blob d'une version antérieure, qui ne connaît qu'une partie des réglages.
    let partial = #"{"general":{"accentColor":"purple"}}"#
    defaults.set(Data(partial.utf8), forKey: "com.whoastudio.whoa-notch.appSettings")

    let storage = SettingsStorage(defaults: defaults)
    #expect(storage.settings.general.accentColor == .purple)
    // Non écrits par le blob partiel, donc rendus par les valeurs par défaut du modèle.
    #expect(storage.settings.general.enableAnimations == GeneralSettings().enableAnimations)
    #expect(storage.settings.brightness == BrightnessSettings())
  }

  @Test("l'ouverture au clic de l'encoche est absente par défaut et se relit")
  func opensOnClickDefaultsAndPersists() {
    let defaults = Self.makeDefaults()
    defaults.set(
      Data(#"{"notchPanel":{"enabled":true}}"#.utf8),
      forKey: "com.whoastudio.whoa-notch.appSettings")
    #expect(SettingsStorage(defaults: defaults).settings.notchPanel.opensOnClick == false)

    let on = Self.makeDefaults()
    on.set(
      Data(#"{"notchPanel":{"opensOnClick":true}}"#.utf8),
      forKey: "com.whoastudio.whoa-notch.appSettings")
    #expect(SettingsStorage(defaults: on).settings.notchPanel.opensOnClick == true)
  }

  @Test(
    "la vérification automatique des mises à jour est active par défaut et son état survit au relancement"
  )
  func autoCheckForUpdatesDefaultsAndPersists() {
    let defaults = Self.makeDefaults()
    defaults.set(Data(#"{"general":{}}"#.utf8), forKey: "com.whoastudio.whoa-notch.appSettings")
    let first = SettingsStorage(defaults: defaults)
    #expect(first.settings.general.autoCheckForUpdates == true)

    first.settings.general.autoCheckForUpdates = false
    #expect(SettingsStorage(defaults: defaults).settings.general.autoCheckForUpdates == false)
  }

  @Test("une valeur d'énumération inconnue retombe sur la valeur par défaut")
  func unknownEnumCaseFallsBack() {
    let defaults = Self.makeDefaults()
    let blob = #"{"general":{"accentColor":"chartreuse","enableAnimations":false}}"#
    defaults.set(Data(blob.utf8), forKey: "com.whoastudio.whoa-notch.appSettings")

    let storage = SettingsStorage(defaults: defaults)
    #expect(storage.settings.general.accentColor == GeneralSettings().accentColor)
    // Le voisin lisible est conservé : un cas inconnu n'emporte pas la section.
    #expect(storage.settings.general.enableAnimations == false)
  }

  /// `appearanceMode` a été retiré avec le thème clair : un blob écrit par une version qui le
  /// portait encore ne doit pas emporter les réglages posés à côté de lui.
  @Test("une clé retirée depuis est ignorée sans emporter le reste de la section")
  func retiredKeyIsIgnored() {
    let defaults = Self.makeDefaults()
    let blob = #"{"general":{"appearanceMode":"light","accentColor":"pink"}}"#
    defaults.set(Data(blob.utf8), forKey: "com.whoastudio.whoa-notch.appSettings")

    let storage = SettingsStorage(defaults: defaults)
    #expect(storage.settings.general.accentColor == .pink)
    #expect(storage.settings.general.enableAnimations == GeneralSettings().enableAnimations)
  }

  /// Les réglages ajoutés par cette version : un blob qui les ignore doit garder le reste.
  @Test("un blob antérieur garde ce qu'il porte, les nouveaux réglages prennent leur défaut")
  func olderBlobKeepsWhatItCarries() {
    let defaults = Self.makeDefaults()
    let older = #"{"general":{"launchAtLogin":true,"accentColor":"blue","enableAnimations":false}}"#
    defaults.set(Data(older.utf8), forKey: "com.whoastudio.whoa-notch.appSettings")

    let storage = SettingsStorage(defaults: defaults)
    #expect(storage.settings.general.launchAtLogin == true)
    #expect(storage.settings.general.accentColor == .blue)
    #expect(storage.settings.general.enableAnimations == false)
    // Absents du blob, donc à leur valeur par défaut — et non perdus avec tout le reste.
    #expect(storage.settings.general.panelOpacity == GeneralSettings().panelOpacity)
    #expect(storage.settings.general.togglePanelShortcut == .disabled)
    #expect(storage.settings.brightness == BrightnessSettings())
  }

  @Test("la réponse libre après un tour est désactivée par défaut, absente d'un ancien blob, et persiste")
  func stopReplyDefaultsAndPersists() {
    #expect(AISettings().stopReplyEnabled == false)

    let defaults = Self.makeDefaults()
    let older = #"{"ai":{"desktopWatcherEnabled":true}}"#
    defaults.set(Data(older.utf8), forKey: "com.whoastudio.whoa-notch.appSettings")
    let storage = SettingsStorage(defaults: defaults)
    #expect(storage.settings.ai.desktopWatcherEnabled == true)
    #expect(storage.settings.ai.stopReplyEnabled == false)

    storage.settings.ai.stopReplyEnabled = true
    let relaunched = SettingsStorage(defaults: defaults)
    #expect(relaunched.settings.ai.stopReplyEnabled == true)
    #expect(relaunched.settings.ai.desktopWatcherEnabled == true)
  }

  @Test("une valeur réécrite à l'identique n'est pas réécrite sur le disque")
  func identicalWriteDoesNotPersistAgain() {
    let suite = "whoa-notch.tests.counting"
    let defaults = CountingDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)

    let storage = SettingsStorage(defaults: defaults)
    storage.settings.general.accentColor = .purple
    let afterFirstWrite = defaults.writeCount
    #expect(afterFirstWrite > 0)

    // `SettingsStorage` compare l'ancienne et la nouvelle valeur avant de persister.
    storage.settings.general.accentColor = .purple
    #expect(defaults.writeCount == afterFirstWrite)

    storage.settings.general.accentColor = .blue
    #expect(defaults.writeCount == afterFirstWrite + 1)
  }
}

/// Compte les écritures, pour vérifier que `SettingsStorage` ne persiste pas deux fois la
/// même valeur. `UserDefaults` n'expose rien de tel.
private final class CountingDefaults: UserDefaults {
  private(set) var writeCount = 0

  override func set(_ value: Any?, forKey defaultName: String) {
    writeCount += 1
    super.set(value, forKey: defaultName)
  }
}
