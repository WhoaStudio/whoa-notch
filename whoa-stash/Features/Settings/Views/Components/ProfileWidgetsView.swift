import AppKit

/// Les widgets d'un profil : un bouton d'ajout par type du registre, puis la liste des widgets déjà
/// posés, que l'on retire un à un. Agit sur le profil choisi, actif ou non.
@MainActor
final class ProfileWidgetsView: NSStackView {

  var onAdd: ((String) -> Void)?
  var onRemove: ((String) -> Void)?
  private let addRow = NSStackView()
  private let placedStack = NSStackView()
  private var addButtons: [NSButton] = []

  init() {
    super.init(frame: .zero)
    orientation = .vertical
    alignment = .leading
    spacing = 8
    addRow.orientation = .horizontal
    addRow.spacing = 8
    for kind in DockWidgetRegistry.all {
      let button = NSButton(
        image: NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil) ?? NSImage(),
        target: self, action: #selector(addTapped(_:)))
      button.title = "Add \(kind.title)"
      button.imagePosition = .imageLeading
      button.bezelStyle = .rounded
      button.identifier = NSUserInterfaceItemIdentifier(kind.id)
      addRow.addArrangedSubview(button)
      addButtons.append(button)
    }
    placedStack.orientation = .vertical
    placedStack.alignment = .leading
    placedStack.spacing = 6
    addArrangedSubview(addRow)
    addArrangedSubview(placedStack)
  }

  @available(*, unavailable) required init(coder: NSCoder) { fatalError() }

  func setEnabled(_ enabled: Bool) { addButtons.forEach { $0.isEnabled = enabled } }

  func apply(_ widgets: [DockWidgetPlacement]) {
    placedStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for placement in widgets {
      guard let kind = DockWidgetRegistry.kind(for: placement.kind) else { continue }
      let icon = NSImageView(
        image: NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil) ?? NSImage())
      let remove = NSButton(
        image: NSImage(
          systemSymbolName: "minus.circle", accessibilityDescription: "Remove \(kind.title)")
          ?? NSImage(),
        target: self, action: #selector(removeTapped(_:)))
      remove.isBordered = false
      remove.identifier = NSUserInterfaceItemIdentifier(placement.id)
      let row = NSStackView(views: [icon, NSTextField(labelWithString: kind.title), remove])
      row.spacing = 8
      placedStack.addArrangedSubview(row)
    }
  }

  @objc private func addTapped(_ sender: NSButton) {
    guard let id = sender.identifier?.rawValue else { return }
    onAdd?(id)
  }

  @objc private func removeTapped(_ sender: NSButton) {
    guard let id = sender.identifier?.rawValue else { return }
    onRemove?(id)
  }
}
