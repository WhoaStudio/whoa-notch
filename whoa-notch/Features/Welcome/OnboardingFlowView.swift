import SwiftUI

/// Contenu du parcours d'accueil, posé sur la silhouette de l'encoche (voir `WelcomeController`).
/// Cinq étapes courtes ; le contenu glisse dans le sens du déplacement et suit le doigt pendant
/// un balayage. Sans mouvement (réglage ou Reduce Motion), il se fond simplement.
struct OnboardingFlowView: View {

  let model: OnboardingModel
  let size: CGSize
  let topInset: CGFloat
  /// Seul le premier affichage écrit « hello » au trait ; revenir en arrière le montre d'un bloc.
  let animatesHello: Bool

  private var motion: Bool { OverlayAnimation.allowsMotion }

  private var slide: AnyTransition {
    guard motion else { return .opacity }
    let offset = CGFloat(model.direction) * 28
    return .asymmetric(
      insertion: .offset(x: offset).combined(with: .opacity),
      removal: .offset(x: -offset).combined(with: .opacity))
  }

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .top) {
        stepView
          .id(model.step)
          .transition(slide)
          .offset(x: model.dragOffset)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .padding(.top, topInset)
      .animation(motion ? SpringPreset.snappy.swiftUIAnimation : nil, value: model.step)

      ProgressDots(model: model)
        .frame(height: OnboardingFlow.progressHeight)
    }
    .padding(.horizontal, WelcomeController.contentInsetX)
    .frame(
      width: size.width,
      height: OnboardingFlow.panelHeight(for: model.step, topInset: topInset),
      alignment: .top
    )
    .animation(motion ? SpringPreset.gentle.swiftUIAnimation : nil, value: model.step)
    .frame(width: size.width, height: size.height, alignment: .top)
  }

  @ViewBuilder private var stepView: some View {
    switch model.step {
    case .hello: HelloStep(model: model, animated: animatesHello)
    case .notch: NotchStep()
    case .tabs: TabsStep()
    case .permissions: PermissionsStep(model: model)
    case .done: DoneStep(model: model)
    }
  }
}

// MARK: - Style commun

enum OnboardingStyle {
  /// Crème de l'icône de l'app et son encre : les mêmes que le bouton de l'ancien accueil.
  static let cream = Color(red: 0xFC / 255, green: 0xEB / 255, blue: 0xD3 / 255)
  static let ink = Color(red: 0x1F / 255, green: 0x21 / 255, blue: 0x28 / 255)
}

private struct PrimaryButton: View {
  let title: String
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(OnboardingStyle.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(OnboardingStyle.cream, in: RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
  }
}

private struct SecondaryButton: View {
  let title: String
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.7))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
  }
}

private struct StepHeader: View {
  let title: String
  let subtitle: String
  var body: some View {
    VStack(spacing: 6) {
      Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
      Text(subtitle)
        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.top, 8)
  }
}

// MARK: - Indicateur de progression

/// Un point par étape ; l'étape courante s'étire en capsule. Cliquer un point y va.
private struct ProgressDots: View {
  let model: OnboardingModel

  var body: some View {
    HStack(spacing: 6) {
      ForEach(OnboardingStep.allCases) { step in
        Capsule()
          .fill(step == model.step ? OnboardingStyle.cream : .white.opacity(0.25))
          .frame(width: step == model.step ? 20 : 6, height: 6)
          .contentShape(Rectangle().inset(by: -6))
          .onTapGesture { model.goTo(step) }
      }
    }
    .animation(
      OverlayAnimation.allowsMotion ? SpringPreset.snappy.swiftUIAnimation : nil,
      value: model.step
    )
    .accessibilityElement()
    .accessibilityLabel("Step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
  }
}

// MARK: - 1. Hello

private struct HelloStep: View {
  let model: OnboardingModel
  let animated: Bool
  @State private var showContent: Bool

  init(model: OnboardingModel, animated: Bool) {
    self.model = model
    self.animated = animated
    _showContent = State(initialValue: !animated)
  }

