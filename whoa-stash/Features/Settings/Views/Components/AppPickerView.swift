import AppKit

/// Une pastille de catégorie, cliquable.
private final class PickerPillView: NSView {
  private let label: NSTextField
  var onClick: (() -> Void)?
  var isSelected = false { didSet { refresh() } }

  init(title: String) {
    label = NSTextField(labelWithString: title)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 15
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.sizeToFit()
    addSubview(label)
    frame.size = NSSize(width: label.frame.width + 28, height: 30)
    label.frame.origin = NSPoint(x: 14, y: (30 - label.frame.height) / 2)
    refresh()
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  private func refresh() {
    layer?.backgroundColor = NSColor.white.withAlphaComponent(isSelected ? 0.2 : 0.07).cgColor
    label.textColor = isSelected ? .white : .secondaryLabelColor
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Une appli du sélecteur : son icône et son nom, cliquable pour l'ajouter ou la retirer.
private final class AppCellView: NSView, NSDraggingSource {
  static let size = NSSize(width: 100, height: 96)

  let app: InstalledApp
  var onClick: (() -> Void)?
  private let icon = NSImageView()
  private let label: NSTextField

  init(app: InstalledApp) {
    self.app = app
    label = NSTextField(labelWithString: app.name)
    super.init(frame: NSRect(origin: .zero, size: Self.size))
    // Chaque cellule dans son calque : icône et nom se déplacent ensemble au défilement.
    wantsLayer = true
    icon.image = NSWorkspace.shared.icon(forFile: app.path)
    icon.frame = NSRect(x: (Self.size.width - 56) / 2, y: 30, width: 56, height: 56)
    label.font = .systemFont(ofSize: 11)
    label.alignment = .center
    label.lineBreakMode = .byTruncatingTail
    label.frame = NSRect(x: 4, y: 6, width: Self.size.width - 8, height: 16)
    label.toolTip = app.name
    addSubview(icon)
    addSubview(label)
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  private var didDrag = false

  override func mouseDown(with event: NSEvent) { didDrag = false }

  /// Glisser une appli vers la maquette du dock l'y ajoute ; un simple clic la coche ou la décoche.
  override func mouseDragged(with event: NSEvent) {
    guard !didDrag, let image = icon.image else { return }
    didDrag = true
    let item = DockAppDrag.item(for: app.pinned, image: image, size: 44)
    let origin = convert(event.locationInWindow, from: nil)
    item.draggingFrame = NSRect(x: origin.x - 22, y: origin.y - 22, width: 44, height: 44)
    beginDraggingSession(with: [item], event: event, source: self)
  }

  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .withinApplication ? .copy : []
  }

  override func mouseUp(with event: NSEvent) {
    if !didDrag, bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
  }
}

private final class FlippedDocumentView: NSView {
  override var isFlipped: Bool { true }
}

/// Sélecteur d'applis façon Launchpad : des pastilles de catégories en haut, puis une grille. Les
/// applis choisies forment la première rangée ; un filet les sépare de toutes les autres, que les
/// pastilles filtrent. Un clic fait passer une appli d'une section à l'autre.
final class AppPickerView: NSView {

  var onToggle: ((InstalledApp, Bool) -> Void)?

  private let apps: [InstalledApp]
  private var cells: [String: AppCellView] = [:]
  private var selected: Set<String> = []
  private var category = "All"
  private var pills: [String: PickerPillView] = [:]
  private let pillsScroll = NSScrollView()
  private let gridScroll = NSScrollView()
  private let document = FlippedDocumentView()
  private let separator = NSView()
  private let hint = NSTextField(labelWithString: "Click an app below to add it to this profile")
  private var isEnabled = true

  init(apps: [InstalledApp], size: NSSize) {
    self.apps = apps
    super.init(frame: NSRect(origin: .zero, size: size))
    translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: size.width),
      heightAnchor.constraint(equalToConstant: size.height),
    ])
    buildPills(width: size.width)
    buildGrid(size: size)
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  private func buildPills(width: CGFloat) {
    let present = Set(apps.map(\.category))
    let titles = ["All"] + InstalledApps.categoryOrder.filter { present.contains($0) }
    let row = NSView()
    var x: CGFloat = 0
    for title in titles {
      let pill = PickerPillView(title: title)
      pill.frame.origin = NSPoint(x: x, y: 0)
      pill.isSelected = title == category
      pill.onClick = { [weak self] in self?.select(category: title) }
      row.addSubview(pill)
      pills[title] = pill
      x += pill.frame.width + 8
    }
    row.frame = NSRect(x: 0, y: 0, width: max(x, width), height: 30)
    pillsScroll.contentView.copiesOnScroll = false
    pillsScroll.documentView = row
    pillsScroll.hasHorizontalScroller = false
    pillsScroll.drawsBackground = false
    pillsScroll.frame = NSRect(x: 0, y: frame.height - 34, width: width, height: 32)
    pillsScroll.autoresizingMask = [.minYMargin, .width]
    addSubview(pillsScroll)
  }

  private func buildGrid(size: NSSize) {
    separator.wantsLayer = true
    separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
    hint.font = .systemFont(ofSize: 12)
    hint.textColor = .tertiaryLabelColor
    document.addSubview(separator)
    document.addSubview(hint)
    for app in apps {
      let cell = AppCellView(app: app)
      cell.onClick = { [weak self] in self?.toggle(app) }
      document.addSubview(cell)
      cells[app.bundleID] = cell
    }
    // Fond transparent + copie au défilement = fantômes : AppKit recopie les pixels déplacés au lieu de
    // les redessiner, et sans fond opaque l'ancien contenu reste visible sous le nouveau.
    gridScroll.contentView.copiesOnScroll = false
    document.wantsLayer = true
    gridScroll.documentView = document
    gridScroll.hasVerticalScroller = true
    gridScroll.autohidesScrollers = true
    gridScroll.drawsBackground = false
    gridScroll.borderType = .noBorder
    gridScroll.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height - 42)
    gridScroll.autoresizingMask = [.width, .height]
    addSubview(gridScroll)
    layoutGrid(animated: false)
  }

