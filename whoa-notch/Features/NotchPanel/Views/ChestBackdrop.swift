import AppKit

/// Le fond du coffre : une tuile arrondie en dégradé bleu, avec une bande claire d'horizon à
/// mi-hauteur et un halo doux autour du coffre refermé. Dessinée une fois à la taille exacte, en
/// pixels, pour qu'un calque l'affiche sans rien recalculer.
enum ChestBackdrop {
  /// Dont la tuile déborde le coffre de chaque côté, en points.
  static let padding: CGFloat = 3

  /// - Parameters:
  ///   - size: taille de la tuile, en points.
  ///   - chestRect: le coffre dans la tuile, en points, repère AppKit.
  ///   - silhouettes: les morceaux du coffre refermé, dont l'ombre dessine le halo.
  static func render(size: CGSize, chestRect: CGRect, silhouettes: [NSImage], scale: CGFloat)
    -> CGImage?
  {
    let width = Int((size.width * scale).rounded())
    let height = Int((size.height * scale).rounded())
    guard width > 0, height > 0,
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
    else { return nil }

    // Tout est calculé en pixels : le décalage d'une ombre ne suit pas la matrice du contexte.
    let pixels = CGSize(width: CGFloat(width), height: CGFloat(height))
    let radius = min(pixels.width, pixels.height) * 0.24
    context.addPath(
      CGPath(
        roundedRect: CGRect(origin: .zero, size: pixels),
        cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()

    // Du bas vers le haut : bleu profond, puis la bande d'horizon dont le bord bas est net et
    // le haut se fond dans le bleu.
    let colors = [
      CGColor(srgbRed: 0.15, green: 0.10, blue: 0.74, alpha: 1),
      CGColor(srgbRed: 0.21, green: 0.17, blue: 0.84, alpha: 1),
      CGColor(srgbRed: 0.75, green: 0.74, blue: 1.00, alpha: 1),
      CGColor(srgbRed: 0.33, green: 0.34, blue: 0.96, alpha: 1),
      CGColor(srgbRed: 0.29, green: 0.30, blue: 0.95, alpha: 1),
    ]
    if let gradient = CGGradient(
      colorsSpace: space, colors: colors as CFArray, locations: [0, 0.47, 0.50, 0.74, 1])
    {
      context.drawLinearGradient(
        gradient, start: .zero, end: CGPoint(x: 0, y: pixels.height), options: [])
    }

    // Le halo : l'ombre blanche des morceaux, dessinés hors du cadre et ramenés par le décalage
    // de l'ombre, pour que seule l'ombre se voie — le couvercle, lui, bouge.
    let far: CGFloat = 10_000
    context.setShadow(
      offset: CGSize(width: -far, height: 0), blur: 3.2 * scale,
      color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.6))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let target = CGRect(
      x: chestRect.minX * scale + far, y: chestRect.minY * scale,
      width: chestRect.width * scale, height: chestRect.height * scale)
    for image in silhouettes { image.draw(in: target) }
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()
  }
}
