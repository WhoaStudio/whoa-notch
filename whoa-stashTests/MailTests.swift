import Foundation
import Testing

@testable import whoa_stash

@Suite("Décodage du courrier")
struct MailBodyDecoderTests {

  @Test("un mot encodé en base64 et un autre en quoted-printable se décodent")
  func motsEncodes() {
    #expect(MailBodyDecoder.decodeHeader("=?UTF-8?B?w4lsw6l2YXRpb24=?=") == "Élévation")
    #expect(MailBodyDecoder.decodeHeader("=?iso-8859-1?Q?Caf=E9_cr=E8me?=") == "Café crème")
  }

  @Test("deux mots encodés qui se suivent se recollent")
  func motsRecolles() {
    let value = "=?UTF-8?B?Qm9u?= =?UTF-8?B?am91cg==?= tout le monde"
    #expect(MailBodyDecoder.decodeHeader(value) == "Bonjour tout le monde")
  }

  @Test("le nom affiché d'un From vient avant l'adresse, sinon c'est l'adresse")
  func nomAffiche() {
    #expect(
      MailBodyDecoder.displayName(fromHeader: "\"Ada Lovelace\" <ada@example.org>")
        == "Ada Lovelace")
    #expect(MailBodyDecoder.displayName(fromHeader: "<ada@example.org>") == "ada@example.org")
    #expect(MailBodyDecoder.displayName(fromHeader: "ada@example.org") == "ada@example.org")
  }

  @Test("les en-têtes pliés sont dépliés et les clés passent en minuscules")
  func entetesPlies() {
    let headers = MailBodyDecoder.parseHeaders(
      "Subject: Un objet\r\n  très long\r\nFrom: a@b.c\r\n\r\nCorps: ignoré")
    #expect(headers["subject"] == "Un objet très long")
    #expect(headers["from"] == "a@b.c")
    #expect(headers["corps"] == nil)
  }

  @Test("un corps texte simple devient l'aperçu sur une ligne")
  func texteSimple() {
    let preview = MailBodyDecoder.preview(
      headers: [:], body: Data("Bonjour,\r\n\r\nLe  rendez-vous\nest confirmé.".utf8))
    #expect(preview == "Bonjour, Le rendez-vous est confirmé.")
  }

  @Test("un aperçu trop long est coupé avec une ellipse")
  func apercuCoupe() {
    let preview = MailBodyDecoder.preview(
      headers: [:], body: Data(String(repeating: "mot ", count: 100).utf8), limit: 20)
    #expect(preview.count <= 21)
    #expect(preview.hasSuffix("…"))
  }

  @Test("le quoted-printable en iso-8859-1 est décodé selon le jeu de caractères annoncé")
  func quotedPrintable() {
    let headers = [
      "content-type": "text/plain; charset=iso-8859-1",
      "content-transfer-encoding": "quoted-printable",
    ]
    let preview = MailBodyDecoder.preview(headers: headers, body: Data("Caf=E9 =\r\ncr=E8me".utf8))
    #expect(preview == "Café crème")
  }

  @Test("un corps base64 tronqué en milieu de bloc se décode jusqu'où il va")
  func base64Tronque() {
    let full = Data("Bonjour tout le monde".utf8).base64EncodedString()
    let truncated = String(full.dropLast(3))
    let headers = [
      "content-type": "text/plain; charset=utf-8", "content-transfer-encoding": "base64",
    ]
    let preview = MailBodyDecoder.preview(headers: headers, body: Data(truncated.utf8))
    #expect("Bonjour tout le monde".hasPrefix(preview))
    #expect(preview.count > 5)
  }

  @Test("un multipart/alternative donne la partie texte, pas le HTML")
  func multipartAlternative() {
    let body = """
      --b1\r
      Content-Type: text/plain; charset=utf-8\r
      \r
      Version texte\r
      --b1\r
      Content-Type: text/html; charset=utf-8\r
      \r
      <p>Version <b>HTML</b></p>\r
      --b1--\r

      """
    let headers = ["content-type": "multipart/alternative; boundary=\"b1\""]
    #expect(MailBodyDecoder.preview(headers: headers, body: Data(body.utf8)) == "Version texte")
  }

  @Test("sans partie texte, le HTML est dépouillé de ses balises et de ses styles")
  func htmlSeul() {
    let body =
      "<html><head><style>p{color:red}</style></head><body><p>Salut&nbsp;toi &amp; les autres</p></body></html>"
    let headers = ["content-type": "text/html; charset=utf-8"]
    #expect(
      MailBodyDecoder.preview(headers: headers, body: Data(body.utf8)) == "Salut toi & les autres")
  }

  @Test("un multipart/mixed imbriqué saute la pièce jointe et trouve le texte")
  func multipartImbrique() {
    let body = """
      --outer\r
      Content-Type: multipart/alternative; boundary="inner"\r
      \r
      --inner\r
      Content-Type: text/plain\r
      \r
      Le vrai texte\r
      --inner--\r
      --outer\r
      Content-Type: text/plain\r
      Content-Disposition: attachment; filename="notes.txt"\r
      \r
      Contenu de la pièce jointe\r
      --outer--\r

      """
    let headers = ["content-type": "multipart/mixed; boundary=outer"]
    #expect(MailBodyDecoder.preview(headers: headers, body: Data(body.utf8)) == "Le vrai texte")
  }
}

