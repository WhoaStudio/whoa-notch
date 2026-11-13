import SwiftUI

/// Fenêtre de bienvenue : dégradé violet, icône et version de l'app, deux cartes de
/// fonctionnalités puis des listes. La version vient du bundle, jamais d'une constante.
struct OnboardingView: View {

  /// Appelée par « Let's start » : ferme la fenêtre, ce qui pose `hasSeenOnboarding`.
  var onStart: () -> Void = {}

  /// Couleurs relevées sur l'icône de l'app : corps anthracite, liseré acier, crème des yeux.
  private enum Palette {
    static let bodyTop = Color(red: 0x37 / 255, green: 0x36 / 255, blue: 0x3C / 255)
    static let bodyBottom = Color(red: 0x1F / 255, green: 0x21 / 255, blue: 0x28 / 255)
    static let vignette = Color(red: 0x0D / 255, green: 0x0E / 255, blue: 0x12 / 255)
    static let cardTop = Color(red: 0x3A / 255, green: 0x3B / 255, blue: 0x42 / 255)
    static let cardBottom = Color(red: 0x2E / 255, green: 0x30 / 255, blue: 0x37 / 255)
    static let bezel = Color(red: 0x8A / 255, green: 0x89 / 255, blue: 0x8B / 255)
    static let cream = Color(red: 0xFC / 255, green: 0xEB / 255, blue: 0xD3 / 255)
  }

  private static var versionString: String {
    let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    return "v\(short)"
  }

  var body: some View {
    ZStack(alignment: .top) {
      LinearGradient(
        colors: [Palette.bodyTop, Palette.bodyBottom],
        startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea()

      // Effet trou noir sur toute la fenêtre : le fond anthracite respire au centre et tombe au noir sur les bords.
      RadialGradient(
        gradient: Gradient(stops: [
          .init(color: .clear, location: 0),
          .init(color: .clear, location: 0.22),
          .init(color: Palette.vignette.opacity(0.75), location: 0.5),
          .init(color: .black.opacity(0.97), location: 0.85),
        ]),
        center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 500
      )
      .mask(
        LinearGradient(
          colors: [.black, .black, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)

      VStack(spacing: 0) {
        ScrollView {
          VStack(spacing: 24) {
            header
            ForEach(OnboardingContent.features) { featureCard($0) }
            section("Also new:", OnboardingContent.alsoNew)
            section("Fixes & improvements:", OnboardingContent.fixes)
          }
          .padding(.horizontal, 40)
          .padding(.top, 44)
          .padding(.bottom, 32)
          // Les mots d'accueil font partie du contenu : ils défilent avec lui.
          .overlay(alignment: .topLeading) {
            note(OnboardingContent.leftNote, .leading).rotationEffect(.degrees(-8)).padding(
              .leading, 40
            ).padding(.top, 100)
          }
          .overlay(alignment: .topTrailing) {
            note(OnboardingContent.rightNote, .trailing).rotationEffect(.degrees(8)).padding(
              .trailing, 40
            ).padding(.top, 100)
          }
        }
        .scrollIndicators(.hidden)

        Button(action: onStart) {
          Text("Let's start").font(.system(size: 15, weight: .semibold)).frame(minWidth: 140)
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.cream)
        .foregroundStyle(Palette.bodyBottom)
        .controlSize(.extraLarge)
        .keyboardShortcut(.defaultAction)
        .padding(.vertical, 20)
      }
    }
    .preferredColorScheme(.dark)
  }

  private var header: some View {
    VStack(spacing: 6) {
      Image("OnboardingLogo")
        .resizable().scaledToFit().frame(width: 150, height: 150)
        .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("Whoa Notch").font(.system(size: 28, weight: .bold))
        Text(Self.versionString).font(.system(size: 18)).foregroundStyle(.secondary)
      }
      Text(OnboardingContent.tagline)
        .font(.system(size: 14)).multilineTextAlignment(.center)
    }
  }

  private func note(_ text: String, _ alignment: TextAlignment) -> some View {
    Text(text)
      .font(.custom("Noteworthy-Bold", size: 14))
      .foregroundStyle(Color.white.opacity(0.55))
      .multilineTextAlignment(alignment)
  }

  private func featureCard(_ feature: OnboardingContent.Feature) -> some View {
    HStack(spacing: 20) {
      RoundedRectangle(cornerRadius: 16)
        .fill(
          LinearGradient(
            colors: [Palette.cardTop, Palette.cardBottom], startPoint: .top, endPoint: .bottom)
        )
        .frame(width: 150, height: 90)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.bezel.opacity(0.6)))
        .overlay(
          Image(systemName: feature.symbol).font(.system(size: 32)).foregroundStyle(Palette.cream))
      VStack(alignment: .leading, spacing: 4) {
        Text(feature.title).font(.system(size: 17, weight: .semibold))
        Text(feature.detail).font(.system(size: 13)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }

  private func section(_ title: String, _ items: [OnboardingContent.Item]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.system(size: 14, weight: .semibold))
      ForEach(items) { item in
        HStack(spacing: 12) {
          Image(systemName: item.symbol).frame(width: 24)
          Text(item.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
