import AppKit
import CoreImage

/// Contenu des deux ailes de l'encoche pendant la lecture : la pochette à gauche, le
/// visualiseur à droite, le centre restant à l'encoche matérielle. Même gabarit que
/// `DeviceStatusPillView`, avec des ailes plus étroites.
///
/// Pas de fond : la silhouette élargie par `NotchPanelContentView` en fait office. Mise en page
/// en frames ; la vue ne reçoit aucun événement.
final class NowPlayingWingsView: NSView {

  private let artworkView = ArtworkView()
  private let visualizer = AudioVisualizerView()

  /// Largeur de chaque aile, de part et d'autre de l'encoche : plus étroite que celle de la
  /// pastille Bluetooth, qui n'a pas à porter de pochette plus grande.
  static let wingWidth: CGFloat = 60

  /// Hauteur ajoutée à l'encoche pendant la lecture.
  static let extraHeight: CGFloat = 2

  /// Mode île : rien de matériel à contourner au centre, donc la pastille se resserre — ailes
  /// et centre plus étroits — et gagne en hauteur pour porter la pochette à l'aise.
  static let islandWingWidth: CGFloat = 52
  static let islandCenterWidth: CGFloat = 76
  static let islandExtraHeight: CGFloat = 10

  /// Décalage vers le haut du contenu : il se centre sur la bande de l'encoche, pas sur le débord
  /// sous elle. Nul en mode île, où le contenu se centre sur toute la pastille.
  var lift: CGFloat = NowPlayingWingsView.extraHeight / 2 { didSet { needsLayout = true } }

  private let inset: CGFloat = NotchPanelGeometry.wingEdgeInset
  private let artworkSize: CGFloat = 28

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    addSubview(artworkView)
    addSubview(visualizer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func apply(_ state: NowPlayingState) {
    artworkView.setArtwork(state.artwork)
    artworkView.setSource(bundleIdentifier: state.bundleIdentifier)
    visualizer.setAnimating(state.isPlaying)
  }

  /// Cadres de la pochette et du visualiseur, dans le repère de la vue : un bout du trajet vers
  /// le lecteur de l'onglet Global (voir `NotchPanelContentView`).
  var artworkFrame: NSRect { artworkView.frame }
  var visualizerFrame: NSRect { visualizer.frame }

  /// Cache pochette et visualiseur pendant que leurs doublures font le trajet.
  func setSharedElementsHidden(_ hidden: Bool) {
    artworkView.isHidden = hidden
    visualizer.isHidden = hidden
  }

  override func layout() {
    super.layout()
    // La vue déborde sous la bande de l'encoche : le contenu est centré sur la bande
    // elle-même, pas sur le débord (voir `lift`).
    artworkView.frame = NSRect(
      x: inset, y: (bounds.height - artworkSize) / 2 + lift, width: artworkSize, height: artworkSize
    )
    let size = visualizer.intrinsicContentSize
    visualizer.frame = NSRect(
      x: bounds.width - inset - size.width, y: (bounds.height - size.height) / 2 + lift,
      width: size.width, height: size.height)
  }
}

/// Pochette arrondie, avec en bas à droite l'icône de l'application qui joue (Spotify, Musique,
/// le navigateur). Un glyphe de note tient lieu d'image tant qu'il n'y en a pas : elle arrive
/// parfois après le titre.
final class ArtworkView: NSView {

  private let imageView = NSImageView()
  /// Copie floutée de la pochette, en remplissage, derrière l'image : elle comble les bandes
  /// laissées par une pochette qui n'est pas carrée, affichée en entier dans le carré.
  private let backdropView = NSView()
  private let badgeView = NSImageView()
  private var currentData: Data?
  private var currentSource: String?

  var cornerRadius: CGFloat = 7 {
    didSet {
      imageView.layer?.cornerRadius = cornerRadius
      backdropView.layer?.cornerRadius = cornerRadius
    }
  }

