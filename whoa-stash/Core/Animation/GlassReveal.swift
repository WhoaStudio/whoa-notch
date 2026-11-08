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

  /// Opacité au départ.
  static let startOpacity: Float = 0

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
    layer.removeAnimation(forKey: animationKey)
    layer.removeAnimation(forKey: "opacity")
    layer.filters = nil
    layer.opacity = 1
    guard OverlayAnimation.allowsMotion else { return }

    view.layerUsesCoreImageFilters = true
    guard let blur = CIFilter(name: "CIGaussianBlur") else { return }
    blur.name = filterName
    blur.setValue(blurRadius, forKey: kCIInputRadiusKey)
    layer.filters = [blur]

    let timing = CAMediaTimingFunction(name: .easeOut)

    let unblur = CABasicAnimation(keyPath: "filters.\(filterName).inputRadius")
    unblur.fromValue = blurRadius
    unblur.toValue = 0
    unblur.duration = duration
    unblur.timingFunction = timing

    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = startOpacity
    fade.toValue = 1
    fade.duration = duration
    fade.timingFunction = timing

    let group = CAAnimationGroup()
    group.animations = [unblur, fade]
    group.duration = duration

    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak layer] in
      // Une apparition plus récente a pu reprendre le calque : on ne retire que la nôtre.
      guard let layer, layer.animation(forKey: animationKey) == nil else { return }
      layer.filters = nil
    }
    layer.add(group, forKey: animationKey)
    CATransaction.commit()
  }
}
