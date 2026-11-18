import Foundation

/// Les scripts du `package.json` d'un projet, et la commande qui les lance avec son gestionnaire
/// de paquets (`pnpm dev`, `npm run build`…).
nonisolated enum PackageScripts {

  struct Script: Equatable {
    var name: String
    /// Le texte du script (`next dev`), pour le montrer à côté du nom.
    var body: String
  }

  /// Scripts les plus utiles d'abord, les autres par ordre alphabétique.
  private static let priority = ["dev", "start", "serve", "build", "test", "lint", "typecheck"]

  static func read(in directory: String) -> [Script] {
    guard let data = FileManager.default.contents(atPath: directory + "/package.json"),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let scripts = json["scripts"] as? [String: Any]
    else { return [] }
    let all = scripts.compactMap { name, body in (body as? String).map { Script(name: name, body: $0) } }
    return all.sorted { lhs, rhs in
      let left = priority.firstIndex(of: lhs.name) ?? priority.count
      let right = priority.firstIndex(of: rhs.name) ?? priority.count
      return left != right ? left < right : lhs.name < rhs.name
    }
  }

  /// Le gestionnaire du projet : le champ `packageManager` du `package.json`, à défaut le
  /// fichier de verrouillage présent, à défaut `npm`.
  static func packageManager(in directory: String) -> String {
    let fileManager = FileManager.default
    if let data = fileManager.contents(atPath: directory + "/package.json"),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let declared = json["packageManager"] as? String
    {
      let name = declared.split(separator: "@").first.map(String.init) ?? declared
      if ["pnpm", "yarn", "bun", "npm"].contains(name) { return name }
    }
    let locks: [(String, String)] = [
      ("pnpm-lock.yaml", "pnpm"), ("yarn.lock", "yarn"), ("bun.lock", "bun"), ("bun.lockb", "bun"),
      ("package-lock.json", "npm"),
    ]
    return locks.first { fileManager.fileExists(atPath: directory + "/" + $0.0) }?.1 ?? "npm"
  }

  /// Noms de scripts que `pnpm` et `yarn` prennent pour leurs propres commandes : ils passent par `run`.
  private static let reserved: Set<String> = [
    "install", "add", "remove", "update", "link", "unlink", "init", "publish", "pack", "run",
    "exec", "dlx", "create", "cache", "config", "list", "outdated", "audit", "store", "why",
    "import", "rebuild", "prune", "patch", "deploy", "env", "setup", "server", "fetch", "up", "rm",
    "i", "ls", "info", "version", "upgrade", "global",
  ]

  static func command(for script: String, in directory: String) -> String {
    let manager = packageManager(in: directory)
    switch manager {
    case "pnpm", "yarn": return reserved.contains(script) ? "\(manager) run \(script)" : "\(manager) \(script)"
    default: return "\(manager) run \(script)"
    }
  }
}
