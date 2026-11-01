import AppKit

/// Le coffre de l'app, à gauche de la semaine dans l'onglet Global déplié.
///
/// Tiré en morceaux de `ChestMark` (intérieur, couvercle, corps, ouverture, fermoir) sur la tuile
/// `ChestBackdrop`. Trois choses l'animent, indépendamment les unes des autres :
/// - le couvercle, qui pivote en perspective autour de son bord du fond (`ChestLidPose`) : il
///   s'entrouvre au survol et s'ouvre en grand au clic ;
/// - le regard, les yeux glissant vers le curseur tant qu'il est dans l'encoche (`ChestGaze`) ;
/// - le clignement, à intervalles aléatoires (`ChestBlink`).
final class NotchHomeLogoView: NSView {
    /// Angle du couvercle, en radians, à pleine ouverture : environ 35°, ce qui laisse voir
    /// l'intérieur sous le couvercle, comme dans l'œuvre.
    private static let maxLidAngle: Double = 0.62
    /// Ressort du couvercle. À l'ouverture il dépasse un peu ; à la fermeture il est amorti
    /// critiquement, sinon il dépasserait la fermeture et enfoncerait le couvercle dans le corps.
    private static let lidStiffness: CGFloat = 170
    private static let openingDamping: CGFloat = 17
    private static var closingDamping: CGFloat { 2 * lidStiffness.squareRoot() }

    /// `--logo-lid=closed|peek|open` fige le couvercle dans cette pose, sans survol ni clic : de
    /// quoi régler et vérifier une pose à l'œil.
    private static let frozenPose: ChestLidPose? = ProcessInfo.processInfo.arguments
        .compactMap { $0.hasPrefix("--logo-lid=") ? ChestLidPose(rawValue: String($0.dropFirst("--logo-lid=".count))) : nil }
        .first

    private let head = CALayer()
    private let backdrop = CALayer()
    /// Les scènes en perspective du couvercle et du fermoir : un même point de fuite, deux étages
    /// dans la pile — le couvercle sous le corps, le fermoir par-dessus.
    private let lidStage = CALayer()
    private let claspStage = CALayer()
    /// Les charnières : leur rotation est l'ouverture.
    private let lidPivot = CALayer()
    private let claspPivot = CALayer()
    private let partLayers: [ChestMark.Part: CALayer] = Dictionary(
        uniqueKeysWithValues: ChestMark.Part.allCases.map { ($0, CALayer()) })
    /// Porte les yeux : son décalage est le regard. Les yeux, dedans, ne font que cligner.
    private let gazeLayer = CALayer()
    private let eyes = CALayer()

    private var partImages: [ChestMark.Part: NSImage] = [:]
    private let eyesImage = ChestMark.eyes()
    /// Taille et échelle du dernier rendu, pour ne refaire les images que si l'une change.
    private var renderedSize: CGSize = .zero
    private var renderedScale: CGFloat = 0

    private var pose = ChestLidPose.closed
    private var isActive = false
    private var gaze: CGVector = .zero
    private var blinkTask: Task<Void, Never>?
    private var hoverArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        backdrop.contentsGravity = .resize
        head.addSublayer(backdrop)

        for pivot in pivots {
            pivot.anchorPoint = CGPoint(x: 0.5, y: 1 - ChestMark.lidHingeY / 256)
        }
        lidStage.addSublayer(lidPivot)
        claspStage.addSublayer(claspPivot)
        // Dans l'ordre de dessin : l'intérieur, sous le couvercle qui le recouvre, puis le
        // couvercle, le corps, son ouverture et le fermoir.
        head.addSublayer(face(.interior))
        head.addSublayer(lidStage)
        head.addSublayer(face(.body))
        head.addSublayer(face(.opening))
        head.addSublayer(claspStage)
        lidPivot.addSublayer(face(.lid))
        claspPivot.addSublayer(face(.clasp))
        for part in ChestMark.Part.allCases {
            face(part).contentsGravity = .resizeAspect
            partImages[part] = ChestMark.image(of: part)
        }
        // Refermé, ni l'intérieur ni l'ouverture du corps ne se voient.
        revealLayers.forEach { $0.opacity = 0 }