  func setSelected(_ ids: Set<String>) {
    guard ids != selected else { return }
    selected = ids
    layoutGrid(animated: window != nil)
  }

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    alphaValue = enabled ? 1 : 0.4
  }

  private func select(category title: String) {
    category = title
    pills.forEach { $0.value.isSelected = $0.key == title }
    layoutGrid(animated: false)
  }

  private func toggle(_ app: InstalledApp) {
    guard isEnabled else { return }
    onToggle?(app, !selected.contains(app.bundleID))
  }

  private func layoutGrid(animated: Bool) {
    let width = gridScroll.contentSize.width
    let columns = max(1, Int((width - 8) / AppCellView.size.width))
    let inset = (width - CGFloat(columns) * AppCellView.size.width) / 2
    var y: CGFloat = 4

    func place(_ list: [InstalledApp], startY: CGFloat) -> CGFloat {
      for (index, app) in list.enumerated() {
        let origin = NSPoint(
          x: inset + CGFloat(index % columns) * AppCellView.size.width,
          y: startY + CGFloat(index / columns) * AppCellView.size.height)
        cells[app.bundleID]?.isHidden = false
        setOrigin(cells[app.bundleID], origin, animated: animated)
      }
      return startY + CGFloat((list.count + columns - 1) / columns) * AppCellView.size.height
    }

    let chosen = apps.filter { selected.contains($0.bundleID) }
    let others = apps.filter {
      !selected.contains($0.bundleID) && (category == "All" || $0.category == category)
    }
    let visible = Set((chosen + others).map(\.bundleID))
    for (id, cell) in cells where !visible.contains(id) { cell.isHidden = true }

    hint.isHidden = !chosen.isEmpty
    if chosen.isEmpty {
      hint.sizeToFit()
      hint.frame.origin = NSPoint(x: inset + 4, y: y + 20)
      y += 56
    } else {
      y = place(chosen, startY: y)
    }
    separator.frame = NSRect(x: 8, y: y + 4, width: width - 16, height: 1)
    y = place(others, startY: y + 12)
    document.frame = NSRect(x: 0, y: 0, width: width, height: y + 8)
  }

  private func setOrigin(_ view: NSView?, _ origin: NSPoint, animated: Bool) {
    guard let view, view.frame.origin != origin else { return }
    if animated && !view.isHidden {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = OverlayAnimation.allowsMotion ? PanelFold.fadeDuration : 0
        view.animator().frame.origin = origin
      }
    } else {
      view.frame.origin = origin
    }
  }
}
