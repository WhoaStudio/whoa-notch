import AppKit

/// Prélève une couleur à l'écran. `nil` quand l'utilisateur annule (Échap).
@MainActor
protocol ColorSampling {
    func pick(_ completion: @escaping (PickedColor?) -> Void)
}

/// Le compte-gouttes du système : il change le curseur, laisse viser n'importe où à l'écran et
/// le rend lui-même à la fin, sans permission d'enregistrement d'écran.
final class SystemColorSampler: ColorSampling {

    private let sampler = NSColorSampler()

    func pick(_ completion: @escaping (PickedColor?) -> Void) {
        sampler.show { color in
            completion(color.flatMap(PickedColor.init))
        }
    }
}

/// Source factice pour vérifier l'interface : rend les couleurs d'une liste, l'une après l'autre,
/// et `nil` (annulation) une fois sur cinq.
final class MockColorSampler: ColorSampling {

    private let colors: [PickedColor]
    private var index = 0

    init(colors: [PickedColor] = ["#E8503A", "#34C759", "#FFD60A", "#AF52DE", "#0A6FE8"].compactMap(PickedColor.init(hex:))) {
        self.colors = colors
    }

    /// `--color-picker=sample`, `nil` sans le drapeau.
    static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments) -> MockColorSampler? {
        arguments.contains("--color-picker=sample") ? MockColorSampler() : nil
    }

    func pick(_ completion: @escaping (PickedColor?) -> Void) {
        let color = colors[index % colors.count]
        index += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { completion(color) }
    }
}
