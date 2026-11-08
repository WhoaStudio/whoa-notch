import AppKit
import Testing

@testable import whoa_stash

/// Mise en page du panneau de l'encoche : la boîte de contenu doit être **inscrite** dans la
/// silhouette dépliée.
///
/// Le panneau est suspendu au bord du haut, donc ce sont ses flancs gauche et droit que les
/// raccords concaves rentrent de `expandedShoulderRadius` — et non son haut et son bas, comme
/// sur une bande de flanc. Prendre les marges d'une bande telles quelles, sans les retourner,
/// laissait le contenu dépasser des flancs peints de la différence entre les deux marges.
@MainActor
struct NotchPanelGeometryTests {

  /// Un écran sans encoche suffit : la silhouette dépliée ne dépend pas de l'encoche, qui ne
  /// décide que de la silhouette repliée et de la marge haute.
  private static let collapsedHeight = NotchPanelGeometry.pillSize.height

  private static func expandedPath(_ size: NSSize) -> CGPath {
    PanelGeometry.silhouette(
      in: NotchPanelGeometry.panelRect(in: NSRect(origin: .zero, size: size), tab: .ai),
      anchoredTo: .top,
      shoulderRadius: NotchPanelGeometry.expandedShoulderRadius,
      farRadius: NotchPanelGeometry.expandedBottomRadius
    )
  }

  /// La boîte de contenu, telle que `NotchPanelContentView` la pose : les marges de la
  /// géométrie retranchées du **panneau**, et non du cadre de la fenêtre — celui-ci porte en
  /// plus la bande basse où flotte la capsule, où le panneau ne peint rien.
  private static func contentBox(_ size: NSSize) -> NSRect {
    let inset = NotchPanelGeometry.contentInsetX
    let panel = NotchPanelGeometry.panelRect(in: NSRect(origin: .zero, size: size), tab: .ai)
    return NSRect(
      x: panel.minX + inset,
      y: panel.minY + NotchPanelGeometry.contentInsetBottom,
      width: panel.width - 2 * inset,
      height: panel.height
        - NotchPanelGeometry.contentInsetTop(forCollapsedHeight: collapsedHeight)
        - NotchPanelGeometry.contentInsetBottom
    )
  }

  @Test("les quatre coins de la boîte de contenu tombent dans la silhouette dépliée")
  func contentBoxFitsInsideExpandedSilhouette() {
    let size = NotchPanelGeometry.expandedSize(collapsedHeight: Self.collapsedHeight)
    let path = Self.expandedPath(size)
    let box = Self.contentBox(size)

    for corner in [
      CGPoint(x: box.minX, y: box.minY),
      CGPoint(x: box.maxX, y: box.minY),
      CGPoint(x: box.minX, y: box.maxY),
      CGPoint(x: box.maxX, y: box.maxY),
    ] {
      #expect(path.contains(corner), "le coin \(corner) sort de la silhouette")
    }
  }

  /// Le bord du contenu ne doit pas seulement tomber dans le chemin à ses quatre coins : les
  /// deux flancs sont échantillonnés sur toute leur hauteur, puisque c'est là que les raccords
  /// concaves rognent.
  @Test("les deux flancs de la boîte de contenu restent dans la silhouette sur toute leur hauteur")
  func contentBoxSidesStayInsideExpandedSilhouette() {
    let size = NotchPanelGeometry.expandedSize(collapsedHeight: Self.collapsedHeight)
    let path = Self.expandedPath(size)
    let box = Self.contentBox(size)

    for step in 0...40 {
      let y = box.minY + box.height * CGFloat(step) / 40
      #expect(path.contains(CGPoint(x: box.minX, y: y)), "le flanc gauche sort à y = \(y)")
      #expect(path.contains(CGPoint(x: box.maxX, y: y)), "le flanc droit sort à y = \(y)")
    }
  }

