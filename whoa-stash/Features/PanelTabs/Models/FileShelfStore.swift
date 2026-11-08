import Foundation
import OSLog

/// Les fichiers posés dans l'onglet Tray, et leur persistance.
///
/// Le bac vit **hors** de la vue : le panneau de l'encoche se replie, se déplie et change
/// d'onglet sans arrêt, et ce qu'on y a déposé ne doit pas disparaître avec la vue qui
/// l'affichait. `FileTrayView` n'en est plus qu'une lecture.
///
/// Les fichiers sont déplacés dans le dossier du bac, puis conservés sous forme de *signets*
/// (`URL` bookmarkData), qui suivent un fichier renommé ou déplacé — un simple chemin ne le ferait
/// pas.
/// Le fichier effacé entre deux lancements laisse un signet qui ne se résout plus : il est
/// retiré en silence au chargement, plutôt que de laisser une ligne qui ne mène nulle part.
///
/// L'app n'est pas en bac à sable (`ENABLE_APP_SANDBOX = NO`), donc pas de signet à portée
/// restreinte ni de `startAccessingSecurityScopedResource` à tenir ouvert.
@MainActor
final class FileShelfStore {

  static let shared = FileShelfStore()

  /// Émise après chaque ajout ou retrait, y compris celui qui vide le bac. Les vues
  /// s'abonnent plutôt que d'être tenues par le store : il y a une `FileTrayView` par écran,
  /// et elles vont et viennent avec les fenêtres.
  static let didChangeNotification = Notification.Name("FileShelfStore.didChange")

  private static let defaultsKey = "com.whoastudio.whoa-stash.fileShelf"

  /// Au-delà, les derniers déposés chassent les premiers : la zone n'a de place que pour
  /// quelques lignes et ne défile pas encore. C'est donc bien le bac qui est borné, pas son
  /// affichage.
  static let capacity = 4

  private let fileManager: FileManager
  private let trayDirectory: URL

  /// Fichiers retenus, dans l'ordre où ils ont été déposés — le dernier en fin de liste.
  private(set) var urls: [URL] = []

  /// Vrai le temps qu'un fichier soit glissé *hors* du bac. Le panneau de l'encoche se replie
  /// dès que le curseur le quitte : `NotchPanelController` gèle ce suivi tant que ce drapeau
  /// est levé, sans quoi le bac se refermerait sous la main qui en sort un fichier.
  var isDraggingOut = false

  private let defaults: UserDefaults

  init(
    defaults: UserDefaults = .standard,
    fileManager: FileManager = .default,
    trayDirectory: URL? = nil
  ) {
    self.defaults = defaults
    self.fileManager = fileManager
    self.trayDirectory = trayDirectory ?? Self.defaultTrayDirectory(fileManager: fileManager)
    urls = Self.load(from: defaults)
  }

  var isEmpty: Bool { urls.isEmpty }

  /// Déplace les fichiers dans le dossier du bac et les ajoute en fin de liste. Un fichier déjà
  /// présent ne fait pas deux lignes : il remonte simplement là où l'utilisateur vient de le
  /// poser. Les fichiers impossibles à déplacer sont ignorés et journalisés.
  @discardableResult
  func add(_ added: [URL]) -> [URL] {
    guard !added.isEmpty else { return [] }

    var moved: [URL] = []
    for source in added {
      guard let destination = moveToTray(source) else { continue }
      moved.append(destination)
    }

    guard !moved.isEmpty else { return [] }
    urls.removeAll { moved.contains($0) }
    urls.append(contentsOf: moved)
    if urls.count > Self.capacity {
      urls.removeFirst(urls.count - Self.capacity)
    }
    commit()
    return moved
  }

  /// Convertit une image du bac dans un autre format et range le résultat dans le bac.
  @discardableResult
  func addConverted(from source: URL, to format: ImageFormat) -> URL? {
    addTransformed(from: source, options: ImageTransformOptions(format: format), suffix: "")
  }

