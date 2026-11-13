import Foundation

/// Une appli épinglée dans le dock : l'identifiant du bundle sert de clé, l'URL de repli quand
/// le bundle n'est pas résolvable par son identifiant (appli déplacée, web app sans identifiant
/// connu de Launch Services).
struct DockPinnedApp: Codable, Equatable, Hashable, Sendable {
  var bundleID: String
  var path: String
}

extension DockPinnedApp {
  /// Lit l'identifiant dans le bundle ; `nil` si ce n'est pas une appli lisible.
  init?(appURL: URL) {
    guard appURL.pathExtension == "app",
      let bundleID = Bundle(url: appURL)?.bundleIdentifier, !bundleID.isEmpty
    else { return nil }
    self.init(bundleID: bundleID, path: appURL.path)
  }
}

/// Valeurs d'origine du Dock macOS avant que l'app ne le masque. `nil` = la clé n'existait pas :
/// elle doit être *supprimée* à la restauration, pas réécrite avec une valeur par défaut, sans
/// quoi `defaults read com.apple.dock` ne reviendrait pas à l'identique.
struct SavedSystemDock: Codable, Equatable, Sendable {
  var autohide: Bool?
  var autohideDelay: Double?
}

/// Un profil : un jeu d'applis, avec un nom, et un logo (symbole SF).
struct DockProfile: Codable, Equatable, Identifiable, Sendable {
  var id: String = UUID().uuidString
  var name: String = "Profile"
  var symbol: String = "square.grid.2x2.fill"
  var apps: [DockPinnedApp] = []
  var widgets: [DockWidgetPlacement] = []

  /// Pose un widget au bout de la rangée du profil.
  mutating func addWidget(kind: String) {
    widgets.append(DockWidgetPlacement(kind: kind, index: apps.count + widgets.count))
  }

  mutating func removeWidget(id: String) {
    widgets.removeAll { $0.id == id }
  }
}

/// Un widget posé dans le dock : son type (clé du registre) et sa place dans la rangée d'icônes.
struct DockWidgetPlacement: Codable, Equatable, Identifiable, Sendable {
  var id: String = UUID().uuidString
  var kind: String
  /// Position dans la rangée d'icônes (applis et widgets mêlés), à partir de 0.
  var index: Int
}

/// Raccourci libre du dock : une touche et des modificateurs au format Carbon (`cmdKey`…).
struct DockHotkey: Codable, Equatable, Sendable {
  var keyCode: UInt32?
  /// Texte de la touche tel qu'affiché (« K », « Space »).
  var keyLabel: String = ""
  var modifiers: UInt32 = 0

  var isSet: Bool { keyCode != nil && modifiers != 0 }
}

extension Array where Element == DockPinnedApp {
  /// Met l'appli à `index` — la déplace si elle y est déjà, l'ajoute sinon. `index` est exprimé
  /// dans la liste d'avant le déplacement.
  mutating func place(_ app: DockPinnedApp, at index: Int) {
    var target = index
    if let existing = firstIndex(where: { $0.bundleID == app.bundleID }) {
      remove(at: existing)
      if existing < target { target -= 1 }
    }
    insert(app, at: Swift.max(0, Swift.min(target, count)))
  }
}

/// Sur quels écrans le dock apparaît. `one` : seulement sur le premier écran attaché de la liste ;
/// `attached` : sur les écrans attachés, en suivant le curseur ; `all` : un dock fixe sur chaque
/// écran attaché.
enum DockScreenMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case one
  case attached
  case all

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .one: return "One Display"
    case .attached: return "Attached Displays"
    case .all: return "All Displays"
    }
  }
}

/// Ce que le groupe de gauche du dock affiche : les profils et celui qui est actif.
struct DockProfileState: Equatable {
  var list: [DockProfile]
  var activeID: String?
}

