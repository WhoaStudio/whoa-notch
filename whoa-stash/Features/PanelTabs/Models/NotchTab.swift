import Foundation

/// Les onglets de la barre haute du panneau, dans l'ordre où ils s'y présentent.
///
/// `Global` porte la bande horizontale de la semaine ; `Calendar` porte l'agenda et la grille
/// mensuelle ; `Tray` recueille les fichiers qu'on y dépose ; `Clipboard` garde l'historique des copies ; `Notes` garde des notes en texte brut ; `Mirror` montre la caméra dans un
/// cercle ; `AI` porte l'utilisation des agents ; `Terminal` porte un shell.
///
/// `StayAwake` est à part : on l'ouvre depuis le bouton tasse de l'en-tête, pas depuis la
/// capsule, et le balayage n'y mène pas (voir `barTabs`).
enum NotchTab: Int, CaseIterable {
    case global
    case calendar
    case tray
    case clipboard
    case notes
    case mirror
    case ai
    case terminal
    case stayAwake

    /// Les onglets de la capsule, dans l'ordre de la rangée.
    static let barTabs: [NotchTab] = allCases.filter { $0 != .stayAwake }

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
        case .stayAwake: "Stay Awake"
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
        case .stayAwake: "cup.and.saucer"
        }
    }
}
