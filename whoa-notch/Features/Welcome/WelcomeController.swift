import AppKit
import SwiftUI

/// Écran de bienvenue du premier lancement. Il emprunte le dessin du panneau de l'encoche : même
/// silhouette suspendue au bord du haut (`PanelGeometry.silhouette`), même fond et même filet,
/// même niveau de fenêtre — et il se déplie depuis l'encoche avec le même ressort, au lieu de
/// glisser d'ailleurs. Il n'écrit rien lui-même : `onStart` et `onTutorial` disent à
/// l'`AppDelegate` quoi faire, et le panneau se replie dans l'encoche.
final class WelcomeController {

  /// Sans boutons, le panneau est plus bas d'autant.
  static func size(showsButtons: Bool) -> CGSize {
    CGSize(width: 464, height: showsButtons ? 318 : 260)
  }
  /// Marge latérale du contenu : les raccords concaves de la silhouette mordent sur les côtés.
  static let contentInsetX: CGFloat = PanelGeometry.cornerRadius + 12

  /// Le panneau ne s'affiche qu'une fois : tant que l'accueil n'a pas été vu, ou si on le force.
  static func shouldShow(hasSeenOnboarding: Bool, forced: Bool) -> Bool {
    !hasSeenOnboarding || forced
  }

  var onStart: (() -> Void)?
  var onTutorial: (() -> Void)?

  private var panel: NSPanel?
  private var root: WelcomeRootView?

  /// Déplie le panneau sur l'écran principal, sous l'encoche. Au premier lancement
  /// (`showsButtons`), il attend un clic sur « Start » ou « See Tutorial » ; ensuite, il joue
  /// l'animation puis se replie seul.
  func activate(showsButtons: Bool) {
    guard panel == nil, let screen = NSScreen.main else { return }
    let size = Self.size(showsButtons: showsButtons)
    let notch = NotchPanelGeometry.notchRect(on: screen)
    let frame = NSRect(
      x: screen.frame.midX - size.width / 2,
      y: NotchPanelGeometry.topAnchor(on: screen) - size.height,
      width: size.width, height: size.height)

    let panel = NSPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.level = .screenSaver
    panel.collectionBehavior = [
      .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
    ]
    // Sans boutons, le panneau ne doit rien intercepter : il se referme tout seul.
    panel.ignoresMouseEvents = !showsButtons

    let root = WelcomeRootView(
      frame: NSRect(origin: .zero, size: size),
      size: size,
      showsButtons: showsButtons,
      collapsedSize: notch?.size ?? NotchPanelGeometry.pillSize,
      topInset: (notch?.height ?? NotchPanelGeometry.pillSize.height) + 6)
    root.onStart = { [weak self] in self?.dismiss(then: self?.onStart) }
    root.onTutorial = { [weak self] in self?.dismiss(then: self?.onTutorial) }
    panel.contentView = root
    panel.setFrame(frame, display: false)
    panel.orderFrontRegardless()

    self.panel = panel
    self.root = root
    root.unfold()

    if !showsButtons {
      // Le temps du dépliage et du dessin, puis une pause pour lire avant de se replier.
      let reading = OverlayAnimation.allowsMotion ? HelloASCIIField.duration + 2.5 : 2.5
      DispatchQueue.main.asyncAfter(deadline: .now() + reading) { [weak self] in
        self?.dismiss(then: nil)
      }
    }
  }

  private func dismiss(then action: (() -> Void)?) {
    guard let panel, let root else { return }
    self.panel = nil
    self.root = nil
    root.fold {
      panel.close()
      action?()
    }
  }
}

/// Une vue qui accepte le premier clic : le panneau est `.nonactivatingPanel`, et sans cela le
/// premier clic sur un bouton ne ferait que « réveiller » la fenêtre.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Fond du panneau : la silhouette de l'encoche, repliée sur l'encoche puis dépliée au ressort.
/// Les deux chemins ont la même suite de segments, ce qui rend le dépliage animable.
private final class WelcomeRootView: NSView {

  var onStart: (() -> Void)?
  var onTutorial: (() -> Void)?

  private let size: CGSize
  private let showsButtons: Bool
  private let collapsedSize: NSSize
  private let topInset: CGFloat
  private let backgroundLayer = CAShapeLayer()
  private let strokeLayer = CAShapeLayer()
  private var hosting: NSView?

  init(frame: NSRect, size: CGSize, showsButtons: Bool, collapsedSize: NSSize, topInset: CGFloat) {
    self.size = size
    self.showsButtons = showsButtons
    self.collapsedSize = collapsedSize
    self.topInset = topInset
    super.init(frame: frame)
    wantsLayer = true

    let palette = OverlayPalette.resolved(for: NSApp.effectiveAppearance)
    backgroundLayer.fillColor = palette.panelBackground
    strokeLayer.fillColor = nil
    strokeLayer.strokeColor = palette.strokeColor
    strokeLayer.lineWidth = PanelGeometry.strokeWidth
    layer?.addSublayer(backgroundLayer)
    layer?.addSublayer(strokeLayer)
    for shape in [backgroundLayer, strokeLayer] {
      shape.frame = bounds
      shape.path = collapsedPath()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func collapsedPath() -> CGPath {
    PanelGeometry.silhouette(
      in: bounds, anchoredTo: .top, size: collapsedSize,
      shoulderRadius: NotchPanelGeometry.collapsedShoulderRadius,
      farRadius: NotchPanelGeometry.collapsedBottomRadius)
  }

  private func expandedPath() -> CGPath {
    PanelGeometry.silhouette(
      in: bounds, anchoredTo: .top, size: size,
      shoulderRadius: NotchPanelGeometry.expandedShoulderRadius,
      farRadius: NotchPanelGeometry.expandedBottomRadius)
  }

  /// Déplie la silhouette, puis pose le contenu une fois le ressort presque posé : le trait
  /// de « hello » ne commence qu'à ce moment-là.
  func unfold() {
    let animated = OverlayAnimation.allowsMotion
    let target = expandedPath()
    strokeLayer.springAnimate(keyPath: "path", to: target, preset: .gentle)
    backgroundLayer.springAnimate(keyPath: "path", to: target, preset: .gentle)
    let delay = animated ? 0.35 : 0
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      self?.showContent(animated: animated)
    }
  }

  private func showContent(animated: Bool) {
    let view = FirstMouseHostingView(
      rootView: WelcomeView(
        animated: animated,
        showsButtons: showsButtons,
        size: size,
        topInset: topInset,
        onStart: { [weak self] in self?.onStart?() },
        onTutorial: { [weak self] in self?.onTutorial?() }))
    view.frame = bounds
    view.autoresizingMask = [.width, .height]
    addSubview(view)
    hosting = view
  }

  /// Retire le contenu, puis replie la silhouette dans l'encoche.
  func fold(completion: @escaping () -> Void) {
    hosting?.removeFromSuperview()
    hosting = nil
    let target = collapsedPath()
    strokeLayer.springAnimate(keyPath: "path", to: target, preset: .gentle)
    backgroundLayer.springAnimate(
      keyPath: "path", to: target, preset: .gentle, completion: completion)
  }
}
