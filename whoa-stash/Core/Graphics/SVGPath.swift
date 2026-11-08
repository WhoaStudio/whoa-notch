import CoreGraphics
import Foundation

/// Traduit l'attribut `d` d'un SVG en `CGPath`, mis à l'échelle dans un cadre donné et rendu
/// dans le repère AppKit — SVG fait descendre l'axe Y, AppKit le fait monter.
///
/// Couvre les commandes utilisées par les marques embarquées (`UsageMarkPath`) : M, L, H, V, C,
/// S, Q, T, A et Z, en absolu comme en relatif. C'est ce qui permet de coller le tracé officiel
/// d'un logo tel quel, au lieu de le redessiner à la main.
enum SVGPath {

  /// `viewBox` est la boîte du SVG d'origine (24×24 pour les marques embarquées) ; le tracé est
  /// centré dans `rect` en conservant ses proportions.
  static func path(from d: String, viewBox: CGSize, in rect: CGRect) -> CGPath {
    let raw = CGMutablePath()
    var scanner = Scanner(d)

    var current = CGPoint.zero
    var subpathStart = CGPoint.zero
    var lastCubicControl: CGPoint?
    var lastQuadControl: CGPoint?
    var command: Character = " "

    while true {
      if let next = scanner.takeCommand() {
        command = next
      } else if scanner.isAtEnd {
        break
      } else if command == "M" {
        // Une commande `moveto` suivie d'autres couples de coordonnées trace des lignes.
        command = "L"
      } else if command == "m" {
        command = "l"
      } else if command == " " {
        break
      }

      let relative = command.isLowercase
      func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
      }

      switch Character(command.lowercased()) {
      case "m":
        guard let x = scanner.number(), let y = scanner.number() else {
          return finish(raw, viewBox, rect)
        }
        current = point(x, y)
        subpathStart = current
        raw.move(to: current)

      case "l":
        guard let x = scanner.number(), let y = scanner.number() else {
          return finish(raw, viewBox, rect)
        }
        current = point(x, y)
        raw.addLine(to: current)

      case "h":
        guard let x = scanner.number() else { return finish(raw, viewBox, rect) }
        current = CGPoint(x: relative ? current.x + x : x, y: current.y)
        raw.addLine(to: current)

      case "v":
        guard let y = scanner.number() else { return finish(raw, viewBox, rect) }
        current = CGPoint(x: current.x, y: relative ? current.y + y : y)
        raw.addLine(to: current)

      case "c":
        guard
          let x1 = scanner.number(), let y1 = scanner.number(),
          let x2 = scanner.number(), let y2 = scanner.number(),
          let x = scanner.number(), let y = scanner.number()
        else { return finish(raw, viewBox, rect) }
        let control1 = point(x1, y1)
        let control2 = point(x2, y2)
        current = point(x, y)
        raw.addCurve(to: current, control1: control1, control2: control2)
        lastCubicControl = control2

      case "s":
        guard
          let x2 = scanner.number(), let y2 = scanner.number(),
          let x = scanner.number(), let y = scanner.number()
        else { return finish(raw, viewBox, rect) }
        // Premier point de contrôle : le reflet du précédent autour du point courant.
        let control1 =
          lastCubicControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) }
          ?? current
        let control2 = point(x2, y2)
        current = point(x, y)
        raw.addCurve(to: current, control1: control1, control2: control2)
        lastCubicControl = control2

      case "q":
        guard
          let x1 = scanner.number(), let y1 = scanner.number(),
          let x = scanner.number(), let y = scanner.number()
        else { return finish(raw, viewBox, rect) }
        let control = point(x1, y1)
        current = point(x, y)
        raw.addQuadCurve(to: current, control: control)
        lastQuadControl = control