@Suite("Lecture des réponses IMAP")
struct IMAPParsingTests {

  @Test("un literal annoncé en fin de ligne donne sa taille et le texte qui le précède")
  func literal() {
    let found = IMAPConnection.literal(in: "* 4 FETCH (UID 9 BODY[TEXT]<0> {312}")
    #expect(found?.size == 312)
    #expect(found?.prefix == "* 4 FETCH (UID 9 BODY[TEXT]<0> ")
    #expect(IMAPConnection.literal(in: "* OK ready") == nil)
    #expect(IMAPConnection.literal(in: "* OK {abc}") == nil)
  }

  @Test("les guillemets et antislashs sont échappés, un saut de ligne est refusé")
  func quote() throws {
    #expect(try IMAPConnection.quote("a\"b\\c") == "\"a\\\"b\\\\c\"")
    #expect(throws: IMAPError.self) { try IMAPConnection.quote("a\nb") }
  }

  @Test("UIDNEXT, UIDVALIDITY et EXISTS se lisent dans la réponse à EXAMINE")
  func examine() {
    let responses = [
      IMAPResponse(line: "* 12 EXISTS", literals: []),
      IMAPResponse(line: "* OK [UIDVALIDITY 3857529045] UIDs valid", literals: []),
      IMAPResponse(line: "* OK [UIDNEXT 4392] Predicted next UID", literals: []),
    ]
    #expect(IMAPParsing.exists(in: responses) == 12)
    #expect(IMAPParsing.value(of: "UIDVALIDITY", in: responses) == 3_857_529_045)
    #expect(IMAPParsing.value(of: "UIDNEXT", in: responses) == 4392)
  }

