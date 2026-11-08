import AppKit

/// L'onglet Terminal : un cadre qui accueille la vue de la `TerminalSession`.
///
/// La vue du terminal n'a qu'un parent à la fois ; chaque fenêtre du panneau a son cadre, et
/// c'est celui de la fenêtre qui se déplie qui la reçoit (voir `attach(_:)`).
final class TerminalTabView: NSView {

  private weak var terminalView: NSView?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.masksToBounds = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Prend la vue du terminal et démarre le shell s'il ne tourne pas.
  func attach(_ session: TerminalSession) {
    let view = session.view
    if view.superview !== self {
      view.removeFromSuperview()
      addSubview(view)
    }
    terminalView = view
    view.frame = bounds
    session.startIfNeeded()
  }

  /// Donne le clavier à la vue du terminal. Faux si elle n'est pas (encore) dans une fenêtre.
  @discardableResult
  func focusTerminal() -> Bool {
    guard let terminalView, let window = terminalView.window else { return false }
    return window.makeFirstResponder(terminalView)
  }

  override func layout() {
    super.layout()
    if let terminalView, terminalView.superview === self { terminalView.frame = bounds }
  }
}
