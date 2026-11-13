import Foundation

/// Compte IMAP surveillé. Le mot de passe n'y figure pas : il vit dans le trousseau
/// (`IMAPCredentialStore`).
nonisolated struct IMAPAccount: Equatable, Hashable, Sendable {
  var host: String
  var port: UInt16
  var username: String
}

/// Fournisseur de courrier : les présets remplissent serveur et port, `other` laisse tout saisir.
/// Outlook.com n'y figure pas : il n'accepte plus que OAuth, que l'app ne gère pas encore.
enum MailProvider: String, Codable, CaseIterable, Identifiable, Sendable {
  case icloud
  case gmail
  case fastmail
  case yahoo
  case other

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .icloud: "iCloud Mail"
    case .gmail: "Gmail"
    case .fastmail: "Fastmail"
    case .yahoo: "Yahoo Mail"
    case .other: "Other (IMAP)"
    }
  }

  /// Serveur et port IMAP du fournisseur ; `nil` pour `other`.
  var preset: (host: String, port: Int)? {
    switch self {
    case .icloud: ("imap.mail.me.com", 993)
    case .gmail: ("imap.gmail.com", 993)
    case .fastmail: ("imap.fastmail.com", 993)
    case .yahoo: ("imap.mail.yahoo.com", 993)
    case .other: nil
    }
  }

  /// Ce qu'il faut saisir comme mot de passe chez ce fournisseur.
  var passwordHint: String {
    switch self {
    case .icloud:
      "Use an app-specific password: create one at account.apple.com ▸ Sign-In and Security. The user name is your iCloud address."
    case .gmail:
      "Turn on 2-step verification, then create an app password at myaccount.google.com/apppasswords. IMAP must be enabled in Gmail's settings."
    case .fastmail:
      "Create an app password in Fastmail ▸ Settings ▸ Privacy & Security ▸ Integrations, with IMAP access."
    case .yahoo:
      "Create an app password in Yahoo ▸ Account security ▸ Generate app password."
    case .other:
      "Enter your provider's IMAP server. Use an app password if your provider offers one. Outlook.com and Microsoft 365 need OAuth, which is not supported yet."
    }
  }
}

/// Réglages du courrier dans l'encoche.
struct MailSettings: Codable, Equatable, Sendable {
  var imapEnabled: Bool = false
  var host: String = ""
  var port: Int = 993
  var username: String = ""
  var provider: MailProvider = .other

  /// Le compte tel que saisi, même désactivé, ou `nil` s'il est incomplet : c'est lui qui désigne
  /// l'entrée du trousseau.
  var configuredAccount: IMAPAccount? {
    let host = host.trimmingCharacters(in: .whitespaces)
    let username = username.trimmingCharacters(in: .whitespaces)
    guard !host.isEmpty, !username.isEmpty, let port = UInt16(exactly: port), port > 0
    else { return nil }
    return IMAPAccount(host: host, port: port, username: username)
  }

  /// Le compte à surveiller, ou `nil` s'il est désactivé ou incomplet.
  var account: IMAPAccount? { imapEnabled ? configuredAccount : nil }
}
