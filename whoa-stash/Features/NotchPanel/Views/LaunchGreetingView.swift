import AppKit

/// Petit coffre d'accueil : les yeux clignent et le visage regarde de chaque côté.
/// Les animations sont finies et ne tournent jamais en arrière-plan après l'accueil.
final class LaunchGreetingView: NSView {
    private let head = CALayer()
    private let artwork = CALayer()
    private let eyes = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(head)
        head.addSublayer(artwork)
        head.addSublayer(eyes)
        artwork.contents = ChestMark.chest()?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
        eyes.contents = ChestMark.eyes()?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
        artwork.contentsGravity = .resizeAspect
        eyes.contentsGravity = .resizeAspect
        setAccessibilityElement(true)
        setAccessibilityLabel("Whoa Stash")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let size = min(32, bounds.height - 4)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        head.frame = NSRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2,
                            width: size, height: size)
        artwork.frame = head.bounds
        eyes.frame = ChestMark.eyesFrame(inChestOfSide: size)
        CATransaction.commit()
    }

    func start() {
        stop()
        guard OverlayAnimation.isEnabled,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        // Un seul regard dans chaque direction, puis retour au centre.
        animate(head, key: "transform.rotation.z",
                values: [0, 0, 0.07, 0.07, -0.07, -0.07, 0, 0],
                times: [0, 0.18, 0.25, 0.39, 0.46, 0.64, 0.71, 1])
        animate(eyes, key: "transform.translation.x",
                values: [0, 0, -1, -1, 1, 1, 0, 0],
                times: [0, 0.18, 0.25, 0.39, 0.46, 0.64, 0.71, 1])
        animate(eyes, key: "transform.scale.y",
                values: [1, 1, 0.08, 1, 1, 0.08, 1, 1],
                times: [0, 0.10, 0.13, 0.16, 0.77, 0.80, 0.83, 1])
    }

    func stop() {
        head.removeAllAnimations()
        eyes.removeAllAnimations()
    }

    private func animate(_ layer: CALayer, key: String, values: [Double], times: [NSNumber]) {
        let animation = CAKeyframeAnimation(keyPath: key)
        animation.values = values
        animation.keyTimes = times
        animation.duration = 3.2
        animation.timingFunctions = Array(
            repeating: CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1),
            count: values.count - 1)
        layer.add(animation, forKey: key)
    }
}
