import CoreGraphics
import Foundation

// Time in the document (`docs/design/video-surface.md` §2).
//
// The whole model is two sentences: **a document may have a duration, and a
// layer may have an in and an out.** Everything a timeline needs follows from
// those and nothing else is invented here — there is no clip object, no track
// object and no media object, because a clip is a layer that happens to occupy
// time and a track is the layers list turned on its side.
//
// What is deliberately NOT here, so the siblings can be built without reopening
// this: transitions, audio lanes, captions and keyframes. Each of them will
// push back on the model, and the model is right when they can be added without
// it changing shape.
//
// Two clocks live in the app now and keeping them apart is the point of this
// file. An ICON repeats: `MotionTiming` is measured from the top of a lap and
// wraps, and the lap has room past it for a bar to overrun into. A DOCUMENT
// finishes: a `LayerTime` is measured from the first frame, nothing wraps, and
// there is nothing past the last frame to draw. `MotionStrip.swift` said the
// two could not share a ruler before either existed, and they still cannot.

/// The stretch of the document's timeline one layer occupies: a point where it
/// starts and a point where it ends, in milliseconds from the first frame.
///
/// **No pixels, ever.** A clip is a layer whose content is a reference and
/// whose time is this, so cutting a recording into pieces copies nothing and
/// throwing a piece away throws away no frames — the same bargain
/// `VideoCutList` already strikes, said in the document's own units.
public struct LayerTime: Hashable, Codable, Sendable {

    /// The shortest stretch there is. A layer occupying no time is a bar of no
    /// width, which is a bar nobody can take hold of again once they let go —
    /// the same floor `MotionStripDrag` puts under a motion, for the same
    /// reason.
    public static let shortestMS = 10

    /// When the layer arrives, never before the document's own first frame.
    public private(set) var inMS: Int
    /// When it goes. Always at least `shortestMS` after the in.
    public private(set) var outMS: Int

    /// Where inside the layer's OWN source this stretch reads from.
    ///
    /// Nought for anything that is simply placed in time — a title, a shape, an
    /// adjustment. For a piece of a recording it is where in the file that
    /// piece starts, which is what makes trimming reversible: the media either
    /// side is still there, it is merely not being played.
    public private(set) var sourceInMS: Int

    /// How long that source runs for, where there is a source at all. With it
    /// the strip can draw what a trim left OUTSIDE the clip, which is what
    /// keeps a video trim as non-destructive as everything else in the app.
    public private(set) var sourceLengthMS: Int?

    public init(inMS: Int, outMS: Int, sourceInMS: Int = 0, sourceLengthMS: Int? = nil) {
        let start = max(0, inMS)
        self.inMS = start
        self.outMS = max(outMS, start + Self.shortestMS)
        self.sourceInMS = max(0, sourceInMS)
        self.sourceLengthMS = sourceLengthMS.map { max(0, $0) }
    }

    /// How long the layer is on screen for.
    public var lengthMS: Int { outMS - inMS }

    /// Whether this stretch holds a moment.
    ///
    /// Half open: the out is the first moment the layer is NOT there, so two
    /// clips meeting at the same millisecond never both draw on that frame.
    public func contains(ms: Int) -> Bool { ms >= inMS && ms < outMS }

    /// How much source there is before the in point, which is what a trim from
    /// the left put out of play.
    public var spareBeforeMS: Int { sourceLengthMS == nil ? 0 : sourceInMS }

    /// How much source there is after the out point.
    public var spareAfterMS: Int {
        guard let sourceLengthMS else { return 0 }
        return max(0, sourceLengthMS - (sourceInMS + lengthMS))
    }

    /// The same stretch starting somewhere else: the length and the place it
    /// reads from its source both come along, which is what sliding a clip
    /// along the timeline means.
    public func moved(toInMS ms: Int) -> LayerTime {
        let start = max(0, ms)
        return LayerTime(inMS: start, outMS: start + lengthMS,
                         sourceInMS: sourceInMS, sourceLengthMS: sourceLengthMS)
    }

