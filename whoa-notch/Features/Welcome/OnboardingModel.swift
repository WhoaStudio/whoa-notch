import AppKit
import Observation

/// Source des autorisations montrées à l'étape « permissions ». Derrière un protocole, comme les
/// autres sources externes, pour qu'on puisse voir l'étape sans toucher aux vraies invites.
@MainActor
protocol OnboardingPermissionProviding {
  func state(for permission: PrivacyPermission) -> PermissionState
  func request(_ permission: PrivacyPermission) async
  func openSettings(_ permission: PrivacyPermission)
}

/// Les vraies autorisations : mêmes lectures et mêmes demandes que Preferences ▸ Privacy.
@MainActor
struct SystemOnboardingPermissions: OnboardingPermissionProviding {
  func state(for permission: PrivacyPermission) -> PermissionState {
    PrivacyPermissionService.state(for: permission)
  }
  func request(_ permission: PrivacyPermission) async {
    await PrivacyPermissionService.request(permission)
  }
  func openSettings(_ permission: PrivacyPermission) {
    PrivacyPermissionService.openSettings(permission)
  }
}

/// Faux états pour `--onboarding-permissions=mock` : une demande accepte, sans invite système.
@MainActor
final class MockOnboardingPermissions: OnboardingPermissionProviding {
  private var states: [PrivacyPermission: PermissionState] = [
    .calendars: .allowed, .camera: .notDetermined, .accessibility: .denied,
    .musicAutomation: .notDetermined,
  ]

  static func fromLaunchArguments() -> OnboardingPermissionProviding {
    CommandLine.arguments.contains("--onboarding-permissions=mock")
      ? MockOnboardingPermissions() : SystemOnboardingPermissions()
  }

  func state(for permission: PrivacyPermission) -> PermissionState {
    states[permission] ?? .unknown
  }
  func request(_ permission: PrivacyPermission) async {
    try? await Task.sleep(for: .milliseconds(400))
    states[permission] = .allowed
  }
  func openSettings(_ permission: PrivacyPermission) {}
}

/// État partagé du parcours d'accueil entre le contrôleur (clavier, balayage, taille du panneau)
/// et les vues SwiftUI.
@MainActor
@Observable
final class OnboardingModel {

  /// Les autorisations proposées, dans l'ordre : seules celles que l'app utilise aujourd'hui.
  static let permissions: [PrivacyPermission] = [
    .calendars, .camera, .accessibility, .musicAutomation,
  ]

  private(set) var step: OnboardingStep
  /// +1 quand on avance, -1 quand on recule : le sens de la glissade du contenu.
  private(set) var direction = 1
  /// Déplacement du contenu pendant un balayage à deux doigts.
  var dragOffset: CGFloat = 0
  private(set) var permissionStates: [PrivacyPermission: PermissionState] = [:]
  var skipped: Set<PrivacyPermission> = []
  private(set) var requesting: Set<PrivacyPermission> = []

  /// Appelés par le contrôleur : nouvelle hauteur de silhouette, et fin du parcours.
  var onStepChanged: ((OnboardingStep) -> Void)?
  var onFinish: (() -> Void)?

  private let provider: OnboardingPermissionProviding

  init(
    start: OnboardingStep = .hello,
    provider: OnboardingPermissionProviding = MockOnboardingPermissions.fromLaunchArguments()
  ) {
    step = start
    self.provider = provider
    refreshPermissions()
  }

  func go(_ delta: Int) {
    guard let next = step.moved(by: delta) else {
      if delta > 0 { onFinish?() }
      return
    }
    goTo(next)
  }

  func goTo(_ target: OnboardingStep) {
    guard target != step else { return }
    direction = target.rawValue > step.rawValue ? 1 : -1
    step = target
    onStepChanged?(target)
    if target == .permissions { refreshPermissions() }
  }

  func refreshPermissions() {
    for permission in Self.permissions {
      permissionStates[permission] = provider.state(for: permission)
    }
  }

  func allow(_ permission: PrivacyPermission) {
    skipped.remove(permission)
    requesting.insert(permission)
    Task {
      await provider.request(permission)
      requesting.remove(permission)
      refreshPermissions()
    }
  }

  func openSettings(_ permission: PrivacyPermission) {
    provider.openSettings(permission)
  }

  func toggleSkip(_ permission: PrivacyPermission) {
    if skipped.contains(permission) {
      skipped.remove(permission)
    } else {
      skipped.insert(permission)
    }
  }
}