        eyes.contentsGravity = .resizeAspect
        gazeLayer.addSublayer(eyes)
        head.addSublayer(gazeLayer)
        layer?.addSublayer(head)

        if let frozen = Self.frozenPose { setModel(pose: frozen) }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Whoa Stash")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func face(_ part: ChestMark.Part) -> CALayer { partLayers[part]! }
    private var pivots: [CALayer] { [lidPivot, claspPivot] }
    private var revealLayers: [CALayer] { [face(.interior), face(.opening)] }
    private var chestSide: CGFloat { min(bounds.width, bounds.height) }

    /// Sans animations ou en mouvement réduit, rien ne bouge : le couvercle change de pose d'un
    /// coup, les yeux restent au centre et ne clignent pas.
    private var motionAllowed: Bool {
        OverlayAnimation.isEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let side = chestSide
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        head.frame = CGRect(x: bounds.minX, y: bounds.maxY - side, width: side, height: side)
        let pad = ChestBackdrop.padding
        backdrop.frame = head.bounds.insetBy(dx: -pad, dy: -pad)

        let center = CGPoint(x: side / 2, y: side / 2)
        for stage in [lidStage, claspStage] {
            stage.bounds = head.bounds
            stage.position = center
            // Le point de fuite : plus loin que le coffre n'est grand, pour une perspective douce.
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / max(side * 4, 1)
            stage.sublayerTransform = perspective
        }
        let hinge = CGPoint(x: side / 2, y: side * (1 - ChestMark.lidHingeY / 256))
        for pivot in pivots {
            pivot.bounds = head.bounds
            pivot.position = hinge
        }
        for part in [ChestMark.Part.interior, .body, .opening, .lid] {
            face(part).bounds = head.bounds
            face(part).position = center
        }
        // Le fermoir est posé plus bas que dans l'œuvre (`claspDrop`), pour retomber à cheval sur
        // la couture.
        face(.clasp).bounds = head.bounds
        face(.clasp).position = CGPoint(x: center.x, y: center.y - side * ChestMark.claspDrop / 256)

        gazeLayer.frame = ChestMark.eyesFrame(inChestOfSide: side)
        eyes.bounds = gazeLayer.bounds
        eyes.position = CGPoint(x: gazeLayer.bounds.midX, y: gazeLayer.bounds.midY)

        if head.bounds.size != renderedSize || scale != renderedScale {
            renderedSize = head.bounds.size
            renderedScale = scale
            for part in ChestMark.Part.allCases {
                face(part).contentsScale = scale
                face(part).contents = partImages[part].flatMap {
                    ChestMark.rasterize($0, size: head.bounds.size, scale: scale)
                }
            }
            eyes.contentsScale = scale
            eyes.contents = eyesImage.flatMap {
                ChestMark.rasterize($0, size: eyes.bounds.size, scale: scale)
            }
            backdrop.contentsScale = scale
            backdrop.contents = ChestBackdrop.render(
                size: backdrop.bounds.size,
                chestRect: CGRect(x: pad, y: pad, width: side, height: side),
                silhouettes: [partImages[.lid], partImages[.body]].compactMap { $0 },
                scale: scale)
        }
        CATransaction.commit()
    }

    // MARK: - Activité

