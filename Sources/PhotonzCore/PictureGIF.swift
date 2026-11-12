import Foundation

/// **A picture that moves, as a GIF** (task `an-animated-picture-exports-as-a-gif`).
///
/// Somebody who asks for "a gif of a bouncing ball" gets a moving icon, and
/// the file they asked for is a GIF. This says which moments of the picture
/// that file photographs, how long each is held and whether it goes round for
/// ever, all read off the document the way the canvas plays it
/// (`PhotonzDocument.moved(toMotionTimeMS:)`), so the GIF and the timeline
/// cannot disagree about the loop.
public struct PictureGIFPlan: Hashable, Sendable {
    /// The moments photographed, in milliseconds into the picture's play.
    public let timesMS: [Int]
    /// How long each is held, in the whole hundredths a GIF keeps.
    public let delaysInHundredths: [Int]
    /// True goes round for ever; false plays once and holds the last
    /// picture, which is where the motion landed.
    public let loops: Bool
    /// How long one play of the file is.
    public let durationMS: Int
}

public enum PictureGIF {

    /// How many pictures a second. Twenty five is a whole four hundredths a
    /// frame, which every reader shows as written, and smooth enough for a
    /// swing or a bounce; fifty doubles the file for a difference a small
    /// icon does not show.
    public static let fps: Double = 25

    /// The longest one play of the file runs. A spinner on its own pace and a
    /// lap that only come round together after minutes would make a GIF of
    /// thousands of frames, so past this the file is one lap long and the
    /// spinner takes a small step at the seam.
    public static let longestMS = 12_000

    /// Whether Export offers a GIF: a picture, not a video, with something on
    /// it that moves.
    public static func offers(_ document: PhotonzDocument) -> Bool {
        !document.hasTime && document.hasMotion
    }

    /// Which moments to photograph, or nil for a picture with nothing moving.
    public static func plan(for document: PhotonzDocument) -> PictureGIFPlan? {
        guard offers(document) else { return nil }
        let cycle = document.motionCycleLengthMS
        guard cycle > 0 else { return nil }
        let (loops, length) = play(of: document, cycleMS: cycle)
        let count = max(1, Int((Double(length) / 1000 * fps).rounded()))
        var times = (0..<count).map { min(length - 1, Int((Double($0) * 1000 / fps).rounded())) }
        var delays = GIFFrameTiming.delaysInHundredths(frameCount: count, fps: fps, durationMS: length)
        if !loops {
            // A file that plays once ends on its last picture for good, so
            // that picture is the one the motion LANDS on rather than the
            // moment just before it.
            times.append(length)
            delays.append(GIFFrameTiming.shortestHundredths)
        }
        return PictureGIFPlan(timesMS: times, delaysInHundredths: delays,
                              loops: loops, durationMS: length)
    }

    /// Whether the picture goes round for ever, and how long one play is.
    ///
    /// Read off the document as it PLAYS (`lappingKeys`), the same reading the
    /// animated SVG and the Export sheet's "It repeats" line take.
    static func play(of document: PhotonzDocument, cycleMS cycle: Int) -> (loops: Bool, ms: Int) {
        // A keyed picture is one lap long or goes round for ever, whatever a
        // motion on it would say for itself (`motionHasSettled(atMS:)`).
        if document.isKeyedPicture, let lap = document.keyLap {
            return (lap.repeats, cycle)
        }
        let motions = (document.lappingKeys.allLayers.flatMap { $0.motions ?? [] }
            + (document.camera?.motions ?? [])).filter(\.isOn)
        let finite = motions.compactMap(\.repeats.cycles)
        guard finite.count < motions.count else {
            // Everything stops: play until the last one has, then hold.
            return (false, cycle * max(1, finite.max() ?? 1))
        }
        // Something goes round for ever. The lap comes round every `cycle`,
        // and a spinner keeping its own pace every turn of its own, so the
        // file is as long as it takes all of them to be back where they began.
        var length = cycle
        for motion in motions where motion.repeats.keepsItsOwnPace {
            length = leastCommonMultiple(length, max(1, motion.timing.durationMS))
            if length > longestMS { return (true, cycle) }
        }
        return (true, length)
    }

    static func leastCommonMultiple(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return a / max(1, x) * b
    }
}
