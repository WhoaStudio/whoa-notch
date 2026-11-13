import Combine
import Foundation
import OSLog

/// Expose le volet « Mail » à sa vue : le compte IMAP, l'état du mot de passe au trousseau et l'essai
/// de connexion.
@MainActor
final class MailSettingsViewModel: ObservableObject {

  private let storage: SettingsStorage
  private var cancellable: AnyCancellable?

  @Published private(set) var settings: MailSettings
  @Published private(set) var hasPassword = false
  /// Résultat du dernier essai ou de la dernière sauvegarde ; vide au départ.
  @Published private(set) var status = ""
  @Published private(set) var statusIsError = false
  @Published private(set) var isTesting = false

  init(storage: SettingsStorage = .shared) {
    self.storage = storage
    self.settings = storage.settings.mail
    cancellable = storage.$settings
      .map(\.mail)
      .removeDuplicates()
      .sink { [weak self] in
        self?.settings = $0
        self?.refreshPasswordState()
      }
    refreshPasswordState()
  }

  func update(_ change: (inout MailSettings) -> Void) {
    var mail = storage.settings.mail
    change(&mail)
    storage.settings.mail = mail
  }

  func refreshPasswordState() {
    hasPassword = settings.configuredAccount.flatMap(IMAPCredentialStore.load(for:)) != nil
  }

  func savePassword(_ password: String) {
    guard let account = settings.configuredAccount else {
      report("Enter the server and user name first.", isError: true)
      return
    }
    IMAPCredentialStore.save(password, for: account)
    NotificationCenter.default.post(name: .imapCredentialsChanged, object: nil)
    refreshPasswordState()
    report("Password saved in the Keychain.", isError: false)
  }

  func removePassword() {
    guard let account = settings.configuredAccount else { return }
    IMAPCredentialStore.delete(for: account)
    NotificationCenter.default.post(name: .imapCredentialsChanged, object: nil)
    refreshPasswordState()
    report("Password removed.", isError: false)
  }

  /// Se connecte une fois avec `typedPassword` (ou, à défaut, celui du trousseau).
  func testConnection(typedPassword: String) {
    guard let account = settings.configuredAccount else {
      report("Enter the server and user name first.", isError: true)
      return
    }
    guard
      let password = typedPassword.isEmpty ? IMAPCredentialStore.load(for: account) : typedPassword
    else {
      report("Enter the password first.", isError: true)
      return
    }
    isTesting = true
    report("Connecting…", isError: false)
    Task {
      do {
        let count = try await IMAPMailSource.test(account: account, password: password)
        report(
          "Connected. The inbox holds \(count) message\(count == 1 ? "" : "s").", isError: false)
      } catch {
        Log.mail.error("Essai IMAP : \(error.localizedDescription, privacy: .private)")
        report(error.localizedDescription, isError: true)
      }
      isTesting = false
    }
  }

  private func report(_ text: String, isError: Bool) {
    status = text
    statusIsError = isError
  }
}