  /// La marge horizontale est celle qui court **le long** du bord d'accroche, donc celle qui
  /// doit couvrir le rayon des raccords. C'est l'invariant que l'ancienne mise en page violait.
  @Test("la marge horizontale couvre le rayon des raccords concaves")
  func horizontalInsetCoversShoulderRadius() {
    #expect(NotchPanelGeometry.contentInsetX >= NotchPanelGeometry.expandedShoulderRadius)
  }

  /// La capsule est centrée sous le panneau : elle doit tenir dans sa largeur, sans quoi elle
  /// déborderait de la silhouette au lieu de flotter sous elle.
  @Test("le panneau est assez large pour porter la capsule")
  func expandedSizeHoldsTabCapsule() {
    let size = NotchPanelGeometry.expandedSize(collapsedHeight: Self.collapsedHeight)
    #expect(size.width >= NotchTabCapsuleView.width)
  }

  /// La bande basse appartient à la capsule : la silhouette du panneau s'arrête au-dessus, et
  /// la capsule se pose dedans sans la toucher.
  @Test("la capsule tient dans la bande basse, sous le panneau")
  func capsuleSitsBelowThePanel() {
    let size = NotchPanelGeometry.expandedSize(collapsedHeight: Self.collapsedHeight)
    let bounds = NSRect(origin: .zero, size: size)
    for tab in NotchTab.allCases {
      let capsule = NotchPanelGeometry.capsuleRect(in: bounds, tab: tab)
      let panel = NotchPanelGeometry.panelRect(in: bounds, tab: tab)

      #expect(capsule.maxY <= panel.minY)
      #expect(panel.minY - capsule.maxY == NotchPanelGeometry.capsuleGap)
      #expect(capsule.minY >= bounds.minY)
    }
  }

  /// La fenêtre garde un cadre fixe : l'onglet Terminal doit tenir dans celui que dimensionnent
  /// les autres, sans le faire grandir.
  @Test("l'onglet Terminal tient dans le cadre de la fenêtre")
  func terminalTabFitsTheWindow() {
    #expect(NotchPanelGeometry.contentHeight(for: .terminal) <= NotchPanelGeometry.tabContentHeight)
    #expect(NotchPanelGeometry.contentWidth(for: .terminal) <= NotchPanelGeometry.tabContentWidth)
  }

  /// Sur un Mac à encoche, le cadre de la fenêtre part du bord haut de la dalle : le contenu
  /// doit commencer sous l'encoche, qui couvre le haut du panneau.
  @Test("la marge haute dégage l'encoche matérielle")
  func topInsetClearsTheNotch() {
    let notchHeight: CGFloat = 38
    #expect(NotchPanelGeometry.contentInsetTop(forCollapsedHeight: notchHeight) > notchHeight)
  }

  // MARK: - Onglets calendrier

