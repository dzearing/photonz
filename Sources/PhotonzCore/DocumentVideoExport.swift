import CoreGraphics
import Foundation

// What a video export of a document is made of, before a pixel is written
// (`docs/design/video.md` §8).
//
// A video export is two questions and this file answers the first one on its
// own: **which moments get photographed, and how big is each picture.** The
// second question — what the picture at a moment looks like — was answered long
// ago by `PhotonzDocument.drawn(atTimeMS:)`, and the exporter simply asks it
// once per frame. So nothing here knows about AVFoundation, Core Image or a
// file, and the arithmetic that decides how long the file runs is testable
// without writing one.
//
// The other thing here is the one shortcut worth having: a recording NOBODY HAS
// TOUCHED does not need photographing at all, because the file it came from is
// already the answer. That check has to fail safe — anything at all different
// about the document and we re-encode — so rather than listing the properties
// that would matter, it compares the document against what opening that
// recording makes. Anything a future layer property adds shows up in that
// comparison for free.

/// Which moments a video export photographs, and how big each picture is.
public struct VideoFramePlan: Hashable, Sendable {

    /// How many pictures there are.
    public let frameCount: Int
    /// How many of them go by in a second.
    public let fps: Double
    /// How big each one is, in pixels.
    public let size: CGSize
    /// How long the file runs for, in milliseconds.
    public let durationMS: Int
    /// What the encoder is allowed to spend on the picture, in bits per
    /// second. Zero for an animated picture, which has no such budget.
    public let videoBitsPerSecond: Int
    /// What it is allowed to spend on the sound.
    public let audioBitsPerSecond: Int

    public init(frameCount: Int, fps: Double, size: CGSize, durationMS: Int,
                videoBitsPerSecond: Int = 0, audioBitsPerSecond: Int = 128_000) {
        self.frameCount = max(0, frameCount)
        self.fps = max(1, fps)
        self.size = size
        self.durationMS = max(0, durationMS)
        self.videoBitsPerSecond = videoBitsPerSecond
        self.audioBitsPerSecond = audioBitsPerSecond
    }

    /// Nothing to photograph: a document with no time in it.
    public var isEmpty: Bool { frameCount == 0 }

    /// How long one picture is on screen for.
    public var frameDelay: TimeInterval { 1 / fps }

    /// The moment of the document the picture at `index` is taken at.
    ///
    /// Never past the last drawable moment: asking for the frame AT the
    /// duration asks for one past the last one there is, and an empty final
    /// frame reads as the video having broken rather than as it having ended
    /// (`DocumentTime.lastDrawableTimeMS`).
    public func timeMS(at index: Int) -> Int {
        let raw = Int((Double(max(0, index)) * 1000 / fps).rounded())
        return min(raw, max(0, durationMS - 1))
    }
}

public enum DocumentVideoExport {

    /// How fast a written movie runs.
    ///
    /// Thirty, which is the grid a clip's frames are fetched on
    /// (`MovieRef.frameStepMS` is 33ms) and finer than any screen recording the
    /// app makes. Asking for more would photograph the same decoded frame twice
    /// and make the file bigger for it.
    public static let movieFPS: Double = 1000 / Double(MovieRef.frameStepMS)

    /// Which moments to photograph and how big, for a document of this length.
    ///
    /// A movie comes out at the document's own size and at `movieFPS`. An
    /// animated picture takes the size preset the recording Export sheet
    /// already offers, so GIF and HEIC mean the same thing whichever door they
    /// are asked for through (`RecordingExport`).
    public static func plan(durationMS: Int, canvasSize: CGSize,
                            format: RecordingFormat,
                            quality: VideoExportQuality) -> VideoFramePlan {
        let length = max(0, durationMS)
        // A movie is photographed on the document's own frame grid and then
        // encoded within the budget the choice allows, so the choice means the
        // same thing here as it does on a recording (`VideoExportRecipe`).
        let recipe = quality.recipe(format: format, sourceSize: canvasSize, sourceFPS: movieFPS)
        let fps = format.isAnimatedImage ? quality.targetFPS : movieFPS
        let size = format.isAnimatedImage
            ? Geometry.downscaledToFit(canvasSize, maxDimension: quality.maxDimension)
            : recipe.size
        guard length > 0 else {
            return VideoFramePlan(frameCount: 0, fps: fps, size: size, durationMS: 0,
                                  videoBitsPerSecond: recipe.videoBitsPerSecond,
                                  audioBitsPerSecond: recipe.audioBitsPerSecond)
        }
        // At least one picture for anything with any length at all: a held
        // frame lasting a tenth of a second is still a thing somebody made.
        let count = max(1, Int((Double(length) / 1000 * fps).rounded()))
        return VideoFramePlan(frameCount: count, fps: fps, size: size, durationMS: length,
                              videoBitsPerSecond: recipe.videoBitsPerSecond,
                              audioBitsPerSecond: recipe.audioBitsPerSecond)
    }

    /// The nearest size with an even number of pixels on each side, never
    /// bigger. H.264 cannot describe an odd side, so a canvas that is odd still
    /// has to come out as a file that plays.
    static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(2, (size.width.rounded(.down) / 2).rounded(.down) * 2),
               height: max(2, (size.height.rounded(.down) / 2).rounded(.down) * 2))
    }
}

extension PhotonzDocument {

    /// The recording this document is nothing but, where it is nothing but one.
    ///
    /// Nil the moment anything has been done to it: a cut, a trim, a held
    /// frame, a different speed, a sound taken off the picture, anything drawn
    /// over it, any styling on the clip at all. Then the file has to be made,
    /// frame by frame, because the file it came from no longer says what the
    /// document says.
    ///
    /// **It answers by rebuilding rather than by listing.** A list of the
    /// properties that would matter is a list somebody has to remember to add
    /// to, and the day they forget it, an edit is silently dropped out of an
    /// export. So this asks a different question: is this document EXACTLY what
    /// opening that recording makes? Anything at all else, however new, is a
    /// difference and takes the fast path away.
    public var untouchedRecording: MovieRef? {
        guard layers.count == 1, let clip = layers.first, let movie = clip.movie else { return nil }
        let asOpened = PhotonzDocument.recording(movie, name: clip.name, pixelScale: pixelScale)
        guard canvasSize == asOpened.canvasSize,
              documentDurationMS == asOpened.documentDurationMS,
              asOpened.layers.count == 1,
              PhotonzDocument.sameShape(clip, asOpened.layers[0])
        else { return nil }
        return movie
    }

    /// Whether two layers say the same thing about themselves, ignoring the
    /// name they were given and the identity they happen to carry.
    ///
    /// Written through the layer's own Codable rather than field by field,
    /// which is what makes it complete: everything a layer remembers about
    /// itself is in what it writes down, so a property added tomorrow is
    /// compared tomorrow with nothing added here.
    static func sameShape(_ one: Layer, _ other: Layer) -> Bool {
        guard let left = shapeBytes(of: one), let right = shapeBytes(of: other) else { return false }
        return left == right
    }

    private static func shapeBytes(of layer: Layer) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(layer),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        // The identity a layer happens to carry and the name somebody typed
        // change not one pixel of what comes out.
        object.removeValue(forKey: "id")
        object.removeValue(forKey: "name")
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
