import AppKit
import Foundation
import Testing

@testable import whoa_stash

@MainActor
private final class FakeDockDefaults: DockDefaultsAccessing {
  var values: [String: Any]
  var restarts = 0

  init(_ values: [String: Any] = [:]) { self.values = values }

  func bool(_ key: String) -> Bool? { values[key] as? Bool }
  func double(_ key: String) -> Double? { values[key] as? Double }
  func set(_ key: String, bool: Bool?) { values[key] = bool }
  func set(_ key: String, double: Double?) { values[key] = double }
  func restartDock() { restarts += 1 }
}

@MainActor
private func makeStorage() -> SettingsStorage {
  SettingsStorage(defaults: UserDefaults(suiteName: "dock-tests-\(UUID().uuidString)")!)
}

@MainActor
@Suite struct SystemDockServiceTests {

  @Test func restaureLesValeursEtSupprimeLesClesAbsentes() {
    let defaults = FakeDockDefaults(["autohide": true])
    let service = SystemDockService(storage: makeStorage(), defaults: defaults)

    service.sync(hidden: true)
    #expect(defaults.values["autohide-delay"] as? Double == SystemDockService.hiddenDelay)

    service.sync(hidden: false)
    #expect(defaults.values["autohide"] as? Bool == true)
    #expect(defaults.values["autohide-delay"] == nil)
    #expect(defaults.restarts == 2)
  }

  @Test func unSecondMasquageNeEcrasePasLaSauvegarde() {
    let defaults = FakeDockDefaults(["autohide": false, "autohide-delay": 0.5])
    let storage = makeStorage()
    let service = SystemDockService(storage: storage, defaults: defaults)

    service.sync(hidden: true)
    service.sync(hidden: true)
    #expect(
      storage.settings.dock.savedSystemDock == SavedSystemDock(autohide: false, autohideDelay: 0.5))

    service.sync(hidden: false)
    #expect(defaults.values["autohide"] as? Bool == false)
    #expect(defaults.values["autohide-delay"] as? Double == 0.5)
    #expect(storage.settings.dock.savedSystemDock == nil)
  }

  @Test func unMasquageAlorsQueLeDockEstDejaMasqueNEnregistrePasNosValeurs() {
    let defaults = FakeDockDefaults([
      "autohide": true, "autohide-delay": SystemDockService.hiddenDelay,
    ])
    let storage = makeStorage()
    SystemDockService(storage: storage, defaults: defaults).sync(hidden: true)
    #expect(
      storage.settings.dock.savedSystemDock == SavedSystemDock(autohide: nil, autohideDelay: nil))
  }

  @Test func restaurerSansSauvegardeNeToucheRien() {
    let defaults = FakeDockDefaults(["autohide": true])
    SystemDockService(storage: makeStorage(), defaults: defaults).restore()
    #expect(defaults.restarts == 0)
    #expect(defaults.values["autohide"] as? Bool == true)
  }
}

@MainActor
@Suite struct DockModelTests {

  @Test func fusionnePingleesEtLancees() {
    let model = DockModel()
    model.setPinned([
      DockPinnedApp(bundleID: "a", path: "/Applications/A.app"),
      DockPinnedApp(bundleID: "b", path: "/Applications/B.app"),
    ])
    model.setRunning([
      DockRunningApp(bundleID: "b", path: "/Applications/B.app", name: "B"),
      DockRunningApp(bundleID: "c", path: "/Applications/C.app", name: "C"),
    ])
    #expect(model.state.items.map(\.bundleID) == ["a", "b"])
    #expect(model.state.items.map(\.isRunning) == [false, true])
    // « c » tourne sans être dans la liste : il va dans le dossier.
    #expect(model.state.overflow.map(\.bundleID) == ["c"])
  }

  @Test func leFinderNEstDansLeDossierQueSiOnLAjoute() {
    let finder = DockRunningApp(
      bundleID: DockModel.finderBundleID, path: "/System/Library/CoreServices/Finder.app",
      name: "Finder")
    let model = DockModel()
    model.setRunning([finder])
    #expect(model.state.items.isEmpty)
    #expect(model.state.overflow.isEmpty)

    model.setPinned([DockPinnedApp(bundleID: DockModel.finderBundleID, path: finder.path)])
    #expect(model.state.items.map(\.bundleID) == [DockModel.finderBundleID])
  }

