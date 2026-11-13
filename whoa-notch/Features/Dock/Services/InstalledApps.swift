import AppKit

struct InstalledApp: Equatable {
  var bundleID: String
  var path: String
  var name: String
  var category: String = "Other"

  var pinned: DockPinnedApp { DockPinnedApp(bundleID: bundleID, path: path) }
}

/// Applis installées, pour choisir celles d'un profil. Lit les dossiers d'applications
/// usuels, sans descendre dans les sous-dossiers (sauf Utilities).
@MainActor
enum InstalledApps {

  static func scan() -> [InstalledApp] {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let folders = [
      "/Applications", "/Applications/Utilities", "/System/Applications",
      "/System/Applications/Utilities", "\(home)/Applications",
    ]
    var seen = Set<String>()
    var apps: [InstalledApp] = []
    for folder in folders {
      let urls =
        (try? FileManager.default.contentsOfDirectory(
          at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)) ?? []
      for url in urls where url.pathExtension == "app" {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier, seen.insert(bundleID).inserted
        else { continue }
        let type =
          Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        apps.append(
          InstalledApp(
            bundleID: bundleID, path: url.path, name: url.deletingPathExtension().lastPathComponent,
            category: categoryName(for: type)))
      }
    }
    return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// Catégories affichées en pastilles : celles du Launchpad, regroupées.
  static let categoryOrder = [
    "Developer Tools", "Productivity & Finance", "Utilities", "Social", "Entertainment",
    "Creativity", "Other",
  ]

  static func categoryName(for type: String?) -> String {
    guard let type = type?.lowercased() else { return "Other" }
    switch true {
    case type.contains("developer-tools"): return "Developer Tools"
    case type.contains("productivity"), type.contains("business"), type.contains("finance"),
      type.contains("education"),
      type.contains("reference"), type.contains("news"):
      return "Productivity & Finance"
    case type.contains("utilities"), type.contains("healthcare"), type.contains("weather"),
      type.contains("lifestyle"):
      return "Utilities"
    case type.contains("social"): return "Social"
    case type.contains("entertainment"), type.contains("games"), type.contains("music"),
      type.contains("video"),
      type.contains("sports"):
      return "Entertainment"
    case type.contains("graphics"), type.contains("photography"): return "Creativity"
    default: return "Other"
    }
  }
}
