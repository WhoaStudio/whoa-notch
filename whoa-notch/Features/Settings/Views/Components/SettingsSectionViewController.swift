import AppKit

/// Vue document d'un `NSScrollView` en coordonnées "haut vers le bas" : sans ça, un contenu
/// plus court que la zone visible s'ancre en bas du scroll view (coordonnées AppKit par
/// défaut) au lieu de rester collé en haut, sous les cartes.
private final class FlippedView: NSView {
  override var isFlipped: Bool { true }
}

/// Base commune aux écrans de Préférences : des groupes (`SettingsGroupView`) dans un scroll view sans chrome visible, sous la barre
/// d'en-tête fixe du volet (`SettingsPaneHeaderView`), avec une apparition en
/// fondu/glissé légère à chaque affichage. Les sous-classes fournissent soit leurs groupes
/// (`makeSections`), soit des lignes que les filets découpent en groupes (`makeRows`).
class SettingsSectionViewController: NSViewController {

  private let animationsEnabled: () -> Bool
  private let stack = NSStackView()
  private var header: SettingsPaneHeaderView?
  private var scrollView: NSScrollView?

  /// Catégorie affichée, posée par la fenêtre avant le chargement de la vue.
  var category: SettingsCategory = .general

  init(animationsEnabled: @escaping () -> Bool) {
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

    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    let documentView = FlippedView()
    documentView.translatesAutoresizingMaskIntoConstraints = false

    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = SettingsMetrics.rowSpacing
    stack.translatesAutoresizingMaskIntoConstraints = false

    documentView.addSubview(stack)
    scrollView.documentView = documentView
    view.addSubview(scrollView)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

      stack.topAnchor.constraint(
        equalTo: documentView.topAnchor,
        constant: showsHeader ? SettingsMetrics.contentTopInset : SettingsMetrics.headerlessTopInset),
      stack.leadingAnchor.constraint(
        equalTo: documentView.leadingAnchor, constant: SettingsMetrics.contentInset),
      stack.trailingAnchor.constraint(
        equalTo: documentView.trailingAnchor, constant: -SettingsMetrics.contentInset),
      stack.bottomAnchor.constraint(
        equalTo: documentView.bottomAnchor, constant: -SettingsMetrics.contentBottomInset),
    ])

    self.scrollView = scrollView
    if showsHeader {
      let header = SettingsPaneHeaderView(category: category)
      view.addSubview(header)
      NSLayoutConstraint.activate([
        header.topAnchor.constraint(equalTo: view.topAnchor),
        header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      ])
      self.header = header
      scrollView.contentView.postsBoundsChangedNotifications = true
      NotificationCenter.default.addObserver(
        self, selector: #selector(contentDidScroll), name: NSView.boundsDidChangeNotification,
        object: scrollView.contentView)
    }
    for section in makeSections() {
      stack.addArrangedSubview(section)
      section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
  }

  @objc private func contentDidScroll(_ notification: Notification) {
    header?.setScrolled((scrollView?.contentView.bounds.origin.y ?? 0) > 0.5)
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    animateRowsIn()
  }

  /// `false` pour un volet à la mise en page libre (« About »), sans l'en-tête commun.
  var showsHeader: Bool { true }

  /// Point d'extension : les groupes du volet. Par défaut, les lignes de `makeRows` découpées
  /// aux filets (`makeSettingsDivider`), un groupe par morceau.
  func makeSections() -> [NSView] {
    var chunks: [[NSView]] = [[]]
    for row in makeRows() {
      if (row as? NSBox)?.boxType == .separator {
        if chunks.last?.isEmpty == false { chunks.append([]) }
      } else {
        chunks[chunks.count - 1].append(row)
      }
    }
    return chunks.filter { !$0.isEmpty }.map { SettingsGroupView(rows: $0) }
  }

  /// Point d'extension simple : les lignes d'un volet, séparées par des filets.
  func makeRows() -> [NSView] { [] }

  private func animateRowsIn() {
    guard animationsEnabled(), OverlayAnimation.allowsMotion else { return }
    for (index, row) in stack.arrangedSubviews.enumerated() {
      row.wantsLayer = true
      guard let layer = row.layer else { continue }
      layer.opacity = 0
      layer.transform = CATransform3DMakeTranslation(0, 8, 0)

      let delay = Double(index) * 0.05
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        layer.springAnimate(keyPath: "opacity", to: 1, preset: .gentle)
        layer.springAnimate(
          keyPath: "transform", to: NSValue(caTransform3D: CATransform3DIdentity), preset: .gentle)
      }
    }
  }
}
