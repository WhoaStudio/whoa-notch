import AppKit
import CoreGraphics
import Foundation
import OSLog

/// Sérialise les transactions DDC/CI hors du main actor.
///
/// Un bus I2C ne supporte qu'une transaction à la fois, et chacune dort quelques dizaines de
/// millisecondes : c'est exactement ce qu'un `actor` garantit, sans file ni verrou à tenir.
actor DDCBus {

  /// Écrit un code VCP. `false` si l'écran n'a jamais accusé réception, après toutes les
  /// tentatives — un écran qui ignore le DDC/CI, ou un dock qui ne le relaie pas.
  func write(vcp: UInt8, value: UInt16, to handle: AVServiceHandle) -> Bool {
    guard let symbols = IOAVServiceSymbols.shared else { return false }
    let packet = DDC.writePacket(vcp: vcp, value: value)

    for attempt in 0...DDC.retries {
      if attempt > 0 {
        usleep(DDC.retrySleep)
      }
      if send(packet, to: handle, with: symbols) {
        return true
      }
    }
    return false
  }

  /// Lit un code VCP et rend la valeur courante rapportée à son maximum, dans `0...1`.
  /// Le maximum vient de l'écran : beaucoup annoncent 100, certains tout autre chose.
  func readNormalized(vcp: UInt8, from handle: AVServiceHandle) -> Float? {
    guard let symbols = IOAVServiceSymbols.shared else { return nil }
    let request = DDC.readRequestPacket(vcp: vcp)

    for attempt in 0...DDC.retries {
      if attempt > 0 {
        usleep(DDC.retrySleep)
      }

      guard send(request, to: handle, with: symbols) else { continue }

      // L'écran a besoin de ce délai pour préparer sa réponse ; le lire plus tôt
      // ramène les octets de la transaction précédente.
      usleep(DDC.readSleep)

      var reply = [UInt8](repeating: 0, count: 11)
      let status = reply.withUnsafeMutableBytes { buffer -> Int32 in
        guard let base = buffer.baseAddress else { return -1 }
        return symbols.read(
          handle.service,
          DDC.chipAddress,
          DDC.dataAddress,
          base,
          UInt32(buffer.count)
        )
      }

      guard status == 0, let decoded = DDC.decodeReply(reply) else { continue }
      return min(1, max(0, Float(decoded.current) / Float(decoded.max)))
    }

    return nil
  }

  private func send(_ packet: [UInt8], to handle: AVServiceHandle, with symbols: IOAVServiceSymbols)
    -> Bool
  {
    var acknowledged = false

    // Deux cycles : la première trame après un silence est régulièrement perdue, et
    // répéter la même consigne est sans effet de bord côté écran.
    for _ in 0..<DDC.writeCycles {
      usleep(DDC.writeSleep)

      let status = packet.withUnsafeBytes { buffer -> Int32 in
        guard let base = buffer.baseAddress else { return -1 }
        return symbols.write(
          handle.service,
          DDC.chipAddress,
          DDC.dataAddress,
          base,
          UInt32(buffer.count)
        )
      }

      acknowledged = acknowledged || status == 0
    }

    return acknowledged
  }
}

/// Luminosité des écrans **externes**, par DDC/CI.
///
/// Deux écarts assumés par rapport à `DisplayServicesBackend`, imposés par la lenteur du bus
/// (une transaction coûte de 20 à 150 ms, là où DisplayServices est immédiat) :
///
/// - **les écritures sont différées et fusionnées.** Une molette produit des dizaines
///   d'événements par seconde ; les jouer tous sur le bus le saturerait et ferait traîner le
///   widget loin derrière le doigt. Seule la dernière valeur par écran est envoyée, et
///   `setBrightness` rend `true` pour « acceptée », pas pour « appliquée ».
/// - **les lectures passent par un cache.** `brightness(for:)` doit répondre tout de suite,
///   sans bloquer l'affichage du widget : la première interrogation d'un écran rend `nil` et
///   lance la lecture en tâche de fond, les suivantes lisent le cache. L'écriture met le cache
///   à jour d'avance, donc le widget suit la molette sans attendre l'écran.
final class DDCBrightnessBackend: DisplayBrightnessBackend {

