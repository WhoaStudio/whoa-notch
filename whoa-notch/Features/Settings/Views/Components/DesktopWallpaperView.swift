import AppKit
import OSLog

/// Le fond d'écran courant de l'écran de la fenêtre, pour poser une maquette de dock dessus. Sans
/// fond d'écran lisible (couleur unie, accès refusé), un dégradé sombre neutre le remplace. Il suit
/// le changement d'écran et d'espace.
final class DesktopWallpaperView: NSView {

  private static let maxWallpaperPixels: CGFloat = 800

  private let wallpaperLayer = CALayer()
  private let fallbackLayer = CAGradientLayer()
  private var loadedURL: URL?
  private var loadTask: Task<Void, Never>?
  private var screenObserver: NSObjectProtocol?
  private var spaceObserver: NSObjectProtocol?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
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
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  isolated deinit {
    loadTask?.cancel()
    removeObservers()
  }

  override func layout() {
    super.layout()
    fallbackLayer.frame = bounds
    wallpaperLayer.frame = bounds
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    removeObservers()
    guard let window else { return }
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.reload() } }
    spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.reload() } }
    reload()
  }

  private func removeObservers() {
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    screenObserver = nil
    spaceObserver = nil
  }

  private func reload() {
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
        Log.settings.error("Fond d'écran illisible pour la maquette du dock")
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
}
