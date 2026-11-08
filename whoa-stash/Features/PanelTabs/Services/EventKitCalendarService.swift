import AppKit
import EventKit
import Foundation
import OSLog

/// Le seul endroit de l'app qui importe EventKit. Tout ce qui en sort est converti ici en
/// valeurs de `CalendarAgenda`, donc ni le modèle de vue ni les vues n'ont à connaître
/// `EKEvent`.
///
/// `nonisolated` de bout en bout : le module est compilé avec `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, et la lecture du magasin ne doit surtout pas s'y faire — voir `fetchAgenda`.
///
/// `@unchecked Sendable` parce qu'`EKEventStore` ne l'est pas : il est pourtant fait pour être
/// interrogé depuis n'importe quel fil, et toutes les lectures passent ici par `queue`, qui est
/// série. Ce qui n'est pas sûr à promener entre fils, ce sont les `EKEvent` qu'il renvoie — et
/// justement, aucun ne sort de la file : ils sont convertis en valeurs avant d'en ressortir.
nonisolated final class EventKitCalendarService: CalendarAgendaProviding, @unchecked Sendable {

  /// Un seul magasin pour toute la vie de l'app : en construire un par lecture relancerait à
  /// chaque fois la connexion au démon des calendriers, et invaliderait les identifiants
  /// d'événements déjà affichés.
  private let store = EKEventStore()

  /// File série des lectures. `events(matching:)` étant synchrone et parfois lent, elle tient
  /// deux rôles : sortir le travail du fil principal, et empêcher deux lectures de se
  /// chevaucher sur le même magasin.
  private let queue = DispatchQueue(
    label: "ugolin-olle.whoa-stash.calendar-fetch", qos: .userInitiated)

  var accessStatus: CalendarAccess {
    Self.access(from: EKEventStore.authorizationStatus(for: .event))
  }

  func requestAccess() async -> CalendarAccess {
    // Rien à demander si le système a déjà tranché : redemander n'ouvrirait aucune fenêtre
    // et renverrait la même réponse.
    guard accessStatus == .notDetermined else { return accessStatus }

    do {
      _ = try await store.requestFullAccessToEvents()
    } catch {
      Log.calendar.error(
        "demande d'accès aux calendriers échouée — \(error.localizedDescription, privacy: .public)")
    }
    // On relit le statut plutôt que de se fier au booléen renvoyé : c'est le système qui
    // fait foi, et lui seul sait si l'accès obtenu est complet.
    return accessStatus
  }

  /// Les événements d'`date` et du lendemain, en une seule interrogation du magasin.
  ///
  /// `events(matching:)` est **synchrone** et Apple demande expressément de ne pas l'appeler
  /// sur le fil principal : un calendrier chargé ou un compte distant lent y figerait tout
  /// l'overlay. D'où le saut sur `queue` — et la conversion vers `AgendaEvent` **à
  /// l'intérieur** de ce saut, `EKEvent` n'étant pas `Sendable` et ne pouvant donc pas en
  /// ressortir.
  func fetchAgenda(for date: Date) async throws -> CalendarAgenda {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: date)

    guard
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
      let dayAfter = calendar.date(byAdding: .day, value: 2, to: today)
    else {
      throw CalendarAgendaError.unresolvableDayBounds
    }

    // Journées vides plutôt qu'une erreur : un accès refusé est un état que le widget sait
    // dire, pas une panne.
    guard accessStatus == .granted else {
      return CalendarAgenda(
        today: AgendaDay(date: today, events: []),
        tomorrow: AgendaDay(date: tomorrow, events: [])
      )
    }

    return await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(
          returning: self.agenda(
            calendar: calendar, today: today, tomorrow: tomorrow, dayAfter: dayAfter)
        )
      }
    }
  }

  func changes() -> AsyncStream<Void> {
    AsyncStream { continuation in
      // `nonisolated(unsafe)` : le jeton renvoyé par `addObserver` n'est pas `Sendable`,
      // et la terminaison du flux est un contexte `@Sendable`. Il est sûr ici parce que
      // rien ne le lit ni ne le mute — il est seulement rendu tel quel au centre de
      // notifications, qui est lui-même sûr à appeler depuis n'importe quel fil.
      nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
        forName: .EKEventStoreChanged,
        object: store,
        queue: .main
      ) { _ in
        continuation.yield()
      }

      continuation.onTermination = { _ in
        NotificationCenter.default.removeObserver(observer)
      }
    }
  }

  // MARK: - Lecture

  /// Exécuté sur `queue`. Tout ce qui touche à `EKEvent` reste dans cette méthode.
  private func agenda(calendar: Calendar, today: Date, tomorrow: Date, dayAfter: Date)
    -> CalendarAgenda
  {
    let predicate = store.predicateForEvents(withStart: today, end: dayAfter, calendars: nil)
    let events = store.events(matching: predicate)

    // Un événement à cheval sur minuit est renvoyé pour les deux journées : il est rangé
    // sous celle où il commence, sauf s'il a commencé avant la fenêtre — auquel cas il
    // appartient au premier jour affiché.
    let grouped = Dictionary(grouping: events) { event -> Date in
      calendar.startOfDay(for: max(event.startDate ?? today, today))
    }

    return CalendarAgenda(
      today: AgendaDay(date: today, events: Self.agendaEvents(from: grouped[today] ?? [])),
      tomorrow: AgendaDay(date: tomorrow, events: Self.agendaEvents(from: grouped[tomorrow] ?? []))
    )
  }

  // MARK: - Conversion

  /// Trie puis convertit. Le tri a lieu ici, et non dans la vue, pour que toute source future
  /// serve ses journées dans le même ordre : les événements sur toute la journée d'abord —
  /// ils ne commencent à aucune heure et flotteraient n'importe où dans un tri par date —,
  /// puis l'ordre chronologique, puis le titre, qui départage deux événements simultanés et
  /// rend l'ordre stable d'une lecture à l'autre.
  private static func agendaEvents(from events: [EKEvent]) -> [AgendaEvent] {
    events
      .sorted { lhs, rhs in
        if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }

        let leftStart = lhs.startDate ?? .distantPast
        let rightStart = rhs.startDate ?? .distantPast
        if leftStart != rightStart { return leftStart < rightStart }

        return (lhs.title ?? "") < (rhs.title ?? "")
      }
      .compactMap(agendaEvent(from:))
  }

  /// `nil` pour un événement sans date de début : il n'a pas de place dans une liste
  /// chronologique, et EventKit en renvoie à l'occasion sur des comptes distants mal
  /// synchronisés.
  private static func agendaEvent(from event: EKEvent) -> AgendaEvent? {
    guard let start = event.startDate else { return nil }

    let title = event.title ?? ""
    return AgendaEvent(
      // `eventIdentifier` est vide pour certains événements d'abonnements ; l'empreinte de
      // repli suffit à distinguer deux lignes d'une même journée.
      id: event.eventIdentifier ?? "\(start.timeIntervalSinceReferenceDate)-\(title)",
      title: title,
      start: start,
      end: event.endDate ?? start,
      isAllDay: event.isAllDay,
      color: color(of: event)
    )
  }

  /// La couleur du calendrier porteur, ramenée en sRGB : `EKCalendar` la donne dans l'espace
  /// où elle a été choisie, et lire ses composantes sans conversion donnerait une teinte
  /// fausse — ou lèverait, pour une couleur à motif.
  private static func color(of event: EKEvent) -> AgendaEventColor {
    guard
      let cgColor = event.calendar?.cgColor,
      let srgb = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB)
    else {
      return .fallback
    }

    return AgendaEventColor(
      red: srgb.redComponent,
      green: srgb.greenComponent,
      blue: srgb.blueComponent,
      alpha: srgb.alphaComponent
    )
  }

  private static func access(from status: EKAuthorizationStatus) -> CalendarAccess {
    switch status {
    case .notDetermined: .notDetermined
    case .fullAccess: .granted
    // Refusé, restreint, ou écriture seule : le widget ne peut rien lire, et les trois se
    // disent à l'utilisateur avec les mêmes mots.
    default: .denied
    }
  }
}

nonisolated enum CalendarAgendaError: Error {
  /// Le calendrier de l'utilisateur n'a pas su situer le lendemain — inatteignable en
  /// pratique, mais `Calendar.date(byAdding:)` est optionnel et l'avaler masquerait un vrai
  /// défaut.
  case unresolvableDayBounds
}
