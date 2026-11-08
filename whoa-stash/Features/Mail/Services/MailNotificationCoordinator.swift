import Foundation
import OSLog

extension Notification.Name {
  /// Le mot de passe IMAP vient d'être enregistré ou supprimé : la source doit se reconnecter.
  static let imapCredentialsChanged = Notification.Name(
    "ugolin-olle.whoa-stash.imapCredentialsChanged")
}

/// Réunit les sources de courrier, écarte les doublons (un même `Message-ID` vu par deux sources)
/// et remet chaque nouveau message à l'encoche.
@MainActor
final class MailNotificationCoordinator {

  /// Appelé pour chaque message jamais vu.
  var onMessage: ((MailMessage) -> Void)?

  private var tasks: [String: Task<Void, Never>] = [:]
  private var seenOrder: [String] = []
  private var seen: Set<String> = []
  private let memory = 200
  private var imapSettings = MailSettings()
  private var observer: NSObjectProtocol?

  init() {
    observer = NotificationCenter.default.addObserver(
      forName: .imapCredentialsChanged, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.apply(settings: self.imapSettings)
      }
    }
  }

  /// Lance `source` sous ce nom ; une source déjà lancée sous le même nom est arrêtée d'abord.
  func start(_ source: some MailSource, name: String) {
    tasks[name]?.cancel()
    tasks[name] = Task { [weak self] in
      for await message in source.messages() {
        self?.receive(message)
      }
    }
  }

  func stop(name: String) {
    tasks[name]?.cancel()
    tasks[name] = nil
  }

  /// Démarre, redémarre ou arrête la source IMAP selon les réglages.
  func apply(settings: MailSettings) {
    imapSettings = settings
    guard let account = settings.account else {
      stop(name: "imap")
      return
    }
    start(IMAPMailSource(account: account), name: "imap")
  }

  /// Renvoie `false` pour un message déjà vu.
  @discardableResult
  func receive(_ message: MailMessage) -> Bool {
    guard seen.insert(message.id).inserted else { return false }
    seenOrder.append(message.id)
    if seenOrder.count > memory {
      seen.remove(seenOrder.removeFirst())
    }
    onMessage?(message)
    return true
  }
}
