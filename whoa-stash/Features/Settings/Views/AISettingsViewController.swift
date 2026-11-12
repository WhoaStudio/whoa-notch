import AppKit
import Combine

/// Écran "AI" : les hooks Claude Code (installation globale en un clic) et la veille de Claude Desktop.
final class AISettingsViewController: SettingsSectionViewController {

  private let viewModel = AISettingsViewModel()
  private var cancellables: Set<AnyCancellable> = []

  private let statusLabel = NSTextField(labelWithString: "")
  private let errorLabel = NSTextField(labelWithString: "")
  private let installButton = NSButton(title: "Install hooks", target: nil, action: nil)
  private let uninstallButton = NSButton(title: "Uninstall", target: nil, action: nil)
  private lazy var desktopCheckbox = NSButton.settingsCheckbox(
    "Notify when a chat reply is ready", target: self, action: #selector(desktopChanged))
  private lazy var stopReplyCheckbox = NSButton.settingsCheckbox(
    "Offer a reply when a session finishes", target: self, action: #selector(stopReplyChanged))

  override func makeRows() -> [NSView] {
    installButton.target = self
    installButton.action = #selector(installTapped)
    uninstallButton.target = self
    uninstallButton.action = #selector(uninstallTapped)
    for button in [installButton, uninstallButton] { button.bezelStyle = .rounded }
    let buttons = NSStackView(views: [installButton, uninstallButton])
    buttons.spacing = 8

    statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
    errorLabel.font = .systemFont(ofSize: 11)
    errorLabel.textColor = .systemRed
    errorLabel.isHidden = true
    errorLabel.preferredMaxLayoutWidth = SettingsMetrics.captionMaxWidth

    return [
      SettingsFormRowView(
        title: "Claude Code",
        control: makeSettingsControlStack([statusLabel, buttons, errorLabel]),
        caption:
          "Shows a notch notification when a session finishes or needs input, and lets you allow, answer questions, approve plans and fill MCP forms from the notch. Applies to every project. Reinstall the hooks after an update."
      ),
      SettingsFormRowView(
        title: "Replies", control: stopReplyCheckbox,
        caption:
          "Off by default. When a turn ends, the notch offers a reply field for about 25 seconds; what you type goes back to Claude, which carries on. The session waits that long before it finishes."
      ),
      SettingsFormRowView(title: "Hook script", control: makePathLabel(viewModel.scriptPath)),
      SettingsFormRowView(title: "Settings file", control: makePathLabel(viewModel.settingsPath)),
      makeSettingsDivider(),
      SettingsFormRowView(
        title: "Claude Desktop", control: desktopCheckbox,
        caption:
          "Experimental. Claude Desktop has no hooks. When you leave it while it is writing, Whoa Stash checks once a second, through Accessibility, whether its Stop button is still there. Nothing of the chat is read."
      ),
    ]
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    viewModel.$hookStatus.sink { [weak self] in self?.apply(status: $0) }.store(in: &cancellables)
    viewModel.$errorMessage.sink { [weak self] in
      guard let self else { return }
      let message = $0 ?? ""
      let changed = errorLabel.stringValue != message
      errorLabel.stringValue = message
      errorLabel.isHidden = $0 == nil
      if changed, !errorLabel.isHidden, errorLabel.window != nil {
        errorLabel.wantsLayer = true
        errorLabel.layer?.springReveal(y: -4)
      }
    }.store(in: &cancellables)
    viewModel.$settings.sink { [weak self] in
      self?.desktopCheckbox.state = $0.desktopWatcherEnabled ? .on : .off
      self?.stopReplyCheckbox.state = $0.stopReplyEnabled ? .on : .off
    }.store(in: &cancellables)
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    viewModel.refresh()
  }

  private func makePathLabel(_ path: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: (path as NSString).abbreviatingWithTildeInPath)
    label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    label.textColor = .secondaryLabelColor
    label.isSelectable = true
    label.preferredMaxLayoutWidth = SettingsMetrics.captionMaxWidth
    return label
  }

  private func apply(status: ClaudeHookInstaller.Status) {
    statusLabel.stringValue = status.text
    statusLabel.textColor = status == .installed ? .systemGreen : .secondaryLabelColor
    uninstallButton.isEnabled = status != .notInstalled
  }

  @objc private func installTapped() { viewModel.installHooks() }

  @objc private func uninstallTapped() { viewModel.uninstallHooks() }

  @objc private func stopReplyChanged() {
    viewModel.setStopReplyEnabled(stopReplyCheckbox.state == .on)
  }

  @objc private func desktopChanged() {
    let enabled = desktopCheckbox.state == .on
    viewModel.setDesktopWatcherEnabled(enabled)
    if enabled && !AccessibilityPermissionService.shared.isTrusted {
      AccessibilityPermissionService.shared.requestAccess()
    }
  }
}
