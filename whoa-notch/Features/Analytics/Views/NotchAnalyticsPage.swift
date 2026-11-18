import AppKit

/// Une page de l'onglet Analytics : un titre (celui de l'en-tête), un glyphe pour la barre
/// d'onglets et la vue elle-même. Ajouter un onglet, c'est ajouter une page à `NotchAnalyticsHostView`.
protocol NotchAnalyticsPage: AnyObject {
  var pageTitle: String { get }
  var pageSymbol: String { get }
  var pageView: NSView { get }
  /// Vrai quand la page a un champ de saisie : le panneau prend alors le clavier au clic.
  var acceptsTyping: Bool { get }
}

extension NotchAnalyticsPage {
  var acceptsTyping: Bool { false }
}

extension NotchAnalyticsTabView: NotchAnalyticsPage {
  var pageTitle: String { "Usage" }
  var pageSymbol: String { "chart.bar" }
  var pageView: NSView { self }
}
