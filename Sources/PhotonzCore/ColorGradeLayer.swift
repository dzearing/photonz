import CoreGraphics
import Foundation

/// **A colour grade on a track of its own**, over every clip below it
/// (`docs/design/mocks/pages/video-compositing.html`: the V4 colour grade
/// track, above the matte on V3 and the two clips under it).
///
/// What Premiere calls an adjustment layer with Lumetri on it. It is not a new
/// kind of thing: it is a lens the size of the frame whose adjustment is the
/// Color Grade in its own Effects list (`LensAdjustment.colorGrade`). A lens
/// already draws whatever is composited under it, so a grade on V4 grades V1
/// to V3 and nothing above it; its Blending is the Blending every layer has,
/// and its Masked by is the one every layer has, borrowing the shape or the
/// brightness of the layer directly under it. A keyed shape on the track
/// below is therefore a reveal that moves, with nothing built for it.
///
/// It arrives as the per-clip effect does, as the mock's Warm grade
/// (`ColorGradeEffect.starting`), so adding one visibly does something, and
/// blended Normal, which on a grade means the graded picture itself. Screen,
/// Multiply and Add then mix that graded picture with the one under it.
public enum ColorGradeLayer {
    /// The layer's name on its bar, the panel's word for the effect it wears.
    public static let layerName = "Color Grade"
    /// The track it lands on when it gets one of its own: Grade, Grade 2 and on.
    public static let trackName = "Grade"
    /// Less than this left before the end and the whole video is graded
    /// instead: a playhead parked on the last frame meant the video.
    public static let shortestTailMS = 1_000

    /// A grade covering the whole frame of a `canvas`-sized video for `time`.
    public static func layer(canvas: CGSize, time: LayerTime) -> Layer {
        var layer = Layer(name: layerName, content: .lens(LensContent(adjustment: .colorGrade)),
                          frame: CGRect(origin: .zero, size: canvas), style: LensBuilder.defaultStyle)
        layer.style.effects = [.colorGrade(.starting)]
        layer.time = time
        return layer
    }

    /// When a grade added at `ms` runs, in a video `lengthMS` long: from the
    /// playhead to the end, or the whole of it when the playhead leaves too
    /// little to see.
    public static func span(atMS ms: Int, lengthMS: Int) -> LayerTime {
        let start = min(max(0, ms), lengthMS)
        let from = lengthMS - start < shortestTailMS ? 0 : start
        return LayerTime(inMS: from, outMS: max(from + LayerTime.shortestMS, lengthMS))
    }
}

extension Layer {
    /// Whether this layer is a colour grade over what is under it, rather
    /// than a lens drawn with the Lens tool.
    public var isColorGrade: Bool { lens?.adjustment == .colorGrade }
}

extension PhotonzDocument {

    /// How long the video runs, for a grade that should run to its end: what
    /// it says it is, or where its last clip ends.
    var colorGradeLengthMS: Int? {
        let lastOut = allLayers.compactMap { $0.time?.outMS }.max()
        guard let length = durationMS ?? lastOut, length > 0 else { return nil }
        return max(length, lastOut ?? 0)
    }

    /// Where a grade added at `ms` would land: on `trackID` when that track is
    /// free for the whole of it, on a new Grade track at the top otherwise.
    /// Nil for a document with no time.
    public func colorGradeLanding(atMS ms: Int, onTrack trackID: UUID? = nil) -> ClipLanding? {
        guard let length = colorGradeLengthMS else { return nil }
        let span = ColorGradeLayer.span(atMS: ms, lengthMS: length)
        return titleLanding(lengthMS: span.lengthMS, atMS: span.inMS, over: trackID.map { .onto($0) },
                            newTrackNamed: ColorGradeLayer.trackName)
    }

    /// Put a colour grade over the video from `ms` to its end, on its own
    /// track at the top (or on `trackID` when that track is free), as the
    /// layer on top of every clip it lies over. Its id, or nil, and nothing
    /// changed, for a document with no time.
    @discardableResult
    public mutating func addColorGrade(atMS ms: Int, onTrack trackID: UUID? = nil) -> UUID? {
        guard let landing = colorGradeLanding(atMS: ms, onTrack: trackID) else { return nil }
        let time = LayerTime(inMS: landing.startMS, outMS: landing.endMS)
        return land(ColorGradeLayer.layer(canvas: canvasSize, time: time), at: landing)
    }
}