  /// Réécrit une image du bac avec `options` sous un nom libre — `suffix` s'ajoute au nom, et
  /// l'extension suit le format de sortie. Le résultat est rangé dans le bac, à côté de
  /// l'original, qui n'est jamais modifié ; avec `directory`, il est écrit là et reste hors du
  /// bac. Renvoie le nouveau fichier, ou `nil` si l'écriture échoue (journalisée).
  @discardableResult
  func addTransformed(
    from source: URL,
    options: ImageTransformOptions,
    suffix: String,
    in directory: URL? = nil
  ) -> URL? {
    let source = source.standardizedFileURL
    let target = directory ?? trayDirectory
    let name = source.deletingPathExtension().lastPathComponent + suffix
    let destination = uniqueDestination(
      for: target.appendingPathComponent(name).appendingPathExtension(options.format.fileExtension),
      in: target
    )
    do {
      try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
      try ImageFormatConverter.write(source, options: options, at: destination)
    } catch {
      Log.sidePanel.error(
        "Transformation d'image impossible : \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
    let written = destination.standardizedFileURL
    guard directory == nil else { return written }
    urls.append(written)
    if urls.count > Self.capacity {
      urls.removeFirst(urls.count - Self.capacity)
    }
    commit()
    return written
  }

  /// Retire un fichier du bac — appelé quand un glisser vers le Finder ou une autre app a
  /// abouti, jamais quand il a été annulé.
  func remove(_ url: URL) {
    guard urls.contains(url) else { return }
    urls.removeAll { $0 == url }
    commit()
  }

  private func commit() {
    persist()
    NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
  }

  // MARK: - Persistance

  private func persist() {
    let bookmarks = urls.compactMap { url -> Data? in
      do {
        return try url.bookmarkData()
      } catch {
        Log.sidePanel.error(
          "File shelf bookmark failed: \(error.localizedDescription, privacy: .public)")
        return nil
      }
    }
    defaults.set(bookmarks, forKey: Self.defaultsKey)
  }

  private func moveToTray(_ source: URL) -> URL? {
    let source = source.standardizedFileURL
    guard fileManager.fileExists(atPath: source.path) else {
      Log.sidePanel.error(
        "File shelf move source does not exist: \(source.path, privacy: .private)")
      return nil
    }

    do {
      try fileManager.createDirectory(at: trayDirectory, withIntermediateDirectories: true)
      if isInsideTray(source) {
        return source
      }
      let destination = uniqueDestination(for: source)
      try fileManager.moveItem(at: source, to: destination)
      return destination.standardizedFileURL
    } catch {
      Log.sidePanel.error(
        "File shelf move failed for \(source.path, privacy: .private): \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }

  private func isInsideTray(_ url: URL) -> Bool {
    let sourcePath = url.standardizedFileURL.path
    let trayPath = trayDirectory.standardizedFileURL.path
    return sourcePath == trayPath || sourcePath.hasPrefix(trayPath + "/")
  }

  private func uniqueDestination(for source: URL, in directory: URL? = nil) -> URL {
    let directory = directory ?? trayDirectory
    let baseName = source.deletingPathExtension().lastPathComponent
    let ext = source.pathExtension
    var candidate = directory.appendingPathComponent(source.lastPathComponent)
    var index = 2

    while fileManager.fileExists(atPath: candidate.path) {
      let name = ext.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(ext)"
      candidate = directory.appendingPathComponent(name)
      index += 1
    }
    return candidate
  }

  private static func defaultTrayDirectory(fileManager: FileManager) -> URL {
    let applicationSupport = fileManager.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return
      applicationSupport
      .appendingPathComponent("whoa-stash", isDirectory: true)
      .appendingPathComponent("Tray", isDirectory: true)
  }

  /// Résout les signets du lancement précédent et laisse tomber ceux dont le fichier n'est
  /// plus là. Un signet « périmé » (`isStale`) désigne un fichier qui a bougé : il se résout
  /// quand même, et la prochaine écriture le remplacera par un signet à jour.
  private static func load(from defaults: UserDefaults) -> [URL] {
    guard let bookmarks = defaults.array(forKey: defaultsKey) as? [Data] else { return [] }

    return bookmarks.compactMap { data in
      var isStale = false
      guard
        let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale),
        FileManager.default.fileExists(atPath: url.path)
      else { return nil }
      return url.standardizedFileURL
    }
  }
}
