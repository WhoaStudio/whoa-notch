import Foundation

/// Contenu de la fenêtre de bienvenue, séparé de la vue pour qu'on puisse le modifier sans la toucher.
enum OnboardingContent {

  struct Feature: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
  }

  struct Item: Identifiable {
    let id = UUID()
    let symbol: String
    let text: String
  }

  static let tagline = "Controls and glanceable info, right on the edges of your screen."

  static let leftNote = "THANK YOU\nFOR USING\nWHOA STASH !!"
  static let rightNote = "WITH ♡ FROM\nWHOA STUDIO"

  static let features: [Feature] = [
    Feature(
      symbol: "rectangle.topthird.inset.filled", title: "Notch panel",
      detail:
        "Unfolds from the notch with tabs for now playing, calendar, tray, clipboard, notes and a terminal."
    ),
    Feature(
      symbol: "dock.rectangle", title: "Custom Dock",
      detail:
        "Pinned and running apps at the bottom of the screen, with the macOS Dock tucked away."),
  ]

  static let alsoNew: [Item] = [
    Item(symbol: "sun.max.fill", text: "Scroll on the screen edge to set brightness and volume."),
    Item(symbol: "doc.on.clipboard", text: "Clipboard history of your last 50 copies."),
    Item(
      symbol: "circle.hexagongrid.fill",
      text: "Radial menu under the cursor to launch apps and Shortcuts."),
    Item(
      symbol: "hand.tap.fill", text: "Knock on your Mac to turn the display off or lock the screen."
    ),
  ]

  static let fixes: [Item] = [
    Item(
      symbol: "gearshape.fill",
      text: "Everything is tunable in Preferences, from the menu bar icon.")
  ]
}
