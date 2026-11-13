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
extension KeyedDecodingContainer {
  /// La valeur stockée sous `key`, ou `fallback` si elle est absente ou illisible.
  fileprivate func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
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
    case volumeDialEnabled
    case sidePanelEnabled
    case showMenuBarIcon
    case autoCheckForUpdates
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
      togglePanelShortcut: container.value(.togglePanelShortcut, defaults.togglePanelShortcut),
      volumeDialEnabled: container.value(.volumeDialEnabled, defaults.volumeDialEnabled),
      sidePanelEnabled: container.value(.sidePanelEnabled, defaults.sidePanelEnabled),
      showMenuBarIcon: container.value(.showMenuBarIcon, defaults.showMenuBarIcon),
      autoCheckForUpdates: container.value(.autoCheckForUpdates, defaults.autoCheckForUpdates)
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
    case enabled
    case edgePosition
    case sliderHeight
    case sensitivity
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = EdgeSliderSettings()
    self.init(
      enabled: container.value(.enabled, defaults.enabled),
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
    case disabledTabs
    case opensOnClick
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = NotchPanelSettings()
    self.init(
      enabled: container.value(.enabled, defaults.enabled),
      notchlessStyle: container.value(.notchlessStyle, defaults.notchlessStyle),
      disabledTabs: container.value(.disabledTabs, defaults.disabledTabs),
      opensOnClick: container.value(.opensOnClick, defaults.opensOnClick)
    )
  }
}

extension AISettings {
  enum CodingKeys: String, CodingKey {
    case desktopWatcherEnabled
    case stopReplyEnabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = AISettings()
    self.init(
      desktopWatcherEnabled: container.value(.desktopWatcherEnabled, defaults.desktopWatcherEnabled),
      stopReplyEnabled: container.value(.stopReplyEnabled, defaults.stopReplyEnabled)
    )
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

extension ColorPickerSettings {
  enum CodingKeys: String, CodingKey {
    case recent, saved, format
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = ColorPickerSettings()
    self.init(
      recent: container.value(.recent, defaults.recent),
      saved: container.value(.saved, defaults.saved),
      format: container.value(.format, defaults.format))
  }
}

extension AppSettings {
  enum CodingKeys: String, CodingKey {
    case general
    case brightness
    case edgeSlider
    case notchPanel
    case spotify
    case dock
    case radialMenu
    case ai
    case mail
    case colorPicker
    case hasSeenOnboarding
    case lastSettingsPane
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = AppSettings()
    self.init(
      general: container.value(.general, defaults.general),
      brightness: container.value(.brightness, defaults.brightness),
      edgeSlider: container.value(.edgeSlider, defaults.edgeSlider),
      notchPanel: container.value(.notchPanel, defaults.notchPanel),
      spotify: container.value(.spotify, defaults.spotify),
      dock: container.value(.dock, defaults.dock),
      radialMenu: container.value(.radialMenu, defaults.radialMenu),
      ai: container.value(.ai, defaults.ai),
      mail: container.value(.mail, defaults.mail),
      colorPicker: container.value(.colorPicker, defaults.colorPicker),
      hasSeenOnboarding: container.value(.hasSeenOnboarding, defaults.hasSeenOnboarding),
      lastSettingsPane: container.value(.lastSettingsPane, defaults.lastSettingsPane)
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
    case profiles
    case activeProfileID
    case launchExcluded
    case widgets
    case theme
    case magnification
    case dockSize
    case widgetSpacing
    case cornerRadius
    case dockShadow
    case screenMode
    case detachedDisplays
    case monochromeWidgets
    case tileBackgrounds
    case reduceTransparency
    case grayscaleIcons
    case adaptsToFit
  }

  /// Clés d'avant le renommage « espace » → « profil », lues seulement en repli.
  private enum LegacyCodingKeys: String, CodingKey {
    case workspaces
    case activeWorkspaceID
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = DockSettings()
    // Migration : avant les profils, ils s'appelaient « espaces » (`workspaces`). Les nouvelles
    // clés priment ; l'ancien `colorHex` des profils est simplement ignoré au décodage.
    let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
    let profiles: [DockProfile] =
      container.contains(.profiles)
      ? container.value(.profiles, defaults.profiles)
      : legacy.value(.workspaces, defaults.profiles)
    let activeProfileID: String? =
      container.contains(.activeProfileID)
      ? container.value(.activeProfileID, defaults.activeProfileID)
      : legacy.value(.activeWorkspaceID, defaults.activeProfileID)
    self.init(
      enabled: container.value(.enabled, defaults.enabled),
      hideSystemDock: container.value(.hideSystemDock, defaults.hideSystemDock),
      pinnedApps: container.value(.pinnedApps, defaults.pinnedApps),
      didSeedPinnedApps: container.value(.didSeedPinnedApps, defaults.didSeedPinnedApps),
      savedSystemDock: container.value(.savedSystemDock, defaults.savedSystemDock),
      toggleHotkey: container.value(.toggleHotkey, defaults.toggleHotkey),
      autoHide: container.value(.autoHide, defaults.autoHide),
      profiles: profiles,
      activeProfileID: activeProfileID,
      launchExcluded: container.value(.launchExcluded, defaults.launchExcluded),
      widgets: container.value(.widgets, defaults.widgets),
      theme: container.value(.theme, defaults.theme),
      magnification: container.value(.magnification, defaults.magnification),
      dockSize: container.value(.dockSize, defaults.dockSize),
      widgetSpacing: container.value(.widgetSpacing, defaults.widgetSpacing),
      cornerRadius: container.value(.cornerRadius, defaults.cornerRadius),
      dockShadow: container.value(.dockShadow, defaults.dockShadow),
      monochromeWidgets: container.value(.monochromeWidgets, defaults.monochromeWidgets),
      tileBackgrounds: container.value(.tileBackgrounds, defaults.tileBackgrounds),
      reduceTransparency: container.value(.reduceTransparency, defaults.reduceTransparency),
      grayscaleIcons: container.value(.grayscaleIcons, defaults.grayscaleIcons),
      adaptsToFit: container.value(.adaptsToFit, defaults.adaptsToFit),
      screenMode: container.value(.screenMode, defaults.screenMode),
      detachedDisplays: container.value(.detachedDisplays, defaults.detachedDisplays)
    )
  }
}

extension DockProfile {
  enum CodingKeys: String, CodingKey {
    case id
    case name
    case symbol
    case apps
    case widgets
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = DockProfile()
    self.init(
      id: container.value(.id, defaults.id),
      name: container.value(.name, defaults.name),
      symbol: container.value(.symbol, defaults.symbol),
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
    let items = ((try? container.decodeIfPresent([Lossy].self, forKey: .items)) ?? nil)?.compactMap(
      \.item)
    self.init(
      enabled: container.value(.enabled, defaults.enabled),
      button: container.value(.button, defaults.button),
      items: items ?? defaults.items
    )
  }
}
