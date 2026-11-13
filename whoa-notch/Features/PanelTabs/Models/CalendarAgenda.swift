import CoreGraphics
import Foundation

// Tous les types de ce fichier sont `nonisolated` : le module est compilé avec
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, qui les isolerait sinon sur l'acteur principal —
// or c'est justement hors de lui que la source EventKit les construit, la lecture du magasin des
// calendriers ne devant pas s'y faire.

/// Couleur du calendrier d'un événement, portée en composantes plutôt qu'en `NSColor` ou
/// `CGColor` : la lecture d'EventKit se fait hors de l'acteur principal, et aucun de ces deux
/// types n'est `Sendable`. La conversion inverse a lieu au moment de peindre.
nonisolated struct AgendaEventColor: Equatable, Sendable {

  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double

  init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = min(1, max(0, red))
    self.green = min(1, max(0, green))
    self.blue = min(1, max(0, blue))
    self.alpha = min(1, max(0, alpha))
  }

  var cgColor: CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
  }

  /// Repli quand un calendrier n'annonce pas de couleur — rare, mais `EKCalendar.color` est
  /// optionnel et une barre d'accent invisible se lirait comme un défaut d'affichage.
  static let fallback = AgendaEventColor(red: 0.42, green: 0.42, blue: 0.42)
}

/// Un événement de la journée, réduit à ce que la liste affiche. Volontairement détaché
/// d'`EKEvent` : c'est ce qui permet au widget d'ignorer EventKit, et à une autre source de le
/// remplacer sans toucher aux vues.
nonisolated struct AgendaEvent: Equatable, Sendable, Identifiable {

  /// `EKEvent.eventIdentifier` quand il existe. Sert à comparer deux instantanés sans
  /// rapprocher les titres, qui peuvent être identiques dans la même journée.
  let id: String
  let title: String
  let start: Date
  let end: Date
  let isAllDay: Bool
  let color: AgendaEventColor

  init(
    id: String,
    title: String,
    start: Date,
    end: Date,
    isAllDay: Bool = false,
    color: AgendaEventColor = .fallback
  ) {
    self.id = id
    self.title = title
    self.start = start
    self.end = end
    self.isAllDay = isAllDay
    self.color = color
  }

  /// Événement sans durée — un rappel posé à une heure précise. La ligne n'affiche alors que
  /// son heure de début, et non un intervalle qui se lirait « 17:00 – 17:00 ».
  var isPointInTime: Bool { !isAllDay && end <= start }
}

/// Une journée et ses événements, déjà triés par la source : la vue affiche l'ordre qu'elle
/// reçoit et n'a pas de règle de tri à elle.
nonisolated struct AgendaDay: Equatable, Sendable {

  let date: Date
  let events: [AgendaEvent]

  var isEmpty: Bool { events.isEmpty }
}

/// Ce que le widget montre : aujourd'hui, et demain pour que la liste ne soit pas vide tous les
/// soirs.
nonisolated struct CalendarAgenda: Equatable, Sendable {

  let today: AgendaDay
  let tomorrow: AgendaDay

  var isEmpty: Bool { today.isEmpty && tomorrow.isEmpty }
}

/// Droit d'accès au calendrier, réduit aux trois cas qui changent l'affichage. EventKit en
/// distingue davantage (restreint, accès en écriture seule), mais ils mènent tous au même
/// écriteau.
nonisolated enum CalendarAccess: Equatable, Sendable {
  case notDetermined
  case denied
  case granted
}

/// État complet du widget, sur le modèle de `ClaudeUsageState` : la vue doit distinguer « pas
/// encore chargé » d'une journée réellement vide, et les deux d'un accès refusé — trois
/// situations qui ne se disent pas avec les mêmes mots.
nonisolated enum CalendarAgendaState: Equatable {
  case loading
  case loaded(CalendarAgenda)
  case unavailable(CalendarAccess)

  var agenda: CalendarAgenda? {
    if case .loaded(let agenda) = self { return agenda }
    return nil
  }
}

extension CalendarAgendaState {

  /// Le même état réduit à sa première journée : `AgendaListView` n'annonce « Tomorrow » que
  /// si demain a des événements, donc une liste dont demain est vide ne montre que le jour
  /// choisi, sans que la vue ait un mode de plus.
  nonisolated var showingFirstDayOnly: CalendarAgendaState {
    guard case .loaded(let agenda) = self else { return self }
    return .loaded(
      CalendarAgenda(
        today: agenda.today,
        tomorrow: AgendaDay(date: agenda.tomorrow.date, events: [])
      )
    )
  }
}
