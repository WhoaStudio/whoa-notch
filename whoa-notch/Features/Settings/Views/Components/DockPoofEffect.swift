import AppKit

/// Le « poof » d'une icône qu'on sort du dock : elle grossit un peu et s'efface sur place, dans
/// une fenêtre sans bordure posée sous le curseur. Remplace `NSAnimationEffect`, déprécié.
@MainActor
enum DockPoofEffect {

  /// `size` est le côté de l'icône ; `screenPoint` est l'endroit où elle a été lâchée.
  static func show(image: NSImage, size: CGFloat, at screenPoint: NSPoint) {
    // Réglage « Enable animations » coupé : l'icône disparaît, sans effet.
    guard OverlayAnimation.isEnabled else { return }
    let side = size * 1.5
    let window = NSWindow(
      contentRect: NSRect(
        x: screenPoint.x - side / 2, y: screenPoint.y - side / 2, width: side, height: side),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.isReleasedWhenClosed = false
    window.level = .statusBar

    let view = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
    view.wantsLayer = true
    let imageView = NSImageView(
      frame: NSRect(x: (side - size) / 2, y: (side - size) / 2, width: size, height: size))
    imageView.image = image
    imageView.imageScaling = .scaleProportionallyUpOrDown
    view.addSubview(imageView)
    window.contentView = view
    window.orderFrontRegardless()

    // « Réduire les animations » : un simple fondu, sans grossissement.
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let duration: CFTimeInterval = reduceMotion ? 0.15 : 0.25
    guard let layer = view.layer else {
      window.orderOut(nil)
      return
    }
    CATransaction.begin()
    CATransaction.setCompletionBlock {
      MainActor.assumeIsolated { window.orderOut(nil) }
    }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1
    fade.toValue = 0
    fade.duration = duration
    fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
    fade.fillMode = .forwards
    fade.isRemovedOnCompletion = false
    layer.add(fade, forKey: "poofFade")
    if !reduceMotion {
      let grow = CABasicAnimation(keyPath: "transform.scale")
      grow.fromValue = 1
      grow.toValue = 1.4
      grow.duration = duration
      grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
      grow.fillMode = .forwards
      grow.isRemovedOnCompletion = false
      layer.add(grow, forKey: "poofGrow")
    }
    CATransaction.commit()
  }
}
