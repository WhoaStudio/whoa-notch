import AppKit
import Foundation
import Testing
@testable import whoa_stash

@MainActor
private func makeItem(_ id: String, pinned: Bool = true) -> DockItem {
    DockItem(bundleID: id, path: "/Applications/\(id).app", name: id, isRunning: false, isWebApp: false, isPinned: pinned)
}

@MainActor
private func makeDock(items: Int = 3, widgets: [DockWidgetPlacement] = []) -> DockContentView {
    let dock = DockContentView(frame: NSRect(x: 0, y: 0, width: 900, height: 120))
    dock.apply(items: (0..<items).map { makeItem("app\($0)") }, overflow: [])
    dock.apply(widgets: widgets)
    return dock
}

@MainActor
@Suite struct DockWidgetRowTests {

    @Test func inserePuisOrdonneLesWidgetsDansLaRangee() {
        let items = (0..<3).map { makeItem("app\($0)") }
        let battery = DockWidgetPlacement(id: "w1", kind: "battery", index: 1)
        let row = DockRow.entries(items: items, widgets: [battery])
        #expect(row.count == 4)
        #expect(row[1] == .widget(battery))
        #expect(row[0] == .app(items[0]))
        #expect(row[2] == .app(items[1]))
    }

    @Test func unIndiceTropGrandColleLeWidgetAuBout() {
        let items = (0..<2).map { makeItem("app\($0)") }
        let widget = DockWidgetPlacement(id: "w1", kind: "battery", index: 99)
        #expect(DockRow.entries(items: items, widgets: [widget]).last == .widget(widget))
    }

    @Test func deuxWidgetsAuMemeIndiceGardentLeurOrdre() {
        let a = DockWidgetPlacement(id: "a", kind: "battery", index: 0)
        let b = DockWidgetPlacement(id: "b", kind: "battery", index: 0)
        #expect(DockRow.entries(items: [], widgets: [a, b]) == [.widget(a), .widget(b)])
    }

    @Test func deplacerUnWidgetRecalculeLesPositions() {
        let items = (0..<3).map { makeItem("app\($0)") }
        let a = DockWidgetPlacement(id: "a", kind: "battery", index: 1)
        let b = DockWidgetPlacement(id: "b", kind: "battery", index: 3)
        let row = DockRow.entries(items: items, widgets: [a, b])  // app0 a app1 b app2
        let moved = DockRow.placements(placing: a, at: 4, in: row)  // a passe après b : app0 app1 b a app2
        #expect(moved.map(\.id) == ["b", "a"])
        #expect(moved.map(\.index) == [2, 3])
    }

    @Test func retirerUnWidgetGardeLesAutresACoteDeLeursApplis() {
        let items = (0..<2).map { makeItem("app\($0)") }
        let a = DockWidgetPlacement(id: "a", kind: "battery", index: 0)
        let b = DockWidgetPlacement(id: "b", kind: "battery", index: 2)
        let row = DockRow.entries(items: items, widgets: [a, b])  // a app0 b app1
        let left = DockRow.placements(removing: "a", from: row)
        #expect(left.map(\.id) == ["b"])
        #expect(left.map(\.index) == [1])
    }
}

@MainActor
@Suite struct DockWidgetDropTests {

    private var payload: DockWidgetDragPayload { DockWidgetDragPayload(kind: BatteryWidget.kind.id, placementID: nil) }

    /// Première abscisse qui accepte un dépôt : le bord droit de la zone des espaces de travail.
    private func boundary(of dock: DockContentView) -> CGFloat? {
        stride(from: CGFloat(0), to: 900, by: 1).first { dock.widgetDropIndex(atX: $0) != nil }
    }

    @Test func unDepotDansLaRangeePlaceLeWidget() throws {
        let dock = makeDock()
        var received: [DockWidgetPlacement]?
        dock.onWidgetsChanged = { received = $0 }
        let edge = try #require(boundary(of: dock))

        #expect(dock.dropWidget(payload, atX: edge + 1))
        #expect(received?.count == 1)
        #expect(received?.first?.kind == "battery")
        #expect(received?.first?.index == 0)

        #expect(dock.dropWidget(payload, atX: 890))
        #expect(received?.first?.index == 3)
    }

    @Test func unTypeInconnuEstRefuse() throws {
        let dock = makeDock()
        let edge = try #require(boundary(of: dock))
        #expect(!dock.dropWidget(DockWidgetDragPayload(kind: "inconnu", placementID: nil), atX: edge + 1))
    }

