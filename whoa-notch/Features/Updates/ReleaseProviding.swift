import Foundation

/// Dernière version publiée, telle que la renvoie la source de mises à jour.
nonisolated struct ReleaseInfo: Equatable, Sendable {
  let version: String
  let url: URL
}

/// Source de la dernière version publiée. Derrière un protocole pour vérifier l'interface sans
/// réseau (`MockReleaseProvider`, via `--update-check=available|current|failed`).
nonisolated protocol ReleaseProviding: Sendable {
  func latestRelease() async throws -> ReleaseInfo
}

/// Dernière release GitHub du dépôt, via l'API publique (sans jeton, 60 requêtes/heure/IP).
nonisolated struct GitHubReleaseProvider: ReleaseProviding {
  enum Failure: Error { case badResponse(Int) }

  private struct Payload: Decodable {
    let tagName: String
    let htmlURL: URL
    enum CodingKeys: String, CodingKey {
      case tagName = "tag_name"
      case htmlURL = "html_url"
    }
  }

  private static let endpoint = URL(
    string: "https://api.github.com/repos/WhoaStudio/whoa-notch/releases/latest")!

  func latestRelease() async throws -> ReleaseInfo {
    var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("whoa-notch", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw Failure.badResponse(status) }
    let payload = try JSONDecoder().decode(Payload.self, from: data)
    return ReleaseInfo(version: payload.tagName, url: payload.htmlURL)
  }
}

/// Source factice : le résultat est fixé par `--update-check=available|current|failed`.
nonisolated struct MockReleaseProvider: ReleaseProviding {
  let outcome: String
  private static let url = URL(string: "https://github.com/WhoaStudio/whoa-notch/releases/latest")!

  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments)
    -> MockReleaseProvider?
  {
    guard let argument = arguments.first(where: { $0.hasPrefix("--update-check=") }) else {
      return nil
    }
    return MockReleaseProvider(outcome: String(argument.dropFirst("--update-check=".count)))
  }

  func latestRelease() async throws -> ReleaseInfo {
    switch outcome {
    case "available": return ReleaseInfo(version: "v999.0", url: Self.url)
    case "current": return ReleaseInfo(version: "v0.0.1", url: Self.url)
    default: throw GitHubReleaseProvider.Failure.badResponse(500)
    }
  }
}

/// Comparaison de numéros de version (`1.2.3`, avec ou sans « v »), composante par composante.
nonisolated enum AppVersion {
  static func isNewer(_ candidate: String, than current: String) -> Bool {
    let a = components(candidate)
    let b = components(current)
    for index in 0..<max(a.count, b.count) {
      let x = index < a.count ? a[index] : 0
      let y = index < b.count ? b[index] : 0
      if x != y { return x > y }
    }
    return false
  }

  private static func components(_ version: String) -> [Int] {
    version.drop(while: { $0 == "v" || $0 == "V" }).split(separator: ".").map { Int($0) ?? 0 }
  }
}