  var body: some View {
    VStack(spacing: 12) {
      HelloASCIIView(animated: animated)
      VStack(spacing: 6) {
        Text("Welcome to Whoa Notch!").font(.system(size: 22, weight: .bold))
          .foregroundStyle(.white)
        Text("A one-minute tour. Swipe or use the arrow keys.")
          .font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
      }
      .opacity(showContent ? 1 : 0)
      .offset(y: showContent || !OverlayAnimation.allowsMotion ? 0 : 8)
      HStack(spacing: 10) {
        PrimaryButton(title: "Start") { model.go(1) }
        SecondaryButton(title: "Skip tour") { model.onFinish?() }
      }
      .padding(.top, 4)
      .opacity(showContent ? 1 : 0)
      .allowsHitTesting(showContent)
    }
    .task {
      guard animated else { return }
      try? await Task.sleep(for: .milliseconds(HelloASCIIField.duration * 1000 + 100))
      withAnimation(OverlayAnimation.allowsMotion ? SpringPreset.snappy.swiftUIAnimation : nil) {
        showContent = true
      }
    }
  }
}

// MARK: - 2. L'encoche

/// L'île se déplie au survol ou au clic, comme la vraie : c'est le geste central de l'app.
private struct NotchStep: View {
  @State private var open = false
  @State private var tried = false

  private var animation: Animation? {
    OverlayAnimation.allowsMotion ? SpringPreset.gentle.swiftUIAnimation : nil
  }

  var body: some View {
    VStack(spacing: 14) {
      StepHeader(
        title: "Everything starts at the notch",
        subtitle: tried
          ? "It folds back when you leave. That’s the whole gesture."
          : "Hover the island below, or click it, to unfold it.")
      island
        .frame(height: 112, alignment: .top)
    }
  }

  private var island: some View {
    let shape = UnevenRoundedRectangle(
      bottomLeadingRadius: open ? 22 : 11, bottomTrailingRadius: open ? 22 : 11)
    return ZStack(alignment: .top) {
      shape.fill(.black)
      shape.strokeBorder(.white.opacity(open ? 0.22 : 0.12), lineWidth: 1)
      if open {
        HStack(spacing: 14) {
          ForEach(["music.note", "calendar", "tray", "doc.on.clipboard", "terminal"], id: \.self) {
            Image(systemName: $0).font(.system(size: 14))
              .foregroundStyle(.white.opacity(0.75))
          }
        }
        .padding(.top, 34)
        .transition(.opacity)
      }
    }
    .frame(width: open ? 300 : 120, height: open ? 96 : 28)
    .frame(maxWidth: .infinity)
    .contentShape(Rectangle())
    .onHover { hovering in set(hovering) }
    .onTapGesture { set(!open) }
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel("Notch demo")
  }

  private func set(_ value: Bool) {
    withAnimation(animation) { open = value }
    if value { tried = true }
  }
}

// MARK: - 3. Les onglets

private struct DemoTab: Identifiable {
  let id: String
  let symbol: String
  let detail: String
}

private let demoTabs: [DemoTab] = [
  DemoTab(id: "Global", symbol: "music.note", detail: "Week strip, Now Playing and what plays next."),
  DemoTab(id: "Calendar", symbol: "calendar", detail: "Agenda and a month grid you can swipe."),
  DemoTab(id: "Clipboard", symbol: "doc.on.clipboard", detail: "Your last 50 copies, one click away."),
  DemoTab(id: "Notes", symbol: "note.text", detail: "Plain-text notes, saved as you type."),
  DemoTab(id: "Terminal", symbol: "terminal", detail: "Your login shell, kept alive across folds."),
  DemoTab(id: "Color", symbol: "eyedropper", detail: "Pick any colour on screen and copy it."),
]

private struct TabsStep: View {
  @State private var selected = "Global"
  @Namespace private var highlight

  private var animation: Animation? {
    OverlayAnimation.allowsMotion ? SpringPreset.snappy.swiftUIAnimation : nil
  }