    @Test func deplacerUnWidgetExistantLeReplaceSansLeDupliquer() throws {
        let existing = DockWidgetPlacement(id: "w1", kind: "battery", index: 0)
        let dock = makeDock(widgets: [existing])
        var received: [DockWidgetPlacement]?
        dock.onWidgetsChanged = { received = $0 }

        #expect(dock.dropWidget(DockWidgetDragPayload(kind: "battery", placementID: "w1"), atX: 890))
        #expect(received?.map(\.id) == ["w1"])
        #expect(received?.first?.index == 3)
    }

    @Test func lesWidgetsInconnusSontIgnoresALAffichage() {
        let dock = makeDock(widgets: [DockWidgetPlacement(kind: "disparu", index: 0)])
        #expect(dock.rowCount == 3)
    }
}

@MainActor
@Suite struct DockWidgetPersistenceTests {

    private func makeDefaults() -> UserDefaults { UserDefaults(suiteName: "dock-widget-tests-\(UUID().uuidString)")! }

    @Test func lesPositionsSurviventAuRechargement() {
        let defaults = makeDefaults()
        let placements = [
            DockWidgetPlacement(id: "w1", kind: "battery", index: 2),
            DockWidgetPlacement(id: "w2", kind: "battery", index: 5),
        ]
        let first = SettingsStorage(defaults: defaults)
        first.settings.dock.widgets = placements

        let second = SettingsStorage(defaults: defaults)
        #expect(second.settings.dock.widgets == placements)
    }

    @Test func chaqueEspaceGardeSesWidgets() {
        let work = DockWorkspace(id: "work", name: "Work")
        let home = DockWorkspace(id: "home", name: "Home")
        var dock = DockSettings(workspaces: [work, home], activeWorkspaceID: "work")
        let mine = DockWidgetPlacement(id: "w1", kind: "battery", index: 1)

        dock.setVisibleWidgets([mine])
        #expect(dock.visibleWidgets == [mine])

        dock.activeWorkspaceID = "home"
        #expect(dock.visibleWidgets.isEmpty)

        dock.activeWorkspaceID = nil
        #expect(dock.visibleWidgets.isEmpty)
        dock.setVisibleWidgets([DockWidgetPlacement(id: "g", kind: "battery", index: 0)])

        dock.activeWorkspaceID = "work"
        #expect(dock.visibleWidgets == [mine])
        #expect(dock.widgets.map(\.id) == ["g"])
    }

    @Test func onAjouteEtRetireDesWidgetsDansUnEspaceChoisiSansToucherLesAutres() {
        let model = SettingsStorage(defaults: makeDefaults())
        model.settings.dock.workspaces = [DockWorkspace(id: "a", apps: [DockPinnedApp(bundleID: "x", path: "/x.app")]), DockWorkspace(id: "b")]
        model.settings.dock.activeWorkspaceID = "a"
        let viewModel = WorkspacesSettingsViewModel(storage: model)

        viewModel.selectedID = "b"  // espace choisi mais pas actif
        viewModel.addWidget(kind: "battery")
        #expect(model.settings.dock.workspaces[1].widgets.map(\.kind) == ["battery"])
        #expect(model.settings.dock.workspaces[0].widgets.isEmpty)
        #expect(model.settings.dock.visibleWidgets.isEmpty)  // le dock affiche toujours « a »

        viewModel.selectedID = "a"
        viewModel.addWidget(kind: "battery")
        #expect(model.settings.dock.visibleWidgets.first?.index == 1)  // après l'unique appli

        viewModel.selectedID = "b"
        viewModel.removeWidget(id: model.settings.dock.workspaces[1].widgets[0].id)
        #expect(model.settings.dock.workspaces[1].widgets.isEmpty)
        #expect(model.settings.dock.workspaces[0].widgets.count == 1)
    }

    @Test func lesWidgetsDUnEspaceSurviventAuRechargement() {
        let defaults = makeDefaults()
        let mine = DockWidgetPlacement(id: "w1", kind: "battery", index: 2)
        let first = SettingsStorage(defaults: defaults)
        first.settings.dock.workspaces = [DockWorkspace(id: "work")]
        first.settings.dock.activeWorkspaceID = "work"
        first.settings.dock.setVisibleWidgets([mine])

        let second = SettingsStorage(defaults: defaults)
        #expect(second.settings.dock.workspaces.first?.widgets == [mine])
        #expect(second.settings.dock.visibleWidgets == [mine])
    }

