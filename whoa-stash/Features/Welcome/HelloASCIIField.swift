import SwiftUI

/// Le mot « hello » (tracé SVG d'origine, repère 638 × 200) converti en grille de caractères.
/// Rien ici ne dépend de la vue : on calcule une fois, pour chaque case touchée par le trait, le
/// caractère, la couleur et l'instant où la plume y passe, puis la vue n'a plus qu'à dessiner.
struct HelloASCIIField: Sendable {

    struct Cell: Sendable {
        let column: Int
        let row: Int
        /// Indice dans `glyphs`.
        let glyph: Int
        /// Instant (secondes depuis le début du dessin) où la plume atteint la case.
        let revealTime: Double
        let red: Double
        let green: Double
        let blue: Double
    }

    /// Du plus dense au plus léger : le cœur du trait est en `@`, les bords s'effilochent.
    nonisolated static let glyphs: [Character] = ["@", "#", "%", "*", "+", "=", "-"]

    nonisolated static let columns = 90
    nonisolated static let rows = 28

    /// Durée totale du dessin, dernier trait compris.
    nonisolated static let duration: Double = 3.5

    let cells: [Cell]

    /// Rayon du trait dans le repère SVG : plus épais que le tracé d'origine (7,4), pour que les
    /// lettres tiennent en trois ou quatre caractères de large.
    private nonisolated static let radius: Double = 12
    private nonisolated static let design = (width: 638.0, height: 200.0)

    /// Un trait : son départ et sa durée (comme les deux `motion.path` de l'exemple d'origine),
    /// puis ses points, déjà échantillonnés.
    private struct Stroke {
        let start: Double
        let duration: Double
        let points: [CGPoint]
    }

    nonisolated static let shared = HelloASCIIField()

    nonisolated init() {
        let strokes = [
            Stroke(start: 0, duration: 0.8, points: Self.sample(Self.firstData)),
            Stroke(start: 0.7, duration: 2.8, points: Self.sample(Self.restData)),
        ]
        let cellWidth = Self.design.width / Double(Self.columns)
        let cellHeight = Self.design.height / Double(Self.rows)

        struct Best { var distance: Double; var strokeIndex: Int; var fraction: Double }
        var best: [Int: Best] = [:]

        for (strokeIndex, stroke) in strokes.enumerated() {
            let points = stroke.points
            var lengths: [Double] = [0]
            for i in 1..<points.count {
                lengths.append(lengths[i - 1] + Double(hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)))
            }
            let total = max(lengths.last ?? 1, 1)

            for (i, point) in points.enumerated() {
                let x = Double(point.x), y = Double(point.y)
                let minC = max(0, Int((x - Self.radius) / cellWidth))
                let maxC = min(Self.columns - 1, Int((x + Self.radius) / cellWidth))
                let minR = max(0, Int((y - Self.radius) / cellHeight))
                let maxR = min(Self.rows - 1, Int((y + Self.radius) / cellHeight))
                guard minC <= maxC, minR <= maxR else { continue }
                for r in minR...maxR {
                    for c in minC...maxC {
                        let cx = (Double(c) + 0.5) * cellWidth
                        let cy = (Double(r) + 0.5) * cellHeight
                        let d = hypot(cx - x, cy - y)
                        guard d <= Self.radius else { continue }
                        let key = r * Self.columns + c
                        if let current = best[key], current.distance <= d { continue }
                        best[key] = Best(distance: d, strokeIndex: strokeIndex, fraction: lengths[i] / total)
                    }
                }
            }
        }

