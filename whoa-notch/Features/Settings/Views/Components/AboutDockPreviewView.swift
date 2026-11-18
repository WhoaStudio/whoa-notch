import AppKit
import OSLog
import UniformTypeIdentifiers

/// Aperçu d'un Dock façon macOS pour l'écran « About » : Finder, l'icône de l'app, un
/// séparateur puis la corbeille vide, posés sur le fond d'écran courant de l'écran de la
/// fenêtre. Sans fond d'écran lisible, un dégradé sombre neutre le remplace.
final class AboutDockPreviewView: NSView {

  private static let size = NSSize(width: 400, height: 130)
  private static let iconSize: CGFloat = 56
  private static let maxWallpaperPixels: CGFloat = 800

  private let wallpaperLayer = CALayer()
  private let fallbackLayer = CAGradientLayer()
  private var loadedURL: URL?
  private var loadTask: Task<Void, Never>?
  private var screenObserver: NSObjectProtocol?
  private var spaceObserver: NSObjectProtocol?

  override init(frame frameRect: NSRect) {
    super.init(frame: NSRect(origin: .zero, size: Self.size))
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  isolated deinit {
    loadTask?.cancel()
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
  }

  override var intrinsicContentSize: NSSize { Self.size }

  private func setUp() {
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.cornerRadius = 16
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
    layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor

    fallbackLayer.colors = [
      NSColor(white: 0.22, alpha: 1).cgColor, NSColor(white: 0.05, alpha: 1).cgColor,
    ]
    fallbackLayer.startPoint = CGPoint(x: 0, y: 1)
    fallbackLayer.endPoint = CGPoint(x: 1, y: 0)
    wallpaperLayer.contentsGravity = .resizeAspectFill
    wallpaperLayer.opacity = 0
    layer?.addSublayer(fallbackLayer)
    layer?.addSublayer(wallpaperLayer)

    let dock = makeDock()
    addSubview(dock)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: Self.size.width),
      heightAnchor.constraint(equalToConstant: Self.size.height),
      dock.centerXAnchor.constraint(equalTo: centerXAnchor),
      dock.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  override func layout() {
    super.layout()
    fallbackLayer.frame = bounds
    wallpaperLayer.frame = bounds
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    screenObserver = nil
    spaceObserver = nil
    guard let window else { return }
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.reloadWallpaper() } }
    spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.reloadWallpaper() } }
    reloadWallpaper()
  }

  // MARK: - Fond d'écran

  private func reloadWallpaper() {
    let screen = window?.screen ?? NSScreen.main
    guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
      showFallback()
      return
    }
    guard url != loadedURL else { return }
    loadTask?.cancel()
    let maxPixels = Self.maxWallpaperPixels
    loadTask = Task { [weak self] in
      let image = await Task.detached(priority: .utility) {
        Self.downsampledImage(at: url, maxPixels: maxPixels)
      }.value
      guard !Task.isCancelled, let self else { return }
      if let image {
        self.loadedURL = url
        self.wallpaperLayer.contents = image
        self.wallpaperLayer.opacity = 1
      } else {
        Log.settings.error("Fond d'écran illisible pour l'aperçu du Dock")
        self.showFallback()
      }
    }
  }

  private func showFallback() {
    loadedURL = nil
    wallpaperLayer.contents = nil
    wallpaperLayer.opacity = 0
  }

  /// Décode le fond d'écran réduit : certains fonds HEIC font plusieurs dizaines de mégapixels.
  nonisolated private static func downsampledImage(at url: URL, maxPixels: CGFloat) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  // MARK: - Dock

  private func makeDock() -> NSView {
    let finderURL = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: "com.apple.finder")
    let finderIcon =
      finderURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
      ?? NSWorkspace.shared.icon(for: .applicationBundle)
    let trashIcon = NSImage(named: NSImage.trashEmptyName) ?? NSImage()

    let separator = NSView()
    separator.translatesAutoresizingMaskIntoConstraints = false
    separator.wantsLayer = true
    separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    NSLayoutConstraint.activate([
      separator.widthAnchor.constraint(equalToConstant: 1),
      separator.heightAnchor.constraint(equalToConstant: Self.iconSize - 6),
    ])

    let stack = NSStackView(views: [
      Self.iconView(finderIcon),
      Self.iconView(NSApp.applicationIconImage ?? NSImage()),
      separator,
      Self.iconView(trashIcon),
    ])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    stack.translatesAutoresizingMaskIntoConstraints = false

    let glass = NSVisualEffectView()
    glass.material = .hudWindow
    glass.blendingMode = .withinWindow
    glass.state = .active
    glass.wantsLayer = true
    glass.layer?.cornerRadius = 22
    glass.layer?.cornerCurve = .continuous
    glass.layer?.masksToBounds = true
    glass.layer?.borderWidth = 1
    glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
    glass.translatesAutoresizingMaskIntoConstraints = false
    glass.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
      stack.topAnchor.constraint(equalTo: glass.topAnchor),
      stack.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
    ])
    return glass
  }

  private static func iconView(_ image: NSImage) -> NSImageView {
    let view = NSImageView(image: image)
    view.imageScaling = .scaleProportionallyUpOrDown
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      view.widthAnchor.constraint(equalToConstant: iconSize),
      view.heightAnchor.constraint(equalToConstant: iconSize),
    ])
    return view
  }
}
