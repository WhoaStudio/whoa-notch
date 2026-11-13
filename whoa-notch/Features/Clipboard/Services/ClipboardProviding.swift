import AppKit
import OSLog

/// Source du presse-papiers. Derrière un protocole, comme les autres sources externes :
/// l'interface se vérifie sans toucher au vrai presse-papiers (`MockClipboardProvider`).
protocol ClipboardProviding: AnyObject {
  /// Appelé sur le fil principal à chaque nouvelle copie, sauf les contenus confidentiels.
  var onSnapshot: ((ClipboardSnapshot) -> Void)? { get set }
  func start()
  func stop()
  /// Remet un élément dans le presse-papiers, sans que la source le signale comme une copie.
  func copy(_ classification: ClipboardClassification)
}

/// Le vrai presse-papiers, surveillé par sondage : macOS n'envoie aucune notification quand il
/// change, seul `changeCount` bouge.
final class PasteboardClipboardProvider: ClipboardProviding {

  var onSnapshot: ((ClipboardSnapshot) -> Void)?

  private let pasteboard: NSPasteboard
  private var timer: Timer?
  private var lastChangeCount: Int

  private static let concealedTypes: Set<String> = [
    "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
  ]

  init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
    lastChangeCount = pasteboard.changeCount
  }

  func start() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.poll() }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func poll() {
    guard pasteboard.changeCount != lastChangeCount else { return }
    lastChangeCount = pasteboard.changeCount

    let snapshot = readSnapshot()
    guard !snapshot.isConcealed else { return }
    onSnapshot?(snapshot)
  }

  private func readSnapshot() -> ClipboardSnapshot {
    let types = Set((pasteboard.types ?? []).map(\.rawValue))
    var snapshot = ClipboardSnapshot()
    snapshot.isConcealed = !types.isDisjoint(with: Self.concealedTypes)
    let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    snapshot.sourceBundleID = source == Bundle.main.bundleIdentifier ? nil : source

    let urls =
      pasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    snapshot.fileURLs = urls ?? []
    snapshot.string = pasteboard.string(forType: .string)

    if snapshot.fileURLs.isEmpty {
      if let png = pasteboard.data(forType: .png) {
        snapshot.imageData = png
      } else if let tiff = pasteboard.data(forType: .tiff),
        let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
      {
        snapshot.imageData = png
      }
    }
    return snapshot
  }

  func copy(_ classification: ClipboardClassification) {
    pasteboard.clearContents()
    if let url = classification.fileURL {
      pasteboard.writeObjects([url as NSURL])
    } else if let data = classification.imageData {
      pasteboard.setData(data, forType: .png)
    } else if let text = classification.text {
      pasteboard.setString(text, forType: .string)
    }
    // Notre propre écriture n'est pas une copie de l'utilisateur.
    lastChangeCount = pasteboard.changeCount
  }
}

/// `--clipboard-history=sample` : quelques copies fixes, sans toucher au presse-papiers.
final class MockClipboardProvider: ClipboardProviding {

  var onSnapshot: ((ClipboardSnapshot) -> Void)?

  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments)
    -> MockClipboardProvider?
  {
    arguments.contains("--clipboard-history=sample") ? MockClipboardProvider() : nil
  }

  func start() {
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(300))
      guard let self else { return }
      // Du plus ancien au plus récent : la dernière copie arrive en tête.
      onSnapshot?(
        ClipboardSnapshot(
          fileURLs: [URL(fileURLWithPath: "/tmp/Archive.zip")], sourceBundleID: "com.apple.finder"))
      onSnapshot?(
        ClipboardSnapshot(string: "www.mynotchbar.com", sourceBundleID: "com.apple.Safari"))
      onSnapshot?(
        ClipboardSnapshot(
          string: "Drag In. Drag Out. Done. That's it.", sourceBundleID: "com.apple.mail"))
      onSnapshot?(
        ClipboardSnapshot(imageData: Self.sampleImage(), sourceBundleID: "com.apple.Photos"))
    }
  }

  func stop() {}

  func copy(_ classification: ClipboardClassification) {}

  private static func sampleImage() -> Data? {
    let image = NSImage(size: NSSize(width: 240, height: 160), flipped: false) { rect in
      NSGradient(colors: [.systemBlue, .systemTeal, .systemYellow])?.draw(in: rect, angle: 35)
      return true
    }
    guard let tiff = image.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
  }
}
