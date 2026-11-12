import QuartzCore
import SwiftUI

/// Deux profils de ressort réutilisés par tout l'overlay, pour que chaque micro-interaction
/// (apparition du widget, allumage d'une graduation, crossfade du bouton) partage la même
/// signature de mouvement plutôt que des durées ad hoc.
enum SpringPreset {
  /// Mouvements d'ensemble (apparition/disparition du widget) : ample et posé.
  case gentle
  /// Changements d'état ponctuels (graduation, glow, bouton) : vif mais toujours amorti.
  case snappy

  /// Réutilise les mêmes paramètres physiques dans les vues SwiftUI.
  var swiftUIAnimation: Animation {
    let spring = makeAnimation(keyPath: "opacity")
    return .interpolatingSpring(
      mass: spring.mass, stiffness: spring.stiffness, damping: spring.damping)
  }

  fileprivate func makeAnimation(keyPath: String) -> CASpringAnimation {
    let animation = CASpringAnimation(keyPath: keyPath)
    switch self {
    case .gentle:
      animation.damping = 20
      animation.stiffness = 140
      animation.mass = 1.1
    case .snappy:
      animation.damping = 18
      animation.stiffness = 260
      animation.mass = 0.9
    }
    animation.initialVelocity = 0
    animation.duration = animation.settlingDuration
    return animation
  }
}

extension CALayer {
  /// Fait entrer le contenu sur un court trajet, sans déplacer sa zone interactive.
  func springReveal(x: CGFloat = 0, y: CGFloat = -8, preset: SpringPreset = .snappy) {
    let key = "contentReveal"
    guard OverlayAnimation.allowsMotion else {
      removeAnimation(forKey: key)
      return
    }

    let current = animation(forKey: key) == nil ? nil : presentation()
    let horizontal = preset.makeAnimation(keyPath: "transform.translation.x")
    horizontal.fromValue = current?.value(forKeyPath: "transform.translation.x") ?? x
    horizontal.toValue = 0

    let vertical = preset.makeAnimation(keyPath: "transform.translation.y")
    vertical.fromValue = current?.value(forKeyPath: "transform.translation.y") ?? y
    vertical.toValue = 0

    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = current?.opacity ?? 0
    fade.toValue = opacity
    fade.duration = PanelFold.fadeDuration

    let group = CAAnimationGroup()
    group.animations = [horizontal, vertical, fade]
    group.duration = vertical.duration
    add(group, forKey: key)
  }

  /// Fait entrer un calque en fondu avec un léger grossissement (0,97 → 1), après `delay` : la
  /// moitié « entrante » d'un contenu qui prend la place d'un autre pendant que l'ancien s'efface.
  /// Sans mouvement autorisé, le calque est simplement là.
  func crossfadeIn(delay: CFTimeInterval = 0.06, duration: CFTimeInterval = 0.2) {
    let key = "crossfadeIn"
    guard OverlayAnimation.allowsMotion else {
      removeAnimation(forKey: key)
      return
    }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = opacity
    let scale = CABasicAnimation(keyPath: "transform.scale")
    scale.fromValue = 0.97
    scale.toValue = 1
    let group = CAAnimationGroup()
    group.animations = [fade, scale]
    group.duration = duration
    group.beginTime = CACurrentMediaTime() + delay
    group.fillMode = .backwards
    group.timingFunction = CAMediaTimingFunction(name: .easeOut)
    add(group, forKey: key)
  }

  /// Anime `keyPath` vers `value` avec un `CASpringAnimation`, et met à jour la valeur du
  /// modèle en parallèle pour que le calque reste dans le bon état une fois l'animation retirée.
  func springAnimate(
    keyPath: String, to newValue: Any, from initialValue: Any? = nil,
    preset: SpringPreset = .snappy, completion: (() -> Void)? = nil
  ) {
    // Réglage `General > Enable animations` coupé : la valeur est posée sèchement, et la
    // complétion appelée tout de suite — les appelants s'en servent pour retirer une fenêtre
    // repliée, et attendre un ressort qui n'existe pas la laisserait à l'écran.
    guard OverlayAnimation.allowsMotion else {
      removeAnimation(forKey: keyPath)
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      setValue(newValue, forKeyPath: keyPath)
      CATransaction.commit()
      completion?()
      return
    }

    CATransaction.begin()
    if let completion {
      CATransaction.setCompletionBlock(completion)
    }

    let animation = preset.makeAnimation(keyPath: keyPath)
    animation.fromValue =
      initialValue ?? presentation()?.value(forKeyPath: keyPath) ?? self.value(forKeyPath: keyPath)
    animation.toValue = newValue

    setValue(newValue, forKeyPath: keyPath)
    add(animation, forKey: keyPath)

    CATransaction.commit()
  }
}
