import AppKit

/// Interrupteur en pastille façon iOS : bleu allumé, gris clair éteint, pastille blanche qui glisse.
final class SettingsSwitch: NSControl {

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            updateLayers(animated: window != nil)
        }
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.4 }
    }

    private let track = CALayer()
    private let knob = CALayer()
    private let size = NSSize(width: 38, height: 22)

    override var intrinsicContentSize: NSSize { size }
    override var acceptsFirstResponder: Bool { false }

    init() {
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.addSublayer(track)
        layer?.addSublayer(knob)
        knob.backgroundColor = NSColor.white.cgColor
        knob.shadowColor = NSColor.black.cgColor
        knob.shadowOpacity = 0.25
        knob.shadowRadius = 1.5
        knob.shadowOffset = CGSize(width: 0, height: -1)
        setAccessibilityRole(.checkBox)
        updateLayers(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas pris en charge") }

    override func layout() {
        super.layout()
        updateLayers(animated: false)
    }

    private func updateLayers(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.18)
        track.frame = bounds
        track.cornerRadius = bounds.height / 2
        track.backgroundColor = (isOn ? NSColor.systemBlue : NSColor(white: 0.78, alpha: 1)).cgColor
        let d = bounds.height - 4
        knob.cornerRadius = d / 2
        knob.frame = CGRect(x: isOn ? bounds.width - d - 2 : 2, y: 2, width: d, height: d)
        CATransaction.commit()
        setAccessibilityValue(isOn ? 1 : 0)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isOn.toggle()
        sendAction(action, to: target)
    }
}
