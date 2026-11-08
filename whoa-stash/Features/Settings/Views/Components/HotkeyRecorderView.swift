import AppKit
import Carbon.HIToolbox

/// Une tuile du sélecteur : un modificateur (⇧ ⌃ ⌥ ⌘, allumé ou éteint) ou la touche (grande
/// lettre au centre). Dessinée à la main : cinq rectangles arrondis, pas de contrôle standard.
private final class HotkeyTileView: NSView {

  enum Kind {
    case modifier(symbol: String, label: String)
    case key
  }

  let kind: Kind
  var isOn = false { didSet { needsDisplay = true } }
  var keyText = "" { didSet { needsDisplay = true } }
  var isRecording = false { didSet { needsDisplay = true } }
  var onClick: (() -> Void)?

  init(kind: Kind) {
    self.kind = kind
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: 72),
      heightAnchor.constraint(equalToConstant: 56),
    ])
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  override var isFlipped: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { onClick?() }

  override func draw(_ dirtyRect: NSRect) {
    let active: Bool
    switch kind {
    case .modifier: active = isOn
    case .key: active = isRecording || !keyText.isEmpty
    }
    let fill = NSColor.white.withAlphaComponent(active ? 0.16 : 0.05)
    fill.setFill()
    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
    path.fill()
    NSColor.white.withAlphaComponent(isRecording ? 0.5 : 0.1).setStroke()
    path.lineWidth = 1
    path.stroke()

    let color = active ? NSColor.white : NSColor.white.withAlphaComponent(0.35)
    switch kind {
    case .modifier(let symbol, let label):
      draw(
        symbol, font: .systemFont(ofSize: 17, weight: .regular), color: color,
        at: NSPoint(x: 12, y: 8))
      draw(
        label, font: .systemFont(ofSize: 13, weight: .medium), color: color,
        at: NSPoint(x: 12, y: bounds.height - 12 - 16))
    case .key:
      let text = isRecording ? "…" : (keyText.isEmpty ? "—" : keyText)
      let font = NSFont.systemFont(ofSize: keyText.count > 2 ? 14 : 22, weight: .semibold)
      let size = (text as NSString).size(withAttributes: [.font: font])
      draw(
        text, font: font, color: color,
        at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
  }

  private func draw(_ text: String, font: NSFont, color: NSColor, at point: NSPoint) {
    (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
  }
}

/// Sélecteur de raccourci : quatre tuiles de modificateurs qu'on allume d'un clic, et une tuile
/// de touche qui enregistre la prochaine frappe. Échap annule, Retour arrière efface la touche.
final class HotkeyRecorderView: NSView {

  var onChange: ((DockHotkey) -> Void)?

  private(set) var hotkey = DockHotkey()
  private let tiles: [HotkeyTileView]
  private let keyTile = HotkeyTileView(kind: .key)
  private var isRecording = false { didSet { keyTile.isRecording = isRecording } }

  private static let modifiers: [(mask: Int, symbol: String, label: String)] = [
    (shiftKey, "⇧", "shift"), (controlKey, "⌃", "ctrl"), (optionKey, "⌥", "opt"),
    (cmdKey, "⌘", "cmd"),
  ]

  init() {
    tiles = Self.modifiers.map {
      HotkeyTileView(kind: .modifier(symbol: $0.symbol, label: $0.label))
    }
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.cornerRadius = 18
    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

    for (index, tile) in tiles.enumerated() {
      tile.onClick = { [weak self] in self?.toggleModifier(at: index) }
    }
    keyTile.onClick = { [weak self] in self?.startRecording() }

    let stack = NSStackView(views: tiles + [keyTile])
    stack.orientation = .horizontal
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
    ])
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  func setHotkey(_ value: DockHotkey) {
    hotkey = value
    for (index, tile) in tiles.enumerated() {
      tile.isOn = value.modifiers & UInt32(Self.modifiers[index].mask) != 0
    }
    keyTile.keyText = value.keyCode == nil ? "" : value.keyLabel
  }

  private func commit(_ value: DockHotkey) {
    setHotkey(value)
    onChange?(value)
  }

  private func toggleModifier(at index: Int) {
    var value = hotkey
    value.modifiers ^= UInt32(Self.modifiers[index].mask)
    commit(value)
  }

  // MARK: - Enregistrement de la touche

  private func startRecording() {
    isRecording = true
    window?.makeFirstResponder(self)
  }

  override var acceptsFirstResponder: Bool { true }

  override func resignFirstResponder() -> Bool {
    isRecording = false
    return super.resignFirstResponder()
  }

  /// ⌘K et consorts passeraient sinon au menu de l'app avant d'arriver à `keyDown`.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isRecording else { return super.performKeyEquivalent(with: event) }
    keyDown(with: event)
    return true
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else { return super.keyDown(with: event) }
    defer { isRecording = false }
    switch Int(event.keyCode) {
    case kVK_Escape:
      return
    case kVK_Delete, kVK_ForwardDelete:
      var value = hotkey
      value.keyCode = nil
      value.keyLabel = ""
      commit(value)
    default:
      var value = hotkey
      value.keyCode = UInt32(event.keyCode)
      value.keyLabel = Self.label(for: event)
      // Les modificateurs tenus pendant la frappe s'ajoutent à ceux déjà allumés.
      value.modifiers |= Self.carbonModifiers(event.modifierFlags)
      commit(value)
    }
  }

  static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var mask = 0
    if flags.contains(.shift) { mask |= shiftKey }
    if flags.contains(.control) { mask |= controlKey }
    if flags.contains(.option) { mask |= optionKey }
    if flags.contains(.command) { mask |= cmdKey }
    return UInt32(mask)
  }

  private static func label(for event: NSEvent) -> String {
    switch Int(event.keyCode) {
    case kVK_Space: return "Space"
    case kVK_Return: return "↩"
    case kVK_Tab: return "⇥"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
  }
}
