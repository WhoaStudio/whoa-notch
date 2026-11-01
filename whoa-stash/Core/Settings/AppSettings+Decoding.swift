import Foundation

/// Décodage tolérant des préférences.
///
/// L'`init(from:)` synthétisé par Swift **lève** dès qu'une clé manque : il n'emprunte pas la
/// valeur par défaut de la propriété. Un blob écrit par une version antérieure, qui ne connaît
/// pas un réglage ajouté depuis, échouerait donc à se décoder — et comme `SettingsStorage`
/// retombe alors sur `.default`, l'utilisateur perdrait *toutes* ses préférences à chaque
/// version qui ajoute un réglage.
///
/// Chaque structure lit donc ses clés une à une, en retombant sur sa valeur par défaut quand
/// l'une manque ou n'est plus décodable (un cas d'énumération retiré, par exemple). Ajouter un
/// réglage ne casse plus rien, et en retirer un non plus.
private extension KeyedDecodingContainer {
    /// La valeur stockée sous `key`, ou `fallback` si elle est absente ou illisible.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        guard let decoded = try? decodeIfPresent(T.self, forKey: key) else { return fallback }
        return decoded ?? fallback
    }
}

extension GeneralSettings {
    enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case accentColor
        case enableAnimations
        case enableHapticFeedback
        case enableSoundFeedback
        case enableButtonSound
        case panelOpacity
        case togglePanelShortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GeneralSettings()
        self.init(
            launchAtLogin: container.value(.launchAtLogin, defaults.launchAtLogin),
            accentColor: container.value(.accentColor, defaults.accentColor),
            enableAnimations: container.value(.enableAnimations, defaults.enableAnimations),
            enableHapticFeedback: container.value(.enableHapticFeedback, defaults.enableHapticFeedback),
            enableSoundFeedback: container.value(.enableSoundFeedback, defaults.enableSoundFeedback),
            enableButtonSound: container.value(.enableButtonSound, defaults.enableButtonSound),
            panelOpacity: container.value(.panelOpacity, defaults.panelOpacity),
            togglePanelShortcut: container.value(.togglePanelShortcut, defaults.togglePanelShortcut)
        )
    }
}

extension BrightnessSettings {
    enum CodingKeys: String, CodingKey {
        case showPercentage
        case autoHideDelay
        case glowIntensity
        case scrollSensitivity
        case widgetPosition
        case widgetSize
        case enableOverlay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BrightnessSettings()
        self.init(
            showPercentage: container.value(.showPercentage, defaults.showPercentage),
            autoHideDelay: container.value(.autoHideDelay, defaults.autoHideDelay),
            glowIntensity: container.value(.glowIntensity, defaults.glowIntensity),
            scrollSensitivity: container.value(.scrollSensitivity, defaults.scrollSensitivity),
            widgetPosition: container.value(.widgetPosition, defaults.widgetPosition),
            widgetSize: container.value(.widgetSize, defaults.widgetSize),
            enableOverlay: container.value(.enableOverlay, defaults.enableOverlay)
        )
    }
}

extension EdgeSliderSettings {
    enum CodingKeys: String, CodingKey {
        case edgePosition
        case sliderHeight
        case sensitivity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = EdgeSliderSettings()
        self.init(
            edgePosition: container.value(.edgePosition, defaults.edgePosition),
            sliderHeight: container.value(.sliderHeight, defaults.sliderHeight),
            sensitivity: container.value(.sensitivity, defaults.sensitivity)
        )
    }
}

extension NotchPanelSettings {
    enum CodingKeys: String, CodingKey {
        case enabled
        case notchlessStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = NotchPanelSettings()
        self.init(
            enabled: container.value(.enabled, defaults.enabled),
            notchlessStyle: container.value(.notchlessStyle, defaults.notchlessStyle)
        )
    }
}

extension KnockSettings {
    enum CodingKeys: String, CodingKey {
        case enabled
        case single
        case double
        case sensitivity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = KnockSettings()
        self.init(
            enabled: container.value(.enabled, defaults.enabled),
            single: container.value(.single, defaults.single),
            double: container.value(.double, defaults.double),
            sensitivity: container.value(.sensitivity, defaults.sensitivity)
        )
    }
}

extension AISettings {
    enum CodingKeys: String, CodingKey {
        case desktopWatcherEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AISettings()
        self.init(desktopWatcherEnabled: container.value(.desktopWatcherEnabled, defaults.desktopWatcherEnabled))
    }
}

extension SpotifySettings {
    enum CodingKeys: String, CodingKey {
        case clientID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SpotifySettings()
        self.init(clientID: container.value(.clientID, defaults.clientID))
    }
}

