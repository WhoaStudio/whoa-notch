import AppKit

/// Liste des événements du jour : une barre d'accent à la couleur du calendrier porteur, l'heure,
/// puis le titre. Quand la journée est épuisée, la liste enchaîne sur demain sous un intertitre —
/// sans quoi le widget serait vide tous les soirs.
///
/// Dessinée dans `draw(_:)`, comme `MonthGridView` : une ligne n'est qu'une barre et deux chaînes,
/// et la liste change au rythme des événements, pas à celui de la souris.
final class AgendaListView: NSView {

  private var state: CalendarAgendaState = .loading

  /// Hauteur d'une ligne d'événement.
  private let rowHeight: CGFloat = 24

  /// Hauteur de l'intertitre « Tomorrow », plus serré qu'une ligne d'événement : il sépare, il
  /// ne s'énumère pas.
  private let headingHeight: CGFloat = 18

  /// Largeur de la barre d'accent et son écart au texte.
  private let accentWidth: CGFloat = 3
  private let accentGap: CGFloat = 9

  /// Largeur réservée à l'heure, devant le titre. Fixe, pour que tous les titres s'alignent :
  /// mesurer chaque heure les ferait tous danser d'une ligne à l'autre.
  private let timeColumnWidth: CGFloat = 52

  /// Heures affichées dans le format de l'utilisateur — 24 h en France, AM/PM aux États-Unis.
  private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("j:mm")
    return formatter
  }()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ newState: CalendarAgendaState, travel: CGFloat? = nil) {
    guard newState != state else { return }
    state = newState
    needsDisplay = true
    if let travel, window != nil {
      layer?.springReveal(x: travel, y: travel == 0 ? -8 : 0)
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  // MARK: - Ce qu'il y a à écrire

  /// Une entrée de la liste, déjà résolue : la mise en page n'a plus à distinguer d'où vient la
  /// ligne, et le calcul de ce qui tient dans la hauteur se fait sur une seule séquence.
  private enum Entry {
    case heading(String)
    case event(AgendaEvent)
  }

  private func entries() -> [Entry] {
    guard let agenda = state.agenda else { return [] }

    var entries = agenda.today.events.map(Entry.event)
    // Demain ne s'annonce que s'il a quelque chose à annoncer, et toujours sous son
    // intertitre : sans lui, les événements de demain se liraient comme ceux d'aujourd'hui.
    if !agenda.tomorrow.isEmpty {
      entries.append(.heading("Tomorrow"))
      entries.append(contentsOf: agenda.tomorrow.events.map(Entry.event))
    }
    return entries
  }

  /// Mot à afficher quand il n'y a aucune ligne. Les trois situations ne se disent pas avec les
  /// mêmes mots : l'utilisateur doit savoir s'il n'a rien de prévu, ou si l'app n'a simplement
  /// pas le droit de le lui dire.
  private var placeholder: String? {
    switch state {
    case .loading:
      nil
    case .loaded:
      "No events"
    case .unavailable(.notDetermined):
      "Calendar access not granted"
    case .unavailable:
      "Calendar access denied — enable it in System Settings"
    }
  }

  // MARK: - Tracé

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let palette = OverlayPalette.resolved(for: effectiveAppearance)
    let all = entries()

    guard !all.isEmpty else {
      if let placeholder {
        draw(
          placeholder,
          font: .systemFont(ofSize: 11, weight: .regular),
          color: palette.tabInactiveContent,
          at: NSPoint(x: bounds.minX, y: bounds.maxY - rowHeight)
        )
      }
      return
    }

    // Ce qui tient dans la hauteur. Une ligne de trop vaut mieux qu'un titre coupé en deux,
    // donc on s'arrête à la dernière entrée entièrement visible et on dit combien il en
    // reste.
    var shown: [Entry] = []
    var used: CGFloat = 0
    for entry in all {
      let height = self.height(of: entry)
      guard used + height <= bounds.height else { break }
      shown.append(entry)
      used += height
    }

    let hidden = all.count - shown.count
    // La mention du reste prend elle-même une ligne : si elle ne tient pas, on sacrifie la
    // dernière entrée affichée pour la lui laisser.
    if hidden > 0, used + headingHeight > bounds.height, let last = shown.popLast() {
      used -= height(of: last)
    }

    var y = bounds.maxY
    for entry in shown {
      let height = self.height(of: entry)
      y -= height
      draw(
        entry, in: NSRect(x: bounds.minX, y: y, width: bounds.width, height: height),
        palette: palette)
    }

    let remaining = all.count - shown.count
    if remaining > 0 {
      draw(
        "+\(remaining) more",
        font: .systemFont(ofSize: 10, weight: .medium),
        color: palette.tabInactiveContent,
        at: NSPoint(x: bounds.minX + accentWidth + accentGap, y: y - headingHeight + 4)
      )
    }
  }

  private func height(of entry: Entry) -> CGFloat {
    switch entry {
    case .heading: headingHeight
    case .event: rowHeight
    }
  }

  private func draw(_ entry: Entry, in rect: NSRect, palette: OverlayPalette) {
    switch entry {
    case .heading(let title):
      draw(
        title.uppercased(),
        font: .systemFont(ofSize: 9, weight: .semibold),
        color: palette.tabInactiveContent,
        at: NSPoint(x: rect.minX, y: rect.minY + 4)
      )

    case .event(let event):
      // Barre d'accent à la couleur du calendrier porteur : c'est le seul endroit du
      // panneau où la couleur ne vient pas de la palette, et c'est voulu — elle est le
      // rappel du calendrier d'où sort l'événement.
      let bar = NSRect(
        x: rect.minX,
        y: rect.minY + 3,
        width: accentWidth,
        height: rect.height - 6
      )
      let accent = NSColor(cgColor: event.color.cgColor) ?? palette.tabActiveContent
      accent.setFill()
      NSBezierPath(roundedRect: bar, xRadius: accentWidth / 2, yRadius: accentWidth / 2).fill()

      // Le titre et l'heure se teintent de cette même couleur, relevée pour l'un,
      // assombrie pour l'autre : les trois marques d'une ligne disent alors le même
      // calendrier, là où un titre blanc et une heure grise les détachaient de leur barre.
      let textY = rect.midY - 7
      draw(
        time(of: event),
        font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium),
        color: OverlayPalette.agendaTimeColor(for: accent),
        at: NSPoint(x: bar.maxX + accentGap, y: textY)
      )

      let titleX = bar.maxX + accentGap + timeColumnWidth
      draw(
        event.title.isEmpty ? "(no title)" : event.title,
        font: .systemFont(ofSize: 11, weight: .regular),
        color: OverlayPalette.agendaTitleColor(for: accent),
        at: NSPoint(x: titleX, y: textY),
        maxWidth: rect.maxX - titleX
      )
    }
  }

  /// « All day » pour un événement sans heure, l'heure seule pour un rappel sans durée — qui
  /// s'écrirait sinon « 17:00 – 17:00 » —, et l'heure de début sinon. La liste étant étroite,
  /// l'heure de fin n'y figure jamais : c'est le début qui situe la journée.
  private func time(of event: AgendaEvent) -> String {
    guard !event.isAllDay else { return "All day" }
    return timeFormatter.string(from: event.start)
  }

  private func draw(
    _ text: String,
    font: NSFont,
    color: NSColor,
    at point: NSPoint,
    maxWidth: CGFloat? = nil
  ) {
    var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]

    if let maxWidth {
      // Les titres d'événements sont écrits par l'utilisateur et débordent vite : on coupe
      // par des points de suspension plutôt que de laisser le texte sortir de la colonne.
      let style = NSMutableParagraphStyle()
      style.lineBreakMode = .byTruncatingTail
      attributes[.paragraphStyle] = style

      NSAttributedString(string: text, attributes: attributes).draw(
        with: NSRect(
          x: point.x, y: point.y, width: max(0, maxWidth), height: font.boundingRectForFont.height),
        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
      )
      return
    }

    NSAttributedString(string: text, attributes: attributes).draw(at: point)
  }
}
