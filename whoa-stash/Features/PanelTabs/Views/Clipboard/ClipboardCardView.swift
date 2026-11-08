import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

extension ClipboardKind {
  /// Couleur de la bordure basse de la carte. L'app est toujours en `.darkAqua` : pas de variante.
  var accentColor: NSColor {
    switch self {
    case .image: NSColor(srgbRed: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255, alpha: 1)
    case .text: NSColor(srgbRed: 0x5C / 255, green: 0xC8 / 255, blue: 0x5A / 255, alpha: 1)
    case .link: NSColor(srgbRed: 0x5A / 255, green: 0xC8 / 255, blue: 0xFA / 255, alpha: 1)
    case .file: NSColor(srgbRed: 0xB0 / 255, green: 0x3F / 255, blue: 0xE0 / 255, alpha: 1)
    case .video: NSColor(srgbRed: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255, alpha: 1)
    }
  }
}

/// Une carte de l'historique : aperçu ou texte, pastille de type en bas à gauche, bordure basse
/// colorée selon le type. Un clic la remet dans le presse-papiers.
final class ClipboardCardView: NSView {

  static let size = NSSize(width: 124, height: 104)

  var onClick: (() -> Void)?

  private let item: ClipboardItem
  /// Icône d'un fichier ; image et vidéo remplissent la carte par `coverView`.
  private let previewView = NSImageView()
  private let coverView = NSView()
  private let textLabel = NSTextField(labelWithString: "")
  private let sourceIconView = NSImageView()
  private let ageLabel = NSTextField(labelWithString: "")
  private let shade = CAGradientLayer()
  private let accentBar = CALayer()
  private var thumbnailTask: Task<Void, Never>?

  private let barHeight: CGFloat = 4
  private let padding: CGFloat = 10

  init(item: ClipboardItem, imageURL: URL?) {
    self.item = item
    super.init(frame: NSRect(origin: .zero, size: Self.size))
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.backgroundColor = NSColor(white: 0.1, alpha: 1).cgColor
    setUp(imageURL: imageURL)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit { thumbnailTask?.cancel() }

  private func setUp(imageURL: URL?) {
    accentBar.backgroundColor = item.kind.accentColor.cgColor
    layer?.addSublayer(accentBar)

    switch item.kind {
    case .text, .link:
      textLabel.stringValue = item.text ?? ""
      textLabel.font = .systemFont(ofSize: 12, weight: .regular)
      textLabel.textColor = .white
      textLabel.lineBreakMode = .byTruncatingTail
      textLabel.maximumNumberOfLines = 3
      textLabel.cell?.wraps = true
      textLabel.cell?.truncatesLastVisibleLine = true
      addSubview(textLabel)
    case .image, .video, .file:
      previewView.imageScaling = .scaleProportionallyUpOrDown
      coverView.wantsLayer = true
      coverView.layer?.contentsGravity = .resizeAspectFill
      addSubview(item.kind == .file ? previewView : coverView)
      loadPreview(imageURL: imageURL)
    }

    if item.kind == .image || item.kind == .video {
      // Voile bas : l'icône et l'âge restent lisibles sur n'importe quelle image.
      shade.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.6).cgColor]
      layer?.insertSublayer(shade, above: coverView.layer)
    }

    sourceIconView.imageScaling = .scaleProportionallyUpOrDown
    sourceIconView.image = Self.sourceIcon(bundleID: item.sourceBundleID)
    addSubview(sourceIconView)

    ageLabel.font = .systemFont(ofSize: 11, weight: .regular)
    ageLabel.textColor = NSColor(white: 0.85, alpha: 1)
    addSubview(ageLabel)
    refreshAge()
  }

  /// Recalcule « il y a N min » — appelé à chaque dépliage du panneau.
  func refreshAge() {
    ageLabel.stringValue = ClipboardItem.ageText(since: item.date)
    needsLayout = true
  }

  private static func sourceIcon(bundleID: String?) -> NSImage? {
    guard
      let bundleID,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
  }

  // MARK: - Aperçu

  private func loadPreview(imageURL: URL?) {
    if let imageURL, let image = NSImage(contentsOf: imageURL) {
      show(image)
      return
    }
    guard let url = item.fileURL else { return }
    show(Self.icon(for: url))

    // Un fichier garde l'icône du Finder ; image et vidéo prennent leur aperçu.
    guard item.kind != .file else { return }
    let request = QLThumbnailGenerator.Request(
      fileAt: url, size: Self.size, scale: NSScreen.main?.backingScaleFactor ?? 2,
      representationTypes: .thumbnail)
    thumbnailTask = Task { [weak self] in
      guard
        let representation = try? await QLThumbnailGenerator.shared
          .generateBestRepresentation(for: request), !Task.isCancelled
      else { return }
      self?.show(representation.nsImage)
    }
  }

  private func show(_ image: NSImage) {
    if item.kind == .file {
      previewView.image = image
    } else {
      coverView.layer?.contents = image
    }
    needsLayout = true
  }

  /// Icône du Finder, ou celle du type quand le fichier n'existe plus.
  private static func icon(for url: URL) -> NSImage {
    if FileManager.default.fileExists(atPath: url.path) {
      return NSWorkspace.shared.icon(forFile: url.path)
    }
    return NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .data)
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()
    accentBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: barHeight)

    let iconSide: CGFloat = 22
    let footerY = barHeight + 8
    let hasIcon = sourceIconView.image != nil
    sourceIconView.isHidden = !hasIcon
    sourceIconView.frame = CGRect(x: 10, y: footerY, width: iconSide, height: iconSide)
    let ageSize = ageLabel.sizeThatFits(NSSize(width: 200, height: 20))
    let ageX = hasIcon ? sourceIconView.frame.maxX + 6 : 10
    ageLabel.frame = CGRect(
      x: ageX, y: footerY + (iconSide - ceil(ageSize.height)) / 2,
      width: min(ceil(ageSize.width), bounds.width - ageX - 6), height: ceil(ageSize.height))
    let chip = CGRect(x: 0, y: footerY, width: 0, height: iconSide)
    shade.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height / 2)

    switch item.kind {
    case .text, .link:
      let top = bounds.maxY - padding
      let bottom = chip.maxY + 6
      textLabel.preferredMaxLayoutWidth = bounds.width - 2 * padding
      textLabel.frame = CGRect(
        x: padding, y: bottom, width: bounds.width - 2 * padding, height: max(0, top - bottom))
      textLabel.alignment = .left
    case .image, .video:
      coverView.frame = bounds
    case .file:
      let side: CGFloat = 54
      previewView.frame = CGRect(
        x: bounds.midX - side / 2, y: bounds.maxY - side - 14, width: side, height: side)
    }
  }

  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
  }
}