    /// The in dragged, with the out staying put.
    public func withIn(_ ms: Int) -> LayerTime {
        let start = min(max(0, ms), outMS - Self.shortestMS)
        // Pulling the in later reads later into the source by exactly as much,
        // which is how the frames stay where they were rather than sliding.
        return LayerTime(inMS: start, outMS: outMS,
                         sourceInMS: sourceInMS + (start - inMS),
                         sourceLengthMS: sourceLengthMS)
    }

    /// The out dragged, with the in staying put.
    public func withOut(_ ms: Int) -> LayerTime {
        LayerTime(inMS: inMS, outMS: max(ms, inMS + Self.shortestMS),
                  sourceInMS: sourceInMS, sourceLengthMS: sourceLengthMS)
    }

    private enum CodingKeys: String, CodingKey {
        case inMS, outMS, sourceInMS, sourceLengthMS
    }

    /// A stretch that is simply a place in time writes two numbers. The two
    /// about its source are only written where there is one, so a title on a
    /// timeline never carries a recording's bookkeeping.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(inMS, forKey: .inMS)
        try c.encode(outMS, forKey: .outMS)
        if sourceInMS != 0 { try c.encode(sourceInMS, forKey: .sourceInMS) }
        if let sourceLengthMS { try c.encode(sourceLengthMS, forKey: .sourceLengthMS) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(inMS: try c.decode(Int.self, forKey: .inMS),
                  outMS: try c.decode(Int.self, forKey: .outMS),
                  sourceInMS: try c.decodeIfPresent(Int.self, forKey: .sourceInMS) ?? 0,
                  sourceLengthMS: try c.decodeIfPresent(Int.self, forKey: .sourceLengthMS))
    }
}

// MARK: - What a layer says about time

extension Layer {

    /// Whether this layer occupies a stretch of the document's time, which is
    /// the one question that decides whether its row on the strip is a bar or
    /// a heading.
    public var occupiesTime: Bool { time != nil }

    /// Whether this layer or anything inside it occupies time.
    public var occupiesTimeInside: Bool {
        occupiesTime || (group?.children.contains { $0.occupiesTimeInside } ?? false)
    }

    /// Whether this layer is drawn at a moment: inside its own stretch, or at
    /// every moment where it has none. A background has no in and no out and is
    /// on screen the whole way through, which is the case that makes deleting
    /// the layers list impossible (`video-surface.md` §3).
    public func isOnScreen(atTimeMS ms: Int) -> Bool {
        guard let time else { return true }
        return time.contains(ms: ms)
    }
}

// MARK: - What a document says about time

extension PhotonzDocument {

    /// Whether this document has time in it at all: somebody wrote a duration
    /// down, or something in it occupies a stretch.
    ///
    /// False for every document anybody has today, which is what makes the
    /// timeline appear for a recording and for nothing else.
    public var hasTime: Bool {
        durationMS != nil || layers.contains { $0.occupiesTimeInside }
    }

    /// How long the document runs for: the duration written down, else as long
    /// as the last thing in it leaves, else nothing.
    ///
    /// A duration you can write down is not the same as one read off the
    /// layers, and both are needed. Read off the layers, a document could never
    /// hold on a frame after its last clip, because the moment the clip ended
    /// so would the document.
    public var documentDurationMS: Int {
        if let durationMS { return durationMS }
        return allLayers.compactMap { $0.time?.outMS }.max() ?? 0
    }

    /// The length the strip's ruler measures: the document's own duration
    /// where it has one, and one lap of the motion where it does not.
    ///
    /// The two are never added together and never averaged. A document that
    /// finishes is measured by when it finishes; an icon that repeats is
    /// measured by its lap.
    public var timelineLengthMS: Int {
        hasTime ? documentDurationMS : motionCycleLengthMS
    }

