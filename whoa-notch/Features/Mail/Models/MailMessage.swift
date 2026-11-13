import Foundation

/// Un message qui vient d'arriver, tel que l'encoche l'affiche. Rien n'y dit de quelle source il
/// vient : IMAP, simulation ou autre, l'encoche voit la même chose.
nonisolated struct MailMessage: Equatable, Sendable {
  /// Clé de dédoublonnage : le `Message-ID` quand il existe, sinon compte + UID.
  var id: String
  var sender: String
  var subject: String
  /// Début du texte, sur une ligne.
  var preview: String
  /// Libellé du compte (nom d'utilisateur).
  var account: String
}