  var showsSourceBadge = true {
    didSet { badgeView.isHidden = !showsSourceBadge || badgeView.image == nil }
  }

  /// Taille de l'icône (part du côté de la pochette) et retrait depuis le coin bas droit :
  /// négatif, elle déborde de la pochette ; positif, elle se pose dedans.
  var badgeScale: CGFloat = 0.5 { didSet { needsLayout = true } }
  var badgeInset: CGFloat = -3 { didSet { needsLayout = true } }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true

    backdropView.wantsLayer = true
    backdropView.layer?.cornerRadius = cornerRadius
    backdropView.layer?.masksToBounds = true
    backdropView.layer?.contentsGravity = .resizeAspectFill
    addSubview(backdropView)

    // Le coin arrondi est sur l'image seule : l'icône déborde un peu de la pochette.
    imageView.wantsLayer = true
    imageView.layer?.cornerRadius = cornerRadius
    imageView.layer?.masksToBounds = true
    imageView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.contentTintColor = .white.withAlphaComponent(0.7)
    addSubview(imageView)

    badgeView.imageScaling = .scaleProportionallyUpOrDown
    badgeView.isHidden = true
    addSubview(badgeView)
    showPlaceholder()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    backdropView.frame = bounds
    imageView.frame = bounds
    let badge = (bounds.width * badgeScale).rounded()
    badgeView.frame = NSRect(
      x: bounds.maxX - badge - badgeInset, y: bounds.minY + badgeInset, width: badge, height: badge)
  }

  func setArtwork(_ data: Data?) {
    guard data != currentData else { return }
    currentData = data
    if let data, let image = NSImage(data: data) {
      // Proportions gardées, image entière : ni étirée ni rognée.
      imageView.imageScaling = .scaleProportionallyUpOrDown
      imageView.image = image
      backdropView.layer?.contents = Self.blurredBackdrop(from: data)
    } else {
      showPlaceholder()
    }
    if window != nil { layer?.springReveal(x: 6, y: 0) }
  }

  /// Anime le rayon des coins depuis `start` jusqu'au rayon courant, au ressort du dépliage :
  /// une doublure mise à l'échelle garde ainsi des coins constants à l'écran.
  func animateCornerRadius(from start: CGFloat) {
    for layer in [imageView.layer, backdropView.layer].compactMap({ $0 }) {
      layer.springAnimate(keyPath: "cornerRadius", to: cornerRadius, from: start, preset: .gentle)
    }
  }

  /// Icône de l'application dont on donne l'identifiant ; rien si le système ne la connaît pas.
  func setSource(bundleIdentifier: String) {
    guard bundleIdentifier != currentSource else { return }
    currentSource = bundleIdentifier
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
      badgeView.image = NSWorkspace.shared.icon(forFile: url.path)
      badgeView.isHidden = !showsSourceBadge
    } else {
      badgeView.image = nil
      badgeView.isHidden = true
    }
  }

  /// Retire l'icône : plus rien ne joue.
  func clearSource() {
    currentSource = nil
    badgeView.image = nil
    badgeView.isHidden = true
  }

  private func showPlaceholder() {
    backdropView.layer?.contents = nil
    imageView.imageScaling = .scaleProportionallyDown
    imageView.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
  }

  private static let ciContext = CIContext()

  /// Pochette réduite puis floutée, assombrie, pour le fond. Réduite d'abord : le flou sur une
  /// petite image coûte peu et suffit, la vue ne dépasse pas quelques dizaines de points.
  private static func blurredBackdrop(from data: Data) -> CGImage? {
    guard let source = CIImage(data: data) else { return nil }
    let extent = source.extent
    guard extent.width > 0, extent.height > 0 else { return nil }
    let scale = 64 / max(extent.width, extent.height)
    let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let blurred = small.clampedToExtent()
      .applyingGaussianBlur(sigma: 6)
      .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.15])
      .cropped(to: small.extent)
    return ciContext.createCGImage(blurred, from: small.extent)
  }
}