    /// The last moment there is a picture at. Asking for the frame AT the
    /// duration is asking for one past the last one there is, and an empty
    /// final frame reads as the video having broken rather than as the video
    /// having ended.
    public var lastDrawableTimeMS: Int { max(0, documentDurationMS - 1) }

    /// **The whole picture as it looks at a moment of the document's own
    /// clock**: everything outside its stretch taken off screen, and everything
    /// that moves sampled there.
    ///
    /// This is what the renderer composites for a frame of video, and it needs
    /// nothing of the renderer's to work out — it hands back an ordinary
    /// document, which the renderer has always known how to draw. The document
    /// itself is untouched, exactly as `moved(toMotionTimeMS:)` leaves it: the
    /// layer you can still drag is the one you drew.
    ///
    /// A document with no time in it is left to the motion path it has always
    /// taken, so nothing about a still picture or an icon changes.
    ///
    /// `framesInHand` is what the window has already read of each recording.
    /// Given, a clip whose frame is still being read shows the newest frame
    /// that has been, rather than nothing (`MovieFramesInHand.swift`). Left
    /// out, every clip points at exactly the frame at the moment, which is
    /// what an export wants: it waits for each frame it writes.
    public func drawn(atTimeMS ms: Int, framesInHand: MovieFramesInHand? = nil) -> PhotonzDocument {
        guard hasTime else { return moved(toMotionTimeMS: ms) }
        let moment = min(max(0, ms), lastDrawableTimeMS)
        var shown = self
        shown.layers = layers.map { $0.shownTree(atTimeMS: moment, framesInHand: framesInHand) }
        // A track switched off, or outsoloed, takes its clips off screen the
        // way their own stretch ending does (`DocumentTracks.swift`).
        let offTrack = layersOffScreenByTrack()
        if !offTrack.isEmpty {
            for index in shown.layers.indices where offTrack.contains(shown.layers[index].id) {
                shown.layers[index].isVisible = false
            }
        }
        // In a document that finishes, the lap IS the document: four seconds in
        // is four seconds in, never four seconds modulo something.
        let cycle = max(1, documentDurationMS)
        shown.layers = shown.layers.map {
            $0.movedTree(atDocumentTimeMS: moment, documentCycleMS: cycle)
        }
        // ...and a cut with a transition on it puts a second picture on screen
        // beside the first, or a panel of colour over it
        // (`ClipTransitions.swift`). Last, so a layer told to fade over the
        // shot is faded and THEN dissolved, rather than the dissolve being
        // overwritten by the fade.
        shown.layers = shown.layers.flatMap {
            $0.withTransitionDrawn(atTimeMS: moment, framesInHand: framesInHand)
        }
        return shown
    }
}

extension Layer {

    /// This layer and everything inside it, with whatever is not on screen at
    /// this moment hidden. A layer already hidden by hand stays hidden: the
    /// timeline decides when something COULD be on screen, and the eye in the
    /// layers list still decides whether it is.
    func shownTree(atTimeMS ms: Int, framesInHand: MovieFramesInHand? = nil) -> Layer {
        var shown = self
        if !isOnScreen(atTimeMS: ms) { shown.isVisible = false }
        // ...and whatever IS on screen and plays a recording shows the frame
        // this moment lands on, which is the whole of "what is drawn at a
        // moment is what the renderer composites for that moment"
        // (`MovieClip.swift`).
        if shown.isVisible { shown = shown.playing(atTimeMS: ms, framesInHand: framesInHand) }
        if shown.isGroup {
            shown.children = children.map { $0.shownTree(atTimeMS: ms, framesInHand: framesInHand) }
        }
        return shown
    }
}

// MARK: - A recording, said in the document's units

extension VideoCutList {

    /// How long the kept pieces run for, in the document's own milliseconds.
    public var documentDurationMS: Int { VideoCutList.ms(timelineDuration) }

