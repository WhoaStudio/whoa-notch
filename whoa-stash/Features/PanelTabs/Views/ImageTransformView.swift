import AppKit
import OSLog
import QuickLookThumbnailing

/// La vue Transform : elle prend la place de l'onglet Tray quand on lâche une image du bac sur le
/// bouton « Transform ». Un en-tête (titre, nom et poids du fichier, bouton de fermeture), la
/// vignette de l'image, une rangée d'actions, les réglages de l'action choisie, et le gros bouton
/// qui l'exécute.
///
/// Chaque action réécrit l'image sous un nom libre avec `FileShelfStore.addTransformed` : l'original
/// n'est jamais modifié. « Next to the original » range le résultat dans le bac, à côté de lui ;
/// « Downloads » l'écrit dans le dossier Téléchargements, hors du bac.
final class ImageTransformView: NSView {

  /// Fermeture demandée : bouton de la vue, ou action menée à son terme.
  var onClose: (() -> Void)?

  private let store: FileShelfStore
  private var sourceURL: URL?
  private var sourceFormat: ImageFormat = .png
  private var action: Action = .convert

  // Choix courants des réglages.
  private var convertFormat: ImageFormat = .jpeg
  private var qualityIndex = 0
  private var scaleIndex = 1
  private var rotationIndex = 0
  private var saveToIndex = 0

