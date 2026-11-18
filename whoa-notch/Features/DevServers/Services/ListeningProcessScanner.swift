import Darwin
import Foundation
import os

/// Liste les processus à l'écoute avec `lsof`, puis lit pour chacun son dossier courant
/// (`proc_pidinfo`), sa ligne de commande (`sysctl KERN_PROCARGS2`) et son groupe de processus.
/// Tout est en lecture seule, et ne voit que les processus de l'utilisateur.
nonisolated struct ListeningProcessScanner: ListeningProcessProviding {

  func detectedServers(actionGroups: [Int32: String]) async -> [DetectedServerGroup] {
    await Task.detached(priority: .utility) {
      DevServerClassifier.group(
        Self.scan(), home: NSHomeDirectory(), actionGroups: actionGroups)
    }.value
  }

  private static func scan() -> [ListeningProcess] {
    guard let output = runLsof() else { return [] }
    return DevServerClassifier.parseLsof(output).map { entry in
      ListeningProcess(
        pid: entry.pid, name: entry.name, ports: entry.ports, cwd: currentDirectory(of: entry.pid),
        arguments: arguments(of: entry.pid), groupLeader: groupLeader(of: entry.pid))
    }
  }

  private static func runLsof() -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      Log.devServers.error("lsof impossible à lancer : \(error.localizedDescription, privacy: .public)")
      return nil
    }
    // Lire avant d'attendre : une sortie plus grande que le tube bloquerait `lsof`.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
  }

  private static func currentDirectory(of pid: Int32) -> String? {
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
    let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { buffer in
      String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
    return path.isEmpty ? nil : path
  }

  /// `argv` d'un processus : un entier (`argc`), le chemin du programme, des zéros de bourrage,
  /// puis les `argc` arguments séparés par des zéros.
  private static func arguments(of pid: Int32) -> [String] {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
    let count = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
    var index = MemoryLayout<Int32>.size
    while index < size, buffer[index] != 0 { index += 1 }
    while index < size, buffer[index] == 0 { index += 1 }
    var result: [String] = []
    while result.count < count, index < size {
      var end = index
      while end < size, buffer[end] != 0 { end += 1 }
      result.append(String(decoding: buffer[index..<end], as: UTF8.self))
      index = end + 1
    }
    return result
  }

  private static func groupLeader(of pid: Int32) -> Int32? {
    let group = getpgid(pid)
    return group > 0 ? group : nil
  }
}
