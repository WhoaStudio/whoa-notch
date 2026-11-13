import Combine
import Foundation

/// Expose la section "General" à sa vue. Toute écriture passe par `SettingsStorage` ; l'effet
/// de bord système du lancement au démarrage est délégué à `LaunchAtLoginService`, jamais
/// déclenché depuis la vue.
@MainActor
final class GeneralSettingsViewModel: ObservableObject {

  private let storage: SettingsStorage
  private let launchAtLoginService: LaunchAtLoginService
  private var cancellable: AnyCancellable?
  private var notchPanelCancellable: AnyCancellable?
  private var edgeSliderCancellable: AnyCancellable?
  private var spotifyCancellable: AnyCancellable?
  private var spotifyStatusCancellable: AnyCancellable?

  @Published private(set) var settings: GeneralSettings
  /// Le panneau de l'encoche n'a pas de section à lui : son unique réglage est présenté
  /// dans « General », d'où ce second flux à côté de `settings`.
  @Published private(set) var notchPanel: NotchPanelSettings
  @Published private(set) var edgeSlider: EdgeSliderSettings
  /// Compte Spotify de la colonne « Playing Next », présenté lui aussi dans « General ».
  @Published private(set) var spotify: SpotifySettings
  @Published private(set) var spotifyStatus: SpotifyAccount.Status

  init(storage: SettingsStorage = .shared, launchAtLoginService: LaunchAtLoginService = .shared) {
    self.storage = storage
    self.launchAtLoginService = launchAtLoginService
    self.settings = storage.settings.general
    self.notchPanel = storage.settings.notchPanel
    self.edgeSlider = storage.settings.edgeSlider
    self.spotify = storage.settings.spotify
    self.spotifyStatus = SpotifyAccount.shared.status

    cancellable = storage.$settings
      .map(\.general)
      .removeDuplicates()
      .sink { [weak self] in self?.settings = $0 }

    edgeSliderCancellable = storage.$settings
      .map(\.edgeSlider)
      .removeDuplicates()
      .sink { [weak self] in self?.edgeSlider = $0 }

    notchPanelCancellable = storage.$settings
      .map(\.notchPanel)
      .removeDuplicates()
      .sink { [weak self] in self?.notchPanel = $0 }

    spotifyCancellable = storage.$settings
      .map(\.spotify)
      .removeDuplicates()
      .sink { [weak self] in self?.spotify = $0 }

    spotifyStatusCancellable = SpotifyAccount.shared.$status
      .sink { [weak self] in self?.spotifyStatus = $0 }
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    guard settings.launchAtLogin != enabled else { return }
    storage.settings.general.launchAtLogin = enabled
    launchAtLoginService.setEnabled(enabled)
  }

  func setAutoCheckForUpdates(_ enabled: Bool) {
    storage.settings.general.autoCheckForUpdates = enabled
  }

  func setShowMenuBarIcon(_ show: Bool) {
    storage.settings.general.showMenuBarIcon = show
  }

  func setAccentColor(_ color: AccentColor) {
    storage.settings.general.accentColor = color
  }

  func setEnableAnimations(_ enabled: Bool) {
    storage.settings.general.enableAnimations = enabled
  }

  func setEnableHapticFeedback(_ enabled: Bool) {
    storage.settings.general.enableHapticFeedback = enabled
  }

  func setEnableSoundFeedback(_ enabled: Bool) {
    storage.settings.general.enableSoundFeedback = enabled
  }

  func setEnableButtonSound(_ enabled: Bool) {
    storage.settings.general.enableButtonSound = enabled
  }

  func setVolumeDialEnabled(_ enabled: Bool) {
    storage.settings.general.volumeDialEnabled = enabled
  }

  func setSidePanelEnabled(_ enabled: Bool) {
    storage.settings.general.sidePanelEnabled = enabled
  }

  func setEdgeSliderEnabled(_ enabled: Bool) {
    storage.settings.edgeSlider.enabled = enabled
  }

  func setTab(_ tab: NotchTab, enabled: Bool) {
    var names = storage.settings.notchPanel.disabledTabs.filter { $0 != tab.title }
    if !enabled { names.append(tab.title) }
    storage.settings.notchPanel.disabledTabs = names
  }

  func setNotchPanelEnabled(_ enabled: Bool) {
    storage.settings.notchPanel.enabled = enabled
  }

  func setOpensOnClick(_ on: Bool) {
    storage.settings.notchPanel.opensOnClick = on
  }

  func setNotchlessStyle(_ style: NotchPanelStyle) {
    storage.settings.notchPanel.notchlessStyle = style
  }

  func setSpotifyClientID(_ clientID: String) {
    let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard storage.settings.spotify.clientID != trimmed else { return }
    storage.settings.spotify.clientID = trimmed
  }

  func connectSpotify() {
    SpotifyAccount.shared.connect(clientID: spotify.clientID)
  }

  func disconnectSpotify() {
    SpotifyAccount.shared.disconnect()
  }

  func setPanelOpacity(_ opacity: Double) {
    storage.settings.general.panelOpacity = opacity
  }

  func setTogglePanelShortcut(_ shortcut: GlobalShortcut) {
    storage.settings.general.togglePanelShortcut = shortcut
  }

  /// Remet tout à zéro, y compris l'effet de bord système : `resetToDefaults` ne touche que le
  /// modèle, donc le lancement au démarrage doit être désenregistré explicitement.
  func resetToDefaults() {
    let wasLaunchingAtLogin = settings.launchAtLogin
    storage.resetToDefaults()
    if wasLaunchingAtLogin != AppSettings.default.general.launchAtLogin {
      launchAtLoginService.setEnabled(AppSettings.default.general.launchAtLogin)
    }
  }
}