  private let iconBackground = NSView()
  private let headerIcon = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "Transform")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private let closeButton = NSButton()
  private let thumbnailView = NSImageView()
  private let fileLabel = NSTextField(labelWithString: "")
  private var tiles: [TransformActionTileView] = []
  private let optionsBox = NSView()
  private var optionRows: [OptionRow] = []
  private let runButton = NSButton()
  private var thumbnailTask: Task<Void, Never>?
  private var resetTitleTask: Task<Void, Never>?

  private static let accent = NSColor(srgbRed: 0.39, green: 0.40, blue: 0.95, alpha: 1)
  private static let rowHeight: CGFloat = 44

  init(store: FileShelfStore = .shared) {
    self.store = store
    super.init(frame: .zero)
    wantsLayer = true
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit { thumbnailTask?.cancel() }

  // MARK: - Actions

  private enum Action: CaseIterable {
    case compress, convert, resize, rotate, removeMetadata

    var title: String {
      switch self {
      case .compress: "Compress"
      case .convert: "Convert"
      case .resize: "Resize"
      case .rotate: "Rotate"
      case .removeMetadata: "Remove metadata"
      }
    }

    var symbol: String {
      switch self {
      case .compress: "arrow.down.right.and.arrow.up.left"
      case .convert: "arrow.triangle.2.circlepath"
      case .resize: "magnifyingglass"
      case .rotate: "rotate.right"
      case .removeMetadata: "eye.slash"
      }
    }

    /// Ajouté au nom du fichier écrit, pour qu'il ne se confonde pas avec l'original.
    var suffix: String {
      switch self {
      case .compress: " compressed"
      case .convert: ""
      case .resize: " resized"
      case .rotate: " rotated"
      case .removeMetadata: " clean"
      }
    }
  }

  private static let qualities: [(String, CGFloat)] = [
    ("High", 0.9), ("Medium", 0.7), ("Low", 0.5),
  ]
  private static let scales: [(String, CGFloat)] = [("75 %", 0.75), ("50 %", 0.5), ("25 %", 0.25)]
  private static let rotations: [(String, Int)] = [
    ("90° right", 90), ("90° left", 270), ("180°", 180),
  ]
  private static let destinations = ["Next to the original", "Downloads"]

  // MARK: - Contenu

  private func setUp() {
    iconBackground.wantsLayer = true
    iconBackground.layer?.cornerRadius = 11
    iconBackground.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
    addSubview(iconBackground)

    headerIcon.image = NSImage(
      systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
    headerIcon.contentTintColor = Self.accent
    headerIcon.imageScaling = .scaleNone
    addSubview(headerIcon)

    titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
    titleLabel.textColor = .white
    subtitleLabel.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
    subtitleLabel.textColor = .gray
    subtitleLabel.lineBreakMode = .byTruncatingMiddle
    addSubview(titleLabel)
    addSubview(subtitleLabel)

    closeButton.isBordered = false
    closeButton.wantsLayer = true
    closeButton.layer?.cornerRadius = 15
    closeButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
    closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
      .withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
    closeButton.contentTintColor = .white
    closeButton.imagePosition = .imageOnly
    closeButton.target = self
    closeButton.action = #selector(close)
    addSubview(closeButton)

    thumbnailView.imageScaling = .scaleProportionallyUpOrDown
    thumbnailView.wantsLayer = true
    thumbnailView.layer?.cornerRadius = 8
    thumbnailView.layer?.masksToBounds = true
    addSubview(thumbnailView)

    fileLabel.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
    fileLabel.textColor = .lightGray
    fileLabel.alignment = .center
    fileLabel.maximumNumberOfLines = 2
    fileLabel.lineBreakMode = .byTruncatingMiddle
    addSubview(fileLabel)

    for action in Action.allCases {
      let tile = TransformActionTileView(
        title: action.title, symbol: action.symbol, accent: Self.accent)
      tile.onClick = { [weak self] in self?.select(action) }
      tiles.append(tile)
      addSubview(tile)
    }

    optionsBox.wantsLayer = true
    optionsBox.layer?.cornerRadius = 12
    optionsBox.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
    addSubview(optionsBox)

    runButton.isBordered = false
    runButton.wantsLayer = true
    runButton.layer?.cornerRadius = 16
    runButton.layer?.backgroundColor = Self.accent.withAlphaComponent(0.3).cgColor
    runButton.target = self
    runButton.action = #selector(run)
    addSubview(runButton)

    select(.convert)
  }

  /// Montre l'image à transformer, avec l'action Convert choisie et ses réglages par défaut.
  func show(url: URL) {
    sourceURL = url
    sourceFormat = ImageFormat(url: url) ?? .png
    convertFormat = sourceFormat.conversionTargets.first ?? .jpeg
    qualityIndex = 0
    scaleIndex = 1
    rotationIndex = 0
    saveToIndex = 0

    let size =
      (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
      .map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? ""
    subtitleLabel.stringValue =
      size.isEmpty ? url.lastPathComponent : "\(url.lastPathComponent), \(size)"
    fileLabel.stringValue =
      size.isEmpty ? url.lastPathComponent : "\(url.lastPathComponent)\n\(size)"
    thumbnailView.image = NSWorkspace.shared.icon(forFile: url.path)
    loadThumbnail(for: url)
    select(.convert)
  }

  private func loadThumbnail(for url: URL) {
    thumbnailTask?.cancel()
    let request = QLThumbnailGenerator.Request(
      fileAt: url, size: CGSize(width: 64, height: 64),
      scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
    thumbnailTask = Task { [weak self] in
      do {
        let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(
          for: request)
        guard !Task.isCancelled else { return }
        guard let self else { return }
        thumbnailView.image = representation.nsImage
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.springReveal()
      } catch {
        Log.sidePanel.debug(
          "Pas de vignette QuickLook : \(error.localizedDescription, privacy: .private)")
      }
    }
  }

  private func select(_ newAction: Action) {
    let changed = action != newAction
    action = newAction
    for (tile, candidate) in zip(tiles, Action.allCases) {
      tile.isSelected = candidate == newAction
    }
    runButton.attributedTitle = NSAttributedString(
      string: newAction.title,
      attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.65, green: 0.66, blue: 1, alpha: 1),
      ])
    rebuildOptionRows()
    if changed, window != nil {
      for row in optionRows {
        for view in [row.label, row.popUp] as [NSView] {
          view.wantsLayer = true
          view.layer?.springReveal(x: 8, y: 0)
        }
      }
    }
    needsLayout = true
  }

  // MARK: - Réglages

  private struct OptionRow {
    let label: NSTextField
    let popUp: NSPopUpButton
  }

  private func rebuildOptionRows() {
    optionRows.forEach {
      $0.label.removeFromSuperview()
      $0.popUp.removeFromSuperview()
    }
    optionRows = []

    switch action {
    case .convert:
      addRow(
        "Format", sourceFormat.conversionTargets.map(\.label),
        selected: sourceFormat.conversionTargets.firstIndex(of: convertFormat) ?? 0
      ) { [weak self] index in
        guard let self else { return }
        convertFormat = sourceFormat.conversionTargets[index]
      }
    case .compress:
      addRow("Quality", Self.qualities.map(\.0), selected: qualityIndex) { [weak self] in
        self?.qualityIndex = $0
      }
    case .resize:
      addRow("Scale", Self.scales.map(\.0), selected: scaleIndex) { [weak self] in
        self?.scaleIndex = $0
      }
    case .rotate:
      addRow("Direction", Self.rotations.map(\.0), selected: rotationIndex) { [weak self] in
        self?.rotationIndex = $0
      }
    case .removeMetadata:
      break
    }
    addRow("Save to", Self.destinations, selected: saveToIndex) { [weak self] in
      self?.saveToIndex = $0
    }
  }

  private func addRow(
    _ title: String, _ items: [String], selected: Int, onChange: @escaping (Int) -> Void
  ) {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .white

    let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
    popUp.addItems(withTitles: items)
    popUp.selectItem(at: min(selected, items.count - 1))
    popUp.controlSize = .small
    // Le panneau se replie dès que le curseur le quitte : ce délégué gèle son suivi tant que
    // le menu déroulant est ouvert (voir `OverlayContextMenu.isPresenting`).
    popUp.menu?.delegate = OverlayContextMenu.shared
    popUp.target = self
    popUp.action = #selector(optionChanged(_:))
    changeHandlers[ObjectIdentifier(popUp)] = onChange

    addSubview(label)
    addSubview(popUp)
    optionRows.append(OptionRow(label: label, popUp: popUp))
  }

  private var changeHandlers: [ObjectIdentifier: (Int) -> Void] = [:]

  @objc private func optionChanged(_ sender: NSPopUpButton) {
    changeHandlers[ObjectIdentifier(sender)]?(sender.indexOfSelectedItem)
  }

  // MARK: - Exécution

  @objc private func close() {
    onClose?()
  }

  @objc private func run() {
    guard let sourceURL else { return }
    var options = ImageTransformOptions(format: sourceFormat)
    switch action {
    case .convert:
      options.format = convertFormat
    case .compress:
      // Un PNG est sans perte : il n'y a rien à gagner à le recompresser, il part en JPEG.
      if sourceFormat == .png { options.format = .jpeg }
      options.quality = Self.qualities[qualityIndex].1
    case .resize:
      options.scale = Self.scales[scaleIndex].1
    case .rotate:
      options.rotationDegrees = Self.rotations[rotationIndex].1
    case .removeMetadata:
      options.stripMetadata = true
    }

    let downloads =
      saveToIndex == 1
      ? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first : nil
    guard
      let written = store.addTransformed(
        from: sourceURL, options: options, suffix: action.suffix, in: downloads)
    else {
      showFailure()
      return
    }
    if downloads != nil { NSWorkspace.shared.activateFileViewerSelecting([written]) }
    onClose?()
  }

  private func showFailure() {
    runButton.attributedTitle = NSAttributedString(
      string: "Couldn't write the file",
      attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: NSColor.systemRed,
      ])
    runButton.wantsLayer = true
    runButton.layer?.springReveal(y: -4)
    resetTitleTask?.cancel()
    resetTitleTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled, let self else { return }
      select(action)
      runButton.layer?.springReveal(y: 4)
    }
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()
    var top = bounds.maxY

    // En-tête.
    let headerHeight: CGFloat = 40
    iconBackground.frame = NSRect(
      x: 0, y: top - headerHeight, width: headerHeight, height: headerHeight)
    let icon = headerIcon.intrinsicContentSize
    headerIcon.frame = NSRect(
      x: iconBackground.frame.midX - icon.width / 2, y: iconBackground.frame.midY - icon.height / 2,
      width: icon.width, height: icon.height)
    closeButton.frame = NSRect(
      x: bounds.maxX - 30, y: top - headerHeight / 2 - 15, width: 30, height: 30)
    let textX = headerHeight + 10
    let textWidth = max(0, closeButton.frame.minX - 10 - textX)
    titleLabel.frame = NSRect(x: textX, y: top - 21, width: textWidth, height: 20)
    subtitleLabel.frame = NSRect(x: textX, y: top - 39, width: textWidth, height: 16)
    top -= headerHeight + 12

    // Vignette et nom.
    let thumbnail: CGFloat = 52
    thumbnailView.frame = NSRect(x: 0, y: top - thumbnail, width: thumbnail, height: thumbnail)
    fileLabel.frame = NSRect(
      x: thumbnail + 10, y: top - thumbnail, width: max(0, bounds.width - thumbnail - 10),
      height: thumbnail)
    fileLabel.alignment = .left
    top -= thumbnail + 12

    // Rangée d'actions : six emplacements, comme sur la maquette, cinq occupés.
    let gap: CGFloat = 8
    let slots: CGFloat = 6
    let tileWidth = (bounds.width - gap * (slots - 1)) / slots
    let tileHeight: CGFloat = 78
    for (index, tile) in tiles.enumerated() {
      tile.frame = NSRect(
        x: CGFloat(index) * (tileWidth + gap), y: top - tileHeight, width: tileWidth,
        height: tileHeight)
    }
    top -= tileHeight + 10

    // Réglages.
    let boxHeight = CGFloat(optionRows.count) * Self.rowHeight
    optionsBox.frame = NSRect(x: 0, y: top - boxHeight, width: bounds.width, height: boxHeight)
    for (index, row) in optionRows.enumerated() {
      let rowTop = top - CGFloat(index) * Self.rowHeight
      let labelHeight = row.label.intrinsicContentSize.height
      row.label.frame = NSRect(
        x: 14, y: rowTop - Self.rowHeight / 2 - labelHeight / 2, width: bounds.width / 2,
        height: labelHeight)
      let popUpSize = NSSize(width: 170, height: 24)
      row.popUp.frame = NSRect(
        x: bounds.maxX - 10 - popUpSize.width,
        y: rowTop - Self.rowHeight / 2 - popUpSize.height / 2,
        width: popUpSize.width, height: popUpSize.height)
    }

    // Bouton d'exécution, contre le bas.
    runButton.frame = NSRect(x: 0, y: bounds.minY, width: bounds.width, height: 40)
  }
}