  @Test func reconnaitLesWebApps() {
    #expect(DockModel.isWebApp(bundleID: "com.google.Chrome.app.xyz", path: "/x.app"))
    #expect(!DockModel.isWebApp(bundleID: "com.apple.Safari", path: "/Applications/Safari.app"))
  }
}

@MainActor
@Suite struct PinnedAppsStoreTests {

  private let sample: [[String: Any]] = [
    [
      "tile-data": [
        "bundle-identifier": "com.spotify.client",
        "file-data": ["_CFURLString": "file:///Applications/Spotify.app/"],
      ]
    ],
    ["tile-type": "spacer-tile", "tile-data": [String: Any]()],
  ]

  @Test func extraitLesApplisEtIgnoreLesSeparateurs() {
    let apps = PinnedAppsStore.parse(persistentApps: sample)
    #expect(
      apps == [DockPinnedApp(bundleID: "com.spotify.client", path: "/Applications/Spotify.app")])
  }

  @Test func nAmorceQuUneFois() {
    let storage = makeStorage()
    let store = PinnedAppsStore(storage: storage)
    store.seedIfNeeded { sample }
    storage.settings.dock.pinnedApps = []
    store.seedIfNeeded { sample }
    #expect(storage.settings.dock.pinnedApps.isEmpty)
  }
}

@MainActor
@Suite struct DockSettingsDecodingTests {
  @Test func unBlobSansCleDockSeDecodeAvecLesDefauts() throws {
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    #expect(decoded.dock == DockSettings())
  }
}

@MainActor
@Suite struct DockAppearanceTests {

  @Test func reprendLesReglagesDuDockMacOS() {
    let defaults = FakeDockDefaults([
      "tilesize": 63.0, "largesize": 105.0, "magnification": true, "autohide": true,
      "autohide-delay": 0.2,
    ])
    let look = DockAppearance.read(from: defaults, saved: nil)
    #expect(
      look
        == DockAppearance(
          iconSize: 63, magnification: true, magnifiedSize: 105, autohide: true, revealDelay: 0.2,
          bounceOnLaunch: true))
  }

  @Test func valeursParDefautQuandLesClesManquent() {
    #expect(DockAppearance.read(from: FakeDockDefaults(), saved: nil) == DockAppearance())
  }

  @Test func dockMasqueParNousLitLaSauvegarde() {
    let defaults = FakeDockDefaults(["autohide": true, "autohide-delay": 1000.0])
    let saved = SavedSystemDock(autohide: false, autohideDelay: nil)
    let look = DockAppearance.read(from: defaults, saved: saved)
    #expect(!look.autohide)
    #expect(look.revealDelay == 0.5)
  }
}

@MainActor
@Suite struct AppLauncherTests {

  private let safari = DockPinnedApp(bundleID: "com.apple.Safari", path: "/Applications/Safari.app")
  private let notes = DockPinnedApp(bundleID: "com.apple.Notes", path: "/Applications/Notes.app")
  private let ghost = DockPinnedApp(bundleID: "com.example.ghost", path: "/nope/Ghost.app")

  private func makeLauncher(running: Set<String> = [], opened: Opened) -> AppLauncher {
    AppLauncher(
      isRunning: { running.contains($0) },
      resolveURL: { $0.bundleID == "com.example.ghost" ? nil : URL(fileURLWithPath: $0.path) },
      open: { url, _ in opened.urls.append(url) })
  }

  @MainActor final class Opened { var urls: [URL] = [] }

  @Test func lanceToutesLesApplisAbsentes() {
    let opened = Opened()
    makeLauncher(opened: opened).launchAll([safari, notes])
    #expect(opened.urls.count == 2)
  }

  @Test func ignoreLesApplisDejaLancees() {
    let opened = Opened()
    makeLauncher(running: ["com.apple.Safari"], opened: opened).launchAll([safari, notes])
    #expect(opened.urls == [URL(fileURLWithPath: notes.path)])
  }

  @Test func ignoreLesApplisIntrouvablesSansPlanter() {
    let opened = Opened()
    makeLauncher(opened: opened).launchAll([ghost, safari])
    #expect(opened.urls == [URL(fileURLWithPath: safari.path)])
  }

  @Test func nOuvrePasDeDoublonPendantUnLancementEnCours() {
    let opened = Opened()
    let launcher = makeLauncher(opened: opened)
    launcher.launchAll([safari])
    launcher.launchAll([safari])
    #expect(opened.urls.count == 1)
  }

