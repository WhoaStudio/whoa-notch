import Foundation

/// Un processus qui écoute sur un port TCP, tel que le système le décrit : rien n'est encore
/// interprété.
nonisolated struct ListeningProcess: Equatable, Sendable {
  var pid: Int32
  var name: String
  var ports: [Int]
  /// Dossier courant du processus, `nil` s'il n'est pas lisible.
  var cwd: String?
  /// Ligne de commande complète (`argv`), le programme en premier.
  var arguments: [String]
  /// Chef du groupe de processus : celui d'une action lancée depuis l'app est son shell.
  var groupLeader: Int32?
}

/// Ce qu'un serveur de développement est, d'après sa commande et les dépendances de son projet.
nonisolated enum ServerFramework: String, Equatable, Sendable {
  case nextjs, nestjs, hono, nuxt, astro, remix, vite, fastify, express
  case postgres, redis, mysql, mongo, docker
  case node, bun, deno, python, ruby, php, java, go

  var displayName: String {
    switch self {
    case .nextjs: "Next.js"
    case .nestjs: "NestJS"
    case .hono: "Hono"
    case .nuxt: "Nuxt"
    case .astro: "Astro"
    case .remix: "Remix"
    case .vite: "Vite"
    case .fastify: "Fastify"
    case .express: "Express"
    case .postgres: "PostgreSQL"
    case .redis: "Redis"
    case .mysql: "MySQL"
    case .mongo: "MongoDB"
    case .docker: "Docker"
    case .node: "Node"
    case .bun: "Bun"
    case .deno: "Deno"
    case .python: "Python"
    case .ruby: "Ruby"
    case .php: "PHP"
    case .java: "Java"
    case .go: "Go"
    }
  }

  /// Un service (base de données, moteur de conteneurs) qui n'a pas besoin d'un projet pour
  /// compter comme serveur de développement.
  var isService: Bool {
    switch self {
    case .postgres, .redis, .mysql, .mongo, .docker: true
    default: false
    }
  }
}

nonisolated struct DetectedServer: Equatable, Identifiable, Sendable {
  var id: Int32 { pid }
  var pid: Int32
  var processName: String
  var framework: ServerFramework
  var ports: [Int]
  /// Nom de l'action de l'app qui l'a lancé, le cas échéant.
  var actionName: String?
}

/// Les serveurs d'un même projet. `path == nil` : le groupe « Other / System ».
nonisolated struct DetectedServerGroup: Equatable, Identifiable, Sendable {
  static let systemName = "Other / System"

  var id: String { path ?? "system" }
  var name: String
  var path: String?
  var servers: [DetectedServer]
}
