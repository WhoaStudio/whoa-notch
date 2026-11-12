import Foundation
import Testing

@testable import whoa_stash

@Suite struct AgentPromptFormTests {

  private func choice(_ text: String, _ labels: [String], multi: Bool = false) -> AgentEvent.Question {
    AgentEvent.Question(
      text: text, options: labels.map { .init(label: $0, detail: "") }, multiSelect: multi)
  }

  private func field(_ text: String, _ type: AgentEvent.FieldType) -> AgentEvent.Question {
    AgentEvent.Question(
      text: text, options: [], multiSelect: false, freeText: true, field: text, fieldType: type)
  }

  @Test func unChoixSimpleRepondEtTermine() {
    var form = AgentPromptForm(questions: [choice("Q", ["A", "B"])])
    let outcome1 = form.choose("B")
    #expect(outcome1 == .finished(["Q": ["B"]]))
  }

  @Test func unChoixSimpleAvanceVersLaQuestionSuivante() {
    var form = AgentPromptForm(questions: [choice("Q1", ["A", "B"]), choice("Q2", ["C", "D"])])
    let outcome2 = form.choose("A")
    #expect(outcome2 == .advanced)
    #expect(form.index == 1)
    #expect(form.current.text == "Q2")
    let outcome3 = form.choose("D")
    #expect(outcome3 == .finished(["Q1": ["A"], "Q2": ["D"]]))
  }

  @Test func unChoixMultipleSeCocheEtSeDecocheSansAvancer() {
    var form = AgentPromptForm(questions: [choice("Q", ["A", "B", "C"], multi: true)])
    #expect(!form.canSendChoices)
    let outcome4 = form.sendChoices()
    #expect(outcome4 == .stay)
    let outcome5 = form.choose("A")
    #expect(outcome5 == .stay)
    let outcome6 = form.choose("C")
    #expect(outcome6 == .stay)
    let outcome7 = form.choose("A")
    #expect(outcome7 == .stay)
    #expect(form.selections[0] == ["C"])
    #expect(form.canSendChoices)
    let outcome8 = form.sendChoices()
    #expect(outcome8 == .finished(["Q": ["C"]]))
  }

  @Test func otherDansUnChoixMultipleGardeLesCasesCochees() {
    var form = AgentPromptForm(questions: [choice("Q", ["A", "B"], multi: true)])
    form.choose("A")
    form.startTyping()
    #expect(form.isTyping)
    let outcome9 = form.submit(text: " mon idée ")
    #expect(outcome9 == .finished(["Q": ["A", "mon idée"]]))
  }

  @Test func otherDansUnChoixSimpleRemplaceLeChoix() {
    var form = AgentPromptForm(questions: [choice("Q", ["A", "B"])])
    form.startTyping()
    form.stopTyping()
    #expect(!form.isTyping)
    form.startTyping()
    let outcome10 = form.submit(text: "autre")
    #expect(outcome10 == .finished(["Q": ["autre"]]))
  }

  @Test func unTexteVideEstRefuse() {
    var form = AgentPromptForm(questions: [choice("Q", ["A", "B"])])
    form.startTyping()
    let outcome11 = form.submit(text: "   ")
    #expect(outcome11 == .stay)
  }

  @Test func unChampLibreOuvreLeTexteEtNeSeRefermePas() {
    var form = AgentPromptForm(questions: [field("Nom", .string)])
    #expect(form.isTyping)
    form.stopTyping()
    #expect(form.isTyping)
  }

  @Test func unChampNombreVerifieSonType() {
    var form = AgentPromptForm(questions: [field("Points", .integer), field("Ratio", .number)])
    #expect(!form.isValid("trois"))
    #expect(!form.isValid("3.5"))
    let outcome12 = form.submit(text: "trois")
    #expect(outcome12 == .stay)
    #expect(form.index == 0)
    let outcome13 = form.submit(text: "3")
    #expect(outcome13 == .advanced)
    #expect(form.isTyping)
    #expect(form.isValid("3.5"))
    let outcome14 = form.submit(text: "3.5")
    #expect(outcome14 == .finished(["Points": ["3"], "Ratio": ["3.5"]]))
  }

  @Test func laQuestionSuivanteRouvreLeTexteSeulementSiElleEstLibre() {
    var form = AgentPromptForm(questions: [choice("Q1", ["A", "B"]), field("Nom", .string)])
    #expect(!form.isTyping)
    form.choose("A")
    #expect(form.isTyping)
  }
}
