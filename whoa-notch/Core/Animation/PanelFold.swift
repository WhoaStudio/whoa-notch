import QuartzCore

/// Le dépliage partagé par les panneaux de l'overlay : celui de l'encoche, qui passe de la forme
/// de l'encoche au panneau large, et les bandes de flanc, qui se déplient depuis leur bord
/// d'écran. Les deux ne se replient pas sur la même silhouette — l'une reste à l'écran repliée,
/// l'autre s'en retire — mais ils doivent se déplier du même geste : même ressort, même fondu,
/// même façon de poser l'état final quand il n'y a rien à animer.
///
/// Le mouvement est en deux temps qui se recouvrent : la silhouette est portée par un ressort
/// (`SpringPreset.gentle`), et le contenu suit en fondu plutôt qu'au ressort — il doit avoir
/// disparu avant que la silhouette ne soit redevenue trop étroite pour le contenir.
enum PanelFold {

  /// Durée du fondu. Le dépliage de la silhouette, lui, dure le temps que met son ressort à se
  /// stabiliser.
  static let fadeDuration: TimeInterval = 0.18

  /// Porte `shapes` jusqu'à `path`, et les calques qui les accompagnent jusqu'à `opacity`.
  ///
  /// Deux façons de disparaître, parce que les deux panneaux n'ont pas le même état replié :
  ///
  /// - `fading` est le contenu posé **sur** une silhouette qui, elle, reste à l'écran. Il part
  ///   vite, sur `fadeDuration` : il doit avoir disparu avant que la silhouette ne soit
  ///   redevenue trop étroite pour le contenir. C'est le cas du panneau de l'encoche.
  /// - `dissolving` est une surface qui s'en va **avec** le dépliage, silhouette comprise. Son
  ///   fondu est porté par le même ressort, sans quoi elle se serait effacée bien avant d'avoir
  ///   fini de se replier et on ne verrait pas le geste. C'est le cas d'une bande de flanc, qui
  ///   ne laisse rien sur le bord entre deux survols.
  ///
  /// `animated` à faux pose l'état final tel quel, sans animation : c'est le cas d'une mise en
  /// page, où le panneau doit déjà être dans son état courant à la première image.
  ///
  /// `completion` est appelée quand le ressort s'est stabilisé — une bande de flanc en a besoin
  /// pour retirer sa fenêtre une fois repliée, là où le panneau de l'encoche garde la sienne.
  static func apply(
    path: CGPath,
    to shapes: [CAShapeLayer],
    in frame: CGRect,
    fading: [CALayer] = [],
    dissolving: [CALayer] = [],
    to opacity: Float,
    animated: Bool,
    velocity: CGFloat = 0,
    completion: (() -> Void)? = nil
  ) {
    // `OverlayAnimation` coupe le mouvement de tout l'overlay d'un seul réglage : le
    // chemin « pose l'état final » existe déjà, il suffit de l'emprunter.
    guard animated, OverlayAnimation.allowsMotion, let leading = shapes.first else {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      for shape in shapes {
        shape.removeAnimation(forKey: "path")
        shape.frame = frame
        shape.path = path
      }
      for layer in fading + dissolving {
        layer.removeAnimation(forKey: "opacity")
        layer.opacity = opacity
      }
      CATransaction.commit()
      completion?()
      return
    }

    for shape in shapes {
      shape.frame = frame
      // Toutes les silhouettes reçoivent le même ressort et se stabilisent donc ensemble :
      // la complétion n'est attachée qu'à la première, sans quoi l'appelant ferait son
      // travail autant de fois qu'il y a de calques.
      shape.springAnimate(
        keyPath: "path",
        to: path,
        preset: .gentle,
        velocity: velocity,
        completion: shape === leading ? completion : nil
      )
    }

    for layer in fading {
      fade(layer, to: opacity)
    }

    for layer in dissolving {
      layer.springAnimate(keyPath: "opacity", to: opacity, preset: .gentle)
    }
  }

  /// Fondu d'opacité : `easeOut` sur `fadeDuration`, la valeur du modèle posée en parallèle pour
  /// que le calque reste dans le bon état une fois l'animation retirée.
  static func fade(_ layer: CALayer, to opacity: Float) {
    guard OverlayAnimation.allowsMotion else {
      layer.removeAnimation(forKey: "opacity")
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.opacity = opacity
      CATransaction.commit()
      return
    }

    guard layer.opacity != opacity else { return }

    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
    animation.toValue = opacity
    animation.duration = fadeDuration
    animation.timingFunction = CAMediaTimingFunction(name: .easeOut)

    layer.opacity = opacity
    layer.add(animation, forKey: "opacity")
  }
}
