import AppKit
import Combine

/// Écran « Privacy & Permissions » : une ligne par autorisation réellement utilisée, avec son état
/// (Allowed, ou un bouton Allow… / Open Settings…). Ne contient aucune logique — tout transite par
/// `PrivacySettingsViewModel`.
final class PrivacySettingsViewController: SettingsSectionViewController {

  private let viewModel = PrivacySettingsViewModel()
  private var cancellable: AnyCancellable?
  private var activationObserver: NSObjectProtocol?
  private var statusControls: [PrivacyPermission: PermissionStatusControl] = [:]

  override func makeSections() -> [NSView] {
    let rows = PrivacyPermission.allCases.map { permission -> SettingsFormRowView in
      let control = PermissionStatusControl { [weak self] in self?.viewModel.act(on: permission) }
      statusControls[permission] = control
      return SettingsFormRowView(
        title: permission.title, control: control, caption: permission.caption)
    }
    return [
      SettingsGroupView(
        title: "Permissions", rows: rows,
        footer:
          "Whoa Stash only asks for a permission when a feature needs it. Allowed means macOS has granted it."
      )
    ]
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    cancellable = viewModel.$states.sink { [weak self] _ in self?.applyStates() }
  }

  /// Relit les états à chaque retour dans l'app : l'utilisateur vient peut-être de les changer dans Réglages système.
  override func viewWillAppear() {
    super.viewWillAppear()
    viewModel.refresh()
    activationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.viewModel.refresh() }
    }
  }

  override func viewDidDisappear() {
    super.viewDidDisappear()
    if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    activationObserver = nil
  }

  private func applyStates() {
    for (permission, control) in statusControls {
      control.apply(viewModel.state(for: permission))
    }
  }
}

/// Affiche l'état d'une autorisation : « Allowed » en vert avec une coche, sinon un bouton d'action.
private final class PermissionStatusControl: NSStackView {

  private let checkmark = NSImageView()
  private let allowedLabel = NSTextField(labelWithString: "Allowed")
  private let actionButton = NSButton(title: "", target: nil, action: nil)
  private let onAction: () -> Void

  init(onAction: @escaping () -> Void) {
    self.onAction = onAction
    super.init(frame: .zero)
    orientation = .horizontal
    spacing = 6

    checkmark.image = NSImage(
      systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Allowed")
    checkmark.contentTintColor = .systemGreen
    allowedLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    allowedLabel.textColor = .systemGreen

    actionButton.bezelStyle = .rounded
    actionButton.target = self
    actionButton.action = #selector(actionTapped)

    addArrangedSubview(checkmark)
    addArrangedSubview(allowedLabel)
    addArrangedSubview(actionButton)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ state: PermissionState) {
    let allowed = state == .allowed
    let changed = checkmark.isHidden == allowed
    checkmark.isHidden = !allowed
    allowedLabel.isHidden = !allowed
    actionButton.isHidden = allowed
    switch state {
    case .notDetermined: actionButton.title = "Allow…"
    case .denied: actionButton.title = "Open Settings…"
    case .unknown: actionButton.title = "Review…"
    case .allowed: break
    }
    if changed, window != nil {
      for view in [checkmark, allowedLabel, actionButton] as [NSView] where !view.isHidden {
        view.wantsLayer = true
        view.layer?.springReveal(y: -4)
      }
    }
  }

  @objc private func actionTapped() {
    onAction()
  }
}
