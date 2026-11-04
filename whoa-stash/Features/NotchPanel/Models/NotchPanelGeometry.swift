import AppKit

/// Géométrie du panneau de l'encoche pour un écran donné : la silhouette repliée (l'encoche
/// matérielle quand il y en a une, une pastille posée sous la barre de menus sinon), la
/// silhouette dépliée, et la zone sensible qui déclenche le dépliage. Tout est exprimé en
/// coordonnées globales AppKit (origine en bas à gauche de l'écran principal, axe Y vers le haut).
///
/// Jumelle de `SidePanelGeometry`, qui reste la géométrie du panneau du bord droit : les deux
/// placements coexistent, chacun avec son bord d'accroche et sa silhouette, mais ils tiennent
/// leur rayon, leurs marges, leurs écarts et leur filet de `PanelGeometry` — c'est ce qui les
/// fait se lire comme deux états d'une même surface.
enum NotchPanelGeometry {

    // MARK: - Silhouette

    /// Rayon des deux raccords **concaves** du haut, là où le panneau s'évase dans le bord
    /// auquel il est suspendu — le haut de l'écran sur un Mac à encoche, le bas de la barre de
    /// menus sinon.
    /// Le rayon replié est celui de la poignée du fonds commun : la silhouette doit se confondre
    /// avec l'encoche matérielle, qui est trop basse pour porter celui du panneau.
    static let collapsedShoulderRadius = PanelGeometry.collapsedShoulderRadius
    static let expandedShoulderRadius = PanelGeometry.cornerRadius

    /// Rayon des deux coins **convexes** du bas.
    static let collapsedBottomRadius = PanelGeometry.collapsedFarRadius
    static let expandedBottomRadius = PanelGeometry.cornerRadius

    // MARK: - État replié

    /// Largeur retenue quand l'écran annonce une encoche sans que la largeur des deux bandes de
    /// barre de menus soit lisible — l'encoche des MacBook actuels mesure environ cela.
    static let fallbackNotchWidth: CGFloat = 190

    /// Pastille affichée sur les Macs sans encoche : assez large pour se lire comme une poignée,
    /// assez basse pour ne rien masquer de ce qui est sous la barre de menus. C'est la poignée du
    /// fonds commun, posée ici sur le bord du haut.
    static let pillSize = PanelGeometry.collapsedHandleSize

    /// Pastille du mode île : un peu plus étroite et plus haute que la poignée commune.
    static let islandPillSize = CGSize(width: 140, height: 26)

    // MARK: - État déplié

    /// Marges intérieures du contenu. Celles de la bande du bord droit, mais prises dans le bon
    /// repère : ce panneau est suspendu au bord du **haut**, donc ce sont ses flancs gauche et
    /// droit qui courent le long du bord d'accroche — l'inverse d'une bande de flanc.
    ///
    /// La marge horizontale vaut donc au moins le rayon de la silhouette : les deux raccords
    /// concaves rentrent les flancs peints de `expandedShoulderRadius` de chaque côté, et tout
    /// contenu posé en deçà sort du chemin.
    /// Extra breathing room keeps the tab content from feeling pressed against the rounded
    /// shoulders of the notch panel.
    static let contentInsetX = PanelGeometry.contentInsetAlongAnchor + 8

    /// Ce que les coins convexes du bas rognent à l'aplomb du bord du contenu : la marge basse
    /// s'en augmente, sans quoi ce qui descend jusqu'en bas — le liseré du bac à fichiers —
    /// mordrait l'arrondi.
    static var bottomCornerBite: CGFloat {
        let offset = expandedShoulderRadius + expandedBottomRadius - contentInsetX
        guard abs(offset) < expandedBottomRadius else { return 0 }
        return expandedBottomRadius - (expandedBottomRadius * expandedBottomRadius - offset * offset).squareRoot()
    }

    static var contentInsetBottom: CGFloat {
        PanelGeometry.contentInsetAcrossAnchor + bottomCornerBite
    }

    /// Air entre le bas de la bande à laquelle le panneau est suspendu et le début du contenu.
    static let topClearance: CGFloat = 14

    /// Dont l'engrenage des Préférences est descendu sous le centre de la bande de l'encoche :
    /// c'est l'air qu'il garde au-dessus de lui, à régler pour le monter ou le descendre.
    static let gearDrop: CGFloat = 8

    /// Dont l'engrenage est rentré depuis le bord droit du contenu. Négatif : c'est le **glyphe**,
    /// et non sa bulle, qui tombe sur ce bord — le même que celui de tout ce que portent les onglets
    /// (volume du lecteur, grille, cartes), de sorte que tout s'aligne à droite sur l'engrenage.
    static var gearInsetX: CGFloat { -(TabBarMetrics.bubbleSize - TabBarMetrics.iconSize) / 2 }

