import AppKit
import CoreGraphics
import Foundation
import IOKit
import OSLog

/// Associe un `CGDirectDisplayID` à la ligne I2C de l'écran correspondant.
///
/// C'est la partie fragile du DDC/CI sur Apple Silicon : l'`IORegistry` ne donne nulle part
/// l'identifiant `CGDirectDisplayID` à côté du service I2C, et il faut donc rapprocher les deux
/// par ce qu'ils décrivent du même écran — fabricant, modèle, numéro de série.
///
/// La recette suit celle des implémentations de référence :
/// 1. parcourir le plan `IOService` dans l'ordre de l'arbre ;
/// 2. retenir au passage les attributs du dernier nœud de framebuffer rencontré
///    (`IOMobileFramebufferShim`, ou `AppleCLCD2` sur les machines plus anciennes) ;
/// 3. à chaque `DCPAVServiceProxy` dont `Location` vaut `External`, ouvrir un `IOAVService` et
///    l'apparier aux attributs retenus — les deux nœuds d'un même port sont voisins dans
///    l'arbre.
///
/// Le parcours est synchrone et ne fait aucune entrée/sortie I2C : quelques millisecondes, et
/// seulement quand la configuration d'écrans change. Seules les transactions DDC elles-mêmes
/// sont renvoyées hors du main actor, par `DDCBus`.
final class AVServiceLocator {

  /// Attributs qu'un nœud de framebuffer publie sur l'écran qu'il pilote. Tous optionnels :
  /// un écran branché sur un dock n'en remplit parfois aucun.
  private struct DisplayIdentity {
    var vendorID: UInt32?
    var productID: UInt32?
    var serialNumber: UInt32?
  }

  private struct Candidate {
    let identity: DisplayIdentity
    let handle: AVServiceHandle
  }

  private var services: [CGDirectDisplayID: AVServiceHandle]?
  private var screenObserver: NSObjectProtocol?

  init() {
    // Un écran branché ou débranché renumérote les services : la carte entière est à
    // refaire, et c'est la seule chose qui l'invalide.
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.invalidate() }
    }
  }

  func invalidate() {
    services = nil
  }

  /// Ligne I2C de cet écran, ou `nil` s'il n'en a pas : écran interne, écran Apple piloté
  /// autrement, dock qui ne relaie pas le DDC, ou Mac Intel.
  func service(for displayID: CGDirectDisplayID) -> AVServiceHandle? {
    if services == nil {
      services = discover()
    }
    return services?[displayID]
  }

  // MARK: - Parcours de l'IORegistry

  private func discover() -> [CGDirectDisplayID: AVServiceHandle] {
    guard let symbols = IOAVServiceSymbols.shared else { return [:] }

    var iterator = io_iterator_t()
    guard
      IORegistryCreateIterator(
        kIOMainPortDefault,
        kIOServicePlane,
        IOOptionBits(kIORegistryIterateRecursively),
        &iterator
      ) == KERN_SUCCESS
    else {
      Log.brightness.error("parcours de l'IORegistry impossible — pas de DDC/CI")
      return [:]
    }
    defer { IOObjectRelease(iterator) }

    var candidates: [Candidate] = []
    var pendingIdentity = DisplayIdentity()

    while case let entry = IOIteratorNext(iterator), entry != MACH_PORT_NULL {
      defer { IOObjectRelease(entry) }

      guard let name = entryName(entry) else { continue }

      if name.contains("IOMobileFramebufferShim") || name.contains("AppleCLCD2") {
        pendingIdentity = identity(of: entry)
        continue
      }

      guard name.contains("DCPAVServiceProxy"),
        property(entry, "Location") as? String == "External"
      else { continue }

      guard let created = symbols.create(kCFAllocatorDefault, entry)?.takeRetainedValue() else {
        continue
      }

      candidates.append(
        Candidate(identity: pendingIdentity, handle: AVServiceHandle(service: created)))
      pendingIdentity = DisplayIdentity()
    }

    return pair(candidates: candidates)
  }

  private func entryName(_ entry: io_registry_entry_t) -> String? {
    // Taille d'un `io_name_t`, que Swift n'expose pas comme constante.
    var buffer = [CChar](repeating: 0, count: 128)
    guard IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS else { return nil }
    return String(cString: buffer)
  }

  private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue()
  }

  /// `DisplayAttributes` → `ProductAttributes`, où l'écran se décrit lui-même.
  /// `LegacyManufacturerID` est l'identifiant fabricant de l'EDID, celui que renvoie
  /// `CGDisplayVendorNumber` — c'est ce qui rend les deux côtés comparables.
  private func identity(of entry: io_registry_entry_t) -> DisplayIdentity {
    guard
      let attributes = property(entry, "DisplayAttributes") as? [String: Any],
      let product = attributes["ProductAttributes"] as? [String: Any]
    else { return DisplayIdentity() }

    return DisplayIdentity(
      vendorID: (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value,
      productID: (product["ProductID"] as? NSNumber)?.uint32Value,
      serialNumber: (product["SerialNumber"] as? NSNumber)?.uint32Value
    )
  }

  // MARK: - Appariement

  private func pair(candidates: [Candidate]) -> [CGDirectDisplayID: AVServiceHandle] {
    let externals = onlineExternalDisplays()
    guard !externals.isEmpty, !candidates.isEmpty else { return [:] }

    // Cas de loin le plus courant — un seul écran externe, un seul service : les attributs
    // ne peuvent rien désambiguïser, et un écran sur dock n'en publie parfois aucun.
    if externals.count == 1, candidates.count == 1 {
      return [externals[0]: candidates[0].handle]
    }

    var result: [CGDirectDisplayID: AVServiceHandle] = [:]
    var claimed = Set<Int>()

    for displayID in externals {
      let wanted = DisplayIdentity(
        vendorID: CGDisplayVendorNumber(displayID),
        productID: CGDisplayModelNumber(displayID),
        serialNumber: CGDisplaySerialNumber(displayID)
      )

      let best = candidates.enumerated()
        .filter { !claimed.contains($0.offset) }
        .map { ($0.offset, score(candidate: $0.element.identity, against: wanted)) }
        .filter { $0.1 >= 2 }
        .max { $0.1 < $1.1 }

      guard let best else {
        Log.brightness.info("aucun service I2C apparié à l'écran \(displayID, privacy: .public)")
        continue
      }

      claimed.insert(best.0)
      result[displayID] = candidates[best.0].handle
    }

    return result
  }

  /// Le numéro de série pèse double : c'est la seule chose qui distingue deux écrans du même
  /// modèle. Fabricant et modèle seuls suffisent dès qu'il n'y en a qu'un de ce modèle.
  private func score(candidate: DisplayIdentity, against wanted: DisplayIdentity) -> Int {
    var score = 0
    if let a = candidate.vendorID, let b = wanted.vendorID, a == b { score += 1 }
    if let a = candidate.productID, let b = wanted.productID, a == b { score += 1 }
    if let a = candidate.serialNumber, let b = wanted.serialNumber, a == b, a != 0 { score += 2 }
    return score
  }

  private func onlineExternalDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }

    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }

    // Un écran en miroir n'a pas de ligne I2C propre, et l'écran interne ne passe pas par
    // le DDC du tout.
    return ids.filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayIsInMirrorSet($0) == 0 }
  }
}
