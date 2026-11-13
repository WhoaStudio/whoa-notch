import AppKit
import SwiftUI

/// Écran de bienvenue du premier lancement. Il emprunte le dessin du panneau de l'encoche : même
/// silhouette suspendue au bord du haut (`PanelGeometry.silhouette`), même fond et même filet,
/// même niveau de fenêtre — et il se déplie depuis l'encoche avec le même ressort, au lieu de
/// glisser d'ailleurs. Il n'écrit rien lui-même : `onStart` et `onTutorial` disent à
/// l'`AppDelegate` quoi faire, et le panneau se replie dans l'encoche.
final class WelcomeController {

  static let width: CGFloat = 464
  /// Les lancements suivants : le bonjour seul, qui se replie tout seul.
  static let greetingSize = CGSize(width: width, height: 260)
  /// Marge latérale du contenu : les raccords concaves de la silhouette mordent sur les côtés.
  static let contentInsetX: CGFloat = PanelGeometry.cornerRadius + 12

  /// Le panneau ne s'affiche qu'une fois : tant que l'accueil n'a pas été vu, ou si on le force.
  static func shouldShow(hasSeenOnboarding: Bool, forced: Bool) -> Bool {
    !hasSeenOnboarding || forced
  }

  /// Appelée quand le parcours se termine (Finish, Skip tour ou Échap), panneau replié.
  var onFinish: (() -> Void)?

  private var panel: NSPanel?
  private var root: WelcomeRootView?
  private var input: OnboardingInput?

  /// Déplie le panneau sur l'écran principal, sous l'encoche. Au premier lancement (`tour`), il
  /// déroule le parcours à partir de cette étape ; ensuite, il joue le bonjour puis se replie seul.
  func activate(tour: OnboardingStep?) {
    guard panel == nil, let screen = NSScreen.main else { return }
    let notch = NotchPanelGeometry.notchRect(on: screen)
    let topInset = (notch?.height ?? NotchPanelGeometry.pillSize.height) + 6
    let size =
      tour == nil
      ? Self.greetingSize
      : CGSize(width: Self.width, height: OnboardingFlow.maxPanelHeight(topInset: topInset))
    let frame = NSRect(
      x: screen.frame.midX - size.width / 2,
      y: NotchPanelGeometry.topAnchor(on: screen) - size.height,
      width: size.width, height: size.height)

    let panel = OnboardingPanel(
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
    panel.ignoresMouseEvents = tour == nil

    var model: OnboardingModel?
    if let tour { model = OnboardingModel(start: tour) }
    let root = WelcomeRootView(
      frame: NSRect(origin: .zero, size: size),
      size: size,
      model: model,
      collapsedSize: notch?.size ?? NotchPanelGeometry.pillSize,
      topInset: topInset)
    panel.contentView = root
    panel.setFrame(frame, display: false)
    if tour == nil {
      panel.orderFrontRegardless()
    } else {
      panel.makeKeyAndOrderFront(nil)
    }

    self.panel = panel
    self.root = root
    root.unfold()

    if let model {
      model.onFinish = { [weak self] in self?.dismiss(then: self?.onFinish) }
      model.onStepChanged = { [weak root] step in root?.resize(to: step) }
      let input = OnboardingInput(model: model, window: panel)
      input.onSkip = { [weak self] in self?.dismiss(then: self?.onFinish) }
      self.input = input
    } else {
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
    input?.stop()
    input = nil
    root.fold {
      panel.close()
      action?()
    }
  }
}

/// Le parcours prend le clavier (flèches, Retour, Échap) sans activer l'app.
private final class OnboardingPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

/// Une vue qui accepte le premier clic : le panneau est `.nonactivatingPanel`, et sans cela le
/// premier clic sur un bouton ne ferait que « réveiller » la fenêtre.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Fond du panneau : la silhouette de l'encoche, repliée sur l'encoche puis dépliée au ressort.
/// Les deux chemins ont la même suite de segments, ce qui rend le dépliage animable.
private final class WelcomeRootView: NSView {

  private let size: CGSize
  private let model: OnboardingModel?
  /// Hauteur peinte de la silhouette : celle de l'étape courante pour le parcours, sinon toute la fenêtre.
  private var paintedHeight: CGFloat
  private let collapsedSize: NSSize
  private let topInset: CGFloat
  private let backgroundLayer = CAShapeLayer()
  private let strokeLayer = CAShapeLayer()
  private var hosting: NSView?

  init(
    frame: NSRect, size: CGSize, model: OnboardingModel?, collapsedSize: NSSize,
    topInset: CGFloat
  ) {
    self.size = size
    self.model = model
    paintedHeight =
      model.map { OnboardingFlow.panelHeight(for: $0.step, topInset: topInset) } ?? size.height
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
      in: bounds, anchoredTo: .top, size: CGSize(width: size.width, height: paintedHeight),
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

  /// Change la hauteur de la silhouette pour une nouvelle étape, avec le ressort du dépliage.
  func resize(to step: OnboardingStep) {
    paintedHeight = OnboardingFlow.panelHeight(for: step, topInset: topInset)
    let target = expandedPath()
    strokeLayer.springAnimate(keyPath: "path", to: target, preset: .gentle)
    backgroundLayer.springAnimate(keyPath: "path", to: target, preset: .gentle)
  }

  private func showContent(animated: Bool) {
    let view: NSView
    if let model {
      view = FirstMouseHostingView(
        rootView: OnboardingFlowView(
          model: model, size: size, topInset: topInset, animatesHello: animated))
    } else {
      view = FirstMouseHostingView(
        rootView: WelcomeView(animated: animated, size: size, topInset: topInset))
    }
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