  @Test func listeVideNeFaitRien() {
    let opened = Opened()
    makeLauncher(opened: opened).launchAll([])
    #expect(opened.urls.isEmpty)
  }

  @Test func refuseUnFichierQuiNEstPasUneAppli() {
    #expect(DockPinnedApp(appURL: URL(fileURLWithPath: "/etc/hosts")) == nil)
  }
}

@MainActor
@Suite struct DockSettingsViewModelTests {

  @Test func ajouteEtRetireUneAppli() {
    let storage = makeStorage()
    let viewModel = DockSettingsViewModel(storage: storage)
    viewModel.addApp(at: URL(fileURLWithPath: "/System/Applications/Notes.app"))
    viewModel.addApp(at: URL(fileURLWithPath: "/System/Applications/Notes.app"))
    #expect(storage.settings.dock.pinnedApps.count == 1)
    viewModel.removeApp(bundleID: "com.apple.Notes")
    #expect(storage.settings.dock.pinnedApps.isEmpty)
  }

  @Test func exclureUneAppliLaRetireDeLaListeDeLancement() {
    let storage = makeStorage()
    let viewModel = DockSettingsViewModel(storage: storage)
    viewModel.addApp(at: URL(fileURLWithPath: "/System/Applications/Notes.app"))
    viewModel.setLaunchIncluded(false, bundleID: "com.apple.Notes")
    #expect(storage.settings.dock.launchApps.isEmpty)
    #expect(storage.settings.dock.pinnedApps.count == 1)
    viewModel.setLaunchIncluded(true, bundleID: "com.apple.Notes")
    #expect(storage.settings.dock.launchApps.count == 1)
  }

  @Test func retirerUneAppliOublieSonExclusion() {
    let storage = makeStorage()
    let viewModel = DockSettingsViewModel(storage: storage)
    viewModel.addApp(at: URL(fileURLWithPath: "/System/Applications/Notes.app"))
    viewModel.setLaunchIncluded(false, bundleID: "com.apple.Notes")
    viewModel.removeApp(bundleID: "com.apple.Notes")
    #expect(storage.settings.dock.launchExcluded.isEmpty)
  }
}

@MainActor
@Suite struct DockProfileTests {

  private let app = DockPinnedApp(bundleID: "a", path: "/Applications/A.app")

  @Test func leProfilActifRemplaceLesEpinglesGlobales() {
    var dock = DockSettings()
    dock.pinnedApps = [app]
    #expect(dock.visibleApps == [app])

    let profile = DockProfile(name: "Build", apps: [])
    dock.profiles = [profile]
    dock.activeProfileID = profile.id
    #expect(dock.visibleApps.isEmpty)
  }

  @Test func epinglerCibleLeProfilActif() {
    var dock = DockSettings()
    let profile = DockProfile()
    dock.profiles = [profile]
    dock.activeProfileID = profile.id
    dock.togglePin(app)
    #expect(dock.profiles[0].apps == [app])
    #expect(dock.pinnedApps.isEmpty)
    dock.togglePin(app)
    #expect(dock.profiles[0].apps.isEmpty)
  }

  @Test func unIdentifiantInconnuRetombeSurLesEpingles() {
    var dock = DockSettings()
    dock.pinnedApps = [app]
    dock.activeProfileID = "inconnu"
    #expect(dock.visibleApps == [app])
  }

  @Test func garantitUnProfilParDefaut() {
    let storage = makeStorage()
    storage.settings.dock.pinnedApps = [app]
    ProfileSeeder.seedIfNeeded(storage)
    #expect(storage.settings.dock.profiles.count == 1)
    #expect(storage.settings.dock.profiles[0].apps == [app])
    #expect(storage.settings.dock.activeProfileID == storage.settings.dock.profiles[0].id)

    // Déjà un profil : rien n'est ajouté.
    ProfileSeeder.seedIfNeeded(storage)
    #expect(storage.settings.dock.profiles.count == 1)
  }

  @Test func lesProfilsSurvivent​AUnRelancement() throws {
    var dock = DockSettings()
    dock.profiles = [DockProfile(name: "Focus", symbol: "bolt.fill", apps: [app])]
    dock.toggleHotkey = DockHotkey(keyCode: 40, keyLabel: "K", modifiers: 4352)
    let decoded = try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(dock))
    #expect(decoded == dock)
  }

  @Test func couleurHexAllerRetour() {
    #expect(NSColor(hex: "#2E70D1").hexString == "#2E70D1")
  }
}

