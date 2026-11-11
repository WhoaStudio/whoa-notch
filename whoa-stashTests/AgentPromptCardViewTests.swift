import AppKit
import Foundation
import Testing

@testable import whoa_stash

/// La carte de l'onglet AI pilotée comme par l'utilisateur : on clique ses boutons et on tape dans
/// son champ, et on lit les décisions qu'elle rend.
@MainActor @Suite struct AgentPromptCardViewTests {

  private var size: NSSize {
    NSSize(width: NotchPanelGeometry.tabContentWidth, height: NotchPanelGeometry.aiTabHeight)
  }

  /// La carte, dans une fenêtre hors écran (le champ de texte en a besoin), et les décisions reçues.
  private final class Rig {
    let card: AgentPromptCardView
    let window: NSWindow
    var decisions: [AgentEvent.Decision] = []

    init(size: NSSize) {
      card = AgentPromptCardView(frame: NSRect(origin: .zero, size: size))
      window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered,
        defer: true)
      window.contentView = card
      card.onDecision = { [unowned self] _, decision in decisions.append(decision) }
    }

    func show(_ event: AgentEvent) {
      card.apply(event)
      card.layoutSubtreeIfNeeded()
    }

    /// Les titres des boutons visibles du pied de carte.
    var buttonTitles: [String] { buttons().map(\.title) }

    private func buttons() -> [(title: String, view: NSView)] {
      var found: [(String, NSView)] = []
      func walk(_ view: NSView) {
        if String(describing: type(of: view)) == "PromptButton", !view.isHidden,
          let label = view.subviews.compactMap({ $0 as? NSTextField }).first
        {
          found.append((label.stringValue, view))
        }
        view.subviews.forEach(walk)
      }
      walk(card)
      return found
    }

    /// Clique le bouton de ce titre ; faux s'il n'y en a pas.
    @discardableResult
    func click(_ title: String) -> Bool {
      guard let button = buttons().first(where: { $0.title == title })?.view else { return false }
      let event = NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
      guard let event else { return false }
      button.mouseDown(with: event)
      card.layoutSubtreeIfNeeded()
      return true
    }

    /// Une touche au clavier ; vrai si la carte l'a prise.
    @discardableResult
    func press(_ characters: String, keyCode: UInt16, shift: Bool = false) -> Bool {
      guard
        let event = NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, characters: characters,
          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
      else { return false }
      let handled = card.performKeyEquivalent(with: event)
      card.layoutSubtreeIfNeeded()
      return handled
    }

    /// Le champ de texte, s'il est visible.
    var field: NSTextField? {
      var found: NSTextField?
      func walk(_ view: NSView) {
        if let text = view as? NSTextField, text.isEditable, !text.isHiddenOrHasHiddenAncestor {
          found = text
        }
        view.subviews.forEach(walk)
      }
      walk(card)
      return found
    }

