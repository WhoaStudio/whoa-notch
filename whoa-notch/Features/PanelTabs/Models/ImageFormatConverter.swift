import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Un format d'image que le bac sait lire et écrire.
enum ImageFormat: CaseIterable, Equatable, Sendable {
  case jpeg
  case png
  case heic

  var utType: UTType {
    switch self {
    case .jpeg: .jpeg
    case .png: .png
    case .heic: .heic
    }
  }

  /// Extension du fichier écrit.
  var fileExtension: String {
    switch self {
    case .jpeg: "jpg"
    case .png: "png"
    case .heic: "heic"
    }
  }

  /// Libellé de la pastille de conversion.
  var label: String { fileExtension.uppercased() }

  /// Format d'un fichier d'après son extension (jpg, jpeg, png, heic), `nil` pour tout autre
  /// fichier : un fichier qui n'est pas une image ne propose aucune conversion.
  init?(url: URL) {
    guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
    guard let format = Self.allCases.first(where: { $0.utType == type }) else { return nil }
    self = format
  }

  /// ImageIO sait-il écrire ce format sur cette machine ? HEIC dépend du matériel et du système.
  var isWritable: Bool {
    let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
    return identifiers.contains(utType.identifier)
  }

  /// Les formats proposés pour ce fichier source : tous ceux qu'on sait écrire, sauf le sien.
  var conversionTargets: [ImageFormat] {
    Self.allCases.filter { $0 != self && $0.isWritable }
  }
}

/// Ce qu'on fait à une image en la réécrivant : format de sortie, qualité, échelle, rotation et
/// métadonnées. Les actions de la vue Transform (Convert, Compress, Resize, Rotate, Remove
/// metadata) sont chacune une valeur de ce type.
struct ImageTransformOptions: Equatable {
  var format: ImageFormat
  var quality: CGFloat = ImageFormatConverter.lossyQuality
  /// Facteur appliqué aux deux dimensions, entre 0 et 1.
  var scale: CGFloat = 1
  /// Rotation dans le sens horaire, en degrés : 0, 90, 180 ou 270.
  var rotationDegrees = 0
  var stripMetadata = false
}

/// Réécrit une image avec ImageIO, sans jamais toucher à l'original.
enum ImageFormatConverter {

  enum ConversionError: Error {
    case unreadable
    case unsupportedTarget
    case writeFailed
  }

  /// Qualité de la compression avec perte (JPEG, HEIC).
  static let lossyQuality: CGFloat = 0.9

  /// Écrit `source` au format `format` dans `destination`, qui ne doit pas exister : l'appelant
  /// choisit un nom libre. Les métadonnées sont conservées.
  static func convert(_ source: URL, to format: ImageFormat, at destination: URL) throws {
    try write(source, options: ImageTransformOptions(format: format), at: destination)
  }

  /// Écrit `source` transformée par `options` dans `destination`, qui ne doit pas exister. Un
  /// échec ne laisse aucun fichier partiel.
  static func write(_ source: URL, options: ImageTransformOptions, at destination: URL) throws {
    guard options.format.isWritable else { throw ConversionError.unsupportedTarget }
    guard
      let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      CGImageSourceGetCount(imageSource) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { throw ConversionError.unreadable }

    // La vignette de taille pleine applique l'orientation EXIF et redimensionne d'un coup :
    // l'image écrite est droite, sans balise d'orientation à rejouer.
    let longSide = Int((CGFloat(max(width, height)) * min(max(options.scale, 0.01), 1)).rounded())
    let thumbnailOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(1, longSide),
    ]
    guard
      var image = CGImageSourceCreateThumbnailAtIndex(
        imageSource, 0, thumbnailOptions as CFDictionary)
    else { throw ConversionError.unreadable }

    if options.rotationDegrees % 360 != 0,
      let rotated = rotated(image, degrees: options.rotationDegrees)
    {
      image = rotated
    }
    // Le JPEG n'a pas de transparence : une image qui en a est posée sur du blanc plutôt que
    // laissée à un fond noir.
    if options.format == .jpeg, let flat = flattened(image) { image = flat }

    var output: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: options.quality]
    if !options.stripMetadata {
      for (key, value) in properties
      where ![
        kCGImagePropertyOrientation, kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight,
      ].contains(key) {
        output[key] = value
      }
    }

    guard
      let destinationRef = CGImageDestinationCreateWithURL(
        destination as CFURL, options.format.utType.identifier as CFString, 1, nil)
    else { throw ConversionError.writeFailed }
    CGImageDestinationAddImage(destinationRef, image, output as CFDictionary)
    guard CGImageDestinationFinalize(destinationRef) else {
      try? FileManager.default.removeItem(at: destination)
      throw ConversionError.writeFailed
    }
  }

  /// L'image posée sur fond blanc si elle a un canal alpha, `nil` si elle est déjà opaque.
  private static func flattened(_ image: CGImage) -> CGImage? {
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast: return nil
    default: break
    }
    guard
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(rect)
    context.draw(image, in: rect)
    return context.makeImage()
  }

  /// L'image tournée dans le sens horaire de `degrees` (multiple de 90).
  private static func rotated(_ image: CGImage, degrees: Int) -> CGImage? {
    let turns = ((degrees / 90) % 4 + 4) % 4
    let swapped = turns % 2 == 1
    let width = swapped ? image.height : image.width
    let height = swapped ? image.width : image.height
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    // CoreGraphics tourne dans le sens antihoraire : le sens horaire est l'opposé.
    context.rotate(by: -CGFloat(turns) * .pi / 2)
    context.draw(
      image,
      in: CGRect(
        x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width),
        height: CGFloat(image.height)))
    return context.makeImage()
  }
}
