import Foundation
import os

/// Nombre de doigts posés sur le trackpad, lu par `MultitouchSupport.framework`.
///
/// macOS n'expose aucun événement « clic à trois doigts » : seul ce framework privé, chargé par
/// `dlopen` comme les symboles DDC, donne le nombre de contacts à chaque image. S'il manque
/// (autre version de macOS), le compteur reste à 0 et le déclencheur ne fait simplement rien.
nonisolated final class MultitouchFingerCounter: @unchecked Sendable {

  nonisolated static let shared = MultitouchFingerCounter()

  private typealias ContactCallback =
    @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) ->
    Int32
  private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
  private typealias Register = @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
  private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void

  /// Doigts par appareil : un trackpad et une Magic Mouse émettent chacun leurs images.
  private let perDevice = OSAllocatedUnfairLock(initialState: [UInt: Int]())
  private let startLock = OSAllocatedUnfairLock(initialState: false)
  private var devices: CFArray?

  /// Appelé, depuis un thread d'arrière-plan, quand le nombre de doigts change.
  nonisolated var onChange: (@Sendable (Int) -> Void)? {
    get { changeHandler.withLock { $0 } }
    set { changeHandler.withLock { $0 = newValue } }
  }
  private let changeHandler = OSAllocatedUnfairLock<(@Sendable (Int) -> Void)?>(initialState: nil)

  /// Le plus grand nombre de doigts vu sur un appareil.
  nonisolated var fingers: Int { perDevice.withLock { $0.values.max() ?? 0 } }

  nonisolated func start() {
    let alreadyStarted = startLock.withLock { started -> Bool in
      defer { started = true }
      return started
    }
    guard !alreadyStarted else { return }

    guard
      let handle = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY
      ),
      let createSymbol = dlsym(handle, "MTDeviceCreateList"),
      let registerSymbol = dlsym(handle, "MTRegisterContactFrameCallback"),
      let startSymbol = dlsym(handle, "MTDeviceStart")
    else {
      Log.radialMenu.error("MultitouchSupport indisponible : clic à trois doigts inactif")
      return
    }
    let createList = unsafeBitCast(createSymbol, to: CreateList.self)
    let register = unsafeBitCast(registerSymbol, to: Register.self)
    let startDevice = unsafeBitCast(startSymbol, to: Start.self)

    guard let list = createList()?.takeRetainedValue() else { return }
    devices = list
    let callback: ContactCallback = { device, _, count, _, _ in
      let key = UInt(bitPattern: device)
      let counter = MultitouchFingerCounter.shared
      let (before, after) = counter.perDevice.withLock { fingers -> (Int, Int) in
        let before = fingers.values.max() ?? 0
        fingers[key] = Int(count)
        return (before, fingers.values.max() ?? 0)
      }
      if before != after { counter.onChange?(after) }
      return 0
    }
    for index in 0..<CFArrayGetCount(list) {
      guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
      let pointer = UnsafeMutableRawPointer(mutating: device)
      register(pointer, callback)
      startDevice(pointer, 0)
    }
    Log.radialMenu.info(
      "lecture des doigts démarrée (\(CFArrayGetCount(list), privacy: .public) appareils)")
  }
}
