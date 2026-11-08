import AppKit
import Testing

@testable import whoa_stash

/// Le dépliage partagé par les trois panneaux repose sur un invariant que rien, dans le type des
/// valeurs, ne protège : les deux silhouettes d'un même panneau — repliée et dépliée — doivent
/// avoir la **même suite de segments**. Core Animation interpole un `CGPath` segment à segment ;
/// deux chemins de structures différentes ne s'interpolent pas, et le ressort de `PanelFold`
/// dégénère alors en saut sec, sans rien signaler.
///
/// Les tailles et les rayons changent d'un état à l'autre et d'un panneau à l'autre, mais jamais
/// la recette. C'est ce que ces tests tiennent.
@MainActor
struct PanelFoldTests {

  /// Les trois accroches réellement utilisées : le haut pour le panneau de l'encoche, les deux
  /// flancs pour la bande de bagues et le widget de luminosité.
  private static let anchors: [PanelGeometry.Anchor] = [.top, .left, .right]

  /// La suite des types de segments, qui est ce que l'interpolation exige d'identique — les
  /// points, eux, ont le droit de bouger : c'est tout le sujet de l'animation.
  private static func structure(of path: CGPath) -> [Int32] {
    var kinds: [Int32] = []
    path.applyWithBlock { kinds.append($0.pointee.type.rawValue) }
    return kinds
  }

  private static func collapsed(_ anchor: PanelGeometry.Anchor, in rect: CGRect) -> CGPath {
    PanelGeometry.silhouette(
      in: rect,
      anchoredTo: anchor,
      size: PanelGeometry.collapsedHandleSize,
      shoulderRadius: PanelGeometry.collapsedShoulderRadius,
      farRadius: PanelGeometry.collapsedFarRadius
    )
  }

  private static func expanded(_ anchor: PanelGeometry.Anchor, in rect: CGRect) -> CGPath {
    PanelGeometry.silhouette(in: rect, anchoredTo: anchor)
  }

  /// Le cadre d'une bande de flanc, et celui — bien plus large que haut — du panneau de
  /// l'encoche : les deux proportions que l'overlay met réellement à l'écran.
  private static let frames: [CGRect] = [
    CGRect(x: 0, y: 0, width: PanelGeometry.panelWidth, height: PanelGeometry.minimumPanelHeight),
    CGRect(x: 0, y: 0, width: 790, height: 316),
  ]

  @Test("les deux états d'un panneau ont la même suite de segments, sur les trois accroches")
  func collapsedAndExpandedShareTheSameStructure() {
    for anchor in Self.anchors {
      for frame in Self.frames {
        let collapsed = Self.structure(of: Self.collapsed(anchor, in: frame))
        let expanded = Self.structure(of: Self.expanded(anchor, in: frame))

        #expect(
          collapsed == expanded,
          "accroche \(anchor), cadre \(frame.size) : \(collapsed.count) segments repliés contre \(expanded.count) dépliés"
        )
      }
    }
  }

  /// Une poignée plus profonde que le panneau, ou plus longue que son bord, serait rognée — et
  /// les clampages qui la ramènent dans le cadre ne doivent pas, au passage, lui retirer un
  /// segment.
  @Test("une poignée ramenée dans un cadre trop petit garde sa structure")
  func clampedHandleKeepsItsStructure() {
    let cramped = CGRect(x: 0, y: 0, width: 30, height: 40)

    for anchor in Self.anchors {
      let collapsed = Self.structure(of: Self.collapsed(anchor, in: cramped))
      let expanded = Self.structure(of: Self.expanded(anchor, in: cramped))

      #expect(collapsed == expanded, "accroche \(anchor) : la poignée rognée perd un segment")
    }
  }

  /// La poignée est la silhouette **depuis** laquelle le panneau se déplie : elle doit toucher
  /// le bord d'accroche, sinon le dépliage partirait d'un point détaché de l'écran.
  @Test("la poignée affleure le bord d'accroche et reste dans le cadre")
  func handleTouchesItsAnchorEdge() {
    let frame = CGRect(
      x: 0, y: 0, width: PanelGeometry.panelWidth, height: PanelGeometry.minimumPanelHeight)
    // Les arcs sont rendus en courbes, donc la boîte englobante d'un chemin déborde des
    // points de contrôle : `boundingBoxOfPath` prend le contour réel.
    let tolerance: CGFloat = 0.001

    let edges: [(PanelGeometry.Anchor, (CGRect) -> CGFloat, CGFloat)] = [
      (.top, { $0.maxY }, frame.maxY),
      (.left, { $0.minX }, frame.minX),
      (.right, { $0.maxX }, frame.maxX),
    ]

    for (anchor, reach, edge) in edges {
      let box = Self.collapsed(anchor, in: frame).boundingBoxOfPath
      #expect(abs(reach(box) - edge) <= tolerance, "la poignée de \(anchor) ne touche pas son bord")
      #expect(
        frame.insetBy(dx: -tolerance, dy: -tolerance).contains(box),
        "la poignée de \(anchor) sort du cadre")
    }
  }
}