extension MailSettings {
    enum CodingKeys: String, CodingKey {
        case imapEnabled
        case host
        case port
        case username
        case provider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MailSettings()
        self.init(
            imapEnabled: container.value(.imapEnabled, defaults.imapEnabled),
            host: container.value(.host, defaults.host),
            port: container.value(.port, defaults.port),
            username: container.value(.username, defaults.username),
            provider: container.value(.provider, defaults.provider)
        )
    }
}

extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case general
        case brightness
        case edgeSlider
        case notchPanel
        case knock
        case spotify
        case dock
        case radialMenu
        case ai
        case mail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        self.init(
            general: container.value(.general, defaults.general),
            brightness: container.value(.brightness, defaults.brightness),
            edgeSlider: container.value(.edgeSlider, defaults.edgeSlider),
            notchPanel: container.value(.notchPanel, defaults.notchPanel),
            knock: container.value(.knock, defaults.knock),
            spotify: container.value(.spotify, defaults.spotify),
            dock: container.value(.dock, defaults.dock),
            radialMenu: container.value(.radialMenu, defaults.radialMenu),
            ai: container.value(.ai, defaults.ai),
            mail: container.value(.mail, defaults.mail)
        )
    }
}

extension DockPinnedApp {
    enum CodingKeys: String, CodingKey {
        case bundleID
        case path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bundleID: container.value(.bundleID, ""),
            path: container.value(.path, "")
        )
    }
}

extension SavedSystemDock {
    enum CodingKeys: String, CodingKey {
        case autohide
        case autohideDelay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            autohide: container.value(.autohide, nil as Bool?),
            autohideDelay: container.value(.autohideDelay, nil as Double?)
        )
    }
}

extension DockSettings {
    enum CodingKeys: String, CodingKey {
        case enabled
        case hideSystemDock
        case pinnedApps
        case didSeedPinnedApps
        case savedSystemDock
        case toggleHotkey
        case autoHide
        case workspaces
        case activeWorkspaceID
        case launchExcluded
        case widgets
        case theme
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DockSettings()
        self.init(
            enabled: container.value(.enabled, defaults.enabled),
            hideSystemDock: container.value(.hideSystemDock, defaults.hideSystemDock),
            pinnedApps: container.value(.pinnedApps, defaults.pinnedApps),
            didSeedPinnedApps: container.value(.didSeedPinnedApps, defaults.didSeedPinnedApps),
            savedSystemDock: container.value(.savedSystemDock, defaults.savedSystemDock),
            toggleHotkey: container.value(.toggleHotkey, defaults.toggleHotkey),
            autoHide: container.value(.autoHide, defaults.autoHide),
            workspaces: container.value(.workspaces, defaults.workspaces),
            activeWorkspaceID: container.value(.activeWorkspaceID, defaults.activeWorkspaceID),
            launchExcluded: container.value(.launchExcluded, defaults.launchExcluded),
            widgets: container.value(.widgets, defaults.widgets),
            theme: container.value(.theme, defaults.theme)
        )
    }
}

extension DockWorkspace {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case symbol
        case colorHex
        case apps
        case widgets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DockWorkspace()
        self.init(
            id: container.value(.id, defaults.id),
            name: container.value(.name, defaults.name),
            symbol: container.value(.symbol, defaults.symbol),
            colorHex: container.value(.colorHex, defaults.colorHex),
            apps: container.value(.apps, defaults.apps),
            widgets: container.value(.widgets, defaults.widgets)
        )
    }
}

extension DockHotkey {
    enum CodingKeys: String, CodingKey {
        case keyCode
        case keyLabel
        case modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DockHotkey()
        self.init(
            keyCode: container.value(.keyCode, defaults.keyCode),
            keyLabel: container.value(.keyLabel, defaults.keyLabel),
            modifiers: container.value(.modifiers, defaults.modifiers)
        )
    }
}

extension RadialMenuItem {
    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
        case bundleID
        case path
    }

    /// Un type inconnu (relu d'une version future) fait lever : l'élément est alors écarté par
    /// `RadialMenuSettings`, sans perdre les autres.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.value(.id, UUID().uuidString),
            kind: try container.decode(Kind.self, forKey: .kind),
            name: container.value(.name, ""),
            bundleID: container.value(.bundleID, ""),
            path: container.value(.path, "")
        )
    }
}

extension RadialMenuSettings {
    enum CodingKeys: String, CodingKey {
        case enabled
        case button
        case items
    }

    private struct Lossy: Decodable {
        let item: RadialMenuItem?
        init(from decoder: Decoder) throws { item = try? RadialMenuItem(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = RadialMenuSettings()
        let items = ((try? container.decodeIfPresent([Lossy].self, forKey: .items)) ?? nil)?.compactMap(\.item)
        self.init(
            enabled: container.value(.enabled, defaults.enabled),
            button: container.value(.button, defaults.button),
            items: items ?? defaults.items
        )
    }
}
