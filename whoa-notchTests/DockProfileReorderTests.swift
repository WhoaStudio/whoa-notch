import Foundation
import Testing

@testable import whoa_notch

/// Réorganiser, ajouter et retirer les applis et les widgets d'un profil, comme la maquette de
/// Préférences le fait : une seule rangée où ils se mêlent.
@MainActor
@Suite struct DockProfileReorderTests {

  private func app(_ id: String) -> DockPinnedApp {
    DockPinnedApp(bundleID: id, path: "/Applications/\(id).app")
  }

  /// Un profil dont la rangée est `layout` : un nom en minuscule est une appli, `*nom` un widget
  /// de ce nom (son identifiant de placement).
  private func profile(_ layout: [String]) -> DockProfile {
    var profile = DockProfile(id: "p")
    for (position, name) in layout.enumerated() {
      if name.hasPrefix("*") {
        profile.widgets.append(
          DockWidgetPlacement(id: String(name.dropFirst()), kind: "battery", index: position))
      } else {
        profile.apps.append(app(name))
      }
    }
    return profile
  }

  private func ids(_ row: [DockRowEntry]) -> [String] { row.map(\.id) }

  private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "dock-reorder-tests-\(UUID().uuidString)")!
  }

  private func makeModel(_ profile: DockProfile, defaults: UserDefaults? = nil)
    -> ProfilesSettingsViewModel
  {
    let storage = SettingsStorage(defaults: defaults ?? makeDefaults())
    storage.settings.dock.profiles = [profile]
    return ProfilesSettingsViewModel(storage: storage)
  }

  // MARK: - Déplacement

  @Test("déplacer vers la droite : l'indice est compté sans la case levée")
  func moveRight() {
    var profile = profile(["a", "b", "c"])
    let moved = profile.moveEntry("a", toRemainingIndex: 2)
    #expect(moved)
    #expect(ids(profile.row) == ["b", "c", "a"])
  }

  @Test("déplacer vers la gauche")
  func moveLeft() {
    var profile = profile(["a", "b", "c"])
    profile.moveEntry("c", toRemainingIndex: 0)
    #expect(ids(profile.row) == ["c", "a", "b"])
  }

  @Test("lâcher une case à sa place ne change rien")
  func moveOntoOwnSlot() {
    var profile = profile(["a", "b", "c"])
    profile.moveEntry("b", toRemainingIndex: 1)
    #expect(ids(profile.row) == ["a", "b", "c"])
  }

  @Test("un indice hors de la rangée est borné")
  func moveClampsIndex() {
    var profile = profile(["a", "b", "c"])
    profile.moveEntry("a", toRemainingIndex: 99)
    #expect(ids(profile.row) == ["b", "c", "a"])
    profile.moveEntry("a", toRemainingIndex: -4)
    #expect(ids(profile.row) == ["a", "b", "c"])
  }

  @Test("déplacer une case absente ne fait rien")
  func moveUnknown() {
    var profile = profile(["a", "b"])
    let moved = profile.moveEntry("z", toRemainingIndex: 0)
    #expect(!moved)
    #expect(ids(profile.row) == ["a", "b"])
  }

  @Test("un widget se déplace entre les applis, qui gardent leur ordre")
  func moveWidgetAmongApps() {
    var profile = profile(["a", "*w", "b", "c"])
    profile.moveEntry("w", toRemainingIndex: 2)
    #expect(ids(profile.row) == ["a", "b", "w", "c"])
    #expect(profile.apps.map(\.bundleID) == ["a", "b", "c"])
    #expect(profile.widgets.map(\.index) == [2])
  }

  @Test("une appli qui passe un widget le décale dans la rangée")
  func moveAppPastWidget() {
    var profile = profile(["a", "*w", "b"])
    profile.moveEntry("a", toRemainingIndex: 2)
    #expect(ids(profile.row) == ["w", "b", "a"])
    #expect(profile.widgets.map(\.index) == [0])
  }

  // MARK: - Insertion

  @Test("insérer une appli à l'indice du dépôt décale les widgets suivants")
  func insertApp() {
    var profile = profile(["a", "*w"])
    let inserted = profile.insertApp(app("x"), atRowIndex: 1)
    #expect(inserted)
    #expect(ids(profile.row) == ["a", "x", "w"])
    #expect(profile.widgets.map(\.index) == [2])
  }

  @Test("insérer au bout, au début et dans une rangée vide")
  func insertAtEnds() {
    var profile = DockProfile(id: "p")
    profile.insertApp(app("a"), atRowIndex: 0)
    profile.insertApp(app("b"), atRowIndex: 5)
    profile.insertApp(app("c"), atRowIndex: -1)
    #expect(ids(profile.row) == ["c", "a", "b"])
  }

  @Test("une appli déjà présente n'est pas dupliquée")
  func insertIgnoresDuplicate() {
    var profile = profile(["a", "b"])
    let inserted = profile.insertApp(app("a"), atRowIndex: 1)
    #expect(!inserted)
    #expect(ids(profile.row) == ["a", "b"])
  }

  @Test("insérer un widget à l'indice du dépôt")
  func insertWidget() {
    var profile = profile(["a", "b"])
    profile.insertWidget(kind: "battery", atRowIndex: 1)
    #expect(profile.widgets.count == 1)
    #expect(profile.widgets[0].index == 1)
    #expect(profile.row[1].id == profile.widgets[0].id)
    #expect(profile.apps.map(\.bundleID) == ["a", "b"])
  }

  @Test("deux widgets du même type ont chacun leur identifiant")
  func insertTwoWidgets() {
    var profile = DockProfile(id: "p")
    profile.insertWidget(kind: "battery", atRowIndex: 0)
    profile.insertWidget(kind: "battery", atRowIndex: 0)
    #expect(Set(profile.widgets.map(\.id)).count == 2)
  }

  // MARK: - Retrait

  @Test("retirer une appli laisse les widgets à leur place dans la rangée")
  func removeApp() {
    var profile = profile(["a", "*w", "b"])
    let removed = profile.removeEntry("a")
    #expect(removed)
    #expect(ids(profile.row) == ["w", "b"])
    #expect(profile.widgets.map(\.index) == [0])
    let again = profile.removeEntry("a")
    #expect(!again)
  }

  @Test("retirer un widget")
  func removeWidget() {
    var profile = profile(["a", "*w", "b"])
    profile.removeEntry("w")
    #expect(ids(profile.row) == ["a", "b"])
    #expect(profile.widgets.isEmpty)
  }

  // MARK: - Profil et persistance

  @Test("le view model déplace, ajoute et retire dans le profil choisi")
  func viewModelOperations() {
    let model = makeModel(profile(["a", "b", "*w"]))
    model.moveEntry("w", toRemainingIndex: 0)
    #expect(model.selected?.row.map(\.id) == ["w", "a", "b"])
    model.insertApp(app("d"), atRowIndex: 2)
    #expect(model.selected?.row.map(\.id) == ["w", "a", "d", "b"])
    model.removeEntry("a")
    #expect(model.selected?.row.map(\.id) == ["w", "d", "b"])
  }

  @Test("cocher et décocher une appli du sélecteur garde les widgets en place")
  func pickerToggleKeepsWidgets() {
    let model = makeModel(profile(["a", "*w", "b"]))
    model.setApp(app("a"), selected: false)
    #expect(model.selected?.row.map(\.id) == ["w", "b"])
    model.setApp(app("c"), selected: true)
    #expect(model.selected?.row.map(\.id) == ["w", "b", "c"])
  }

  @Test("le nouvel ordre, widgets compris, survit à un redémarrage")
  func orderPersists() {
    let defaults = makeDefaults()
    let model = makeModel(profile(["a", "b", "c", "*w"]), defaults: defaults)
    model.moveEntry("a", toRemainingIndex: 2)
    model.insertApp(app("d"), atRowIndex: 0)
    model.removeEntry("b")
    model.insertWidget(kind: "storage", atRowIndex: 1)

    let reloaded = SettingsStorage(defaults: defaults).settings.dock.profiles.first
    #expect(reloaded?.apps.map(\.bundleID) == ["d", "c", "a"])
    #expect(reloaded?.widgets.count == 2)
    #expect(reloaded?.row.map(\.id) == model.selected?.row.map(\.id))
  }

  @Test("les autres profils ne bougent pas")
  func otherProfilesUntouched() {
    let storage = SettingsStorage(defaults: makeDefaults())
    var other = profile(["x", "y"])
    other.id = "q"
    storage.settings.dock.profiles = [profile(["a", "b"]), other]
    let model = ProfilesSettingsViewModel(storage: storage)
    model.selectedID = "p"
    model.moveEntry("a", toRemainingIndex: 1)
    #expect(storage.settings.dock.profiles[1].apps.map(\.bundleID) == ["x", "y"])
  }

  @Test("le drapeau d'exemple donne un profil de cinq applis et un widget, sans lui rien")
  func sampleLaunchFlag() {
    #expect(ProfilesSettingsViewModel.fromLaunchArguments(["whoa-notch"]) == nil)
    let model = ProfilesSettingsViewModel.fromLaunchArguments([
      "whoa-notch", "--profile-apps=sample",
    ])
    #expect(model?.selected?.apps.count == 5)
    #expect(model?.selected?.widgets.count == 1)
    model?.removeEntry("com.apple.Safari")
    #expect(model?.selected?.apps.count == 4)
  }
}
