import AppKit
import ApplicationServices

/// Enveloppe l'API Accessibility (`AXIsProcessTrusted`) et l'ouverture du panneau Réglages
/// Système correspondant — jamais appelées directement depuis une vue.
final class AccessibilityPermissionService {

  static let shared = AccessibilityPermissionService()

  var isTrusted: Bool { AXIsProcessTrusted() }

  /// Affiche l'invite système de permission Accessibilité si elle n'est pas déjà accordée.
  func requestAccess() {
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  }

  func openSystemSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    else { return }
    NSWorkspace.shared.open(url)
  }
}
