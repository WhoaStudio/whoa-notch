import Foundation

/// L'avancement des réponses à une série de questions de Claude (`AskUserQuestion`) ou aux champs
/// d'un formulaire MCP. La carte de l'encoche n'en montre qu'une à la fois ; ce type garde ce qui
/// est coché ou tapé et dit quand tout est répondu.
///
/// Un choix simple répond et passe à la suite ; un choix multiple se coche puis se valide ; « Other… »
/// ouvre un champ de texte (qui s'ajoute aux cases cochées d'un choix multiple) ; un champ libre
/// s'ouvre directement sur le texte, vérifié selon son type.
nonisolated struct AgentPromptForm: Equatable, Sendable {

  nonisolated enum Outcome: Equatable, Sendable {
    /// Rien à changer d'écran (une case cochée, un texte refusé).
    case stay
    /// La question suivante prend la carte.
    case advanced
    /// Tout est répondu : texte de question → libellés.
    case finished([String: [String]])
  }

  let questions: [AgentEvent.Question]
  private(set) var index = 0
  private(set) var selections: [[String]]
  /// Le champ de texte est ouvert sur la question en cours.
  private(set) var isTyping: Bool

  init(questions: [AgentEvent.Question]) {
    self.questions = questions
    selections = Array(repeating: [], count: questions.count)
    isTyping = questions.first?.freeText ?? false
  }

  var current: AgentEvent.Question { questions[min(index, questions.count - 1)] }
  var isLast: Bool { index >= questions.count - 1 }

  /// Au moins un choix est coché : un choix multiple peut être validé.
  var canSendChoices: Bool { !selections[index].isEmpty }

  /// Un choix. Simple : il répond et passe à la suite. Multiple : il se coche ou se décoche.
  @discardableResult
  mutating func choose(_ label: String) -> Outcome {
    guard !questions.isEmpty else { return .stay }
    if current.multiSelect {
      if let position = selections[index].firstIndex(of: label) {
        selections[index].remove(at: position)
      } else {
        selections[index].append(label)
      }
      return .stay
    }
    selections[index] = [label]
    return advance()
  }

  /// Valide les cases d'un choix multiple.
  @discardableResult
  mutating func sendChoices() -> Outcome {
    guard canSendChoices else { return .stay }
    return advance()
  }

  /// « Other… » : ouvre le champ de texte.
  mutating func startTyping() { isTyping = true }

  /// Referme le champ de texte d'une question à choix (un champ libre n'a pas d'autre écran).
  mutating func stopTyping() {
    guard !current.freeText else { return }
    isTyping = false
  }

  /// Le texte tapé a le bon type et n'est pas vide.
  func isValid(_ text: String) -> Bool {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return false }
    return AgentEvent.fieldValue(text, type: current.fieldType) != nil
  }

  /// Valide le texte tapé. Un choix multiple le garde avec les cases cochées ; sinon il est la réponse.
  @discardableResult
  mutating func submit(text: String) -> Outcome {
    guard isValid(text) else { return .stay }
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if current.multiSelect {
      if !selections[index].contains(text) { selections[index].append(text) }
    } else {
      selections[index] = [text]
    }
    return advance()
  }

  private mutating func advance() -> Outcome {
    if isLast {
      var answers: [String: [String]] = [:]
      for (question, selected) in zip(questions, selections) { answers[question.text] = selected }
      return .finished(answers)
    }
    index += 1
    isTyping = questions[index].freeText
    return .advanced
  }
}