  /// La bande de la semaine reste dans Global, tandis que le nouvel onglet Calendar reçoit
  /// toute la hauteur du contenu pour afficher la grille du mois sans la tasser.
  @Test("l'onglet Calendar laisse la grille du mois respirer")
  func calendarTabHoldsMonthGrid() {
    let calendarHeight = NotchPanelGeometry.calendarTabHeight
    #expect(
      calendarHeight >= 15 + CGFloat(MonthGridLayout.weekRowCount) * 20,
      "la grille du mois serait tassée dans \(calendarHeight) pt"
    )
  }

  /// Le panneau garde une seule taille d'un onglet à l'autre, et c'est le plus haut qui la
  /// fixe. L'invariant vaut quel que soit celui qui prend la tête.
  @Test("la hauteur de contenu couvre tous les onglets")
  func tabContentHeightCoversEveryTab() {
    #expect(NotchPanelGeometry.tabContentHeight >= NotchPanelGeometry.calendarTabHeight)
    #expect(NotchPanelGeometry.tabContentHeight >= NotchPanelGeometry.aiTabHeight)
    #expect(NotchPanelGeometry.tabContentHeight >= NotchPanelGeometry.analyticsTabHeight)
    #expect(NotchPanelGeometry.tabContentHeight >= NotchPanelGeometry.weekStripHeight)
  }

  /// Seul l'onglet Analytics est plus haut : les autres gardent leur panneau court, suspendu au même
  /// bord haut, et la capsule remonte sous lui.
  @Test("le panneau ne grandit que pour l'onglet Analytics")
  func panelGrowsOnlyForAnalytics() {
    let size = NotchPanelGeometry.expandedSize(collapsedHeight: Self.collapsedHeight)
    let bounds = NSRect(origin: .zero, size: size)
    let analytics = NotchPanelGeometry.panelRect(in: bounds, tab: .analytics)
    let calendar = NotchPanelGeometry.panelRect(in: bounds, tab: .calendar)

    #expect(analytics.maxY == calendar.maxY)
    #expect(
      analytics.height - calendar.height
        == NotchPanelGeometry.analyticsTabHeight - NotchPanelGeometry.calendarTabHeight)
  }

  /// Les deux colonnes du widget se partagent la largeur de l'onglet : la grille du mois est
  /// calée à droite, et il doit rester de quoi écrire un agenda à gauche.
  @Test("la grille du mois laisse une colonne utile à l'agenda")
  func monthGridLeavesRoomForTheAgenda() {
    let size = NotchPanelGeometry.expandedSize(collapsedHeight: Self.collapsedHeight)
    let bodyWidth = size.width - 2 * NotchPanelGeometry.contentInsetX
    let agendaWidth =
      bodyWidth
      - NotchPanelGeometry.monthGridWidth
      - NotchPanelGeometry.columnGap
      - NotchPanelGeometry.dividerWidth

    #expect(
      agendaWidth > NotchPanelGeometry.monthGridWidth,
      "l'agenda porte du texte, il doit rester le plus large")
  }

  @Test("la pastille flottante est détachée du bord du haut et reste dans sa boîte")
  func islandFloatsBelowTheTopEdge() {
    let rect = CGRect(x: 0, y: 0, width: 400, height: 200)
    let gap = NotchPanelGeometry.islandTopGap
    let bounds = PanelGeometry.islandSilhouette(
      in: rect, size: NotchPanelGeometry.pillSize, topGap: gap
    ).boundingBoxOfPath

    #expect(abs(bounds.maxY - (rect.maxY - gap)) < 0.01)
    #expect(abs(bounds.height - NotchPanelGeometry.pillSize.height) < 0.01)
    #expect(abs(bounds.midX - rect.midX) < 0.01)
  }

  @Test("un écran sans encoche en mode notch garde la silhouette collée au bord")
  func notchStyleHasNoGap() {
    guard
      let screen = NSScreen.screens.first(where: { NotchPanelGeometry.notchRect(on: $0) == nil })
    else { return }
    #expect(NotchPanelGeometry.collapsedTopGap(on: screen, style: .notch) == 0)
    #expect(
      NotchPanelGeometry.collapsedTopGap(on: screen, style: .island)
        == NotchPanelGeometry.islandTopGap)
  }

  @Test("l'île dépliée est une pastille détachée du bord, sans raccords concaves")
  func expandedIslandIsAFloatingPill() {
    let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
    let gap = NotchPanelGeometry.islandTopGap
    let path = PanelGeometry.islandSilhouette(
      in: rect, size: rect.size, topGap: gap, cornerRadius: NotchPanelGeometry.expandedBottomRadius)
    let bounds = path.boundingBoxOfPath

    #expect(abs(bounds.maxY - (rect.maxY - gap)) < 0.01)
    #expect(abs(bounds.width - rect.width) < 0.01)
    #expect(
      !path.contains(CGPoint(x: bounds.minX + 1, y: bounds.maxY - 1)), "le coin haut est arrondi")
    #expect(NotchPanelGeometry.islandPillSize.width < NotchPanelGeometry.pillSize.width)
    #expect(NotchPanelGeometry.islandPillSize.height > NotchPanelGeometry.pillSize.height)
  }
}
