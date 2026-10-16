// What each clip's timeline bar last drew for its sound, so a walk can claim a
// waveform is on screen rather than photograph a thin green line and guess.
// Probe-only, like the rest of the harness: `PHOTONZ_PLAYTEST` is defined for
// the dev and probe bundles, so the shipping build does not contain this file.
#if PHOTONZ_PLAYTEST
import Foundation
import PhotonzCore

/// Whether each clip's bar drew the shape of its sound the last time it drew.
///
/// The library having read a file is not the question: the shape of b-roll's
/// sound was read within a moment of it landing on the timeline, and its bar
/// still drew a flat line for as long as anyone watched, because nothing told
/// the bar the shape had arrived (`SoundLibrary`). Only the bar can say what
/// it drew.
@MainActor
final class DrawnWaveforms {
    static let shared = DrawnWaveforms()

    private var drawn: [UUID: Bool] = [:]

    /// Called from the bar's body with what it is about to draw.
    func bar(of layerID: UUID, drew: Bool) {
        drawn[layerID] = drew
    }

    /// What the bar of this clip last drew: `nil` when it has never drawn.
    func drew(_ layerID: UUID) -> Bool? { drawn[layerID] }

    /// What one piece of a bar last drew: the sound it asked for, and whether
    /// the shape was that sound's own rather than the file standing in for a
    /// cleaned copy not made yet.
    struct Piece { let sound: SoundRef; let own: Bool }
    private var pieces: [UUID: [Int: Piece]] = [:]

    func piece(_ index: Int, of layerID: UUID, sound: SoundRef, own: Bool) {
        pieces[layerID, default: [:]][index] = Piece(sound: sound, own: own)
    }

    func drew(_ layerID: UUID, piece index: Int) -> Piece? { pieces[layerID]?[index] }
}
#endif