    /// Tape du texte et valide, comme Entrée.
    func typeText(_ text: String) {
      guard let field else { return }
      field.stringValue = text
      if let action = field.action { NSApp.sendAction(action, to: field.target, from: field) }
      card.layoutSubtreeIfNeeded()
    }
  }

  private func simulated(_ name: String) throws -> AgentEvent {
    try #require(AgentEvent.fromLaunchArguments(["app", "--agent-event=\(name)"]))
  }

  // MARK: - Permission

  @Test("une permission offre Deny, Allow et Always, et chaque bouton rend sa décision")
  func permissionButtons() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("permission"))
    #expect(rig.buttonTitles == ["Deny", "Allow", "Always"])
    rig.click("Allow")
    rig.click("Deny")
    rig.click("Always")
    #expect(rig.decisions == [.allow, .deny, .allowAlways])
  }

  @Test("sans règle proposée par Claude, Always n'est pas offert")
  func noAlwaysWithoutSuggestion() {
    let rig = Rig(size: size)
    rig.show(
      AgentEvent(
        kind: .needsInput, project: "p", prompt: .tool(name: "Bash", detail: "ls"), replyID: "r"))
    #expect(rig.buttonTitles == ["Deny", "Allow"])
  }

  // MARK: - Hauteur

  @Test("la hauteur voulue suit le contenu et reste dans la fenêtre du panneau")
  func fittingHeightFollowsContent() throws {
    let width = NotchPanelGeometry.contentWidth(for: .ai)
    let short = Rig(size: size)
    short.show(
      AgentEvent(
        kind: .needsInput, project: "p", prompt: .tool(name: "Bash", detail: "ls"), replyID: "r"))
    let long = Rig(size: size)
    long.show(try simulated("permission-long"))
    #expect(long.card.fittingHeight(width: width) > short.card.fittingHeight(width: width))

    let ceiling = NotchPanelGeometry.tabContentHeight
    for name in ["permission", "permission-long", "plan", "question", "question-multi", "elicit", "reply"] {
      let rig = Rig(size: size)
      rig.show(try simulated(name))
      let height = rig.card.fittingHeight(width: width)
      #expect(height > 100 && height <= ceiling, "\(name) : \(height)")
    }
  }

  @Test("une carte qui change de contenu prévient le panneau")
  func contentChangeIsReported() throws {
    let rig = Rig(size: size)
    var changes = 0
    rig.card.onContentChanged = { changes += 1 }
    rig.show(try simulated("question"))
    let before = changes
    rig.click("Other…")
    #expect(changes > before)
    #expect(rig.card.showsTextInput)
  }

  // MARK: - Clavier

  @Test("un chiffre choisit l'option correspondante")
  func digitPicksOption() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("question"))
    #expect(rig.press("2", keyCode: 19))
    #expect(rig.decisions == [.answer(["Which framework should I use?": ["Vue"]])])
  }

  @Test("choix multiple au clavier : chiffres pour cocher, Entrée pour passer à la suite")
  func multiSelectByKeyboard() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("question-multi"))
    rig.press("1", keyCode: 18)
    rig.press("3", keyCode: 20)
    #expect(rig.press("\r", keyCode: 36))
    #expect(rig.buttonTitles.prefix(2) == ["Terminal", "File"])
    #expect(rig.decisions.isEmpty)
  }

  @Test("les flèches déplacent le focus et Entrée valide le choix au focus")
  func arrowsThenReturn() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("question"))
    rig.press("", keyCode: 125)  // bas : premier choix
    rig.press("", keyCode: 125)  // bas : deuxième
    #expect(rig.press("\r", keyCode: 36))
    #expect(rig.decisions == [.answer(["Which framework should I use?": ["Vue"]])])
  }

  @Test("Entrée n'autorise jamais un outil")
  func returnNeverAllows() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("permission"))
    #expect(!rig.press("\r", keyCode: 36))
    #expect(!rig.press("1", keyCode: 18))
    #expect(rig.decisions.isEmpty)
  }

  @Test("Échap referme « Other… », puis replie le panneau")
  func escapeClosesThenFolds() throws {
    let rig = Rig(size: size)
    var folds = 0
    rig.card.onFoldRequested = { folds += 1 }
    rig.show(try simulated("question"))
    rig.click("Other…")
    #expect(rig.field != nil)
    rig.press("\u{1B}", keyCode: 53)
    #expect(rig.field == nil)
    #expect(folds == 0)
    rig.press("\u{1B}", keyCode: 53)
    #expect(folds == 1)
    #expect(rig.decisions.isEmpty)
  }

  @Test("les chiffres ne sont pas pris pendant la frappe dans « Other… »")
  func digitsTypeIntoField() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("question"))
    rig.click("Other…")
    #expect(!rig.press("1", keyCode: 18))
    #expect(rig.decisions.isEmpty)
  }

  @Test("une carte en lecture seule ne lit pas le clavier")
  func readOnlyIgnoresKeys() {
    let rig = Rig(size: size)
    var folds = 0
    rig.card.onFoldRequested = { folds += 1 }
    rig.show(AgentEvent(kind: .needsInput, project: "p", prompt: .message("Besoin de toi")))
    #expect(!rig.press("\u{1B}", keyCode: 53))
    #expect(folds == 0)
  }

  // MARK: - Transitions

  @Test("le bouton actionné se coche quand la réponse part")
  func answeredButtonShowsCheck() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("permission"))
    rig.click("Allow")
    #expect(rig.decisions == [.allow])
    #expect(rig.buttonTitles.contains("✓"))
    #expect(!rig.buttonTitles.contains("Allow"))
  }

  @Test("une autre demande prend la place de la première, contenu et boutons à jour")
  func swappingPromptsKeepsContentCorrect() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("permission"))
    // Les événements simulés partagent un replyID : la vraie file en a un par demande.
    var next = try simulated("question")
    next.replyID = "autre"
    rig.show(next)
    #expect(rig.buttonTitles.prefix(3) == ["React", "Vue", "Other…"])
    rig.click("Vue")
    #expect(rig.decisions == [.answer(["Which framework should I use?": ["Vue"]])])
  }

  @Test("passer à la question suivante garde les réponses et change les boutons")
  func advancingQuestionSwapsContent() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("question-multi"))
    rig.click("Lint")
    rig.click("Next")
    #expect(rig.buttonTitles.prefix(2) == ["Terminal", "File"])
    #expect(rig.decisions.isEmpty)
  }

  // MARK: - Réponse libre et lecture seule

  @Test("la réponse libre s'envoie avec le rond d'envoi, vide il ne fait rien")
  func replySendIcon() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("reply"))
    #expect(rig.buttonTitles.contains("Send"))
    rig.click("Send")
    #expect(rig.decisions.isEmpty)
    rig.field?.stringValue = "ajoute un test"
    // La frappe réelle prévient le délégué : c'est elle qui allume le rond d'envoi.
    rig.card.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    rig.click("Send")
    #expect(rig.decisions == [.reply("ajoute un test")])
  }

  @Test("une demande en lecture seule dit où répondre, et Claude Desktop propose de l'ouvrir")
  func readOnlyPointsToWhereToAnswer() {
    let code = Rig(size: size)
    code.show(AgentEvent(kind: .needsInput, project: "p", prompt: .message("Besoin de toi")))
    #expect(code.buttonTitles.isEmpty)

    let desktop = Rig(size: size)
    desktop.show(
      AgentEvent(
        kind: .needsInput, project: "p", prompt: .message("Besoin de toi"), source: .claudeDesktop))
    #expect(desktop.buttonTitles == ["Open Claude"])
  }

  // MARK: - Plan

  @Test("un plan offre Change plan, Auto mode et Manual")
  func planButtons() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("plan"))
    #expect(rig.buttonTitles == ["Change plan", "Auto mode", "Manual"])
    rig.click("Auto mode")
    rig.click("Manual")
    rig.click("Change plan")
    #expect(rig.decisions == [.plan(.auto), .plan(.manual), .plan(.change)])
  }

  // MARK: - Questions

  @Test("un choix simple répond tout de suite")
  func singleChoiceAnswers() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("question"))
    #expect(rig.buttonTitles.prefix(3) == ["React", "Vue", "Other…"])
    rig.click("Vue")
    #expect(rig.decisions == [.answer(["Which framework should I use?": ["Vue"]])])
  }

  @Test("choix multiple puis question suivante : cocher, Next, répondre")
  func multiSelectThenNextQuestion() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("question-multi"))
    // Rien n'est coché : « Next » est là mais sans effet.
    #expect(rig.buttonTitles.contains("Next"))
    rig.click("Next")
    #expect(rig.decisions.isEmpty)

    rig.click("Lint")
    rig.click("Types")
    rig.click("Lint")  // décoché
    rig.click("E2E")
    rig.click("Next")
    #expect(rig.decisions.isEmpty)
    // La seconde question a pris la carte.
    #expect(rig.buttonTitles.prefix(3) == ["Terminal", "File", "Other…"])
    rig.click("File")
    #expect(
      rig.decisions == [
        .answer([
          "Which checks should run before merge?": ["Types", "E2E"],
          "Where should the report go?": ["File"],
        ])
      ])
  }

  @Test("Other… ouvre un champ : le texte tapé s'ajoute aux cases cochées d'un choix multiple")
  func otherAddsToMultiSelect() throws {
    let rig = Rig(size: size)
    rig.show(
      AgentEvent(
        kind: .needsInput, project: "p",
        prompt: .questions([
          .init(
            text: "Quoi ?", options: [.init(label: "A", detail: ""), .init(label: "B", detail: "")],
            multiSelect: true)
        ]), replyID: "r", response: .question))
    #expect(rig.field == nil)
    rig.click("A")
    rig.click("Other…")
    #expect(rig.field != nil)
    #expect(rig.buttonTitles.contains("✕"))
    rig.typeText("mon idée")
    #expect(rig.decisions == [.answer(["Quoi ?": ["A", "mon idée"]])])
  }

  @Test("✕ referme le champ sans rien répondre")
  func backReturnsToChoices() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("question"))
    rig.click("Other…")
    #expect(rig.field != nil)
    rig.click("✕")
    #expect(rig.field == nil)
    #expect(rig.buttonTitles.prefix(2) == ["React", "Vue"])
    #expect(rig.decisions.isEmpty)
  }

  @Test("« Reply in terminal » rend la main, « Reply in Claude » pour Claude Desktop")
  func handBackButton() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("question"))
    #expect(rig.buttonTitles.last == "Reply in terminal")
    rig.click("Reply in terminal")
    #expect(rig.decisions == [.handBack])

    let desktop = Rig(size: size)
    var event = try simulated("question")
    event.source = .claudeDesktop
    desktop.show(event)
    #expect(desktop.buttonTitles.last == "Reply in Claude")
  }

  @Test("une question sans identifiant de réponse reste en lecture seule")
  func readOnlyQuestion() {
    let rig = Rig(size: size)
    rig.show(
      AgentEvent(
        kind: .needsInput, project: "p",
        prompt: .questions([.init(text: "Q ?", options: [.init(label: "A", detail: "")], multiSelect: false)])
      ))
    #expect(rig.buttonTitles.isEmpty)
    #expect(rig.field == nil)
  }

  // MARK: - Formulaire MCP

  @Test("un formulaire MCP se remplit champ par champ puis rend ses valeurs")
  func elicitationForm() throws {
    let rig = Rig(size: size)
    let event = try simulated("elicit")
    rig.show(event)
    // Dans l'ordre des clés : notify (oui/non), priority (choix), project (texte).
    #expect(rig.buttonTitles.contains("Decline"))
    rig.click("Yes")
    rig.click("High")
    // Le champ libre est ouvert d'emblée, sans « ✕ ».
    #expect(rig.field != nil)
    #expect(!rig.buttonTitles.contains("✕"))
    rig.typeText("DOCS")
    guard case .answer(let answers) = rig.decisions.first else {
      Issue.record("pas de réponse : \(rig.decisions)")
      return
    }
    // Le premier champ porte aussi le message du formulaire.
    #expect(answers["Notify the team — Create a Jira issue"] == ["Yes"])
    #expect(answers["priority"] == ["High"])
    #expect(answers["Project key"] == ["DOCS"])
    let json = try #require(event.replyJSON(for: .answer(answers)))
    #expect(json.contains(#""notify":true"#))
    #expect(json.contains(#""project":"DOCS""#))
  }

  @Test("un nombre invalide est refusé et la carte reste sur le champ")
  func invalidNumberIsRefused() {
    let rig = Rig(size: size)
    rig.show(
      AgentEvent(
        kind: .needsInput, project: "p",
        prompt: .questions([
          .init(
            text: "Points ?", options: [], multiSelect: false, freeText: true, field: "points",
            fieldType: .integer)
        ]), replyID: "r", response: .elicitation))
    rig.typeText("trois")
    #expect(rig.decisions.isEmpty)
    #expect(rig.field != nil)
    rig.typeText("3")
    #expect(rig.decisions == [.answer(["Points ?": ["3"]])])
  }

  @Test("Decline refuse le formulaire")
  func declineForm() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("elicit"))
    rig.click("Decline")
    #expect(rig.decisions == [.deny])
  }

  // MARK: - Réponse libre

  @Test("après un tour, le texte tapé est la réponse ; Dismiss rend la main")
  func stopReply() throws {
    let rig = Rig(size: size)
    rig.show(try simulated("reply"))
    #expect(rig.field != nil)
    #expect(rig.buttonTitles.contains("Dismiss"))
    rig.typeText("   ")
    #expect(rig.decisions.isEmpty)
    rig.typeText("ajoute un test")
    rig.click("Dismiss")
    #expect(rig.decisions == [.reply("ajoute un test"), .handBack])
  }

  // MARK: - Mise à jour du même événement

  @Test("une mise à jour du même événement garde l'avancement du formulaire")
  func reapplyKeepsProgress() throws {
    let rig = Rig(size: size)
    let event = try simulated("question-multi")
    rig.show(event)
    rig.click("Lint")
    rig.click("Next")
    var again = event
    again.project = "autre"  // le compteur ou le nom changent, pas la demande
    rig.show(event)
    #expect(rig.buttonTitles.prefix(2) == ["Terminal", "File"])
    _ = again
  }
}
