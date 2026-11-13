import AppKit
import SwiftTerm

/// La vue du terminal, habillée pour l'encoche : fond transparent (le verre et la carte de
/// `TerminalTabView` passent derrière), curseur barre aux couleurs de l'accent, sélection
/// teintée, et trois rappels dont l'onglet a besoin (focus, position de défilement, zoom).
///
/// Elle ne touche ni au PTY ni au shell : seul l'habillage et ce qu'elle remonte à l'onglet.
final class TerminalSurface: LocalProcessTerminalView {

  static let defaultFontSize: CGFloat = 12
  private static let fontSizeRange: ClosedRange<CGFloat> = 9...18

  /// Position de défilement (0…1, 1 = tout en bas) et vrai si l'utilisateur a défilé à la main.
  var onScrollChanged: ((Double, Bool) -> Void)?

  /// Vrai dès qu'une molette a défilé le terminal ; repasse à faux une fois revenu en bas.
  /// Sans lui, « 0 » (haut de l'historique) ne se distingue pas de « pas d'historique ».
  private var scrolledByUser = false
  private(set) var fontSize = TerminalSurface.defaultFontSize

  override init(frame: CGRect) {
    var options = TerminalOptions.default
    options.cursorStyle = .steadyBar
    super.init(
      frame: frame,
      font: NSFont.monospacedSystemFont(
        ofSize: TerminalSurface.defaultFontSize, weight: .regular),
      options: options)
    nativeForegroundColor = NSColor(white: 0.92, alpha: 1)
    nativeBackgroundColor = NSColor(white: 0.06, alpha: 1)
    // Fond de la cellule par défaut transparent : la bande qui reste sous la dernière ligne
    // (le cadre n'est pas un multiple de la hauteur de cellule) prend ainsi la couleur de la
    // carte, au lieu d'un aplat noir qui la dénoncerait.
    backgroundOpacity = 0
    applyAccent()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Curseur et sélection suivent l'accent choisi dans les Préférences.
  func applyAccent() {
    let accent = NSColor(cgColor: OverlayPalette.accent.cgColor(for: effectiveAppearance)) ?? .systemGreen
    caretColor = accent
    caretTextColor = NSColor(white: 0.06, alpha: 1)
    selectedTextBackgroundColor = accent.withAlphaComponent(0.35)
  }

  // MARK: - Rappels vers l'onglet

  override func scrolled(source: TerminalView, position: Double) {
    super.scrolled(source: source, position: position)
    // Un haut d'historique atteint d'un bond (0) ne se distingue pas de « pas d'historique » :
    // seule une position intermédiaire prouve que l'utilisateur a remonté.
    if position >= 0.999 {
      scrolledByUser = false
    } else if position > 0 {
      scrolledByUser = true
    }
    onScrollChanged?(position, scrolledByUser)
  }

  /// Revient tout en bas de l'historique.
  func scrollToBottom() {
    scrolledByUser = false
    scrollTo(row: Int.max)
    onScrollChanged?(1, false)
  }

  // MARK: - Taille de police

  /// ⌘+ ⌘− ⌘0, relayés par l'onglet (la vue de SwiftTerm n'est pas ouverte à la surcharge).
  func handleZoomShortcut(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift) == .command,
      let key = event.charactersIgnoringModifiers
    else { return false }
    switch key {
    case "+", "=": setFontSize(fontSize + 1)
    case "-": setFontSize(fontSize - 1)
    case "0": setFontSize(Self.defaultFontSize)
    default: return false
    }
    return true
  }

  private func setFontSize(_ size: CGFloat) {
    let clamped = min(max(size, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
    guard clamped != fontSize else { return }
    fontSize = clamped
    font = NSFont.monospacedSystemFont(ofSize: clamped, weight: .regular)
  }
}
