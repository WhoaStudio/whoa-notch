import SwiftUI

/// Contenu de l'écran de bienvenue, posé sur la silhouette de l'encoche (voir
/// `WelcomeController`) : « hello » qui s'écrit en ASCII, puis le titre et le sous-titre qui glissent
/// en place. Aucun fond ici — c'est la silhouette qui le porte.
struct WelcomeView: View {

  let animated: Bool
  let size: CGSize
  /// Hauteur à laisser libre en haut : celle de l'encoche matérielle.
  let topInset: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showContent: Bool

  init(animated: Bool, size: CGSize, topInset: CGFloat) {
    self.animated = animated
    self.size = size
    self.topInset = topInset
    _showContent = State(initialValue: !animated)
  }

  var body: some View {
    VStack(spacing: 14) {
      HelloASCIIView(animated: animated)
        .padding(.top, topInset)

      VStack(spacing: 8) {
        Text("Welcome to Whoa Notch!")
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
}
