import AppKit

/// Page Servers : les processus lancés depuis les actions, avec leur état, et de quoi les arrêter,
/// les relancer ou les oublier.
/// Page Servers : ce qui tourne. D'abord les processus lancés depuis les actions, avec leur état et de
/// quoi les arrêter, les relancer ou les oublier ; puis, en lecture seule, les serveurs de
/// développement à l'écoute sur un port, groupés par projet.
final class NotchServersPageView: NSView, NotchAnalyticsPage {

  var pageTitle: String { "Servers" }
  var pageSymbol: String { "server.rack" }
  var pageView: NSView { self }

  var commands = DevServersCommands()

  private let list = NotchDevListView()
  private let emptyLabel = NSTextField(
    wrappingLabelWithString: "No server yet. Run an action from the Actions tab.")
  private var state = DevServersState()
  private var clock: Timer?
  private var scanClock: Timer?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    list.rowHeight = 64
    emptyLabel.font = .systemFont(ofSize: 12.5)
    emptyLabel.textColor = NSColor.white.withAlphaComponent(0.45)
    emptyLabel.alignment = .center
    [list, emptyLabel].forEach(addSubview)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ newState: DevServersState) {
    guard newState != state else { return }
    state = newState
    reload()
  }

  private func reload() {
    // Un serveur lancé d'ici est à l'écoute aussi : il n'est montré que dans sa propre section.
    let groups = state.detected.compactMap { group -> DetectedServerGroup? in
      var group = group
      group.servers.removeAll { $0.actionName != nil }
      return group.servers.isEmpty ? nil : group
    }
    emptyLabel.isHidden = !state.servers.isEmpty || !groups.isEmpty
    var rows: [NSView] = []
    if !state.servers.isEmpty {
      rows.append(NotchDetectedSectionRowView(title: "Started here"))
      rows += state.servers.map { server in
        let row = NotchServerRowView(server: server)
        row.onStop = { [weak self] in self?.commands.stop(server.id) }
        row.onRestart = { [weak self] in self?.commands.restart(server.id) }
        row.onRemove = { [weak self] in self?.commands.remove(server.id) }
        return row
      }
    }
    if !groups.isEmpty {
      rows.append(NotchDetectedSectionRowView(title: "Running now"))
      for group in groups {
        rows.append(NotchDetectedGroupRowView(group: group))
        rows += group.servers.map { NotchDetectedServerRowView(server: $0) }
      }
    }
    list.setRows(rows)
    needsLayout = true
  }

  // MARK: - Durée de marche

  /// « Running · 2m 14s » vieillit : la liste se relit chaque seconde, tant que la page se voit.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    clock?.invalidate()
    clock = nil
    scanClock?.invalidate()
    scanClock = nil
    guard window != nil else { return }
    // Les serveurs à l'écoute se relisent toutes les 2 s, tant que la page est sous les yeux :
    // panneau déplié, page affichée. Replié, plus aucun balayage.
    scanClock = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, let window = self.window, window.isVisible, !window.ignoresMouseEvents,
          !self.isHiddenOrHasHiddenAncestor
        else { return }
        self.commands.refreshDetected()
      }
    }
    clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, !self.isHiddenOrHasHiddenAncestor,
          self.state.servers.contains(where: \.isRunning)
        else { return }
        self.reload()
      }
    }
  }

  override func layout() {
    super.layout()
    list.frame = bounds
    emptyLabel.frame = NSRect(
      x: 24, y: bounds.midY - 20, width: max(0, bounds.width - 48), height: 40)
  }
}

/// Un serveur : pastille d'état, nom, commande, dernière ligne écrite, et ses boutons.
private final class NotchServerRowView: NotchDevRowView {

  var onStop: (() -> Void)?
  var onRestart: (() -> Void)?
  var onRemove: (() -> Void)?

  private let dot = CALayer()
  private let nameLabel = NSTextField(labelWithString: "")
  private let statusLabel = NSTextField(labelWithString: "")
  private let commandLabel = NSTextField(labelWithString: "")
  private let outputLabel = NSTextField(labelWithString: "")
  private let primary: NotchUsageIconButton
  private let secondary: NotchUsageIconButton