  @Test("un FETCH avec en-têtes et corps devient un message")
  func fetch() {
    let header =
      "From: =?UTF-8?B?w4lsaXNl?= <elise@example.org>\r\nSubject: Rendez-vous\r\nMessage-ID: <abc@example.org>\r\n\r\n"
    let response = IMAPResponse(
      line: "* 7 FETCH (UID 4391 BODY[HEADER.FIELDS (FROM SUBJECT MESSAGE-ID)]  BODY[TEXT]<0> )",
      literals: [
        IMAPLiteral(
          label: "* 7 FETCH (UID 4391 BODY[HEADER.FIELDS (FROM SUBJECT MESSAGE-ID)] ",
          data: Data(header.utf8)),
        IMAPLiteral(label: " BODY[TEXT]<0> ", data: Data("À demain, 10 h.".utf8)),
      ])
    let result = IMAPParsing.message(from: response, account: "moi", validity: 3)
    #expect(result?.uid == 4391)
    #expect(
      result?.message
        == MailMessage(
          id: "<abc@example.org>", sender: "Élise", subject: "Rendez-vous",
          preview: "À demain, 10 h.", account: "moi"))
  }

  @Test("sans Message-ID, l'identifiant combine compte, validité et UID")
  func identifiantDeRepli() {
    let response = IMAPResponse(
      line: "* 1 FETCH (UID 5 BODY[HEADER.FIELDS (FROM)] )",
      literals: [
        IMAPLiteral(label: " BODY[HEADER.FIELDS (FROM)] ", data: Data("From: a@b.c\r\n\r\n".utf8))
      ])
    let result = IMAPParsing.message(from: response, account: "moi", validity: 3)
    #expect(result?.message.id == "moi/3/5")
    #expect(result?.message.subject == "(no subject)")
  }
}

@Suite("Courrier dans l'encoche")
@MainActor
struct MailCoordinatorTests {

  private func message(_ id: String) -> MailMessage {
    MailMessage(id: id, sender: "s", subject: "o", preview: "p", account: "a")
  }

  @Test("un même message vu par deux sources n'est montré qu'une fois")
  func doublons() {
    let coordinator = MailNotificationCoordinator()
    var shown: [String] = []
    coordinator.onMessage = { shown.append($0.id) }
    #expect(coordinator.receive(message("x")))
    #expect(!coordinator.receive(message("x")))
    #expect(coordinator.receive(message("y")))
    #expect(shown == ["x", "y"])
  }

  @Test("la source simulée émet son message fixe")
  func sourceSimulee() async {
    var iterator = MockMailSource().messages().makeAsyncIterator()
    let first = await iterator.next()
    #expect(first?.sender == "Ada Lovelace")
  }

  @Test("--mail=sample active la source simulée, rien d'autre")
  func argument() {
    #expect(MockMailSource.fromLaunchArguments(["app", "--mail=sample"]) != nil)
    #expect(MockMailSource.fromLaunchArguments(["app"]) == nil)
  }
}

@Suite("Réglages du courrier")
@MainActor
struct MailSettingsTests {

  @Test("un compte désactivé ou incomplet n'est pas surveillé")
  func compte() {
    var settings = MailSettings(
      imapEnabled: true, host: " imap.example.org ", port: 993, username: "moi")
    #expect(settings.account == IMAPAccount(host: "imap.example.org", port: 993, username: "moi"))
    settings.imapEnabled = false
    #expect(settings.account == nil)
    #expect(settings.configuredAccount != nil)
    settings.imapEnabled = true
    settings.host = ""
    #expect(settings.account == nil)
    settings.host = "h"
    settings.port = 70_000
    #expect(settings.account == nil)
  }

  @Test("un blob sans clé « mail » se décode avec les valeurs par défaut")
  func cleAbsente() throws {
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    #expect(decoded.mail == MailSettings())
    let partial = try JSONDecoder().decode(MailSettings.self, from: Data(#"{"host":"h"}"#.utf8))
    #expect(partial.host == "h")
    #expect(partial.port == 993)
  }

  @Test("chaque fournisseur préconfiguré a un serveur IMAP en 993, « Other » n'en a pas")
  func presets() {
    for provider in MailProvider.allCases where provider != .other {
      #expect(provider.preset?.port == 993)
      #expect(provider.preset?.host.hasPrefix("imap.") == true)
    }
    #expect(MailProvider.other.preset == nil)
  }

  @Test("un fournisseur inconnu retombe sur « Other » sans perdre le reste")
  func fournisseurInconnu() throws {
    let decoded = try JSONDecoder().decode(
      MailSettings.self, from: Data(#"{"provider":"aol","host":"h"}"#.utf8))
    #expect(decoded.provider == .other)
    #expect(decoded.host == "h")
  }
}
