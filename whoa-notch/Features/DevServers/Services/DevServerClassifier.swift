import Foundation

/// Transforme les processus à l'écoute en serveurs de développement groupés par projet.
/// Pur, sans appel système autre que la lecture des fichiers de projet : testable avec un
/// dossier temporaire.
nonisolated enum DevServerClassifier {

  // MARK: - Lecture de `lsof`

  /// Sortie de `lsof -nP -iTCP -sTCP:LISTEN -Fpcn` : `p` ouvre un processus, `c` donne son nom,
  /// `n` une adresse (`*:3000`, `127.0.0.1:5432`, `[::1]:5173`).
  static func parseLsof(_ output: String) -> [(pid: Int32, name: String, ports: [Int])] {
    var result: [(pid: Int32, name: String, ports: [Int])] = []
    for line in output.split(separator: "\n") {
      guard let tag = line.first else { continue }
      let value = line.dropFirst()
      switch tag {
      case "p":
        if let pid = Int32(value) { result.append((pid, "", [])) }
      case "c":
        if !result.isEmpty { result[result.count - 1].name = String(value) }
      case "n":
        guard !result.isEmpty, let colon = value.lastIndex(of: ":"),
          let port = Int(value[value.index(after: colon)...])
        else { continue }
        if !result[result.count - 1].ports.contains(port) { result[result.count - 1].ports.append(port) }
      default:
        continue
      }
    }
    return result.filter { !$0.ports.isEmpty }
  }

  // MARK: - Projet

  /// Racine du projet d'un processus : la racine du dépôt git, à défaut le dossier du
  /// `package.json` le plus proche, cherchés depuis son dossier courant puis depuis les chemins
  /// de sa ligne de commande. Seuls comptent les dossiers sous `home`, hors `~/Library` : un
  /// Postgres de Homebrew vit sous `/opt/homebrew`, qui est lui-même un dépôt git.
  static func projectRoot(for process: ListeningProcess, home: String) -> (
    root: String, packageDirectory: String?
  )? {
    var candidates = [process.cwd].compactMap { $0 }
    candidates += process.arguments.dropFirst().filter { $0.hasPrefix("/") }
    for candidate in candidates {
      if let found = locate(from: candidate, home: home) { return found }
    }
    return nil
  }

  private static func locate(from path: String, home: String) -> (
    root: String, packageDirectory: String?
  )? {
    let library = home + "/Library"
    guard isInside(path, home), !isInside(path, library) else { return nil }
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    var directory = URL(fileURLWithPath: path)
    if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
      directory.deleteLastPathComponent()
    }
    var package: String?
    var gitRoot: String?
    while isInside(directory.path, home), directory.path != home {
      if package == nil,
        fileManager.fileExists(atPath: directory.appendingPathComponent("package.json").path)
      {
        package = directory.path
      }
      if fileManager.fileExists(atPath: directory.appendingPathComponent(".git").path) {
        gitRoot = directory.path
        break
      }
      directory.deleteLastPathComponent()
    }
    guard let root = gitRoot ?? package else { return nil }
    return (root, package)
  }

  private static func isInside(_ path: String, _ folder: String) -> Bool {
    path == folder || path.hasPrefix(folder + "/")
  }

  // MARK: - Framework

  /// Dépendances (`dependencies` et `devDependencies`) du `package.json` de `directory`.
  static func dependencies(inPackageAt directory: String?) -> Set<String> {
    guard let directory,
      let data = FileManager.default.contents(atPath: directory + "/package.json"),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [] }
    var names = Set<String>()
    for key in ["dependencies", "devDependencies"] {
      if let section = json[key] as? [String: Any] { names.formUnion(section.keys) }
    }
    return names
  }

  /// La commande d'abord (elle dit ce que le processus est vraiment), puis les dépendances du
  /// projet pour les lanceurs génériques (`node`, `bun`, `tsx`), puis le nom du processus.
  static func framework(
    name: String, arguments: [String], dependencies: Set<String>
  ) -> ServerFramework? {
    let program = (arguments.first.map { ($0 as NSString).lastPathComponent } ?? name).lowercased()
    let command = ([name] + arguments).joined(separator: " ").lowercased()

    switch program {
    case "postgres", "postmaster": return .postgres
    case "redis-server", "redis-stack-server", "valkey-server": return .redis
    case "mysqld", "mariadbd": return .mysql
    case "mongod": return .mongo
    case "next-server": return .nextjs
    default: break
    }
    if name.lowercased().hasPrefix("com.docker") || name.lowercased() == "docker" { return .docker }

    let byCommand: [(String, ServerFramework)] = [
      ("/node_modules/next/", .nextjs), ("next dev", .nextjs), ("next start", .nextjs),
      ("@nestjs/", .nestjs), ("nest start", .nestjs),
      ("/node_modules/nuxt", .nuxt), ("/node_modules/astro", .astro),
      ("/node_modules/vite/", .vite), ("/.bin/vite", .vite), ("vite dev", .vite),
    ]
    for (needle, framework) in byCommand where command.contains(needle) { return framework }

    let byDependency: [(String, ServerFramework)] = [
      ("next", .nextjs), ("@nestjs/core", .nestjs), ("hono", .hono), ("nuxt", .nuxt),
      ("astro", .astro), ("@remix-run/dev", .remix), ("vite", .vite), ("fastify", .fastify),
      ("express", .express),
    ]
    let launchers: Set<String> = ["node", "bun", "deno", "tsx", "ts-node", "npm", "pnpm", "yarn"]
    if launchers.contains(program) || program.hasPrefix("node") {
      for (dependency, framework) in byDependency where dependencies.contains(dependency) {
        return framework
      }
    }

    let runtimes: [String: ServerFramework] = [
      "node": .node, "bun": .bun, "deno": .deno, "python": .python, "python3": .python,
      "ruby": .ruby, "php": .php, "java": .java, "uvicorn": .python, "gunicorn": .python,
    ]
    return runtimes[program] ?? runtimes[name.lowercased()]
  }

  // MARK: - Groupes

  /// - Parameter actionGroups: chef de groupe de processus → nom de l'action de l'app.
  static func group(
    _ processes: [ListeningProcess], home: String, actionGroups: [Int32: String] = [:]
  ) -> [DetectedServerGroup] {
    var projects: [String: [DetectedServer]] = [:]
    var system: [DetectedServer] = []

    for process in processes {
      let project = projectRoot(for: process, home: home)
      let found = framework(
        name: process.name, arguments: process.arguments,
        dependencies: dependencies(inPackageAt: project?.packageDirectory))
      guard let found else { continue }
      // Hors d'un projet, seuls les services (bases de données…) comptent : le reste, ce sont des
      // applis du Mac (Centre de contrôle, Figma, Raycast…).
      guard project != nil || found.isService else { continue }
      let server = DetectedServer(
        pid: process.pid, processName: process.name, framework: found,
        ports: process.ports.sorted(),
        actionName: process.groupLeader.flatMap { actionGroups[$0] })
      if let project { projects[project.root, default: []].append(server) } else { system.append(server) }
    }

    func sorted(_ servers: [DetectedServer]) -> [DetectedServer] {
      servers.sorted { ($0.ports.first ?? 0, $0.pid) < ($1.ports.first ?? 0, $1.pid) }
    }
    var groups = projects.map { path, servers in
      DetectedServerGroup(
        name: (path as NSString).lastPathComponent, path: path, servers: sorted(servers))
    }
    groups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    if !system.isEmpty {
      groups.append(
        DetectedServerGroup(name: DetectedServerGroup.systemName, path: nil, servers: sorted(system)))
    }
    return groups
  }
}
