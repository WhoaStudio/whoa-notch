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

/// Un espace de travail : un jeu d'applis, avec un nom, un logo (symbole SF) et une couleur.
struct DockWorkspace: Codable, Equatable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var name: String = "Workspace"
    var symbol: String = "square.grid.2x2.fill"
    var colorHex: String = "#2E70D1"
    var apps: [DockPinnedApp] = []
    var widgets: [DockWidgetPlacement] = []

    /// Pose un widget au bout de la rangée de l'espace.
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

/// Ce que le groupe de gauche du dock affiche : les espaces et celui qui est actif.
struct DockWorkspaceState: Equatable {
    var list: [DockWorkspace]
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
    var workspaces: [DockWorkspace] = []
    /// `nil` = « All Apps » : les épingles globales.
    var activeWorkspaceID: String?
    /// Identifiants des applis gardées dans la liste mais ignorées par « Launch all ».
    var launchExcluded: [String] = []
    /// Les widgets du dock quand aucun espace n'est actif (« All Apps »). Chaque espace a les siens.
    var widgets: [DockWidgetPlacement] = []
    /// Fond du dock : `dark` (d'origine) ou `liquidGlass`.
    var theme: DockTheme = .dark
    /// Agrandissement des icônes sous le curseur. La taille agrandie reste celle du Dock macOS.
    var magnification: Bool = true

    /// Les applis que « Launch all » ouvre : la liste moins les exclues.
    var launchApps: [DockPinnedApp] { pinnedApps.filter { !launchExcluded.contains($0.bundleID) } }

    var activeWorkspace: DockWorkspace? {
        activeWorkspaceID.flatMap { id in workspaces.first { $0.id == id } }
    }

    /// Les applis épinglées affichées : celles de l'espace actif, sinon les épingles globales.
    var visibleApps: [DockPinnedApp] { activeWorkspace?.apps ?? pinnedApps }

    /// Les widgets affichés : ceux de l'espace actif, sinon les globaux.
    var visibleWidgets: [DockWidgetPlacement] { activeWorkspace?.widgets ?? widgets }

    /// Remplace les widgets de la liste affichée (l'espace actif, sinon les globaux).
    mutating func setVisibleWidgets(_ placements: [DockWidgetPlacement]) {
        if let id = activeWorkspaceID, let position = workspaces.firstIndex(where: { $0.id == id }) {
            workspaces[position].widgets = placements
        } else {
            widgets = placements
        }
    }

    /// Place une appli dans la liste affichée (l'espace actif, sinon les épingles globales).
    mutating func placeApp(_ app: DockPinnedApp, at index: Int) {
        if let id = activeWorkspaceID, let position = workspaces.firstIndex(where: { $0.id == id }) {
            workspaces[position].apps.place(app, at: index)
        } else {
            pinnedApps.place(app, at: index)
        }
    }

    mutating func unpinApp(bundleID: String) {
        if let id = activeWorkspaceID, let position = workspaces.firstIndex(where: { $0.id == id }) {
            workspaces[position].apps.removeAll { $0.bundleID == bundleID }
        } else {
            pinnedApps.removeAll { $0.bundleID == bundleID }
        }
    }

    /// Pose un widget au bout de la rangée affichée (l'espace actif, sinon les globaux).
    mutating func addVisibleWidget(kind: String) {
        if let id = activeWorkspaceID, let position = workspaces.firstIndex(where: { $0.id == id }) {
            workspaces[position].addWidget(kind: kind)
        } else {
            widgets.append(DockWidgetPlacement(kind: kind, index: pinnedApps.count + widgets.count))
        }
    }

    /// Épingle ou désépingle dans la liste affichée (l'espace actif, sinon les épingles globales).
    mutating func togglePin(_ app: DockPinnedApp) {
        func toggle(_ apps: inout [DockPinnedApp]) {
            if let index = apps.firstIndex(where: { $0.bundleID == app.bundleID }) {
                apps.remove(at: index)
            } else {
                apps.append(app)
            }
        }
        if let id = activeWorkspaceID, let index = workspaces.firstIndex(where: { $0.id == id }) {
            toggle(&workspaces[index].apps)
        } else {
            toggle(&pinnedApps)
        }
    }
}
