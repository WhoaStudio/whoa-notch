import AppKit

/// Écran "About" : icône, nom, accroche, version, boutons d'action et crédits — une mise en page
/// centrée, sans l'en-tête commun.
final class AboutSettingsViewController: SettingsSectionViewController {

  private static let githubURL = URL(string: "https://github.com/WhoaStudio/whoa-notch")!
  private static let websiteURL = URL(string: "https://whoastudio.dev")!

  override var showsHeader: Bool { false }

  override func makeSections() -> [NSView] {
    let iconView = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
    iconView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 110),
      iconView.heightAnchor.constraint(equalToConstant: 110),
    ])

    let nameLabel = Self.label("Whoa Notch", size: 30, weight: .bold, color: .labelColor)
    let taglineLabel = Self.label(
      "Controls and glanceable info on the edges of your screen.", size: 15,
      color: .secondaryLabelColor)
    let versionLabel = Self.label(
      "Version \(Self.versionString)", size: 13, color: .secondaryLabelColor)

    let buttons = NSStackView(views: [
      Self.button("Show Onboarding", self, #selector(showOnboarding)),
      Self.button("GitHub", self, #selector(openGitHub)),
      Self.button("Website", self, #selector(openWebsite)),
    ])
    buttons.orientation = .horizontal
    buttons.spacing = 12

    let rule = makeSettingsDivider()
    let credits = Self.label(
      "Sound effect by Universfield from Pixabay.\nNow Playing through mediaremote-adapter. Terminal by SwiftTerm.\n© 2026 Ugolin O. and WhoaStudio. MIT license.",
      size: 12, color: .secondaryLabelColor)

    let column = NSStackView(views: [
      iconView, nameLabel, taglineLabel, versionLabel, buttons, rule, credits,
    ])
    column.orientation = .vertical
    column.alignment = .centerX
    column.spacing = 12
    column.setCustomSpacing(22, after: iconView)
    column.setCustomSpacing(22, after: versionLabel)
    column.setCustomSpacing(28, after: buttons)
    column.setCustomSpacing(20, after: rule)
    rule.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
    credits.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
    return [column]
  }

  private static func label(
    _ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor
  ) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.alignment = .center
    label.isSelectable = false
    return label
  }

  private static func button(_ title: String, _ target: AnyObject, _ action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .rounded
    button.controlSize = .large
    return button
  }

  private static var versionString: String {
    let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "\(short) (\(build))"
  }

  @objc private func showOnboarding() {
    SettingsWindowController.shared.onReplayOnboarding?()
  }

  @objc private func openGitHub() {
    NSWorkspace.shared.open(Self.githubURL)
  }

  @objc private func openWebsite() {
    NSWorkspace.shared.open(Self.websiteURL)
  }
}