// MARK: - Une tuile d'action

/// Une tuile de la rangée d'actions : une icône sur fond arrondi, et son libellé dessous. L'action
/// choisie prend la couleur d'accent.
private final class TransformActionTileView: NSView {

  var onClick: (() -> Void)?

  var isSelected = false {
    didSet {
      guard isSelected != oldValue else { return }
      updateAppearance()
    }
  }

  private let accent: NSColor
  private let plate = NSView()
  private let iconView = NSImageView()
  private let label: NSTextField

  init(title: String, symbol: String, accent: NSColor) {
    self.accent = accent
    label = NSTextField(labelWithString: title)
    super.init(frame: .zero)
    wantsLayer = true

    plate.wantsLayer = true
    plate.layer?.cornerRadius = 12
    addSubview(plate)

    iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
      .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
    iconView.imageScaling = .scaleNone
    addSubview(iconView)

    label.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
    label.alignment = .center
    label.maximumNumberOfLines = 2
    label.lineBreakMode = .byWordWrapping
    addSubview(label)
    updateAppearance()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func updateAppearance() {
    plate.layer?.backgroundColor =
      (isSelected ? accent : NSColor.white.withAlphaComponent(0.09)).cgColor
    iconView.contentTintColor = isSelected ? .white : .lightGray
    label.textColor = isSelected ? .white : .gray
  }

  override func mouseDown(with event: NSEvent) {}

  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
  }

  override func layout() {
    super.layout()
    let plateHeight: CGFloat = 46
    plate.frame = NSRect(
      x: 0, y: bounds.maxY - plateHeight, width: bounds.width, height: plateHeight)
    let icon = iconView.intrinsicContentSize
    iconView.frame = NSRect(
      x: plate.frame.midX - icon.width / 2, y: plate.frame.midY - icon.height / 2,
      width: icon.width, height: icon.height)
    let textHeight = min(
      label.sizeThatFits(NSSize(width: bounds.width, height: .greatestFiniteMagnitude)).height,
      bounds.height - plateHeight - 4)
    label.frame = NSRect(
      x: 0, y: plate.frame.minY - 4 - textHeight, width: bounds.width, height: textHeight)
  }
}