    /// Marge haute. En profondeur la silhouette est pleine, mais le cadre de la fenêtre part du
    /// bord haut de la dalle : le contenu doit donc passer sous la barre de menus et, sur un Mac
    /// à encoche, sous l'encoche elle-même, qui couvre le haut du panneau. La silhouette repliée
    /// mesure exactement cette bande — c'est elle qui fixe la marge, et non une constante qui ne
    /// vaudrait que pour une taille d'encoche.
    static func contentInsetTop(forCollapsedHeight collapsedHeight: CGFloat) -> CGFloat {
        max(PanelGeometry.contentInsetAcrossAnchor, collapsedHeight + topClearance)
    }

    // MARK: - Capsule de navigation

    /// Écart entre le bas du panneau et la capsule de navigation, qui flotte sous lui. Serré
    /// pour que la capsule se lise comme rattachée au panneau, tout en restant détachée de lui.
    static let capsuleGap: CGFloat = 4

    /// Bande basse du cadre de la fenêtre, sous la silhouette du panneau : l'écart, puis la
    /// capsule. Le panneau ne peint rien là — seule la capsule s'y pose.
    static var capsuleBandHeight: CGFloat {
        capsuleGap + TabBarMetrics.capsuleHeight
    }

    /// Bande de la semaine, en tête de l'onglet Global. Même vue que dans la bande du bord
    /// droit, donc même hauteur.
    static let weekStripHeight: CGFloat = 46

    /// Air entre la semaine et le lecteur, dans l'onglet Global.
    static let weekToPlayerGap: CGFloat = 8

    /// Air entre l'en-tête de date et la liste des événements, dans le widget.
    static let calendarHeaderGap: CGFloat = 10

    /// Largeur de la grille du mois, colonne de droite du widget : sept colonnes de 28 pt, la
    /// plus petite largeur où deux chiffres tiennent sans se toucher.
    static let monthGridWidth: CGFloat = 196

    /// Hauteur du contenu de l'onglet Calendar, dont la grille du mois fixe le plancher — six
    /// lignes de semaine plus leurs initiales.
    ///
    /// C'est cet onglet qui est désormais le plus haut, et donc lui qui dimensionne le panneau
    /// (voir `tabContentHeight`).
    static let calendarTabHeight: CGFloat = 150

    /// Écart de chaque côté du filet qui sépare les deux colonnes du widget Calendar.
    static let columnGap: CGFloat = 18
    static let dividerWidth: CGFloat = 1

    /// Onglet AI : une carte d'agent à la fois, à la hauteur des onglets Terminal et Notes.
    static let aiTabHeight: CGFloat = 240

    /// Onglet Analytics : un seul bloc vertical (en-tête, carte du fournisseur, filtres, activité), plus haut que les autres onglets. Le panneau ne grandit donc que pour lui (voir
    /// `panelRect`).
    static let analyticsTabHeight: CGFloat = 280

    /// Largeur du contenu par défaut, celle des onglets Global, Calendar, Mirror et Stay Awake.
    static let aiTabWidth: CGFloat = 440

    /// Largeur du contenu de l'onglet AI (usages) : assez large pour que l'en-tête, les filtres et
    /// les mesures tiennent chacun sur une seule ligne (voir `contentWidth(for:)`).
    static let usageTabWidth: CGFloat = 720

    /// Onglet Clipboard : plus haut et plus large que les autres, pour que les cartes de
    /// l'historique aient la place de respirer. Seul cet onglet s'élargit ; les autres gardent
    /// la largeur de `aiTabWidth` (voir `contentWidth(for:)`).
    static let clipboardTabHeight: CGFloat = 160
    static let clipboardTabWidth: CGFloat = 560

    /// Onglet Tray : seul onglet à s'élargir pour ses vignettes de fichiers.
    static let trayTabWidth: CGFloat = 520

    /// Onglet Terminal : aussi haut que l'onglet AI (la fenêtre ne grandit pas), et assez large
    /// pour une soixantaine de colonnes.
    static let terminalTabHeight: CGFloat = aiTabHeight

    /// Onglet Notes : même gabarit que le Terminal (liste et éditeur côte à côte).
    static let notesTabHeight: CGFloat = aiTabHeight
    static let notesTabWidth: CGFloat = 520
    static let terminalTabWidth: CGFloat = 520

    /// Onglet Mirror : le panneau prend la forme d'un U — en-tête rectangulaire, flancs droits,
    /// et pour fond le cercle de l'aperçu lui-même. Le cercle est donc aussi large que le corps
    /// du panneau, à un liseré près.
    static let mirrorDiameter: CGFloat = 240

    /// Liseré sombre entre l'aperçu et le bord de la silhouette.
    static let mirrorRim: CGFloat = 4

