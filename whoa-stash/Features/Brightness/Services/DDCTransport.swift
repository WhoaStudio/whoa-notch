import CoreGraphics
import Foundation
import IOKit
import OSLog

/// Ligne I2C d'un écran externe, telle que l'expose `IOAVService` — l'interface privée
/// d'`IOKit` par laquelle passe le DDC/CI sur Apple Silicon. Aucun en-tête public ne la
/// déclare : on la charge par `dlopen`/`dlsym`, exactement comme
/// `DisplayServicesBackend` charge DisplayServices, pour qu'un symbole disparu dégrade la
/// fonctionnalité au lieu d'empêcher l'app de se lancer.
///
/// Rien ici ne touche au main actor : les transactions sont bloquantes (quelques dizaines de
/// millisecondes d'`usleep`) et c'est `DDCBus` qui les sérialise hors de lui.
nonisolated struct IOAVServiceSymbols {

  /// `IOAVServiceCreateWithService` suit la Create Rule : la référence rendue est à nous.
  typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
  typealias ReadFn =
    @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
  typealias WriteFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeRawPointer, UInt32) -> Int32

  let create: CreateFn
  let read: ReadFn
  let write: WriteFn

  /// `nil` dès qu'un des trois symboles manque — sur un Mac Intel, notamment, où le DDC
  /// passait par `IOFramebuffer`/`IOI2CSendRequest` et non par `IOAVService`.
  static let shared: IOAVServiceSymbols? = load()

  private static func load() -> IOAVServiceSymbols? {
    guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
      Log.brightness.error("impossible de charger IOKit.framework — pas de DDC/CI")
      return nil
    }

    guard
      let createSymbol = dlsym(handle, "IOAVServiceCreateWithService"),
      let readSymbol = dlsym(handle, "IOAVServiceReadI2C"),
      let writeSymbol = dlsym(handle, "IOAVServiceWriteI2C")
    else {
      // Attendu sur Intel, et possible après une mise à jour de macOS : les écrans
      // externes resteront simplement non pilotables.
      Log.brightness.info(
        "IOAVService indisponible — les écrans externes ne seront pas pilotables en DDC/CI")
      return nil
    }

    return IOAVServiceSymbols(
      create: unsafeBitCast(createSymbol, to: CreateFn.self),
      read: unsafeBitCast(readSymbol, to: ReadFn.self),
      write: unsafeBitCast(writeSymbol, to: WriteFn.self)
    )
  }
}

/// Référence à l'`IOAVService` d'un écran. `CFTypeRef` n'est pas `Sendable` et le service doit
/// pourtant traverser la frontière vers `DDCBus` : la boîte porte cette garantie à la main.
/// Elle tient parce qu'un service n'est jamais touché que depuis `DDCBus`, qui sérialise tout.
nonisolated final class AVServiceHandle: @unchecked Sendable {
  let service: CFTypeRef

  init(service: CFTypeRef) {
    self.service = service
  }
}

/// Encodage DDC/CI (MCCS) sur la ligne I2C : les trames, leurs sommes de contrôle et les
/// temporisations que les écrans exigent entre deux transactions.
///
/// Les constantes viennent des implémentations de référence (`waydabber/AppleSiliconDDC`,
/// `MonitorControl/Arm64DDC.swift`) : un écran DDC/CI ne tolère ni une trame mal cadencée ni
/// une somme de contrôle fausse, et répond alors par du silence plutôt que par une erreur.
nonisolated enum DDC {

  /// Adresse I2C du contrôleur DDC de l'écran, et registre par lequel passent les trames.
  static let chipAddress: UInt32 = 0x37
  static let dataAddress: UInt32 = 0x51

  /// Code VCP de la luminosité (MCCS « Luminance »).
  static let luminanceVCP: UInt8 = 0x10

  /// Deux écritures par tentative : la première trame est régulièrement perdue, et un écran
  /// qui reçoit deux fois la même consigne la traite deux fois sans dommage.
  static let writeCycles = 2
  static let writeSleep: UInt32 = 10_000
  static let retrySleep: UInt32 = 20_000
  static let readSleep: UInt32 = 50_000
  static let retries = 4

  /// Intervalle minimal entre deux consignes envoyées au *même* écran. Certains moniteurs
  /// ignorent purement et simplement une écriture qui suit la précédente de trop près (un LG
  /// connu reste sourd pendant près de 200 ms). Le cache absorbe l'attente : le widget suit
  /// la molette sans que le bus la suive au même rythme.
  static let minimumWriteInterval: Duration = .milliseconds(200)

  /// Opérations MCCS utilisées ici. Les implémentations de référence font porter ce même
  /// octet par la *longueur* de la charge utile — qui vaut 3 pour une écriture et 1 pour une
  /// lecture, donc exactement `setVCP` et `getVCP`. La coïncidence tient pour ces deux
  /// trames et pour elles seules : on l'écrit explicitement pour qu'une troisième opération
  /// ne vienne pas s'y casser.
  private enum Opcode: UInt8 {
    case getVCP = 0x01
    case setVCP = 0x03
  }

  /// Trame d'écriture d'un code VCP : `0x84 0x03 <vcp> <haut> <bas> <somme>`.
  static func writePacket(vcp: UInt8, value: UInt16) -> [UInt8] {
    packet(opcode: .setVCP, body: [vcp, UInt8(value >> 8), UInt8(value & 0xFF)])
  }

  /// Trame de *demande* de lecture : `0x82 0x01 <vcp> <somme>`. La réponse se lit ensuite sur
  /// le même registre, après `readSleep`.
  static func readRequestPacket(vcp: UInt8) -> [UInt8] {
    packet(opcode: .getVCP, body: [vcp])
  }

  private static func packet(opcode: Opcode, body: [UInt8]) -> [UInt8] {
    let message = [opcode.rawValue] + body
    var packet: [UInt8] = [0x80 | UInt8(message.count)]
    packet.append(contentsOf: message)

    // La somme de contrôle porte sur ce que l'écran voit réellement passer : son adresse de
    // destination (`chipAddress` décalée), l'adresse source `0x51`, puis la trame.
    //
    // Écart assumé avec les implémentations de référence (`Arm64DDC`, `AppleSiliconDDC`),
    // qui omettent `0x51` sur la demande de *lecture* : la spécification DDC/CI l'inclut
    // dans les deux sens — `6E ^ 51 ^ 82 ^ 01 ^ 10` vaut `0xAC`, la valeur que publient le
    // standard et `ddcutil`. Un écran qui ne vérifie pas la somme accepte les deux ; un
    // écran qui la vérifie n'accepte que celle-ci.
    var checksum = UInt8(chipAddress << 1) ^ UInt8(dataAddress)
    for byte in packet {
      checksum ^= byte
    }

    packet.append(checksum)
    return packet
  }

  /// Décode la réponse de 11 octets à une demande de lecture : valeur courante et maximum
  /// annoncé par l'écran. `nil` si la somme de contrôle ne tombe pas juste — une réponse
  /// tronquée ou brouillée vaut mieux jetée qu'interprétée.
  static func decodeReply(_ reply: [UInt8]) -> (current: UInt16, max: UInt16)? {
    guard reply.count == 11 else { return nil }

    var checksum: UInt8 = 0x50
    for byte in reply[0..<10] {
      checksum ^= byte
    }
    guard checksum == reply[10] else { return nil }

    let max = UInt16(reply[6]) << 8 | UInt16(reply[7])
    let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
    guard max > 0 else { return nil }
    return (current, max)
  }
}
