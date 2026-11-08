import AVFoundation
import AppKit

/// L'onglet Mirror : l'image de la caméra dans un cercle, avec à sa gauche le curseur courbe de
/// luminosité.
///
/// Le curseur ne règle que l'aperçu : deux voiles posés sur la vidéo, noir pour assombrir et blanc
/// pour éclaircir (`CameraBrightness`). Il ne touche ni à la caméra ni à la luminosité de l'écran.
///
/// La caméra n'est allumée que sur ordre de `setActive(_:)` : c'est le panneau qui sait quand
/// cette vue est réellement à l'écran. Sans autorisation, ou sans caméra, le cercle montre un
/// écriteau à la place de l'image.
final class CameraMirrorView: NSView {

  private let viewModel: CameraMirrorViewModel

  private let circle = NSView()
  private let previewLayer = AVCaptureVideoPreviewLayer()
  /// Dégradé de remplacement, quand la source ne fournit pas de session (fausse source).
  private let placeholderLayer = CAGradientLayer()
  private let darkenLayer = CALayer()
  private let lightenLayer = CALayer()
  private let slider = CurvedBrightnessSlider()

  private let statusIcon = NSImageView()
  private let statusLabel = NSTextField(wrappingLabelWithString: "")
  private let settingsButton = NSButton()

  /// Écart entre le bord du cercle et la piste du curseur.
  private static let sliderGap: CGFloat = 22