  var body: some View {
    VStack(spacing: 12) {
      StepHeader(title: "Tabs for everything", subtitle: "Try them: click a tab.")
      VStack(spacing: 12) {
        HStack(spacing: 4) {
          ForEach(demoTabs) { tab in
            Image(systemName: tab.symbol)
              .font(.system(size: 13))
              .foregroundStyle(tab.id == selected ? OnboardingStyle.ink : .white.opacity(0.7))
              .frame(width: 38, height: 28)
              .background {
                if tab.id == selected {
                  Capsule().fill(OnboardingStyle.cream)
                    .matchedGeometryEffect(id: "pill", in: highlight)
                }
              }
              .contentShape(Capsule())
              .onTapGesture { withAnimation(animation) { selected = tab.id } }
              .help(tab.id)
              .accessibilityLabel(tab.id)
          }
        }
        VStack(spacing: 4) {
          Text(selected).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
          Text(demoTabs.first { $0.id == selected }?.detail ?? "")
            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .id(selected)
        .transition(.opacity)
        .frame(height: 52, alignment: .top)
      }
      .padding(14)
      .frame(maxWidth: .infinity)
      .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1)))
    }
  }
}

// MARK: - 4. Autorisations

private struct PermissionsStep: View {
  let model: OnboardingModel

  var body: some View {
    VStack(spacing: 10) {
      StepHeader(
        title: "Allow what you need",
        subtitle: "Each one is optional. Skip it and the feature simply stays off.")
      VStack(spacing: 6) {
        ForEach(OnboardingModel.permissions) { permission in
          PermissionRow(model: model, permission: permission)
        }
      }
    }
    // Revenu des Réglages Système : l'état se relit à chaque retour dans l'app.
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
      _ in model.refreshPermissions()
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        model.refreshPermissions()
      }
    }
  }
}

private struct PermissionRow: View {
  let model: OnboardingModel
  let permission: PrivacyPermission

  private var state: PermissionState { model.permissionStates[permission] ?? .unknown }
  private var isSkipped: Bool { model.skipped.contains(permission) }

  var body: some View {
    HStack(spacing: 10) {
      statusDot
      VStack(alignment: .leading, spacing: 1) {
        Text(permission.title).font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
        Text(permission.caption).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
          .lineLimit(2).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 6)
      actions
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    .opacity(isSkipped && state != .allowed ? 0.55 : 1)
    .animation(
      OverlayAnimation.allowsMotion ? SpringPreset.snappy.swiftUIAnimation : nil, value: state)
  }

  private var statusDot: some View {
    let color: Color =
      switch state {
      case .allowed: .green
      case .denied: .red
      case .notDetermined, .unknown: .white.opacity(0.3)
      }
    return Circle().fill(color).frame(width: 8, height: 8)
      .accessibilityLabel(Text(String(describing: state)))
  }

  @ViewBuilder private var actions: some View {
    if state == .allowed {
      Label("Allowed", systemImage: "checkmark")
        .font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
    } else if model.requesting.contains(permission) {
      ProgressView().controlSize(.small)
    } else {
      HStack(spacing: 6) {
        chip(isSkipped ? "Undo" : "Skip", prominent: false) { model.toggleSkip(permission) }
        if state == .denied || state == .unknown {
          chip("Open Settings", prominent: true) { model.openSettings(permission) }
        } else {
          chip("Allow", prominent: true) { model.allow(permission) }
        }
      }
    }
  }

  private func chip(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(.system(size: 11, weight: .semibold))
        .foregroundStyle(prominent ? OnboardingStyle.ink : .white.opacity(0.75))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(
          prominent ? OnboardingStyle.cream : .white.opacity(0.1), in: Capsule())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - 5. Fin

private struct DoneStep: View {
  let model: OnboardingModel
  @State private var checked = false

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 40)).foregroundStyle(OnboardingStyle.cream)
        .scaleEffect(checked || !OverlayAnimation.allowsMotion ? 1 : 0.4)
        .opacity(checked ? 1 : 0)
      StepHeader(
        title: "You’re set",
        subtitle: "Scroll the screen edges for brightness and volume. Everything else is in Preferences, from the menu bar icon.")
      PrimaryButton(title: "Finish") { model.onFinish?() }
        .padding(.top, 2)
    }
    .onAppear {
      withAnimation(OverlayAnimation.allowsMotion ? SpringPreset.gentle.swiftUIAnimation : nil) {
        checked = true
      }
    }
  }
}
