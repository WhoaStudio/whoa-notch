import AppKit
import Combine

/// Écran "Screens" : sur quels écrans le dock apparaît, et les écrans branchés, cochables un à un.
/// Ne contient aucune logique — tout transite par `ScreensSettingsViewModel`.
final class ScreensSettingsViewController: SettingsSectionViewController {

  private let viewModel = ScreensSettingsViewModel()
  private var cancellable: AnyCancellable?
  private var screensObserver: NSObjectProtocol?

  private let modeControl = NSSegmentedControl(
    labels: DockScreenMode.allCases.map(\.displayName), trackingMode: .selectOne, target: nil,
    action: nil)
  private let displaysBox = NSStackView()
  private let identifyButton = NSButton(title: "Identify Displays", target: nil, action: nil)

  override func makeSections() -> [NSView] {
    modeControl.target = self
    modeControl.action = #selector(modeChanged)
    displaysBox.orientation = .vertical
    displaysBox.alignment = .leading
    displaysBox.spacing = SettingsMetrics.rowSpacing
    identifyButton.bezelStyle = .rounded
    identifyButton.target = self
    identifyButton.action = #selector(identifyTapped)

    return [
      SettingsGroupView(rows: [
        SettingsFormRowView(
          title: "Show dock on", control: modeControl,
          caption:
            "One: the first ticked display. Attached: ticked displays, following the cursor. All: a fixed dock on each ticked display."
        )
      ]),
      displaysBox,
      SettingsGroupView(rows: [
        SettingsFormRowView(
          title: "Identify", control: identifyButton,
          caption: "Briefly shows each display's number on its screen")
      ]),
    ]
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    cancellable = viewModel.$dock.sink { [weak self] in self?.apply($0) }
  }

  /// Écoute les branchements le temps que l'écran est visible : la liste des écrans suit la réalité.
  override func viewWillAppear() {
    super.viewWillAppear()
    screensObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.reloadDisplays(self?.viewModel.dock ?? DockSettings()) }
    }
  }

  override func viewDidDisappear() {
    super.viewDidDisappear()
    if let screensObserver { NotificationCenter.default.removeObserver(screensObserver) }
    screensObserver = nil
  }

  private func apply(_ dock: DockSettings) {
    if let index = DockScreenMode.allCases.firstIndex(of: dock.screenMode) {
      modeControl.selectedSegment = index
    }
    reloadDisplays(dock)
  }

  /// Reconstruit la liste des écrans branchés (appelée aussi quand un écran arrive ou part).
  private func reloadDisplays(_ dock: DockSettings) {
    displaysBox.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let rows = NSScreen.screens.map { makeDisplayRow($0, dock: dock) }
    guard !rows.isEmpty else { return }
    let group = SettingsGroupView(
      title: "Displays", rows: rows,
      footer: "If none is ticked, the dock stays hidden.")
    displaysBox.addArrangedSubview(group)
    group.widthAnchor.constraint(equalTo: displaysBox.widthAnchor).isActive = true
  }

  private func makeDisplayRow(_ screen: NSScreen, dock: DockSettings) -> SettingsFormRowView {
    let attached = NSButton(
      checkboxWithTitle: "Attached", target: self, action: #selector(attachedTapped(_:)))
    let uuid = screen.displayUUID
    attached.identifier = NSUserInterfaceItemIdentifier(uuid ?? "")
    attached.isEnabled = uuid != nil
    attached.state = uuid.map { dock.detachedDisplays.contains($0) ? .off : .on } ?? .on
    let kind =
      screen.displayID.map { CGDisplayIsBuiltin($0) != 0 } == true ? "Built-in" : "External"
    return SettingsFormRowView(
      title: screen.localizedName, control: attached, caption: "\(kind) · Connected")
  }

  @objc private func modeChanged() {
    let index = modeControl.selectedSegment
    guard DockScreenMode.allCases.indices.contains(index) else { return }
    viewModel.setScreenMode(DockScreenMode.allCases[index])
  }

  @objc private func attachedTapped(_ sender: NSButton) {
    guard let uuid = sender.identifier?.rawValue, !uuid.isEmpty else { return }
    viewModel.setDisplay(uuid: uuid, attached: sender.state == .on)
  }

  /// Affiche le numéro de chaque écran pendant deux secondes, sur l'écran lui-même.
  @objc private func identifyTapped() {
    let windows = NSScreen.screens.enumerated().map { index, screen -> NSWindow in
      let size = NSSize(width: 160, height: 160)
      let frame = NSRect(
        x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
        width: size.width, height: size.height)
      let window = NSWindow(
        contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.level = .statusBar
      window.isOpaque = false
      window.backgroundColor = .clear
      window.ignoresMouseEvents = true

      let badge = NSTextField(labelWithString: "\(index + 1)")
      badge.font = .systemFont(ofSize: 88, weight: .bold)
      badge.textColor = .white
      badge.alignment = .center
      badge.frame = NSRect(origin: .zero, size: size)
      badge.wantsLayer = true
      badge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
      badge.layer?.cornerRadius = 24
      window.contentView = badge
      window.orderFrontRegardless()
      return window
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      windows.forEach { $0.orderOut(nil) }
    }
  }
}
