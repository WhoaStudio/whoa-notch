import Carbon.HIToolbox
import Foundation
import OSLog

/// Enregistre le raccourci global auprès du système et appelle `onTrigger` quand il est frappé.
///
/// Passe par `RegisterEventHotKey` (Carbon) et non par `NSEvent.addGlobalMonitorForEvents` :
/// un moniteur global exige l'autorisation de surveillance de la saisie, un hot key enregistré
/// n'exige rien. C'est aussi lui qui fait que la combinaison est réservée — macOS ne la livre
/// plus à l'app de premier plan tant qu'on la détient.
@MainActor
final class GlobalShortcutService {

  static let shared = GlobalShortcutService()
  /// Raccourci du dock personnalisé : un second hot key, avec sa propre identité.
  static let dock = GlobalShortcutService(hotKeyID: 0x5748_4F42)  // 'WHOB'

  /// Appelé sur la boucle principale à chaque frappe du raccourci enregistré.
  var onTrigger: (() -> Void)?

  private var hotKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?
  private var currentKeyCode: UInt32?
  private var currentModifiers: UInt32 = 0

  /// Identifiant arbitraire mais stable : un seul raccourci est détenu par service, et c'est lui
  /// qu'on reconnaît dans le handler.
  private let hotKeyID: UInt32

  private init(hotKeyID: UInt32 = 0x5748_4F41) {  // 'WHOA'
    self.hotKeyID = hotKeyID
  }

  /// Idempotent : réappliquer le même raccourci ne déséenregistre rien. Appelé à chaque
  /// changement du réglage, donc il doit être sûr à répétition.
  func apply(_ shortcut: GlobalShortcut) {
    apply(
      keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers, name: shortcut.displayName)
  }

  /// Raccourci libre (touche + modificateurs Carbon) : `nil` ou sans modificateur = désactivé.
  func apply(keyCode: UInt32?, modifiers: UInt32, name: String) {
    let next = (keyCode != nil && modifiers != 0) ? keyCode : nil
    guard next != currentKeyCode || modifiers != currentModifiers else { return }
    currentKeyCode = next
    currentModifiers = modifiers

    unregisterHotKey()
    guard let keyCode = next else {
      Log.settings.info("raccourci global désactivé")
      return
    }

    installHandlerIfNeeded()

    let id = EventHotKeyID(signature: OSType(hotKeyID), id: hotKeyID)
    let status = RegisterEventHotKey(
      keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)

    if status == noErr {
      Log.settings.info("raccourci global enregistré → \(name, privacy: .public)")
    } else {
      // Le plus souvent : la combinaison est déjà détenue par le système ou une autre app.
      hotKeyRef = nil
      Log.settings.error(
        "échec de l'enregistrement du raccourci \(name, privacy: .public) — code \(status, privacy: .public)"
      )
    }
  }

  private func unregisterHotKey() {
    guard let hotKeyRef else { return }
    UnregisterEventHotKey(hotKeyRef)
    self.hotKeyRef = nil
  }

  /// Le handler Carbon est posé une seule fois pour la durée de vie du service : seul le hot
  /// key lui-même est enregistré et retiré au fil des changements de réglage.
  private func installHandlerIfNeeded() {
    guard handlerRef == nil else { return }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    // Le callback est une fonction C : il ne capture rien et retrouve son service par `userData`.
    let callback: EventHandlerUPP = { _, event, userData in
      var id = EventHotKeyID()
      let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
      )
      guard status == noErr, let userData else { return OSStatus(eventNotHandledErr) }
      let service = Unmanaged<GlobalShortcutService>.fromOpaque(userData).takeUnretainedValue()
      return MainActor.assumeIsolated {
        guard id.id == service.hotKeyID else { return OSStatus(eventNotHandledErr) }
        service.onTrigger?()
        return noErr
      }
    }

    InstallEventHandler(
      GetApplicationEventTarget(), callback, 1, &eventType,
      Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
  }
}
