import Combine
import Foundation
import OSLog

/// Vérifie si une version plus récente est publiée. Une vérification manuelle (`checkNow`) et une
/// vérification automatique : au lancement puis toutes les 24 h, tant que le réglage
/// `autoCheckForUpdates` est actif. Décocher le réglage arrête le minuteur. L'app n'installe rien :
/// elle indique la version et ouvre la page de la release.
@MainActor
final class UpdateChecker: ObservableObject {

  enum Status: Equatable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case failed
  }

  static let shared = UpdateChecker()

  @Published private(set) var status: Status = .idle

  private let provider: ReleaseProviding
  private let storage: SettingsStorage
  private let currentVersion: String
  private let interval: TimeInterval
  private var timer: Timer?
  private var cancellable: AnyCancellable?

  init(
    provider: ReleaseProviding = MockReleaseProvider.fromLaunchArguments()
      ?? GitHubReleaseProvider(),
    storage: SettingsStorage = .shared,
    currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
      as? String ?? "0",
    interval: TimeInterval = 24 * 60 * 60
  ) {
    self.provider = provider
    self.storage = storage
    self.currentVersion = currentVersion
    self.interval = interval
  }

  /// Suit le réglage : l'abonnement émet la valeur courante tout de suite, ce qui déclenche la
  /// vérification du lancement quand le réglage est actif.
  func start() {
    cancellable = storage.$settings
      .map(\.general.autoCheckForUpdates)
      .removeDuplicates()
      .sink { [weak self] in self?.setAutomatic($0) }
  }

  func checkNow() {
    Task { await check(automatic: false) }
  }

  private func setAutomatic(_ enabled: Bool) {
    timer?.invalidate()
    timer = nil
    guard enabled else {
      Log.updates.info("Vérification automatique des mises à jour désactivée")
      return
    }
    Log.updates.info(
      "Vérification automatique des mises à jour activée (toutes les \(self.interval, privacy: .public) s)"
    )
    Task { await check(automatic: true) }
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.check(automatic: true) }
    }
  }

  private func check(automatic: Bool) async {
    guard status != .checking else { return }
    status = .checking
    Log.updates.info("Vérification des mises à jour (automatique : \(automatic, privacy: .public))")
    do {
      let release = try await provider.latestRelease()
      if AppVersion.isNewer(release.version, than: currentVersion) {
        Log.updates.info("Mise à jour disponible : \(release.version, privacy: .public)")
        status = .available(release)
      } else {
        Log.updates.info(
          "Aucune mise à jour : version \(self.currentVersion, privacy: .public) à jour")
        status = .upToDate
      }
    } catch {
      Log.updates.error(
        "Échec de la vérification des mises à jour : \(error.localizedDescription, privacy: .public)"
      )
      status = .failed
    }
  }
}
