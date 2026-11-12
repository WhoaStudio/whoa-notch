import AppKit
import Combine
import OSLog

/// Gère la fenêtre de Préférences : instance unique, ramenée au premier plan à chaque
/// ouverture. Compose la sidebar et le volet courant ; ne contient aucune logique métier —
/// tout passe par `SettingsViewModel` et les view models de section.
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {

  static let shared = SettingsWindowController()

  private let settingsViewModel = SettingsViewModel()

  private convenience init() {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: SettingsMetrics.windowSize),
      styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "Whoa Stash Settings"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.center()

    self.init(window: window)

    window.delegate = self

    let detail = SettingsDetailViewController(viewModel: settingsViewModel) {
      SettingsStorage.shared.settings.general.enableAnimations
    }
    let sidebar = NSSplitViewItem(
      sidebarWithViewController: SettingsSidebarViewController(viewModel: settingsViewModel))
    sidebar.minimumThickness = SettingsMetrics.sidebarWidth
    sidebar.maximumThickness = SettingsMetrics.sidebarWidth
    let split = NSSplitViewController()
    split.addSplitViewItem(sidebar)
    split.addSplitViewItem(NSSplitViewItem(viewController: detail))
    window.contentViewController = split
    window.setContentSize(SettingsMetrics.windowSize)
    window.center()

    let toolbar = NSToolbar(identifier: "SettingsToolbar")
    toolbar.delegate = self
    window.toolbar = toolbar
  }

  // MARK: - NSToolbarDelegate

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.toggleSidebar]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.toggleSidebar]
  }

  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? { nil }

  /// Seul chemin d'ouverture de la fenêtre — la menu bar, le menu contextuel des panneaux,
  /// `--show-settings` et ⌘, y aboutissent tous. L'icône du Dock apparaît donc exactement
  /// quand la fenêtre apparaît, et la fenêtre est unique : `isReleasedWhenClosed` est faux et
  /// l'instance est un singleton, donc une seconde ouverture ramène la même au premier plan.
  func show() {
    rerouteSettingsMenuItem()
    DockPresence.showIcon()
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  func show(_ category: SettingsCategory) {
    settingsViewModel.selectedCategory = category
    show()
  }

  // MARK: - NSWindowDelegate

  /// La fermeture de la fenêtre est le seul événement qui retire l'icône. Réduire la fenêtre
  /// dans le Dock ne la ferme pas : l'icône reste, et c'est elle qui permet de la ressortir.
  func windowWillClose(_ notification: Notification) {
    DockPresence.hideIcon()
  }

  // MARK: - ⌘,

  /// `Settings { EmptyView() }` fait porter à SwiftUI l'entrée « Settings… » ⌘, du menu de
  /// l'app. Invisible tant qu'on est `.accessory`, elle devient atteignable dès que l'icône du
  /// Dock fait aussi apparaître la menu bar — et ouvrirait alors une *seconde* fenêtre, vide.
  /// On la rebranche donc ici sur cette fenêtre-ci, avant toute bascule en `.regular`.
  ///
  /// L'opération est idempotente, d'où son appel à chaque `show()` plutôt qu'une seule fois au
  /// lancement : le menu principal est construit par SwiftUI, et on ne présume pas qu'il
  /// existe déjà à `applicationDidFinishLaunching`.
  private func rerouteSettingsMenuItem() {
    guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }

    let swiftUISelectors: Set<String> = ["showSettingsWindow:", "showPreferencesWindow:"]

    for item in appMenu.items {
      let isSwiftUIItem =
        item.action.map { swiftUISelectors.contains(NSStringFromSelector($0)) } ?? false
      let isCommandComma = item.keyEquivalent == "," && item.keyEquivalentModifierMask == [.command]
      guard isSwiftUIItem || isCommandComma else { continue }

      item.target = self
      item.action = #selector(showFromMenuItem)
    }
  }

  @objc private func showFromMenuItem(_ sender: Any?) {
    Log.settings.debug("ouverture de la fenêtre de Préférences depuis ⌘,")
    show()
  }
}

/// Affiche le volet de la catégorie sélectionnée et anime le changement par un fondu croisé —
/// jamais un simple `switch` instantané.
private final class SettingsDetailViewController: NSViewController {

  private let viewModel: SettingsViewModel
  private let animationsEnabled: () -> Bool

  private let contentContainer = NSView()
  private var currentCategory: SettingsCategory?
  private var currentChild: NSViewController?
  private var cancellable: AnyCancellable?

  init(viewModel: SettingsViewModel, animationsEnabled: @escaping () -> Bool) {
    self.viewModel = viewModel
    self.animationsEnabled = animationsEnabled
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    view = NSView(frame: NSRect(origin: .zero, size: SettingsMetrics.windowSize))
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    contentContainer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(contentContainer)

    NSLayoutConstraint.activate([
      contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
      contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    cancellable = viewModel.$selectedCategory.sink { [weak self] category in
      self?.show(category)
    }
  }

  private func show(_ category: SettingsCategory) {
    guard category != currentCategory else { return }

    let outgoing = currentChild
    // Un fondu interrompu par un changement d'onglet trop rapide laisse son volet à l'écran, par-dessus
    // le suivant : tout ce qui n'est pas le volet qui s'en va est un reste, retiré tout de suite.
    for child in children where child !== outgoing {
      child.view.removeFromSuperview()
      child.removeFromParent()
    }

    let next = makeViewController(for: category)
    next.category = category
    addChild(next)
    next.view.translatesAutoresizingMaskIntoConstraints = false
    contentContainer.addSubview(next.view)
    NSLayoutConstraint.activate([
      next.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
      next.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
      next.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
      next.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
    ])
    // Le volet affiché change dès maintenant, pas à la fin du fondu : un clic suivant part de lui.
    currentChild = next
    currentCategory = category

    guard let current = outgoing else { return }
    let finish: @Sendable () -> Void = {
      MainActor.assumeIsolated {
        current.view.removeFromSuperview()
        current.removeFromParent()
      }
    }

    if animationsEnabled(), OverlayAnimation.allowsMotion {
      next.view.wantsLayer = true
      next.view.layer?.springReveal(x: 12, y: 0)
      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = PanelFold.fadeDuration
          context.timingFunction = CAMediaTimingFunction(name: .easeOut)
          current.view.animator().alphaValue = 0
        }, completionHandler: finish)
    } else {
      finish()
    }
  }

  private func makeViewController(for category: SettingsCategory) -> SettingsSectionViewController {
    switch category {
    case .general: return GeneralSettingsViewController(animationsEnabled: animationsEnabled)
    case .appearance: return AppearanceSettingsViewController(animationsEnabled: animationsEnabled)
    case .screens: return ScreensSettingsViewController(animationsEnabled: animationsEnabled)
    case .privacy: return PrivacySettingsViewController(animationsEnabled: animationsEnabled)
    case .brightness: return BrightnessSettingsViewController(animationsEnabled: animationsEnabled)
    case .radialMenu: return RadialMenuSettingsViewController(animationsEnabled: animationsEnabled)
    case .dock: return DockSettingsViewController(animationsEnabled: animationsEnabled)
    case .profiles: return ProfilesSettingsViewController(animationsEnabled: animationsEnabled)
    case .ai: return AISettingsViewController(animationsEnabled: animationsEnabled)
    case .mail: return MailSettingsViewController(animationsEnabled: animationsEnabled)
    case .about: return AboutSettingsViewController(animationsEnabled: animationsEnabled)
    }
  }
}
