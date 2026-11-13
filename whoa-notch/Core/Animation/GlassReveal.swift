import AppKit
import QuartzCore

/// Apparition « verre dépoli » du contenu de l'encoche : il passe de flou et transparent à net.
///
/// Le contenu reste en place pendant que la silhouette se déplie. Le filtre n'existe que
/// le temps de l'animation.
enum GlassReveal {

  /// Durée de l'apparition.
  static let duration: TimeInterval = 0.26

  /// Rayon du flou au départ, en points.
  static let blurRadius: CGFloat = 14

  private static let filterName = "glassBlur"
  private static let animationKey = "glassReveal"

  /// Retire le flou si le panneau se referme pendant son apparition.
  static func cancel(on view: NSView) {
    view.layer?.removeAnimation(forKey: animationKey)
    view.layer?.filters = nil
  }

  /// Joue l'apparition sur `view`, qui doit avoir un calque. Sans animation (réglage coupé),
  /// pose simplement l'état net.
  static func play(on view: NSView) {
    guard let layer = view.layer else { return }
    let opacity = layer.presentation()?.opacity ?? layer.opacity
    let radiusKey = "filters.\(filterName).inputRadius"
    let visibleBlur = layer.presentation()?.filters?
      .compactMap { $0 as? CIFilter }
      .first { $0.name == filterName }
    let radius = visibleBlur?.value(forKey: kCIInputRadiusKey) as? CGFloat ?? blurRadius
    cancel(on: view)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.removeAnimation(forKey: "opacity")
    layer.opacity = 1
    CATransaction.commit()
    guard OverlayAnimation.allowsMotion else { return }

    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = opacity
    fade.toValue = 1
    fade.duration = PanelFold.fadeDuration
    fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
    layer.add(fade, forKey: "opacity")

    view.layerUsesCoreImageFilters = true
    guard let blur = CIFilter(name: "CIGaussianBlur") else { return }
    blur.name = filterName
    blur.setValue(0, forKey: kCIInputRadiusKey)
    layer.filters = [blur]

    let unblur = CABasicAnimation(keyPath: radiusKey)
    unblur.fromValue = radius
    unblur.toValue = 0
    unblur.duration = duration
    unblur.timingFunction = CAMediaTimingFunction(name: .easeOut)

    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak layer] in
      // Une apparition plus récente a pu reprendre le calque : on ne retire que la nôtre.
      guard let layer, layer.animation(forKey: animationKey) == nil else { return }
      layer.filters = nil
    }
    layer.add(unblur, forKey: animationKey)
    CATransaction.commit()
  }
}
