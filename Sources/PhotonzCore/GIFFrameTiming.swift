import Foundation

/// How long each frame of a GIF is held, in the hundredths the format keeps.
///
/// A GIF stores a frame's delay as a whole number of hundredths of a second,
/// so asking ImageIO for 1/15 s gets 7 and a four second edit plays for 4.2,
/// while 1/24 s gets 4 and plays fast. Rounding each frame on its own is the
/// drift; rounding where each frame STARTS is not. So frame `i` begins at
/// `i / fps` rounded to a hundredth, the last one ends where the edit ends,
/// and each delay is the gap between: sixes and sevens at fifteen a second,
/// never more than a hundredth off the clock at any frame.
public enum GIFFrameTiming {

    /// The shortest hold a reader shows as written. Browsers and Finder slow a
    /// frame of 0 or 1 hundredth to a tenth of a second, so nothing is shorter.
    public static let shortestHundredths = 2

    /// One delay per frame, in hundredths of a second, adding up to
    /// `durationMS` (to the nearest hundredth).
    public static func delaysInHundredths(frameCount: Int, fps: Double, durationMS: Int) -> [Int] {
        guard frameCount > 0 else { return [] }
        let rate = max(1, fps)
        let end = max(0, durationMS)
        func start(_ index: Int) -> Int {
            index == frameCount
                ? Int((Double(end) / 10).rounded())
                : Int((Double(index) * 100 / rate).rounded())
        }
        return (0..<frameCount).map { index in
            max(shortestHundredths, start(index + 1) - start(index))
        }
    }
}

extension VideoFramePlan {

    /// Each frame's hold for a GIF of this plan (`GIFFrameTiming`).
    public var gifDelaysInHundredths: [Int] {
        GIFFrameTiming.delaysInHundredths(frameCount: frameCount, fps: fps, durationMS: durationMS)
    }
}

extension AnimatedExportPlan {

    /// Each frame's hold for a GIF of this plan (`GIFFrameTiming`).
    public var gifDelaysInHundredths: [Int] {
        let fps = frameDelay > 0 ? 1 / frameDelay : 1
        return GIFFrameTiming.delaysInHundredths(frameCount: frameCount, fps: fps,
                                                 durationMS: Int((duration * 1000).rounded()))
    }
}

/// **How a GIF frame is brought down to the size it is written at.**
///
/// A wide filter (what `AVAssetImageGenerator` and a high quality draw use)
/// turns each crisp edge of a screen recording into a run of in-between greys,
/// and a GIF pays for every colour it has to tell apart. A 640 pixel recording
/// of text came out 26,988 bytes at Small (480 wide) against 23,244 at Standard
/// (kept at 640): the smaller choice wrote the bigger file. A plain bilinear
/// step leaves a 480 pixel frame of it at 16,591, and reads the same.
///
/// A plain step that spans more than two source pixels starts dropping them,
/// so thin lines flicker from bright to faint; that is what the wide filter is
/// for. So a frame goes down in at most two steps: the wide filter to twice the
/// size it ends at, only where it is bigger than that, then one plain step.
public enum GIFFrameScaling {

    /// The size the wide filter brings a frame to before the plain last step,
    /// or nil when the plain step alone does it (the frame is at most twice the
    /// target on both sides).
    public static func firstStep(from source: CGSize, to target: CGSize) -> CGSize? {
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else {
            return nil
        }
        let twice = CGSize(width: target.width * 2, height: target.height * 2)
        guard source.width > twice.width || source.height > twice.height else { return nil }
        return twice
    }
}
