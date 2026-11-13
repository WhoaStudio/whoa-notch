import Foundation

/// Source des événements du widget calendrier. L'abstraction existe pour deux raisons : le
/// widget est développable et vérifiable sans toucher aux calendriers de la machine
/// (`MockCalendarAgendaProvider`), exactement comme `ClaudeUsageProviding` permet de développer
/// la bague sans réseau ; et EventKit reste enfermé dans une seule implémentation, donc aucune
/// vue ne l'importe.
///
/// Le flux de changements fait partie du contrat plutôt que d'être observé en amont : sans lui,
/// le modèle de vue devrait nommer `.EKEventStoreChanged`, importer EventKit, et l'isolement
/// n'aurait plus d'objet.
nonisolated protocol CalendarAgendaProviding: Sendable {

  /// Droit d'accès tel que le système le connaît maintenant, sans rien demander à
  /// l'utilisateur.
  var accessStatus: CalendarAccess { get }

  /// Demande l'accès si besoin et renvoie le droit obtenu. Appelé une fois, à l'activation.
  func requestAccess() async -> CalendarAccess

  /// Les événements d'`date` et du lendemain. Lève si la lecture échoue ; un accès refusé
  /// n'est pas une erreur mais un état, porté par `accessStatus`.
  func fetchAgenda(for date: Date) async throws -> CalendarAgenda

  /// Émet à chaque fois que la base des calendriers change, pour que le widget se recharge
  /// sans attendre la prochaine ouverture du panneau.
  func changes() -> AsyncStream<Void>
}

// MARK: - Source de développement

/// Journée fixe injectée par `--calendar-agenda=<granted|denied|notDetermined>`, dans le même
/// esprit que `--claude-usage=` déjà géré par `AppDelegate`.
///
/// C'est le seul moyen d'atteindre l'écriteau d'accès refusé sans révoquer pour de bon
/// l'autorisation de l'app dans les Réglages Système, et de voir une liste garnie sur une
/// machine dont le calendrier est vide.
nonisolated struct MockCalendarAgendaProvider: CalendarAgendaProviding {

  let accessStatus: CalendarAccess

  func requestAccess() async -> CalendarAccess { accessStatus }

  func fetchAgenda(for date: Date) async throws -> CalendarAgenda {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: date)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

    // Sans le droit d'accès, la fausse source se comporte comme la vraie : des journées
    // vides. C'est ce qui rend l'écriteau de refus vérifiable.
    guard accessStatus == .granted else {
      return CalendarAgenda(
        today: AgendaDay(date: today, events: []),
        tomorrow: AgendaDay(date: tomorrow, events: [])
      )
    }

    return CalendarAgenda(
      today: AgendaDay(date: today, events: Self.sampleToday(from: today)),
      tomorrow: AgendaDay(date: tomorrow, events: Self.sampleTomorrow(from: tomorrow))
    )
  }

  /// Rien à signaler : la journée est figée, donc le flux se termine aussitôt plutôt que de
  /// laisser une tâche attendre une notification qui ne viendra jamais.
  func changes() -> AsyncStream<Void> {
    AsyncStream { $0.finish() }
  }

  /// Parse `--calendar-agenda=denied`. Renvoie `nil` si l'argument est absent ou mal formé,
  /// pour que l'app retombe silencieusement sur la vraie source.
  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments)
    -> MockCalendarAgendaProvider?
  {
    guard let argument = arguments.first(where: { $0.hasPrefix("--calendar-agenda=") }) else {
      return nil
    }

    return switch argument.dropFirst("--calendar-agenda=".count) {
    case "granted": MockCalendarAgendaProvider(accessStatus: .granted)
    case "denied": MockCalendarAgendaProvider(accessStatus: .denied)
    case "notDetermined": MockCalendarAgendaProvider(accessStatus: .notDetermined)
    default: nil
    }
  }

  // MARK: - Journées d'exemple

  /// Volontairement variée : un événement sur toute la journée, deux événements à durée, et un
  /// rappel sans durée — les trois formes que la ligne doit savoir écrire.
  private static func sampleToday(from startOfDay: Date) -> [AgendaEvent] {
    [
      AgendaEvent(
        id: "mock.allday",
        title: "Sprint 42",
        start: startOfDay,
        end: startOfDay.addingTimeInterval(24 * 3600),
        isAllDay: true,
        color: AgendaEventColor(red: 0.58, green: 0.44, blue: 0.86)
      ),
      AgendaEvent(
        id: "mock.standup",
        title: "Standup",
        start: startOfDay.addingTimeInterval(9.5 * 3600),
        end: startOfDay.addingTimeInterval(9.75 * 3600),
        color: AgendaEventColor(red: 0.22, green: 0.6, blue: 0.95)
      ),
      AgendaEvent(
        id: "mock.review",
        title: "Revue de design",
        start: startOfDay.addingTimeInterval(11 * 3600),
        end: startOfDay.addingTimeInterval(12 * 3600),
        color: AgendaEventColor(red: 0.95, green: 0.62, blue: 0.2)
      ),
      AgendaEvent(
        id: "mock.call",
        title: "Appeler maman",
        start: startOfDay.addingTimeInterval(17 * 3600),
        end: startOfDay.addingTimeInterval(17 * 3600),
        color: AgendaEventColor(red: 0.92, green: 0.3, blue: 0.35)
      ),
    ]
  }

  private static func sampleTomorrow(from startOfDay: Date) -> [AgendaEvent] {
    [
      AgendaEvent(
        id: "mock.planning",
        title: "Planification",
        start: startOfDay.addingTimeInterval(9 * 3600),
        end: startOfDay.addingTimeInterval(10 * 3600),
        color: AgendaEventColor(red: 0.22, green: 0.6, blue: 0.95)
      )
    ]
  }
}