        cells = best.map { key, value in
            let row = key / Self.columns
            let column = key % Self.columns
            let stroke = strokes[value.strokeIndex]
            let reveal = stroke.start + stroke.duration * Self.inverseEase(value.fraction)
            let color = Self.color(atFraction: (Double(column) + 0.5) / Double(Self.columns))
            return Cell(
                column: column, row: row,
                glyph: Self.glyph(forRatio: value.distance / Self.radius, column: column, row: row),
                revealTime: reveal, red: color.0, green: color.1, blue: color.2)
        }
        .sorted { $0.revealTime < $1.revealTime }
    }

    // MARK: - Caractères

    /// Le cœur du trait est plein ; plus on s'approche du bord, plus les signes sont légers.
    /// Le hasard est déterministe (case → nombre) pour que le dessin soit le même à chaque lancement.
    private nonisolated static func glyph(forRatio ratio: Double, column: Int, row: Int) -> Int {
        let h = abs((column &* 73_856_093) ^ (row &* 19_349_663)) % 100
        switch ratio {
        case ..<0.55: return h < 90 ? 0 : 1
        case ..<0.8: return h < 60 ? 0 : (h < 80 ? 2 : 1)
        default: return h < 35 ? 3 : (h < 55 ? 4 : (h < 75 ? 5 : (h < 90 ? 6 : 0)))
        }
    }

    // MARK: - Couleurs

    /// Du bleu-vert de l'attaque du « h » au bleu de la queue du « o », en passant par le jaune,
    /// l'orange, le rouge et le violet — la même suite que le « hello » d'Apple, de gauche à droite.
    private nonisolated static let palette: [(position: Double, rgb: (Double, Double, Double))] = [
        (0.00, (0.20, 0.72, 0.82)),
        (0.17, (0.62, 0.78, 0.30)),
        (0.30, (0.97, 0.82, 0.22)),
        (0.45, (0.97, 0.58, 0.24)),
        (0.58, (0.93, 0.36, 0.30)),
        (0.75, (0.68, 0.46, 0.82)),
        (1.00, (0.42, 0.58, 0.95)),
    ]

    private nonisolated static func color(atFraction t: Double) -> (Double, Double, Double) {
        let t = min(max(t, 0), 1)
        for i in 1..<palette.count where t <= palette[i].position {
            let a = palette[i - 1], b = palette[i]
            let u = (t - a.position) / (b.position - a.position)
            return (a.rgb.0 + (b.rgb.0 - a.rgb.0) * u,
                    a.rgb.1 + (b.rgb.1 - a.rgb.1) * u,
                    a.rgb.2 + (b.rgb.2 - a.rgb.2) * u)
        }
        return palette[palette.count - 1].rgb
    }

    // MARK: - Temps

    /// Le trait avance en « ease-in-out » (`u²(3 − 2u)`) : pour savoir quand la plume atteint
    /// une fraction donnée de sa longueur, on inverse cette courbe par dichotomie.
    private nonisolated static func inverseEase(_ fraction: Double) -> Double {
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if mid * mid * (3 - 2 * mid) < fraction { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    // MARK: - Tracé SVG

    private nonisolated static let firstData =
        "M8.69214 166.553C36.2393 151.239 61.3409 131.548 89.8191 98.0295C109.203 75.1488 119.625 49.0228 120.122 31.0026C120.37 17.6036 113.836 7.43883 101.759 7.43883C88.3598 7.43883 79.9231 17.6036 74.7122 40.9363C69.005 66.5793 64.7866 96.0036 54.1166 190.356"

    private nonisolated static let restData =
        "M55.1624 181.135C60.6251 133.114 81.4118 98.0479 107.963 98.0479C123.844 98.0479 133.937 110.703 131.071 128.817C129.457 139.487 127.587 150.405 125.408 163.06C122.869 178.941 130.128 191.348 152.122 191.348C184.197 191.348 219.189 173.523 237.097 145.915C243.198 136.509 245.68 128.073 245.928 119.884C246.176 104.996 237.739 93.8296 222.851 93.8296C203.992 93.8296 189.6 115.17 189.6 142.465C189.6 171.745 205.481 192.341 239.208 192.341C285.066 192.341 335.86 137.292 359.199 75.8585C365.788 58.513 368.26 42.4065 368.26 31.1512C368.26 17.8057 364.042 7.55823 352.131 7.55823C340.469 7.55823 332.777 16.6141 325.829 30.9129C317.688 47.4967 311.667 71.4162 309.203 98.4549C303 166.301 316.896 191.348 349.936 191.348C390 191.348 434.542 135.534 457.286 75.6686C463.803 58.513 466.275 42.4065 466.275 31.1512C466.275 17.8057 462.057 7.55823 450.146 7.55823C438.484 7.55823 430.792 16.6141 423.844 30.9129C415.703 47.4967 409.682 71.4162 407.218 98.4549C401.015 166.301 414.911 191.348 444.416 191.348C473.874 191.348 489.877 165.67 499.471 138.402C508.955 111.447 520.618 94.8221 544.935 94.8221C565.035 94.8221 580.916 109.71 580.916 137.75C580.916 168.768 560.792 192.093 535.362 192.341C512.984 192.589 498.285 174.475 499.774 147.179C501.511 116.907 519.873 94.8221 543.943 94.8221C557.839 94.8221 569.51 100.999 578.682 107.725C603.549 125.866 622.709 114.656 630.047 96.7186"

    /// Lit des données de tracé SVG qui n'emploient que des commandes absolues `M`, `L` et `C`
    /// (c'est tout ce que contiennent les deux traits ci-dessus) et rend les points d'une
    /// polyligne dense qui les suit.
    private nonisolated static func sample(_ data: String) -> [CGPoint] {
        var tokens: [String] = []
        var number = ""
        func flush() { if !number.isEmpty { tokens.append(number); number = "" } }
        for char in data {
            if char.isLetter {
                flush(); tokens.append(String(char))
            } else if char == "-" || (char == "." && number.contains(".")) {
                flush(); number = String(char)
            } else if char == " " || char == "," {
                flush()
            } else {
                number.append(char)
            }
        }
        flush()

        var points: [CGPoint] = []
        var current = CGPoint.zero
        var command = ""
        var index = 0
        func take(_ count: Int) -> [CGFloat]? {
            guard index + count <= tokens.count else { return nil }
            let values = tokens[index..<index + count].compactMap { Double($0).map { CGFloat($0) } }
            guard values.count == count else { return nil }
            index += count
            return values
        }
        while index < tokens.count {
            if let first = tokens[index].first, first.isLetter {
                command = tokens[index]
                index += 1
                continue
            }
            switch command {
            case "M":
                guard let v = take(2) else { return points }
                current = CGPoint(x: v[0], y: v[1])
                points.append(current)
                command = "L"
            case "L":
                guard let v = take(2) else { return points }
                current = CGPoint(x: v[0], y: v[1])
                points.append(current)
            case "C":
                guard let v = take(6) else { return points }
                let p1 = CGPoint(x: v[0], y: v[1]), p2 = CGPoint(x: v[2], y: v[3]), end = CGPoint(x: v[4], y: v[5])
                let steps = 60
                for s in 1...steps {
                    let t = CGFloat(s) / CGFloat(steps), u = 1 - t
                    points.append(CGPoint(
                        x: u * u * u * current.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * end.x,
                        y: u * u * u * current.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * end.y))
                }
                current = end
            default:
                return points
            }
        }
        return points
    }
}