    /// Largeur du corps du panneau Mirror, entre ses deux raccords concaves.
    static var mirrorBodyWidth: CGFloat { mirrorDiameter + 2 * mirrorRim }

    /// Largeur de la silhouette Mirror, raccords compris (voir `PanelGeometry.silhouette`).
    static var mirrorSilhouetteWidth: CGFloat { mirrorBodyWidth + 2 * expandedShoulderRadius }

    /// Hauteur de contenu qui donne au panneau l'en-tête habituel plus le cercle et son liseré :
    /// la marge basse est reprise, le cercle descendant jusqu'au bas de la silhouette.
    static var mirrorTabHeight: CGFloat { mirrorDiameter + mirrorRim - contentInsetBottom }

    /// Hauteur dont le panneau grandit sur l'onglet Tray quand on en glisse une image : la rangée
    /// de conversion (`FileTrayView.conversionRowHeight`) et l'écart qui la sépare des zones.
    /// Elle tient dans le surplus laissé par l'onglet le plus haut, la fenêtre ne bouge donc pas.
    static let trayConversionExtraHeight: CGFloat = 62

    /// Hauteur de la vue Transform, qui prend la place de l'onglet Tray (voir `transformExtraHeight`).
    static let transformViewHeight: CGFloat = 320

    /// Hauteur dont le panneau grandit pour la vue Transform par rapport à l'onglet Tray.
    static var transformExtraHeight: CGFloat { transformViewHeight - calendarTabHeight }

    /// Hauteur du contenu d'un onglet, sous la barre.
    static func contentHeight(for tab: NotchTab) -> CGFloat {
        switch tab {
        case .ai: aiTabHeight
        case .analytics: analyticsTabHeight
        case .mirror: mirrorTabHeight
        case .clipboard: clipboardTabHeight
        case .terminal: terminalTabHeight
        case .notes: notesTabHeight
        case .global, .calendar, .tray, .colorPicker, .stayAwake: calendarTabHeight
        }
    }

    /// Largeur du contenu d'un onglet, hors marges. Seuls l'AI, le Clipboard, le Tray, le Terminal
    /// et les Notes s'écartent de `aiTabWidth`.
    static func contentWidth(for tab: NotchTab) -> CGFloat {
        switch tab {
        case .ai, .analytics: usageTabWidth
        case .clipboard: clipboardTabWidth
        case .tray: trayTabWidth
        case .terminal: terminalTabWidth
        case .notes: notesTabWidth
        default: aiTabWidth
        }
    }

    /// Hauteur de l'onglet le plus haut : c'est elle qui dimensionne la fenêtre, dont le cadre ne
    /// change jamais. Les autres onglets laissent le surplus vide sous leur panneau.
    static var tabContentHeight: CGFloat {
        max(calendarTabHeight, aiTabHeight, analyticsTabHeight, mirrorTabHeight, transformViewHeight, clipboardTabHeight, terminalTabHeight)
    }

    /// Largeur de l'onglet le plus large — AI ou Clipboard. C'est elle qui dimensionne la fenêtre.
    static var tabContentWidth: CGFloat {
        max(aiTabWidth, usageTabWidth, clipboardTabWidth, trayTabWidth, terminalTabWidth)
    }

    /// Taille dépliée, capsule comprise : le cadre de la fenêtre porte les deux, et la hauteur
    /// est donc celle du panneau **plus** la bande basse où flotte la capsule.
    ///
    /// La largeur est celle du plus large de ce que la fenêtre porte : les deux colonnes de
    /// l'onglet AI, ou la capsule — c'est le panneau qui s'élargit, jamais la capsule qui
    /// déborde de lui.
    static func expandedSize(collapsedHeight: CGFloat) -> NSSize {
        NSSize(
            width: 2 * contentInsetX + max(tabContentWidth, NotchTabCapsuleView.width),
            height: contentInsetTop(forCollapsedHeight: collapsedHeight)
                + tabContentHeight
                + contentInsetBottom
                + capsuleBandHeight
        )
    }

    static func expandedSize(on screen: NSScreen, style: NotchPanelStyle = .notch) -> NSSize {
        expandedSize(collapsedHeight: collapsedSize(on: screen, style: style).height)
    }

    // MARK: - Encoche