  init(server: DevServer) {
    primary = NotchUsageIconButton(
      symbolName: server.isRunning ? "arrow.clockwise" : "play.fill",
      description: server.isRunning ? "Restart \(server.name)" : "Start \(server.name)")
    secondary = NotchUsageIconButton(
      symbolName: server.isRunning ? "stop.fill" : "xmark",
      description: server.isRunning ? "Stop \(server.name)" : "Remove \(server.name)")
    super.init(frame: .zero)
    preferredHeight = 64
    layer?.addSublayer(dot)
    dot.cornerRadius = 4
    dot.backgroundColor = Self.color(for: server).cgColor

    nameLabel.stringValue = server.name
    nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
    nameLabel.textColor = .white
    statusLabel.stringValue = Self.status(for: server)
    statusLabel.font = .systemFont(ofSize: 11.5)
    statusLabel.textColor = NSColor.white.withAlphaComponent(0.55)
    commandLabel.stringValue = ">_ " + server.command
    commandLabel.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
    commandLabel.textColor = NSColor.white.withAlphaComponent(0.7)
    outputLabel.stringValue = server.output.last ?? ""
    outputLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
    outputLabel.textColor = NSColor.white.withAlphaComponent(0.4)
    for label in [nameLabel, commandLabel, outputLabel] { label.lineBreakMode = .byTruncatingTail }
    commandLabel.lineBreakMode = .byTruncatingMiddle
    [nameLabel, statusLabel, commandLabel, outputLabel, primary, secondary].forEach(addSubview)

    primary.onClick = { [weak self] in self?.onRestart?() }
    secondary.onClick = { [weak self] in
      if server.isRunning { self?.onStop?() } else { self?.onRemove?() }
    }
    // Un arrêt demandé grise les boutons jusqu'à la fin du processus.
    if server.isStopping {
      primary.alphaValue = 0.35
      secondary.alphaValue = 0.35
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private static func color(for server: DevServer) -> NSColor {
    if server.isRunning { return NSColor(srgbRed: 0.30, green: 0.85, blue: 0.45, alpha: 1) }
    return (server.exitCode ?? 0) == 0
      ? NSColor.white.withAlphaComponent(0.35)
      : NSColor(srgbRed: 1, green: 0.38, blue: 0.34, alpha: 1)
  }

  private static func status(for server: DevServer) -> String {
    if server.isStopping { return "Stopping…" }
    if server.isRunning {
      return "Running · " + duration(Date().timeIntervalSince(server.startedAt))
    }
    return "Stopped · exit \(server.exitCode ?? 0)"
  }

  private static func duration(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval))
    let (hours, minutes, seconds) = (total / 3600, total % 3600 / 60, total % 60)
    if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
    if minutes > 0 { return "\(minutes)m \(String(format: "%02d", seconds))s" }
    return "\(seconds)s"
  }

  override func layout() {
    super.layout()
    let button: CGFloat = 26
    secondary.frame = NSRect(
      x: bounds.maxX - button, y: (bounds.height - button) / 2, width: button, height: button)
    primary.frame = NSRect(
      x: secondary.frame.minX - button - 6, y: secondary.frame.minY, width: button, height: button)
    let textX: CGFloat = 20
    let textWidth = max(0, primary.frame.minX - 12 - textX)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    dot.frame = CGRect(x: 2, y: bounds.height - 21, width: 8, height: 8)
    CATransaction.commit()

    let name = nameLabel.intrinsicContentSize
    let status = statusLabel.intrinsicContentSize
    let command = commandLabel.intrinsicContentSize.height
    let output = outputLabel.intrinsicContentSize.height
    let total = name.height + command + output + 4
    let top = (bounds.height + total) / 2
    let statusWidth = min(ceil(status.width), textWidth * 0.5)
    statusLabel.frame = NSRect(
      x: textX + textWidth - statusWidth, y: top - name.height + 1, width: statusWidth,
      height: status.height)
    nameLabel.frame = NSRect(
      x: textX, y: top - name.height, width: max(0, textWidth - statusWidth - 8), height: name.height)
    commandLabel.frame = NSRect(
      x: textX, y: nameLabel.frame.minY - 2 - command, width: textWidth, height: command)
    outputLabel.frame = NSRect(
      x: textX, y: commandLabel.frame.minY - 2 - output, width: textWidth, height: output)
    dot.frame = CGRect(x: 2, y: nameLabel.frame.midY - 4, width: 8, height: 8)
  }
}