    /// Vrai panneau déplié sur l'onglet Global : les clignements tournent. Faux, tout revient au
    /// repos — couvercle fermé, yeux au centre.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            startBlinking()
        } else {
            blinkTask?.cancel()
            blinkTask = nil
            look(atCursor: nil, insideNotch: false)
            if Self.frozenPose == nil { move(to: .closed) }
        }
    }

    // MARK: - Regard

    /// Dirige les yeux vers `windowPoint` (repère de la fenêtre), ou les ramène au centre si le
    /// curseur est hors de l'encoche. Ne relance le ressort que si le décalage change vraiment.
    func look(atCursor windowPoint: NSPoint?, insideNotch: Bool) {
        var target = CGVector.zero
        if motionAllowed, insideNotch, let windowPoint, chestSide > 0 {
            let side = chestSide
            let eyesFrame = ChestMark.eyesFrame(inChestOfSide: side)
            let center = CGPoint(x: head.frame.minX + eyesFrame.midX, y: head.frame.minY + eyesFrame.midY)
            target = ChestGaze.offset(
                cursor: convert(windowPoint, from: nil), eyesCenter: center, insideNotch: true,
                limit: ChestGaze.limit(forChestSide: side), reach: side * 3)
        }
        guard hypot(target.dx - gaze.dx, target.dy - gaze.dy) >= 0.05 else { return }
        gaze = target
        gazeLayer.springAnimate(
            keyPath: "transform",
            to: NSValue(caTransform3D: CATransform3DMakeTranslation(target.dx, target.dy, 0)),
            preset: .gentle)
    }

    // MARK: - Clignement

    private func startBlinking() {
        blinkTask?.cancel()
        guard motionAllowed else { return }
        blinkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ChestBlink.interval(unit: .random(in: 0..<1))))
                guard !Task.isCancelled, let self else { return }
                self.blink()
                guard ChestBlink.isDouble(unit: .random(in: 0..<1)) else { continue }
                try? await Task.sleep(for: .seconds(ChestBlink.doubleGap))
                guard !Task.isCancelled else { return }
                self.blink()
            }
        }
    }

    /// Un clignement : les yeux s'écrasent sur leur axe horizontal et reviennent.
    private func blink() {
        let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
        animation.values = [1, ChestBlink.closedScale, 1]
        animation.keyTimes = [0, 0.5, 1]
        animation.duration = ChestBlink.duration
        animation.timingFunctions = [CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .easeOut)]
        eyes.add(animation, forKey: "blink")
    }

    // MARK: - Couvercle

    /// Angle de la charnière pour une ouverture donnée. Négatif : le bord avant se lève vers le regard.
    private func angle(forOpenness openness: Double) -> Double { -openness * Self.maxLidAngle }

    /// Pose, sans animation, le couvercle dans `pose`, et retire ce qui l'animait.
    private func setModel(pose: ChestLidPose) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pivots.forEach {
            $0.removeAnimation(forKey: "lid")
            $0.transform = CATransform3DMakeRotation(CGFloat(angle(forOpenness: pose.openness)), 1, 0, 0)
        }
        revealLayers.forEach { $0.opacity = pose == .closed ? 0 : 1 }
        CATransaction.commit()
    }

    /// Mène le couvercle à `target` au ressort, depuis l'angle où il se trouve à l'instant : un
    /// changement de pose en cours de route n'a pas de saut.
    private func move(to target: ChestLidPose) {
        guard target != pose, chestSide > 0 else { return }
        pose = target
        guard motionAllowed else {
            setModel(pose: target)
            return
        }
        let current = (lidPivot.presentation() ?? lidPivot).value(forKeyPath: "transform.rotation.x") as? Double ?? 0
        let goal = angle(forOpenness: target.openness)
        // Ce que le couvercle révèle apparaît d'un coup dès qu'il bouge, et ne disparaît qu'une
        // fois refermé : un fondu laisserait voir le fond de la tuile entre le couvercle et le corps.
        if target != .closed { revealLayers.forEach { $0.opacity = 1 } }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pose == .closed else { return }
                self.revealLayers.forEach { $0.opacity = 0 }
            }
        }
        for pivot in pivots {
            let spring = CASpringAnimation(keyPath: "transform.rotation.x")
            spring.mass = 1
            spring.stiffness = Self.lidStiffness
            spring.damping = target == .closed ? Self.closingDamping : Self.openingDamping
            spring.fromValue = current
            spring.toValue = goal
            spring.duration = spring.settlingDuration
            pivot.transform = CATransform3DMakeRotation(CGFloat(goal), 1, 0, 0)
            pivot.add(spring, forKey: "lid")
        }
        CATransaction.commit()
    }

    // MARK: - Souris

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard isActive, Self.frozenPose == nil else { return }
        move(to: pose.afterEntering())
    }

    override func mouseExited(with event: NSEvent) {
        guard Self.frozenPose == nil else { return }
        move(to: pose.afterExiting())
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { press() }

    override func accessibilityPerformPress() -> Bool {
        press()
        return true
    }

    private func press() {
        guard isActive, Self.frozenPose == nil else { return }
        move(to: pose.afterClick())
    }
}
