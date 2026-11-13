import AppKit
import Combine

/// Écran « Mail » : le compte IMAP dont les nouveaux messages s'affichent dans l'encoche.
final class MailSettingsViewController: SettingsSectionViewController, NSTextFieldDelegate {

  private let viewModel = MailSettingsViewModel()
  private var cancellables: Set<AnyCancellable> = []

  private lazy var enabledCheckbox = NSButton.settingsCheckbox(
    "Show new mail in the notch", target: self, action: #selector(enabledChanged))
  private let providerPopUp = SettingsKeyPopUp()
  private let providerHintLabel = NSTextField(wrappingLabelWithString: "")
  private let hostField = NSTextField()
  private let portField = NSTextField()
  private let usernameField = NSTextField()
  private let passwordField = NSSecureTextField()
  private let saveButton = NSButton(title: "Save", target: nil, action: nil)
  private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
  private let testButton = NSButton(title: "Test connection", target: nil, action: nil)
  private let passwordStateLabel = NSTextField(labelWithString: "")
  private let statusLabel = NSTextField(labelWithString: "")

  override func makeRows() -> [NSView] {
    providerPopUp.target = self
    providerPopUp.action = #selector(providerChanged)
    MailProvider.allCases.forEach { providerPopUp.addItem(withTitle: $0.displayName) }
    providerHintLabel.font = .systemFont(ofSize: 11)
    providerHintLabel.textColor = .secondaryLabelColor
    providerHintLabel.preferredMaxLayoutWidth = SettingsMetrics.captionMaxWidth

    configure(hostField, placeholder: "imap.example.com", width: 250)
    configure(portField, placeholder: "993", width: 70)
    configure(usernameField, placeholder: "you@example.com", width: 250)
    configure(passwordField, placeholder: "Password or app password", width: 250)
    passwordField.delegate = nil

    for (button, action) in [
      (saveButton, #selector(saveTapped)), (removeButton, #selector(removeTapped)),
      (testButton, #selector(testTapped)),
    ] {
      button.target = self
      button.action = action
      button.bezelStyle = .rounded
    }
    let passwordButtons = NSStackView(views: [saveButton, removeButton])
    passwordButtons.spacing = 8

    passwordStateLabel.font = .systemFont(ofSize: 11)
    passwordStateLabel.textColor = .secondaryLabelColor
    statusLabel.font = .systemFont(ofSize: 11)
    statusLabel.preferredMaxLayoutWidth = SettingsMetrics.captionMaxWidth
    let testStack = makeSettingsControlStack([testButton, statusLabel])

    return [
      SettingsFormRowView(
        title: "IMAP", control: enabledCheckbox,
        caption:
          "Whoa Notch connects straight to your mail server over TLS and waits for new messages (IMAP IDLE). Nothing goes through another server. Messages are only read, never marked as read, and nothing is stored."
      ),
      SettingsFormRowView(
        title: "Provider", control: makeSettingsControlStack([providerPopUp, providerHintLabel]),
        alignsTop: true),
      SettingsFormRowView(title: "Server", control: hostField),
      SettingsFormRowView(title: "Port", control: portField),
      SettingsFormRowView(title: "User name", control: usernameField),
      SettingsFormRowView(
        title: "Password",
        control: makeSettingsControlStack([passwordField, passwordButtons, passwordStateLabel]),
        caption:
          "Kept in the Keychain. Changing the server or user name needs the password again."),
      makeSettingsDivider(),
      SettingsFormRowView(title: "Check", control: testStack),
    ]
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    viewModel.$settings.sink { [weak self] in self?.apply($0) }.store(in: &cancellables)
    viewModel.$hasPassword.sink { [weak self] saved in
      self?.passwordStateLabel.stringValue = saved ? "A password is saved." : "No password saved."
      self?.removeButton.isEnabled = saved
    }.store(in: &cancellables)
    viewModel.$status.combineLatest(viewModel.$statusIsError).sink { [weak self] text, isError in
      self?.statusLabel.stringValue = text
      self?.statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }.store(in: &cancellables)
    viewModel.$isTesting.sink { [weak self] in self?.testButton.isEnabled = !$0 }.store(
      in: &cancellables)
  }

  private func configure(_ field: NSTextField, placeholder: String, width: CGFloat) {
    field.placeholderString = placeholder
    field.translatesAutoresizingMaskIntoConstraints = false
    field.widthAnchor.constraint(equalToConstant: width).isActive = true
    if field !== passwordField { field.delegate = self }
  }

  private func apply(_ settings: MailSettings) {
    enabledCheckbox.state = settings.imapEnabled ? .on : .off
    providerPopUp.selectItem(at: MailProvider.allCases.firstIndex(of: settings.provider) ?? 0)
    providerHintLabel.stringValue = settings.provider.passwordHint
    // Un préset fixe serveur et port ; seul « Other » les laisse saisir.
    let isCustom = settings.provider.preset == nil
    hostField.isEnabled = isCustom
    portField.isEnabled = isCustom
    if hostField.currentEditor() == nil { hostField.stringValue = settings.host }
    if portField.currentEditor() == nil { portField.stringValue = String(settings.port) }
    if usernameField.currentEditor() == nil { usernameField.stringValue = settings.username }
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    commitFields()
  }

  private func commitFields() {
    let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
    let username = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
    let port = Int(portField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 993
    viewModel.update {
      $0.host = host
      $0.username = username
      $0.port = port
    }
  }

  @objc private func providerChanged() {
    let provider = MailProvider.allCases[max(0, providerPopUp.indexOfSelectedItem)]
    viewModel.update {
      $0.provider = provider
      if let preset = provider.preset {
        $0.host = preset.host
        $0.port = preset.port
      }
    }
  }

  @objc private func enabledChanged() {
    commitFields()
    viewModel.update { $0.imapEnabled = enabledCheckbox.state == .on }
  }

  @objc private func saveTapped() {
    commitFields()
    guard !passwordField.stringValue.isEmpty else { return }
    viewModel.savePassword(passwordField.stringValue)
    passwordField.stringValue = ""
  }

  @objc private func removeTapped() {
    viewModel.removePassword()
  }

  @objc private func testTapped() {
    commitFields()
    viewModel.testConnection(typedPassword: passwordField.stringValue)
  }
}
