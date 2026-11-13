import Foundation
import Testing

@testable import whoa_notch

/// Le modèle de vue du widget calendrier, vu à travers une fausse source.
///
/// C'est le premier double injecté par protocole de cette suite — les tests existants se
/// contentaient de sous-classer `UserDefaults` —, et c'est précisément ce que
/// `CalendarAgendaProviding` est là pour permettre : vérifier le widget sans toucher aux
/// calendriers de la machine, ni demander d'autorisation à qui que ce soit.
@MainActor
struct CalendarAgendaTests {

  // MARK: - Fausse source

  /// Journée servie à la demande, avec de quoi simuler un refus d'accès et une lecture qui
  /// échoue. `@unchecked Sendable` parce qu'elle est mutable par les tests, qui sont tous sur
  /// l'acteur principal — la vraie source, elle, est immuable.
  private final class FakeProvider: CalendarAgendaProviding, @unchecked Sendable {

    var accessStatus: CalendarAccess
    var agenda: CalendarAgenda?
    var shouldFail = false
    private(set) var fetchCount = 0

    init(accessStatus: CalendarAccess = .granted, agenda: CalendarAgenda? = nil) {
      self.accessStatus = accessStatus
      self.agenda = agenda
    }

    func requestAccess() async -> CalendarAccess { accessStatus }

    func fetchAgenda(for date: Date) async throws -> CalendarAgenda {
      fetchCount += 1
      if shouldFail { throw CalendarAgendaError.unresolvableDayBounds }
      return agenda ?? Self.emptyAgenda(for: date)
    }

    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }

    static func emptyAgenda(for date: Date) -> CalendarAgenda {
      let calendar = Calendar.current
      let today = calendar.startOfDay(for: date)
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
      return CalendarAgenda(
        today: AgendaDay(date: today, events: []),
        tomorrow: AgendaDay(date: tomorrow, events: [])
      )
    }
  }

  /// Attend que le modèle de vue quitte `.loading`. `activate()` lance une tâche, et un test
  /// synchrone la lirait avant qu'elle n'ait rien produit.
  private static func waitForState(
    of viewModel: CalendarAgendaViewModel,
    while predicate: (CalendarAgendaState) -> Bool = { $0 == .loading }
  ) async {
    for _ in 0..<200 where predicate(viewModel.state) {
      await Task.yield()
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  private static func event(
    id: String,
    title: String,
    hour: Double,
    from startOfDay: Date,
    isAllDay: Bool = false
  ) -> AgendaEvent {
    AgendaEvent(
      id: id,
      title: title,
      start: startOfDay.addingTimeInterval(hour * 3600),
      end: startOfDay.addingTimeInterval((hour + 1) * 3600),
      isAllDay: isAllDay
    )
  }

  // MARK: - Chargement

  @Test("une journée garnie arrive dans l'état chargé, dans l'ordre servi par la source")
  func grantedAccessLoadsAgendaInOrder() async {
    let startOfDay = Calendar.current.startOfDay(for: Date())
    let agenda = CalendarAgenda(
      today: AgendaDay(
        date: startOfDay,
        events: [
          Self.event(id: "a", title: "Standup", hour: 9.5, from: startOfDay),
          Self.event(id: "b", title: "Revue", hour: 11, from: startOfDay),
        ]
      ),
      tomorrow: AgendaDay(date: startOfDay.addingTimeInterval(86400), events: [])
    )

    let provider = FakeProvider(agenda: agenda)
    let viewModel = CalendarAgendaViewModel(provider: provider)
    viewModel.activate()
    await Self.waitForState(of: viewModel)

    #expect(
      viewModel.state.agenda?.today.events.map(\.id) == ["a", "b"],
      "l'ordre servi n'est pas celui affiché")
    #expect(viewModel.state.agenda?.tomorrow.isEmpty == true, "demain devrait être vide")
  }

  @Test("un accès refusé ne déclenche aucune lecture et porte le refus dans l'état")
  func deniedAccessYieldsUnavailableState() async {
    let provider = FakeProvider(accessStatus: .denied)
    let viewModel = CalendarAgendaViewModel(provider: provider)
    viewModel.activate()
    await Self.waitForState(of: viewModel)

    #expect(viewModel.state == .unavailable(.denied), "le refus devrait être porté tel quel")
    #expect(viewModel.state.agenda == nil, "un refus ne doit pas laisser d'agenda affiché")
    #expect(provider.fetchCount == 0, "rien ne sert de lire le magasin sans le droit de le lire")
  }

  @Test("un accès pas encore accordé se distingue d'un refus")
  func notDeterminedAccessIsReportedAsSuch() async {
    let viewModel = CalendarAgendaViewModel(provider: FakeProvider(accessStatus: .notDetermined))
    viewModel.activate()
    await Self.waitForState(of: viewModel)

    #expect(viewModel.state == .unavailable(.notDetermined))
  }

  @Test("une lecture qui échoue garde l'agenda déjà affiché plutôt que de le vider")
  func failedRefreshKeepsPreviousAgenda() async {
    let startOfDay = Calendar.current.startOfDay(for: Date())
    let agenda = CalendarAgenda(
      today: AgendaDay(
        date: startOfDay,
        events: [Self.event(id: "a", title: "Standup", hour: 9.5, from: startOfDay)]),
      tomorrow: AgendaDay(date: startOfDay.addingTimeInterval(86400), events: [])
    )

    let provider = FakeProvider(agenda: agenda)
    let viewModel = CalendarAgendaViewModel(provider: provider)
    viewModel.activate()
    await Self.waitForState(of: viewModel)
    #expect(viewModel.state.agenda != nil)

    provider.shouldFail = true
    viewModel.refresh(force: true)
    await Self.waitForState(of: viewModel) { _ in provider.fetchCount < 2 }

    #expect(
      viewModel.state.agenda?.today.events.map(\.id) == ["a"],
      "l'agenda connu devrait survivre à l'échec")
  }

  // MARK: - Modèle

  @Test("un événement sans durée est reconnu comme ponctuel, et pas comme un intervalle")
  func zeroLengthEventIsPointInTime() {
    let now = Date()
    let reminder = AgendaEvent(id: "r", title: "Appeler maman", start: now, end: now)
    let meeting = AgendaEvent(
      id: "m", title: "Revue", start: now, end: now.addingTimeInterval(3600))
    let allDay = AgendaEvent(id: "d", title: "Sprint", start: now, end: now, isAllDay: true)

    #expect(reminder.isPointInTime)
    #expect(!meeting.isPointInTime)
    #expect(
      !allDay.isPointInTime, "un événement sur toute la journée s'écrit « All day », pas une heure")
  }

  @Test("les composantes d'une couleur de calendrier restent bornées à 0…1")
  func colorComponentsAreClamped() {
    let color = AgendaEventColor(red: 1.4, green: -0.2, blue: 0.5, alpha: 2)

    #expect(color.red == 1)
    #expect(color.green == 0)
    #expect(color.blue == 0.5)
    #expect(color.alpha == 1)
  }

  @Test(
    "la fausse source du drapeau de lancement sert une journée garnie, et rien si l'accès est refusé"
  )
  func mockProviderHonoursItsOwnAccessStatus() async throws {
    let granted = MockCalendarAgendaProvider.fromLaunchArguments(["--calendar-agenda=granted"])
    let denied = MockCalendarAgendaProvider.fromLaunchArguments(["--calendar-agenda=denied"])

    #expect(
      MockCalendarAgendaProvider.fromLaunchArguments([]) == nil,
      "sans drapeau, la vraie source doit servir")
    #expect(
      MockCalendarAgendaProvider.fromLaunchArguments(["--calendar-agenda=oui"]) == nil,
      "un drapeau mal formé ne doit pas être deviné")

    let grantedAgenda = try #require(try await granted?.fetchAgenda(for: Date()))
    #expect(!grantedAgenda.today.isEmpty, "la journée d'exemple devrait être garnie")
    #expect(!grantedAgenda.tomorrow.isEmpty, "demain devrait l'être aussi, pour voir l'intertitre")

    let deniedAgenda = try #require(try await denied?.fetchAgenda(for: Date()))
    #expect(deniedAgenda.isEmpty, "sans accès, la fausse source doit se taire comme la vraie")
  }

  // MARK: - Jour choisi dans la bande de la semaine

  @Test(
    "l'état d'un jour choisi garde ses événements et laisse demain vide, même si la source en sert")
  func dayStateKeepsOnlyTheChosenDay() async {
    let startOfDay = Calendar.current.startOfDay(for: Date())
    let agenda = CalendarAgenda(
      today: AgendaDay(
        date: startOfDay, events: [Self.event(id: "a", title: "Standup", hour: 9, from: startOfDay)]
      ),
      tomorrow: AgendaDay(
        date: startOfDay.addingTimeInterval(86400),
        events: [Self.event(id: "b", title: "Demain", hour: 9, from: startOfDay)]
      )
    )
    let viewModel = CalendarAgendaViewModel(provider: FakeProvider(agenda: agenda))

    let state = await viewModel.dayState(for: startOfDay)

    #expect(state.agenda?.today.events.map(\.id) == ["a"], "le jour choisi a perdu ses événements")
    #expect(
      state.agenda?.tomorrow.isEmpty == true,
      "la liste afficherait « Tomorrow » sous le jour choisi")
  }

  @Test("un jour sans événement reste chargé et vide, pour que la liste dise « No events »")
  func emptyDayStaysLoaded() async {
    let viewModel = CalendarAgendaViewModel(provider: FakeProvider())

    let state = await viewModel.dayState(for: Date())

    #expect(state.agenda?.isEmpty == true, "un jour vide ne doit pas devenir une erreur")
  }

  @Test("sans accès, le jour choisi porte le refus au lieu d'être vide")
  func dayStateCarriesAccessDenial() async {
    let provider = FakeProvider(accessStatus: .denied)
    let viewModel = CalendarAgendaViewModel(provider: provider)

    let state = await viewModel.dayState(for: Date())

    #expect(state == .unavailable(.denied), "l'écriteau d'accès refusé doit rester atteignable")
    #expect(provider.fetchCount == 0, "aucune lecture sans accès")
  }

  @Test("un accès accordé après coup est rattrapé à la lecture suivante d'un jour")
  func accessGrantedLaterIsPickedUpByDayRead() async {
    let provider = FakeProvider(accessStatus: .denied)
    let viewModel = CalendarAgendaViewModel(provider: provider)
    viewModel.activate()
    await Self.waitForState(of: viewModel)
    #expect(viewModel.state == .unavailable(.denied), "l'état de départ devrait porter le refus")

    // L'utilisateur accorde l'accès (carte d'accès ou Réglages Système), puis l'onglet relit un
    // jour : l'agenda partagé doit suivre, sans redémarrage.
    provider.accessStatus = .granted
    _ = await viewModel.dayState(for: Date())
    await Self.waitForState(of: viewModel) { $0.agenda == nil }

    #expect(viewModel.state.agenda != nil, "l'agenda partagé devrait être relu une fois l'accès accordé")
  }
}