@MainActor
@Suite struct InstalledAppsCategoryTests {

  @Test func regroupeLesCategoriesDuLaunchpad() {
    #expect(
      InstalledApps.categoryName(for: "public.app-category.developer-tools") == "Developer Tools")
    #expect(
      InstalledApps.categoryName(for: "public.app-category.finance") == "Productivity & Finance")
    #expect(InstalledApps.categoryName(for: "public.app-category.social-networking") == "Social")
    #expect(InstalledApps.categoryName(for: nil) == "Other")
  }

  @Test func rendUnProfilActifMemeSiLIdentifiantEstInconnu() {
    let storage = makeStorage()
    storage.settings.dock.activeProfileID = "inconnu"
    ProfileSeeder.seedIfNeeded(storage)
    #expect(storage.settings.dock.activeProfile != nil)
  }
}

@MainActor
@Suite struct ProfileDockLayoutTests {

  private func app(_ id: String) -> DockPinnedApp {
    DockPinnedApp(bundleID: id, path: "/Applications/\(id).app")
  }

  private func makeModel(_ ids: [String]) -> ProfilesSettingsViewModel {
    let storage = makeStorage()
    storage.settings.dock.profiles = [DockProfile(apps: ids.map(app))]
    return ProfilesSettingsViewModel(storage: storage)
  }

  private func order(_ model: ProfilesSettingsViewModel) -> [String] {
    model.selected?.apps.map(\.bundleID) ?? []
  }

  @Test func ajouteALIndiceDonne() {
    let model = makeModel(["a", "b"])
    model.placeApp(app("c"), at: 1)
    #expect(order(model) == ["a", "c", "b"])
  }

  @Test func deplaceVersLaDroite() {
    let model = makeModel(["a", "b", "c"])
    model.placeApp(app("a"), at: 3)
    #expect(order(model) == ["b", "c", "a"])
  }

  @Test func deplaceVersLaGauche() {
    let model = makeModel(["a", "b", "c"])
    model.placeApp(app("c"), at: 0)
    #expect(order(model) == ["c", "a", "b"])
  }

  @Test func leDepotSurSaPropreFenteNeChangeRien() {
    let model = makeModel(["a", "b", "c"])
    model.placeApp(app("b"), at: 1)
    model.placeApp(app("b"), at: 2)
    #expect(order(model) == ["a", "b", "c"])
  }
}

@MainActor
@Suite struct DockDropTests {

  private func app(_ id: String) -> DockPinnedApp {
    DockPinnedApp(bundleID: id, path: "/Applications/\(id).app")
  }

  @Test func deposerDansLeProfilActifSansToucherAuxEpinglesGlobales() {
    var dock = DockSettings()
    dock.pinnedApps = [app("g")]
    let profile = DockProfile(apps: [app("a"), app("b")])
    dock.profiles = [profile]
    dock.activeProfileID = profile.id

    dock.placeApp(app("c"), at: 1)
    #expect(dock.profiles[0].apps.map(\.bundleID) == ["a", "c", "b"])
    #expect(dock.pinnedApps.map(\.bundleID) == ["g"])
  }

  @Test func sansProfilActifLesEpinglesGlobalesSontVisees() {
    var dock = DockSettings()
    dock.pinnedApps = [app("a"), app("b")]
    dock.placeApp(app("b"), at: 0)
    #expect(dock.pinnedApps.map(\.bundleID) == ["b", "a"])
    dock.unpinApp(bundleID: "a")
    #expect(dock.pinnedApps.map(\.bundleID) == ["b"])
  }

  @Test func sortirUneIconeLaRetireDuProfilActif() {
    var dock = DockSettings()
    let profile = DockProfile(apps: [app("a"), app("b")])
    dock.profiles = [profile]
    dock.activeProfileID = profile.id
    dock.unpinApp(bundleID: "a")
    #expect(dock.profiles[0].apps.map(\.bundleID) == ["b"])
  }

  @Test func lOrdreSurvitAUnRelancement() throws {
    let storage = makeStorage()
    storage.settings.dock.profiles = [DockProfile(apps: [app("a"), app("b"), app("c")])]
    storage.settings.dock.activeProfileID = storage.settings.dock.profiles[0].id
    storage.settings.dock.placeApp(app("c"), at: 0)

    let data = try JSONEncoder().encode(storage.settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    #expect(decoded.dock.visibleApps.map(\.bundleID) == ["c", "a", "b"])
  }
}
