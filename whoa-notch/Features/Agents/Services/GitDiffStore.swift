import Foundation

/// Garde les diffs déjà calculés, un par fichier, et ne lance git qu'à la première demande.
///
/// Une entrée est valable tant que le fichier garde la même date et la même taille, et 30 s au
/// plus : un commit fait dans le terminal ne change pas le fichier, mais change son diff.
final class GitDiffStore {

  /// L'instance de l'app : la source réelle, ou les diffs fixes de `--git-diff=sample`.
  static let shared = GitDiffStore(
    provider: MockGitDiffProvider.fromLaunchArguments() ?? GitDiffService())

  private struct Entry {
    var result: GitDiffResult
    var date: Date
  }

  private let provider: GitDiffProviding
  private let capacity: Int
  private let lifetime: TimeInterval
  private var entries: [String: Entry] = [:]
  /// Du plus ancien au plus récent, pour retirer le plus ancien quand la mémoire est pleine.
  private var order: [String] = []
  private var inFlight: [String: Task<GitDiffResult, Never>] = [:]

  init(provider: GitDiffProviding, capacity: Int = 40, lifetime: TimeInterval = 30) {
    self.provider = provider
    self.capacity = capacity
    self.lifetime = lifetime
  }

  /// Le diff du fichier : celui qu'on a déjà, sinon celui qu'on est en train de calculer, sinon un nouveau.
  func diff(for target: DiffTarget, now: Date = Date()) async -> GitDiffResult {
    let key = Self.key(for: target)
    if let entry = entries[key], now.timeIntervalSince(entry.date) < lifetime {
      return entry.result
    }
    if let task = inFlight[key] { return await task.value }

    let provider = provider
    let task = Task { await provider.diff(for: target) }
    inFlight[key] = task
    let result = await task.value
    inFlight[key] = nil
    store(result, for: key, at: now)
    return result
  }

  /// Le diff déjà en mémoire, sans rien lancer.
  func cached(for target: DiffTarget, now: Date = Date()) -> GitDiffResult? {
    guard let entry = entries[Self.key(for: target)], now.timeIntervalSince(entry.date) < lifetime
    else { return nil }
    return entry.result
  }

  private func store(_ result: GitDiffResult, for key: String, at date: Date) {
    entries[key] = Entry(result: result, date: date)
    order.removeAll { $0 == key }
    order.append(key)
    while order.count > capacity { entries[order.removeFirst()] = nil }
  }

  /// Le chemin, la date de modification et la taille : un fichier réécrit a une autre clé.
  private static func key(for target: DiffTarget) -> String {
    let attributes = try? FileManager.default.attributesOfItem(atPath: target.path)
    let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let size = (attributes?[.size] as? NSNumber)?.intValue ?? -1
    return "\(target.path)|\(date)|\(size)"
  }
}
