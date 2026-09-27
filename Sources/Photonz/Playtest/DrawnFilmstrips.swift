// What the pictures along each clip on the timeline last drew, so a walk can
// claim a zoomed clip shows frames, and a clip at Fit shows none, rather than
// photograph a strip and guess. Probe-only, like the rest of the harness.
#if PHOTONZ_PLAYTEST
import Foundation

/// The strips of pictures on screen, per clip and piece: which frames each is
/// asking for and how strongly it shows (`ClipFilmstripStrip`).
@MainActor
final class DrawnFilmstrips {
    static let shared = DrawnFilmstrips()

    struct Strip {
        let keys: [ClipFilmstripFrames.Key]
        let opacity: Double
    }

    private struct Place: Hashable {
        let layer: UUID
        let piece: Int
    }

    private var strips: [Place: Strip] = [:]

    func showing(_ layer: UUID, piece: Int, keys: [ClipFilmstripFrames.Key], opacity: Double) {
        strips[Place(layer: layer, piece: piece)] = Strip(keys: keys, opacity: opacity)
    }

    func gone(_ layer: UUID, piece: Int) {
        strips[Place(layer: layer, piece: piece)] = nil
    }

    /// Every strip on screen for this clip.
    func strips(of layer: UUID) -> [Strip] {
        strips.filter { $0.key.layer == layer }.map(\.value)
    }
}
#endif
