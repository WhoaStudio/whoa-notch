import Foundation

/// Les onglets de la barre haute du panneau, dans l'ordre où ils s'y présentent.
///
/// `Global` porte la bande horizontale de la semaine ; `Calendar` porte l'agenda et la grille
/// mensuelle ; `Tray` recueille les fichiers qu'on y dépose ; `Clipboard` garde l'historique des copies ; `Notes` garde des notes en texte brut ; `Mirror` montre la caméra dans un
/// cercle ; `AI` porte l'utilisation des agents ; `Terminal` porte un shell ; `Color` prélève
/// une couleur à l'écran.
///
/// `StayAwake` et `Analytics` sont à part : on les ouvre depuis les boutons de l'en-tête (la
/// tasse, la pastille d'usage), pas depuis la capsule, et le balayage n'y mène pas (voir
/// `barTabs`).
enum NotchTab: Int, CaseIterable {
  case global
  case calendar
  case tray
  case clipboard
  case notes
  case mirror
  case ai
  case terminal
  case colorPicker
  case stayAwake
  case analytics

  /// Les onglets de la capsule, dans l'ordre de la rangée.
  static var barTabs: [NotchTab] {
    allCases.filter { $0 != .stayAwake && $0 != .analytics && !disabledTabs.contains($0) }
  }

  /// Onglets que l'utilisateur a coupés dans les Préférences : ils quittent la capsule et le
  /// balayage. `NotchPanelController` la tient à jour et reconstruit les fenêtres à chaque
  /// changement ; `Global` n'y figure jamais, c'est l'onglet de repli.
  static var disabledTabs: Set<NotchTab> = []

  /// Les onglets de la capsule qu'on peut couper.
  static let switchableTabs: [NotchTab] = allCases.filter {
    $0 != .global && $0 != .stayAwake && $0 != .analytics
  }

  /// Les onglets désignés par leur titre, tel qu'il est enregistré dans les réglages ; un titre
  /// inconnu ou `Global` est ignoré.
  static func tabs(named names: [String]) -> Set<NotchTab> {
    Set(switchableTabs.filter { names.contains($0.title) })
  }

  /// L'onglet voisin dans le sens donné, ou `nil` au bout de la rangée — on ne reboucle pas.
  /// Hors de la capsule, un onglet n'a pas de voisin.
  func neighbor(_ direction: TabSwipeTracker.Direction) -> NotchTab? {
    guard let index = Self.barTabs.firstIndex(of: self) else { return nil }
    let target = index + (direction == .next ? 1 : -1)
    return Self.barTabs.indices.contains(target) ? Self.barTabs[target] : nil
  }

  var title: String {
    switch self {
    case .global: "Global"
    case .calendar: "Calendar"
    case .tray: "Tray"
    case .clipboard: "Clipboard"
    case .notes: "Notes"
    case .mirror: "Mirror"
    case .ai: "AI"
    case .terminal: "Terminal"
    case .colorPicker: "Color"
    case .stayAwake: "Stay Awake"
    case .analytics: "Analytics"
    }
  }

  /// Glyphe SF Symbols de l'onglet. Tous existent depuis longtemps dans le système, donc pas
  /// de repli à prévoir côté vue.
  var symbolName: String {
    switch self {
    case .global: "globe"
    case .calendar: "calendar"
    case .tray: "tray"
    case .clipboard: "doc.on.clipboard"
    case .notes: "note.text"
    case .mirror: "camera"
    case .ai: "sparkles"
    case .terminal: "terminal"
    case .colorPicker: "eyedropper"
    case .stayAwake: "cup.and.saucer"
    case .analytics: "chart.bar.xaxis"
    }
  }
}