      case "t":
        guard let x = scanner.number(), let y = scanner.number() else {
          return finish(raw, viewBox, rect)
        }
        let control =
          lastQuadControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) }
          ?? current
        current = point(x, y)
        raw.addQuadCurve(to: current, control: control)
        lastQuadControl = control

      case "a":
        guard
          let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
          let largeArc = scanner.flag(), let sweep = scanner.flag(),
          let x = scanner.number(), let y = scanner.number()
        else { return finish(raw, viewBox, rect) }
        let end = point(x, y)
        addArc(
          to: raw, from: current, to: end,
          rx: rx, ry: ry, rotation: rotation * .pi / 180,
          largeArc: largeArc, sweep: sweep
        )
        current = end

      case "z":
        raw.closeSubpath()
        current = subpathStart

      default:
        return finish(raw, viewBox, rect)
      }

      if Character(command.lowercased()) != "c" && Character(command.lowercased()) != "s" {
        lastCubicControl = nil
      }
      if Character(command.lowercased()) != "q" && Character(command.lowercased()) != "t" {
        lastQuadControl = nil
      }
    }

    return finish(raw, viewBox, rect)
  }

  /// Mise à l'échelle et retournement de l'axe Y, en une seule transformation appliquée au
  /// tracé complet.
  private static func finish(_ path: CGPath, _ viewBox: CGSize, _ rect: CGRect) -> CGPath {
    let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
    let drawn = CGSize(width: viewBox.width * scale, height: viewBox.height * scale)
    let originX = rect.midX - drawn.width / 2
    let originY = rect.midY + drawn.height / 2

    var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: originX, ty: originY)
    return path.copy(using: &transform) ?? path
  }

  /// Arc elliptique SVG (paramétrage par extrémités) converti en segments cubiques, en passant
  /// par le centre comme le décrit l'annexe F.6 de la spécification.
  private static func addArc(
    to path: CGMutablePath,
    from start: CGPoint,
    to end: CGPoint,
    rx: CGFloat,
    ry: CGFloat,
    rotation: CGFloat,
    largeArc: Bool,
    sweep: Bool
  ) {
    guard rx != 0, ry != 0 else {
      path.addLine(to: end)
      return
    }

    var rx = abs(rx)
    var ry = abs(ry)

    let dx2 = (start.x - end.x) / 2
    let dy2 = (start.y - end.y) / 2
    let cosR = cos(rotation)
    let sinR = sin(rotation)

    let x1 = cosR * dx2 + sinR * dy2
    let y1 = -sinR * dx2 + cosR * dy2

    // Rayons trop petits pour relier les deux extrémités : la spec demande de les agrandir.
    let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if lambda > 1 {
      rx *= sqrt(lambda)
      ry *= sqrt(lambda)
    }

    let sign: CGFloat = largeArc == sweep ? -1 : 1
    let numerator = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
    let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
    let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)

    let cx1 = coefficient * rx * y1 / ry
    let cy1 = -coefficient * ry * x1 / rx

    let center = CGPoint(
      x: cosR * cx1 - sinR * cy1 + (start.x + end.x) / 2,
      y: sinR * cx1 + cosR * cy1 + (start.y + end.y) / 2
    )

    func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
      let dot = ux * vx + uy * vy
      let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
      guard len != 0 else { return 0 }
      let value = acos(min(1, max(-1, dot / len)))
      return (ux * vy - uy * vx) < 0 ? -value : value
    }

    let startAngle = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    var sweepAngle = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if !sweep, sweepAngle > 0 {
      sweepAngle -= 2 * .pi
    } else if sweep, sweepAngle < 0 {
      sweepAngle += 2 * .pi
    }

    // Un segment cubique par quart de tour au plus : au-delà, l'approximation se voit.
    let segments = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
    let delta = sweepAngle / CGFloat(segments)
    let alpha = 4.0 / 3.0 * tan(delta / 4)

    var theta = startAngle
    for _ in 0..<segments {
      let next = theta + delta

      func onEllipse(_ t: CGFloat) -> CGPoint {
        CGPoint(
          x: center.x + rx * cos(t) * cosR - ry * sin(t) * sinR,
          y: center.y + rx * cos(t) * sinR + ry * sin(t) * cosR
        )
      }
      func derivative(_ t: CGFloat) -> CGPoint {
        CGPoint(
          x: -rx * sin(t) * cosR - ry * cos(t) * sinR,
          y: -rx * sin(t) * sinR + ry * cos(t) * cosR
        )
      }

      let from = onEllipse(theta)
      let to = onEllipse(next)
      let d1 = derivative(theta)
      let d2 = derivative(next)

      path.addCurve(
        to: to,
        control1: CGPoint(x: from.x + alpha * d1.x, y: from.y + alpha * d1.y),
        control2: CGPoint(x: to.x - alpha * d2.x, y: to.y - alpha * d2.y)
      )
      theta = next
    }
  }

  /// Lecteur de l'attribut `d` : nombres, lettres de commande et drapeaux d'arc, avec les
  /// séparateurs facultatifs que tolère la spec (« 1.5.5 » vaut deux nombres, « 013 » vaut deux
  /// drapeaux puis un nombre).
  private struct Scanner {
    private let characters: [Character]
    private var index = 0

    init(_ string: String) {
      characters = Array(string)
    }

    var isAtEnd: Bool {
      var copy = self
      copy.skipSeparators()
      return copy.index >= copy.characters.count
    }

    private mutating func skipSeparators() {
      while index < characters.count,
        characters[index] == " " || characters[index] == ","
          || characters[index] == "\n" || characters[index] == "\t" || characters[index] == "\r"
      {
        index += 1
      }
    }

    mutating func takeCommand() -> Character? {
      skipSeparators()
      guard index < characters.count, characters[index].isLetter else { return nil }
      defer { index += 1 }
      return characters[index]
    }

    mutating func flag() -> Bool? {
      skipSeparators()
      guard index < characters.count, characters[index] == "0" || characters[index] == "1" else {
        return nil
      }
      defer { index += 1 }
      return characters[index] == "1"
    }

    mutating func number() -> CGFloat? {
      skipSeparators()
      var text = ""

      if index < characters.count, characters[index] == "-" || characters[index] == "+" {
        text.append(characters[index])
        index += 1
      }
      while index < characters.count, characters[index].isNumber || characters[index] == "." {
        // Un second point ouvre le nombre suivant, sans séparateur : « .5.5 ».
        if characters[index] == ".", text.contains(".") { break }
        text.append(characters[index])
        index += 1
      }
      if index < characters.count, characters[index] == "e" || characters[index] == "E" {
        text.append(characters[index])
        index += 1
        if index < characters.count, characters[index] == "-" || characters[index] == "+" {
          text.append(characters[index])
          index += 1
        }
        while index < characters.count, characters[index].isNumber {
          text.append(characters[index])
          index += 1
        }
      }

      return Double(text).map { CGFloat($0) }
    }
  }
}
