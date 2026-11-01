import AppKit
import os

/// Le coffre de l'app : une seule source vectorielle (`LaunchChest.svg`, et `LaunchEyes` pour
/// les yeux), partagée par l'accueil au lancement et par l'onglet Global déplié.
enum ChestMark {
    /// Le coffre tel que dessiné, avec son contour clair.
    static func chest() -> NSImage? {
        svgSource().flatMap { NSImage(data: Data($0.utf8)) }
    }

    /// Les morceaux du coffre, tirés des groupes de `LaunchChest.svg` et rendus dans l'ordre, du
    /// fond vers le dessus : l'intérieur du couvercle (sous lui), le couvercle, le corps, son
    /// ouverture, le fermoir.
    ///
    /// Refermé, le coffre est lisse : le couvercle repose sur le corps et recouvre l'intérieur,
    /// le fermoir tombe de la couture, et l'ouverture du corps ne se voit pas. Couvercle levé,
    /// c'est la pose de l'œuvre : le bleu sombre de l'intérieur sous le couvercle, le fermoir
    /// dessus, l'ouverture sur le corps.
    enum Part: CaseIterable {
        case interior, lid, body, opening, clasp

        fileprivate var groupIDs: [String] {
            switch self {
            case .interior: ["lid-interior"]
            case .lid: ["lid"]
            case .body: ["body"]
            case .opening: ["opening"]
            case .clasp: ["clasp"]
            }
        }

        /// Les contours de l'œuvre ne sont gardés que là où le trait clair fait le bord d'une
        /// ouverture : ailleurs, le coffre refermé s'en passe (voir `image(of:)`).
        fileprivate var keepsStrokes: Bool { self == .interior || self == .opening }
    }

    /// De combien le fermoir descend de sa place dans l'œuvre (grille 256) pour retomber à cheval
    /// sur la couture, sous le bord du couvercle (ordonnée 99).
    static let claspDrop: CGFloat = 30

    /// La couture entre le couvercle et le corps : un trait clair le long du bord bas du
    /// couvercle. Trop fin pour le halo des anciens contours (3 unités sur le coffre entier), il
    /// lève avec le couvercle.
    private static let lidSeam = ##"<path d="M42 86 L58 99 H198 L214 86" fill="none" stroke="#cfc9ff" stroke-opacity="0.9" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>"##

    /// Un morceau du coffre. Sans contour sauf pour ceux de `keepsStrokes` : en petit, le trait
    /// clair de 3 unités tombe sous le pixel et se lit comme un halo blanc autour de la forme.
    /// Même grille 256 et même dégradé que le coffre entier, donc les morceaux se superposent
    /// exactement.
    static func image(of part: Part) -> NSImage? {
        guard let source = svgSource(), let header = source.range(of: "<g id=") else { return nil }
        var svg = String(source[..<header.lowerBound])
        for id in part.groupIDs {
            guard let group = source.range(of: #"<g id="\#(id)">.*?</g>"#, options: .regularExpression) else {
                Log.notchPanel.error("Coffre : groupe \(id, privacy: .public) introuvable")
                return nil
            }
            svg += source[group]
        }
        // Les contours de l'œuvre sont retirés d'abord ; la couture, voulue, est posée après.
        if !part.keepsStrokes {
            svg = svg.replacingOccurrences(
                of: #"\sstroke(-[a-z]+)?="[^"]*""#, with: "", options: .regularExpression)
        }
        if part == .lid { svg += lidSeam }
        svg += "</svg>"
        return NSImage(data: Data(svg.utf8))
    }

    /// Ordonnée de la charnière du couvercle, au bord du fond, dans la grille 256 (0 en haut).
    static let lidHingeY: CGFloat = 40

    static func eyes() -> NSImage? {
        NSImage(named: "LaunchEyes")
    }

    /// Cadre des yeux dans un coffre de côté `side`, repère AppKit (origine en bas à gauche) :
    /// la boîte de `LaunchEyes.svg` (76, 148, 104 × 48) dans la grille 256 du coffre.
    static func eyesFrame(inChestOfSide side: CGFloat) -> CGRect {
        CGRect(x: side * 76 / 256, y: side * 60 / 256, width: side * 104 / 256, height: side * 48 / 256)
    }

    /// Rend `image` à la taille exacte de `size` points × `scale`, pour qu'un calque l'affiche
    /// pixel pour pixel au lieu de réduire une image bien plus grande.
    static func rasterize(_ image: NSImage, size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    private static func svgSource() -> String? {
        guard let data = NSDataAsset(name: "LaunchChest")?.data else {
            Log.notchPanel.error("Coffre : ressource LaunchChest introuvable")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
