import Foundation

protocol AgentActivityProviding: Sendable {
  /// Les requêtes datées de `since` ou après — le fournisseur peut en rendre davantage.
  func records(since: Date) async -> [ActivityRecord]
}

/// Lit `~/.claude/projects` et `~/.codex/sessions`. Les journaux se comptent en centaines de
/// mégaoctets : chaque fichier n'est relu que s'il a changé, et rien ne tourne sur le thread
/// principal.
nonisolated final class LocalAgentActivityService: AgentActivityProviding, @unchecked Sendable {

  private struct Cached {
    let modified: Date
    let size: Int
    let records: [ActivityRecord]
  }

  private let claudeRoot: URL
  private let codexRoots: [URL]
  private let lock = NSLock()
  private var cache: [String: Cached] = [:]

  init(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    claudeRoot = home.appendingPathComponent(".claude/projects")
    let codexHome =
      environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
      ?? home.appendingPathComponent(".codex")
    codexRoots = ["sessions", "archived_sessions"].map { codexHome.appendingPathComponent($0) }
  }

  func records(since: Date) async -> [ActivityRecord] {
    await Task.detached(priority: .utility) { [self] in
      var merged: [String: ActivityRecord] = [:]
      func add(_ records: [ActivityRecord]) {
        for record in records {
          // Les lignes d'un même message se complètent : on garde la plus fournie.
          if let existing = merged[record.key], existing.tokens.output >= record.tokens.output {
            continue
          }
          merged[record.key] = record
        }
      }

      for file in files(under: claudeRoot, since: since) {
        let project = file.url.deletingLastPathComponent().lastPathComponent
        add(load(file) { ActivityLogParser.parseClaude($0, fallbackProject: project) })
      }
      for root in codexRoots {
        for file in files(under: root, since: since) {
          add(
            load(file) {
              ActivityLogParser.parseCodex(
                $0, fileKey: file.url.lastPathComponent, fallbackProject: "codex")
            })
        }
      }
      return Array(merged.values)
    }.value
  }

  private struct LogFile {
    let url: URL
    let modified: Date
    let size: Int
  }

  private func files(under root: URL, since: Date) -> [LogFile] {
    let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
    guard
      let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
    else { return [] }

    var result: [LogFile] = []
    for case let url as URL in enumerator where url.pathExtension == "jsonl" {
      guard let values = try? url.resourceValues(forKeys: Set(keys)),
        values.isRegularFile == true,
        let modified = values.contentModificationDate, modified >= since
      else { continue }
      result.append(LogFile(url: url, modified: modified, size: values.fileSize ?? 0))
    }
    return result
  }

  private func load(_ file: LogFile, parse: (Data) -> [ActivityRecord]) -> [ActivityRecord] {
    let path = file.url.path
    lock.lock()
    let hit = cache[path]
    lock.unlock()
    if let hit, hit.modified == file.modified, hit.size == file.size { return hit.records }

    guard let data = try? Data(contentsOf: file.url, options: .mappedIfSafe) else { return [] }
    let records = parse(data)
    lock.lock()
    cache[path] = Cached(modified: file.modified, size: file.size, records: records)
    lock.unlock()
    return records
  }
}

/// `--activity-sample` : quelques jours d'activité fixes, pour vérifier la section sans lire les
/// journaux de la machine.
struct MockAgentActivityProvider: AgentActivityProviding {

  func records(since: Date) async -> [ActivityRecord] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let samples: [(ActivityAgent, String, String, Int, Int)] = [
      (.claudeCode, "claude-opus-5-5", "whoa-stash", 90_000, 40_000),
      (.claudeCode, "claude-sonnet-5-5", "whoa-stash", 60_000, 25_000),
      (.claudeCode, "claude-haiku-5-5", "claude-kit", 30_000, 8_000),
      (.codex, "gpt-5-codex", "api", 50_000, 20_000),
    ]
    var records: [ActivityRecord] = []
    for dayOffset in stride(from: 0, through: 40, by: 3) {
      guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
      for (index, sample) in samples.enumerated() {
        let scale = 1 + dayOffset % 5
        records.append(
          ActivityRecord(
            key: "mock|\(dayOffset)|\(index)", date: day.addingTimeInterval(3600 * 10),
            agent: sample.0, model: sample.1, project: sample.2,
            tokens: TokenCounts(
              input: sample.3 * scale / 3, output: sample.4 * scale / 3, cacheRead: sample.3 * scale
            )))
      }
    }
    return records
  }

  static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments)
    -> MockAgentActivityProvider?
  {
    arguments.contains("--activity-sample") ? MockAgentActivityProvider() : nil
  }
}