    /// The recording's pieces as stretches of a document's timeline: one per
    /// kept piece, laid back to back with no gaps, each remembering where in
    /// the file it came from.
    ///
    /// This is the projection that lets the recording window and a document
    /// made of clip layers agree about time without either owning the other's
    /// arithmetic. It is lossless in the direction that matters: from the
    /// stretches alone, every piece's place in the source file comes back.
    public func layerTimes() -> [LayerTime] {
        let source = VideoCutList.ms(sourceDuration)
        var times: [LayerTime] = []
        var cursor = 0
        for piece in pieces {
            let length = VideoCutList.ms(piece.end) - VideoCutList.ms(piece.start)
            times.append(LayerTime(inMS: cursor, outMS: cursor + length,
                                   sourceInMS: VideoCutList.ms(piece.start),
                                   sourceLengthMS: source))
            cursor += length
        }
        return times
    }

    /// Seconds to whole milliseconds, rounded once and in one place so the
    /// timeline and the source never disagree by a frame's worth of drift.
    static func ms(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite else { return 0 }
        return Int((max(0, seconds) * 1000).rounded())
    }
}

// MARK: - A move on a clip belongs to the clip's own clock

extension Layer {

    /// The moment this layer's own motions are read at, given a moment of the
    /// DOCUMENT's clock.
    ///
    /// For anything simply placed on a canvas the two are the same clock and
    /// nothing changes. For a layer that occupies a stretch of time they are
    /// not, and the difference is the whole of "a punch-in survives a trim": a
    /// clip's frames SLIDE along the timeline when the clip is trimmed, split
    /// or re-ordered, because the pieces are laid back to back from the clip's
    /// in point (`ClipPieces.swift`). A move written against the document's
    /// clock would stay where it was while the frame it was pointing at moved
    /// out from under it. Written against the clip's own source clock it goes
    /// where the frames go, because it is nailed to a FRAME rather than to a
    /// moment of the finished cut.
    public func motionClockMS(atDocumentTimeMS ms: Int) -> Int {
        guard let time else { return ms }
        let offset = ms - time.inMS
        if let pieces = clipPieces, let source = pieces.sourceMS(atMS: offset) { return source }
        return max(0, offset + time.sourceInMS)
    }

    /// The lap this layer's motions are measured against. A clip's is its whole
    /// recording, so nothing inside it ever wraps; everything else takes the
    /// document's.
    func motionCycleMS(documentCycleMS: Int) -> Int {
        guard let time else { return documentCycleMS }
        if let whole = movie?.durationMS, whole > 0 { return whole }
        if let source = time.sourceLengthMS, source > 0 { return source }
        return max(1, time.sourceInMS + time.lengthMS)
    }

    /// This layer and everything inside it moved for a moment of the document's
    /// own clock, with anything that occupies time read on its own clock.
    ///
    /// A layer INSIDE a clip inherits that clip's clock, which is what makes a
    /// label stuck to a moment of a recording travel with it. A layer inside it
    /// that has a stretch of its own answers for itself instead.
    func movedTree(atDocumentTimeMS ms: Int, documentCycleMS: Int,
                   inheritedClockMS: Int? = nil, inheritedCycleMS: Int? = nil,
                   magnification: CGFloat = 1) -> Layer {
        let clock = time == nil ? (inheritedClockMS ?? ms) : motionClockMS(atDocumentTimeMS: ms)
        let cycle = time == nil
            ? (inheritedCycleMS ?? documentCycleMS)
            : motionCycleMS(documentCycleMS: documentCycleMS)
        var moved = moved(toMotionTimeMS: clock, cycleMS: cycle, magnification: magnification)
        if var group = moved.group {
            let inside = magnification * motionMagnification(atMS: clock, cycleMS: cycle)
            group.children = group.children.map {
                $0.movedTree(atDocumentTimeMS: ms, documentCycleMS: documentCycleMS,
                             inheritedClockMS: clock, inheritedCycleMS: cycle,
                             magnification: inside)
            }
            moved.content = .group(group)
        }
        return moved
    }
}
