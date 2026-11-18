import AVFoundation
import os
import SwiftUI

/// Une ambiance du panneau des sons : son titre, son visuel et sa boucle audio.
///
/// Les ressources sont des emplacements nommés, à déposer plus tard :
/// - l'image `ambient-<id>` dans `Assets.xcassets` ;
/// - la boucle `ambient-<id>.m4a` dans les ressources de l'app.
/// Sans image, la tuile peint un dégradé ; sans boucle, la tuile se sélectionne quand même et
/// l'absence est journalisée.
nonisolated enum AmbientSound: String, CaseIterable, Identifiable, Sendable {
  case cozy, rain, study, jazz, lofi

  var id: String { rawValue }

  var title: String {
    switch self {
    case .cozy: "Cozy"
    case .rain: "Rain"
    case .study: "Study"
    case .jazz: "Jazz"
    case .lofi: "Lo-fi"
    }
  }

  var imageName: String { "ambient-\(rawValue)" }
  var audioName: String { "ambient-\(rawValue)" }

  /// Dégradé de remplacement tant que l'image n'est pas fournie.
  var placeholderColors: [Color] {
    switch self {
    case .cozy: [Color(red: 0.55, green: 0.42, blue: 0.3), Color(red: 0.28, green: 0.2, blue: 0.14)]
    case .rain: [Color(red: 0.55, green: 0.6, blue: 0.62), Color(red: 0.2, green: 0.24, blue: 0.27)]
    case .study: [Color(red: 0.3, green: 0.3, blue: 0.34), Color(red: 0.1, green: 0.1, blue: 0.12)]
    case .jazz: [Color(red: 0.36, green: 0.3, blue: 0.26), Color(red: 0.08, green: 0.07, blue: 0.07)]
    case .lofi: [Color(red: 0.62, green: 0.72, blue: 0.82), Color(red: 0.2, green: 0.3, blue: 0.36)]
    }
  }
}

/// Joue une ambiance en boucle, une seule à la fois, avec un court fondu d'entrée.
///
/// La boucle passe par `AVAudioEngine` : le fichier est décodé une fois en mémoire puis rejoué
/// en boucle par le nœud, sans le blanc que laisse `AVAudioPlayer` au raccord d'un fichier
/// compressé.
final class AmbientSoundPlayer {

  private let engine = AVAudioEngine()
  private let node = AVAudioPlayerNode()
  private var fadeTask: Task<Void, Never>?
  private let targetVolume: Float = 0.6

  init() {
    engine.attach(node)
  }

  func play(_ sound: AmbientSound) {
    stop()
    guard let url = Bundle.main.url(forResource: sound.audioName, withExtension: "m4a") else {
      Log.sound.notice("Boucle d'ambiance absente du bundle : \(sound.audioName, privacy: .public)")
      return
    }
    do {
      let file = try AVAudioFile(forReading: url)
      guard
        let buffer = AVAudioPCMBuffer(
          pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
      else { return }
      try file.read(into: buffer)

      engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
      node.volume = 0
      node.scheduleBuffer(buffer, at: nil, options: .loops)
      try engine.start()
      node.play()
      fadeIn()
    } catch {
      Log.sound.error(
        "Lecture de l'ambiance impossible : \(error.localizedDescription, privacy: .public)")
      stop()
    }
  }

  func stop() {
    fadeTask?.cancel()
    fadeTask = nil
    node.stop()
    engine.stop()
  }

  /// Monte le volume en douze pas sur 0,6 s : la boucle ne démarre pas sur un à-coup.
  private func fadeIn() {
    fadeTask = Task { [weak self] in
      guard let self else { return }
      for step in 1...12 {
        try? await Task.sleep(for: .milliseconds(50))
        if Task.isCancelled { return }
        node.volume = targetVolume * Float(step) / 12
      }
    }
  }
}