  private let bus = DDCBus()
  private let locator = AVServiceLocator()

  /// Dernière valeur connue par écran — celle que l'on vient d'écrire, ou celle que l'écran a
  /// rapportée. Vidé dès que la configuration d'écrans change.
  private var cache: [CGDirectDisplayID: Float] = [:]

  /// Valeur en attente d'écriture, par écran. Écrasée tant que la précédente n'est pas
  /// partie : c'est la fusion des événements de molette.
  private var pending: [CGDirectDisplayID: Float] = [:]
  private var flushTask: Task<Void, Never>?

  /// Écrans dont une lecture est déjà en vol, pour ne pas en lancer une par image.
  private var priming: Set<CGDirectDisplayID> = []

  private var screenObserver: NSObjectProtocol?

  init() {
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.cache.removeAll()
        self?.priming.removeAll()
        self?.primeAll()
      }
    }

    // Le cache est rempli d'avance, pas au premier survol : sans cela, la première
    // apparition du widget sur un écran externe afficherait la valeur par défaut le temps
    // de la lecture, puis sauterait à la vraie.
    primeAll()
  }

  /// `true` si cet écran a une ligne I2C ouverte. C'est ce qui permet à
  /// `RoutingBrightnessBackend` de ne confier au DDC/CI que les écrans qu'il peut piloter.
  func canDrive(_ displayID: CGDirectDisplayID) -> Bool {
    locator.service(for: displayID) != nil
  }

  func brightness(for displayID: CGDirectDisplayID) -> Float? {
    if let cached = cache[displayID] { return cached }
    prime(displayID)
    return nil
  }

  @discardableResult
  func setBrightness(_ value: Float, for displayID: CGDirectDisplayID) -> Bool {
    guard locator.service(for: displayID) != nil else { return false }

    let clamped = min(1, max(0, value))
    cache[displayID] = clamped
    pending[displayID] = clamped
    scheduleFlush()
    return true
  }

  // MARK: - Écriture différée

  private func scheduleFlush() {
    // Une seule tâche de vidage à la fois : elle boucle jusqu'à ce que plus rien n'attende,
    // et prend à chaque tour la *dernière* valeur posée entre-temps.
    guard flushTask == nil else { return }

    flushTask = Task { [weak self] in
      while let next = self?.takeNext() {
        let applied = await self?.bus.write(
          vcp: DDC.luminanceVCP,
          value: UInt16((next.value * 100).rounded()),
          to: next.handle
        )
        if applied == false {
          Log.brightness.info(
            "l'écran \(next.displayID, privacy: .public) n'a pas accusé réception du DDC/CI")
        }
        // Laisse respirer le bus avant la consigne suivante. Pendant cette pause, la
        // molette continue d'écraser `pending` : le tour d'après enverra la valeur la
        // plus récente, pas celle qui attendait ici.
        try? await Task.sleep(for: DDC.minimumWriteInterval)
      }
      self?.flushTask = nil
    }
  }

  private func takeNext() -> (displayID: CGDirectDisplayID, value: Float, handle: AVServiceHandle)?
  {
    guard let (displayID, value) = pending.first else { return nil }
    pending.removeValue(forKey: displayID)
    guard let handle = locator.service(for: displayID) else { return nil }
    return (displayID, value, handle)
  }

  // MARK: - Lecture différée

  /// La valeur réelle de l'écran n'arrive qu'après coup : elle sert au prochain affichage du
  /// widget, pas à celui en cours. Une écriture entre-temps a priorité — c'est la consigne de
  /// l'utilisateur, pas une mesure.
  private func primeAll() {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return }

    for id in ids where CGDisplayIsBuiltin(id) == 0 {
      prime(id)
    }
  }

  private func prime(_ displayID: CGDirectDisplayID) {
    guard !priming.contains(displayID), let handle = locator.service(for: displayID) else { return }
    priming.insert(displayID)

    Task { [weak self] in
      let value = await self?.bus.readNormalized(vcp: DDC.luminanceVCP, from: handle)
      guard let self else { return }
      self.priming.remove(displayID)
      guard let value, self.pending[displayID] == nil, self.cache[displayID] == nil else { return }
      self.cache[displayID] = value
    }
  }
}