  init(viewModel: CameraMirrorViewModel) {
    self.viewModel = viewModel
    super.init(frame: .zero)
    wantsLayer = true
    setUp()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setUp() {
    circle.wantsLayer = true
    circle.layer?.masksToBounds = true
    circle.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
    addSubview(circle)

    // Miroir : on se voit comme dans une glace, pas comme les autres nous voient.
    previewLayer.videoGravity = .resizeAspectFill
    previewLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
    circle.layer?.addSublayer(previewLayer)

    placeholderLayer.colors = [
      NSColor(srgbRed: 0.93, green: 0.64, blue: 0.45, alpha: 1).cgColor,
      NSColor(srgbRed: 0.45, green: 0.46, blue: 0.85, alpha: 1).cgColor,
    ]
    placeholderLayer.isHidden = true
    circle.layer?.addSublayer(placeholderLayer)

    darkenLayer.backgroundColor = NSColor.black.cgColor
    lightenLayer.backgroundColor = NSColor.white.cgColor
    circle.layer?.addSublayer(darkenLayer)
    circle.layer?.addSublayer(lightenLayer)

    statusIcon.contentTintColor = NSColor(white: 0.62, alpha: 1)
    statusIcon.imageScaling = .scaleProportionallyUpOrDown
    statusLabel.alignment = .center
    statusLabel.font = .systemFont(ofSize: 12)
    statusLabel.textColor = NSColor(white: 0.7, alpha: 1)
    settingsButton.title = "Open Settings"
    settingsButton.bezelStyle = .rounded
    settingsButton.controlSize = .small
    settingsButton.target = self
    settingsButton.action = #selector(openCameraSettings)
    for view in [statusIcon, statusLabel, settingsButton] {
      view.isHidden = true
      circle.addSubview(view)
    }

    addSubview(slider)
    slider.onChange = { [weak self] value in self?.applyBrightness(value) }
    applyBrightness(slider.value)

    viewModel.onStateChanged = { [weak self] state in self?.apply(state) }
    apply(viewModel.state)
  }

  /// Allume ou éteint la caméra — voir `CameraMirrorViewModel.setActive(_:)`.
  func setActive(_ active: Bool) {
    viewModel.setActive(active)
  }

  // MARK: - Mise en page

  override func layout() {
    super.layout()

    // Le cercle est le fond du panneau : centré, posé sur son bord bas à un liseré près.
    let diameter = NotchPanelGeometry.mirrorDiameter
    circle.frame = NSRect(
      x: bounds.midX - diameter / 2,
      y: bounds.minY + NotchPanelGeometry.mirrorRim,
      width: diameter,
      height: diameter
    )
    circle.layer?.cornerRadius = diameter / 2
    circle.layer?.cornerCurve = .circular

    let inner = circle.bounds
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    [previewLayer, placeholderLayer, darkenLayer, lightenLayer].forEach { $0.frame = inner }
    CATransaction.commit()

    // La piste longe le cercle dans le coin haut-gauche, entre le cercle et le flanc : même
    // centre, un peu plus large.
    slider.frame = bounds
    slider.arc = ArcSliderGeometry(
      center: CGPoint(x: circle.frame.midX - bounds.minX, y: circle.frame.midY - bounds.minY),
      radius: diameter / 2 + Self.sliderGap,
      startAngle: 150 * .pi / 180,
      endAngle: 122 * .pi / 180
    )

    layoutStatus(in: inner)
  }

  private func layoutStatus(in inner: NSRect) {
    let width = inner.width * 0.62
    let iconSize: CGFloat = 28
    let labelHeight = statusLabel.sizeThatFits(
      NSSize(width: width, height: .greatestFiniteMagnitude)
    ).height
    let buttonHeight: CGFloat = 22
    let gap: CGFloat = 6
    let showsButton = !settingsButton.isHidden
    let total = iconSize + gap + labelHeight + (showsButton ? gap + buttonHeight : 0)

    var y = inner.midY + total / 2
    y -= iconSize
    statusIcon.frame = NSRect(x: inner.midX - iconSize / 2, y: y, width: iconSize, height: iconSize)
    y -= gap + labelHeight
    statusLabel.frame = NSRect(x: inner.midX - width / 2, y: y, width: width, height: labelHeight)
    y -= gap + buttonHeight
    settingsButton.sizeToFit()
    settingsButton.frame.origin = NSPoint(x: inner.midX - settingsButton.frame.width / 2, y: y)
  }

  // MARK: - État

  private func apply(_ state: CameraMirrorState) {
    let showsVideo = state == .running
    if showsVideo {
      // `nil` : la fausse source n'a pas d'image, le dégradé tient la place de la vidéo.
      // Rattachée une seule fois : (re)brancher la couche modifie les connexions de la
      // session, ce qui plante si `startRunning()` tourne en même temps sur sa file.
      if previewLayer.session !== viewModel.session { previewLayer.session = viewModel.session }
      previewLayer.isHidden = false
      placeholderLayer.isHidden = viewModel.session != nil
    } else {
      // Couche masquée à l'arrêt plutôt que détachée : elle ne garde pas la dernière image figée.
      previewLayer.isHidden = true
      placeholderLayer.isHidden = true
    }
    // Les voiles ne règlent que la vidéo : sur l'écriteau, ils grisaient le texte.
    darkenLayer.isHidden = !showsVideo
    lightenLayer.isHidden = !showsVideo

    let message: (symbol: String, text: String, showsSettings: Bool)? =
      switch state {
      case .idle, .running: nil
      case .denied: ("camera.fill", "Camera access is off for Whoa Stash.", true)
      case .unavailable: ("video.slash.fill", "No camera found.", false)
      }

    let previousMessage = statusLabel.stringValue
    statusIcon.isHidden = message == nil
    statusLabel.isHidden = message == nil
    settingsButton.isHidden = !(message?.showsSettings ?? false)
    if let message {
      statusIcon.image = NSImage(systemSymbolName: message.symbol, accessibilityDescription: nil)
      statusLabel.stringValue = message.text
      if previousMessage != message.text {
        for view in [statusIcon, statusLabel, settingsButton] as [NSView] where !view.isHidden {
          view.wantsLayer = true
          view.layer?.springReveal()
        }
      }
    }
    needsLayout = true
  }

  private func applyBrightness(_ value: Double) {
    let overlay = CameraBrightness.overlay(for: value)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    darkenLayer.opacity = Float(overlay.darkness)
    lightenLayer.opacity = Float(overlay.lightness)
    CATransaction.commit()
  }

  @objc private func openCameraSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    else { return }
    NSWorkspace.shared.open(url)
  }
}
