import CoreGraphics
import Foundation

// Playing a recording never blinks (`docs/design/video.md` §4).
//
// A clip draws the frame under the playhead by pointing at that frame's
// `ImageRef` (`MovieClip.swift`). Pointing at a frame nobody has read yet used to
// draw nothing at all, because a picture layer with no picture behind it is
// skipped, so every frame the decoder was late for flashed empty. A full-screen
// Retina recording is late often enough that playing one flickered.
//
// The fix belongs here rather than in the renderer: the document is drawn with
// the frames the window actually HAS, and a frame not in hand is stood in for by
// the newest one that is. That is what every player does, and it is what makes
// the landing redraw a real change too: the clip goes from pointing at the
// stand-in to pointing at the frame that just arrived.

/// Which frames of which recordings are read and ready to draw.
///
/// Numbers only: which recording and which frame of its grid. The pixels are in
/// the app's `ImageStore`, exactly as they have always been.
public struct MovieFramesInHand: Equatable, Sendable {

    private var frames: [UUID: Set<Int>] = [:]

    public init() {}

    public mutating func insert(movie: UUID, frameIndex: Int) {
        frames[movie, default: []].insert(frameIndex)
    }

    public mutating func remove(movie: UUID, frameIndex: Int) {
        frames[movie]?.remove(frameIndex)
        if frames[movie]?.isEmpty == true { frames[movie] = nil }
    }

    public func contains(movie: UUID, frameIndex: Int) -> Bool {
        frames[movie]?.contains(frameIndex) ?? false
    }

    /// The frame to draw where `wanted` is asked for: that frame if it is in
    /// hand, else the newest one before it, else the nearest one after it, else
    /// nil when nothing of this recording has been read at all.
    ///
    /// Before wins over after because a player going forward has just SHOWN the
    /// one before; after is only there so a scrub backwards keeps its picture
    /// instead of going empty.
    public func frameIndexToShow(_ wanted: Int, of movie: UUID) -> Int? {
        guard let held = frames[movie], !held.isEmpty else { return nil }
        if held.contains(wanted) { return wanted }
        if let before = held.filter({ $0 < wanted }).max() { return before }
        return held.filter { $0 > wanted }.min()
    }
}

extension MovieRef {

    /// The reference to draw for the frame at a moment of the file, standing in
    /// the newest frame in hand for one that has not been read yet.
    ///
    /// With no hand at all this is exactly `frameRef(atSourceMS:)`: that is
    /// what an export asks for, because it waits for every frame it writes.
    public func frameRef(atSourceMS ms: Int, holding inHand: MovieFramesInHand?) -> ImageRef {
        let wanted = frameIndex(atSourceMS: ms)
        guard let inHand, let shown = inHand.frameIndexToShow(wanted, of: id) else {
            return frameRef(atSourceMS: ms)
        }
        return ImageRef(id: MovieRef.frameID(movie: id, frameIndex: shown), pixelSize: pixelSize)
    }

    /// How big a frame is worth reading when it is shown at `shownScale` screen
    /// pixels per pixel of the recording.
    ///
    /// Never bigger than the recording, and in steps of an eighth of it, so a
    /// zoom that moves a little does not throw away every frame already read
    /// and read them all again. Never under an eighth, so a stray tiny zoom
    /// does not read a smudge that the next zoom in has to replace.
    public func decodePixelSize(shownScale: CGFloat) -> CGSize {
        let eighths = min(8, max(1, (max(0, shownScale) * 8).rounded(.up)))
        let share = eighths / 8
        return CGSize(width: (pixelSize.width * share).rounded(),
                      height: (pixelSize.height * share).rounded())
    }
}