struct DockSettings: Codable, Equatable, Sendable {
  var enabled: Bool = true
  /// Réglage « Hide macOS Dock » : Dock système en masquage auto avec un très long délai.
  var hideSystemDock: Bool = false
  var pinnedApps: [DockPinnedApp] = []
  /// Vrai une fois les épingles copiées depuis `com.apple.dock` : on ne relit plus jamais.
  var didSeedPinnedApps: Bool = false
  /// Présent seulement tant que le Dock système est masqué par nous.
  var savedSystemDock: SavedSystemDock?
  var toggleHotkey = DockHotkey()
  /// Le dock se retire et ne revient qu'au contact de la zone sensible du bord du bas.
  var autoHide: Bool = true
  var profiles: [DockProfile] = []
  /// `nil` = « All Apps » : les épingles globales.
  var activeProfileID: String?
  /// Identifiants des applis gardées dans la liste mais ignorées par « Launch all ».
  var launchExcluded: [String] = []
  /// Les widgets du dock quand aucun profil n'est actif (« All Apps »). Chaque profil a les siens.
  var widgets: [DockWidgetPlacement] = []
  /// Fond du dock : `dark` (d'origine) ou `liquidGlass`.
  var theme: DockTheme = .dark
  /// Agrandissement des icônes sous le curseur. La taille agrandie reste celle du Dock macOS.
  var magnification: Bool = true
  /// Taille du dock en pourcentage de la taille d'icône du Dock macOS (50 à 150).
  var dockSize: Double = 100
  /// Écart entre les icônes et les widgets, en points de référence (0 à 16).
  var widgetSpacing: Double = 8
  /// Rayon des coins de la capsule, en points de référence (0 à 24).
  var cornerRadius: Double = 14
  /// Ombre portée sous la capsule du dock.
  var dockShadow: Bool = false
  /// Widgets en niveaux de gris (sans couleurs d'accent).
  var monochromeWidgets: Bool = false
  /// Fond et bordure discrets derrière chaque icône.
  var tileBackgrounds: Bool = false
  /// Fond de la capsule plein, sans transparence.
  var reduceTransparency: Bool = false
  /// Icônes d'applis en niveaux de gris.
  var grayscaleIcons: Bool = false
  /// Quand la rangée est plus large que l'écran, réduire les icônes pour qu'elle tienne.
  var adaptsToFit: Bool = true
  /// Écrans où le dock peut apparaître (voir `DockScreenMode`).
  var screenMode: DockScreenMode = .attached
  /// Identifiants des écrans décochés « Attached » : le dock ne s'y affiche jamais.
  var detachedDisplays: [String] = []

  /// Réglages d'apparence transmis au dock (section Appearance).
  var style: DockStyle {
    DockStyle(
      sizePercent: dockSize, widgetSpacing: CGFloat(widgetSpacing),
      cornerRadius: CGFloat(cornerRadius), shadow: dockShadow,
      monochromeWidgets: monochromeWidgets, tileBackgrounds: tileBackgrounds,
      reduceTransparency: reduceTransparency, grayscaleIcons: grayscaleIcons,
      adaptsToFit: adaptsToFit)
  }

  /// Les applis que « Launch all » ouvre : la liste moins les exclues.
  var launchApps: [DockPinnedApp] { pinnedApps.filter { !launchExcluded.contains($0.bundleID) } }

  var activeProfile: DockProfile? {
    activeProfileID.flatMap { id in profiles.first { $0.id == id } }
  }

  /// Les applis épinglées affichées : celles du profil actif, sinon les épingles globales.
  var visibleApps: [DockPinnedApp] { activeProfile?.apps ?? pinnedApps }

  /// Les widgets affichés : ceux du profil actif, sinon les globaux.
  var visibleWidgets: [DockWidgetPlacement] { activeProfile?.widgets ?? widgets }

  /// Remplace les widgets de la liste affichée (le profil actif, sinon les globaux).
  mutating func setVisibleWidgets(_ placements: [DockWidgetPlacement]) {
    if let id = activeProfileID, let position = profiles.firstIndex(where: { $0.id == id }) {
      profiles[position].widgets = placements
    } else {
      widgets = placements
    }
  }

  /// Place une appli dans la liste affichée (le profil actif, sinon les épingles globales).
  mutating func placeApp(_ app: DockPinnedApp, at index: Int) {
    if let id = activeProfileID, let position = profiles.firstIndex(where: { $0.id == id }) {
      profiles[position].apps.place(app, at: index)
    } else {
      pinnedApps.place(app, at: index)
    }
  }

  mutating func unpinApp(bundleID: String) {
    if let id = activeProfileID, let position = profiles.firstIndex(where: { $0.id == id }) {
      profiles[position].apps.removeAll { $0.bundleID == bundleID }
    } else {
      pinnedApps.removeAll { $0.bundleID == bundleID }
    }
  }

  /// Pose un widget au bout de la rangée affichée (le profil actif, sinon les globaux).
  mutating func addVisibleWidget(kind: String) {
    if let id = activeProfileID, let position = profiles.firstIndex(where: { $0.id == id }) {
      profiles[position].addWidget(kind: kind)
    } else {
      widgets.append(DockWidgetPlacement(kind: kind, index: pinnedApps.count + widgets.count))
    }
  }

  /// Épingle ou désépingle une appli dans les épingles globales (section Dock, sélecteur d'applis).
  mutating func togglePinned(_ app: DockPinnedApp, selected: Bool) {
    pinnedApps.removeAll { $0.bundleID == app.bundleID }
    if selected { pinnedApps.append(app) }
    launchExcluded.removeAll { $0 == app.bundleID }
  }

  /// Épingle ou désépingle dans la liste affichée (le profil actif, sinon les épingles globales).
  mutating func togglePin(_ app: DockPinnedApp) {
    func toggle(_ apps: inout [DockPinnedApp]) {
      if let index = apps.firstIndex(where: { $0.bundleID == app.bundleID }) {
        apps.remove(at: index)
      } else {
        apps.append(app)
      }
    }
    if let id = activeProfileID, let index = profiles.firstIndex(where: { $0.id == id }) {
      toggle(&profiles[index].apps)
    } else {
      toggle(&pinnedApps)
    }
  }
}