    @Test func unEspaceSansCleWidgetsSeDecodeAvecUneListeVide() throws {
        let decoded = try JSONDecoder().decode(DockWorkspace.self, from: Data(#"{"id": "a", "name": "Old"}"#.utf8))
        #expect(decoded.widgets.isEmpty)
    }

    @Test func desReglagesSansWidgetsSeDecodentAvecUneListeVide() throws {
        let decoded = try JSONDecoder().decode(DockSettings.self, from: Data(#"{"enabled": false}"#.utf8))
        #expect(!decoded.enabled)
        #expect(decoded.widgets.isEmpty)
    }
}

@MainActor
@Suite struct BatteryWidgetTests {

    @Test func leRemplissageSuitLePourcentage() {
        #expect(BatteryTileView.fraction(percent: 0) == 0)
        #expect(BatteryTileView.fraction(percent: 57) == 0.57)
        #expect(BatteryTileView.fraction(percent: 100) == 1)
        #expect(BatteryTileView.fraction(percent: 140) == 1)
        #expect(BatteryTileView.fraction(percent: -3) == 0)
        #expect(BatteryTileView.fraction(percent: nil) == 0)
    }

    @Test func lAnneauPartDeMidi() throws {
        let path = BatteryTileView.ringPath(in: CGRect(x: 0, y: 0, width: 40, height: 40))
        var start: CGPoint?
        path.applyWithBlock { element in
            if start == nil, element.pointee.type == .moveToPoint { start = element.pointee.points[0] }
        }
        let point = try #require(start)
        #expect(abs(point.x - 20) < 0.001)
        #expect(abs(point.y - 40) < 0.001)  // en haut : l'axe y des calques monte
    }

    @Test func lAnneauEstRempliSelonLeNiveau() throws {
        // 3 h = 25 %, 6 h = 50 %, 9 h = 75 % du tour dans le sens horaire.
        let clock: [(CGFloat, CGFloat)] = [(1, 0), (0, 1), (-1, 0)]
        let expectations: [(Int, [Bool])] = [(0, [false, false, false]), (57, [true, true, false]), (100, [true, true, true])]
        for (percent, filled) in expectations {
            let image = try render(percent: percent)
            for ((dx, dy), expected) in zip(clock, filled) {
                let isGreen = try isGreenPixel(image, dx: dx, dy: dy)
                #expect(isGreen == expected, "\(percent) % : point (\(dx), \(dy))")
            }
        }
    }

    @Test func leNiveauApparaitSansSigneEtLeFournisseurLePousse() throws {
        let provider = MockBatteryProvider(percent: 57)
        let widget = BatteryWidget(provider: provider)
        widget.start()
        let tile = try #require(widget.view as? BatteryTileView)
        let label = try #require(tile.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(label.stringValue == "57")

        provider.percent = 12
        provider.start()
        #expect(label.stringValue == "12")
        widget.stop()
    }

    @Test func leRegistreConnaitLaBatterie() {
        #expect(DockWidgetRegistry.kind(for: "battery") != nil)
        #expect(DockWidgetRegistry.kind(for: "nope") == nil)
    }

    // MARK: - Rendu

    private let side = 60

    private func render(percent: Int) throws -> NSBitmapImageRep {
        let tile = BatteryTileView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        tile.percent = percent
        tile.layout()
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        tile.layer?.render(in: context)
        return NSBitmapImageRep(cgImage: try #require(context.makeImage()))
    }

    /// `dx`, `dy` : direction à partir du centre (dy positif = vers le bas de l'image), sur le rayon de l'anneau.
    private func isGreenPixel(_ image: NSBitmapImageRep, dx: CGFloat, dy: CGFloat) throws -> Bool {
        let radius = CGFloat(side) / 2 - CGFloat(side) * 0.17
        let x = Int((CGFloat(side) / 2 + dx * radius).rounded())
        let y = Int((CGFloat(side) / 2 + dy * radius).rounded())
        let color = try #require(image.colorAt(x: min(x, side - 1), y: min(y, side - 1))?.usingColorSpace(.sRGB))
        return color.greenComponent > color.redComponent + 0.25 && color.greenComponent > color.blueComponent + 0.25
    }
}
