import SwiftUI

/// Contenu de l'écran de bienvenue, posé sur la silhouette de l'encoche (voir
/// `WelcomeController`) : « hello » qui s'écrit en ASCII, puis le titre, le sous-titre et les
/// deux boutons qui glissent en place. Aucun fond ici — c'est la silhouette qui le porte.
struct WelcomeView: View {

  let animated: Bool
  /// Faux aux lancements suivants : le panneau se referme seul, il n'y a rien à cliquer.
  let showsButtons: Bool
  let size: CGSize
  /// Hauteur à laisser libre en haut : celle de l'encoche matérielle.
  let topInset: CGFloat
  let onStart: () -> Void
  let onTutorial: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showContent: Bool

  init(
    animated: Bool, showsButtons: Bool, size: CGSize, topInset: CGFloat,
    onStart: @escaping () -> Void, onTutorial: @escaping () -> Void
  ) {
    self.animated = animated
    self.showsButtons = showsButtons
    self.size = size
    self.topInset = topInset
    self.onStart = onStart
    self.onTutorial = onTutorial
    _showContent = State(initialValue: !animated)
  }

  private static let buttonBlue = Color(red: 0.04, green: 0.52, blue: 1.0)

  var body: some View {
    VStack(spacing: 14) {
      HelloASCIIView(animated: animated)
        .padding(.top, topInset)

      VStack(spacing: 8) {
        Text("Welcome to Whoa Stash!")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(.white)
        Text("Let’s start your day properly.")
          .font(.system(size: 13))
          .foregroundStyle(.white.opacity(0.55))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .offset(y: showContent || reduceMotion ? 0 : 8)
      .opacity(showContent ? 1 : 0)

      if showsButtons {
        HStack(spacing: 10) {
          button("Start", action: onStart)
          button("See Tutorial", action: onTutorial)
        }
        .padding(.top, 8)
        .offset(y: showContent || reduceMotion ? 0 : 8)
        .opacity(showContent ? 1 : 0)
        .allowsHitTesting(showContent)
      }
    }
    .padding(.horizontal, WelcomeController.contentInsetX)
    .padding(.bottom, 26)
    .frame(width: size.width, height: size.height, alignment: .top)
    .task {
      guard animated else { return }
      try? await Task.sleep(for: .milliseconds(HelloASCIIField.duration * 1000 + 100))
      withAnimation(reduceMotion ? nil : SpringPreset.snappy.swiftUIAnimation) {
        showContent = true
      }
    }
  }

  private func button(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Self.buttonBlue, in: RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
  }
}