    /// Cadre de l'encoche matérielle, `nil` sur un écran qui n'en a pas.
    ///
    /// La largeur est déduite des deux bandes de barre de menus laissées libres de part et
    /// d'autre de la caméra, et non de leurs abscisses : selon l'écran, `auxiliaryTopLeftArea`
    /// est donné dans le repère de l'écran ou dans le repère global, alors que les largeurs,
    /// elles, ne dépendent d'aucune origine. L'encoche étant centrée sur la dalle, cela suffit
    /// à la situer.
    static func notchRect(on screen: NSScreen) -> NSRect? {
        let height = screen.safeAreaInsets.top
        guard height > 0 else { return nil }

        let width: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let measured = screen.frame.width - left.width - right.width
            width = measured > 0 ? measured : fallbackNotchWidth
        } else {
            width = fallbackNotchWidth
        }

        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// Bord auquel le panneau est suspendu : toujours le haut de la dalle. Sur un Mac à encoche
    /// la silhouette repliée s'y confond avec l'encoche ; ailleurs la pastille s'y accroche de la
    /// même façon, au milieu de la barre de menus, là où ne vont ni les menus de l'application ni
    /// les icônes d'état. `visibleFrame` s'arrête sous cette barre — c'est lui qui laissait un
    /// vide au-dessus du panneau sur un écran sans encoche. La fenêtre est sans cadre et au
    /// niveau `.screenSaver` (voir `NotchPanelWindow`), donc au-dessus de la barre de menus et
    /// jamais recadrée sous elle.
    static func topAnchor(on screen: NSScreen) -> CGFloat {
        screen.frame.maxY
    }

    // MARK: - Cadres

    /// Le panneau proprement dit dans le cadre de la fenêtre, pour l'onglet affiché : suspendu au
    /// haut du cadre, il s'arrête où le contenu de l'onglet s'arrête. La bande basse et le
    /// surplus des onglets plus courts restent vides ; c'est la capsule qui suit le bas du panneau
    /// (voir `capsuleRect`). C'est ce rectangle, et non le cadre entier, que la silhouette occupe
    /// et dans lequel le contenu se pose.
    static func panelRect(in bounds: CGRect, tab: NotchTab, extraHeight: CGFloat = 0) -> CGRect {
        let slack = tabContentHeight - contentHeight(for: tab) - extraHeight
        let height = max(0, bounds.height - capsuleBandHeight - slack)
        // Centré dans la fenêtre : un onglet plus étroit que la fenêtre garde son axe.
        let width = min(bounds.width, contentWidth(for: tab) + 2 * contentInsetX)
        return CGRect(x: bounds.midX - width / 2, y: bounds.maxY - height, width: width, height: height)
    }

    /// Cadre de la capsule : sous le panneau de l'onglet affiché, centrée.
    static func capsuleRect(in bounds: CGRect, tab: NotchTab, extraHeight: CGFloat = 0) -> CGRect {
        let width = min(NotchTabCapsuleView.width, bounds.width)
        return CGRect(
            x: bounds.midX - width / 2,
            y: panelRect(in: bounds, tab: tab, extraHeight: extraHeight).minY - capsuleBandHeight,
            width: width,
            height: TabBarMetrics.capsuleHeight
        )
    }

    /// Cadre de la fenêtre, identique replié comme déplié : c'est la silhouette qui s'anime à
    /// l'intérieur, jamais la fenêtre, qui redimensionnée à chaque image hacherait le dépliage.
    static func windowFrame(on screen: NSScreen, style: NotchPanelStyle = .notch) -> NSRect {
        let size = expandedSize(on: screen, style: style)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: topAnchor(on: screen) - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Taille de la silhouette repliée : celle de l'encoche quand il y en a une, la pastille
    /// sinon.
    static func collapsedSize(on screen: NSScreen, style: NotchPanelStyle = .notch) -> NSSize {
        notchRect(on: screen).map { NSSize(width: $0.width, height: $0.height) }
            ?? (style == .island ? islandPillSize : pillSize)
    }

    /// Écart entre le bord du haut et la silhouette repliée : nul sauf en mode île, qui ne vaut
    /// que sur un écran sans encoche — l'encoche matérielle, elle, est collée au bord.
    static let islandTopGap: CGFloat = 6

    static func collapsedTopGap(on screen: NSScreen, style: NotchPanelStyle) -> CGFloat {
        notchRect(on: screen) == nil && style == .island ? islandTopGap : 0
    }

    /// Zone sensible qui déclenche le dépliage : la silhouette repliée, élargie de quoi
    /// l'atteindre sans viser au pixel près.
    static let hotZonePadding: CGFloat = 18

    /// Agrandissement de la silhouette repliée quand le curseur la survole en mode « clic » :
    /// quelques points de large et de haut, pour dire qu'elle est cliquable.
    static let hoverPeekGrowth = CGSize(width: 8, height: 3)

    static func hotZone(on screen: NSScreen, style: NotchPanelStyle = .notch) -> NSRect {
        let size = collapsedSize(on: screen, style: style)
        let gap = collapsedTopGap(on: screen, style: style)
        let top = topAnchor(on: screen)
        return NSRect(
            x: screen.frame.midX - size.width / 2 - hotZonePadding,
            y: top - gap - size.height - hotZonePadding,
            width: size.width + 2 * hotZonePadding,
            height: gap + size.height + hotZonePadding
        )
    }
}
