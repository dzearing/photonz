import CoreGraphics
import Foundation

// A zoom region on a clip: a stretch of the recording where one spot of the
// picture fills the frame, eased in and out, and able to follow the pointer
// the recorder took down (`PointerTrack.swift`).
//
// The user, 2026-09-30: "a rectangle region that zooms a particular spot. If it
// can follow the mouse, that's amazing." Screen Studio's auto-zoom is the
// grown-up tool here, and its shape is the one kept: a bar on the clip for WHEN,
// a box on the picture for WHERE.
//
// **It is not Scale and Position.** A punch-in (`ClipReframe.swift`) grows the
// clip's box, which is right for a camera move a person keys by hand and wrong
// for this: a clip laid out smaller than the frame would grow out over
// everything beside it, and following the pointer would be a key every frame.
// A zoom instead chooses which part of the recording the clip's box SHOWS, so
// the box never moves and the picture inside it does. It is drawn as a window
// into the picture at the moment (`Layer.zoomWindow`), set on the drawn
// document only, so playback, scrubbing and every export read the one answer.
//
// Everything is on the clip's own clock, the recording's milliseconds
// (`Layer.motionClockMS(atDocumentTimeMS:)`), for the reason punch-ins are: a
// zoom is nailed to the frames it frames, so trimming the clip or cutting it
// takes the zoom with its frames. It is also the clock the pointer was taken
// down on, which is what lets a zoom follow it without converting anything.

/// One zoom region on a clip.
public struct ClipZoom: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Where the zoom starts to ease in and finishes easing out, on the clip's
    /// own clock.
    public var startMS: Int
    public var endMS: Int
    /// How long the way in and the way out take.
    public var easeInMS: Int
    public var easeOutMS: Int
    /// How far in: 2 shows half the width of the picture you can see across
    /// the whole of it (`ZoomStage.swift`).
    public var scale: Double
    /// The middle of the spot, a point of the recording as fractions of the
    /// whole recording from its top-left, so a crop made afterwards leaves the
    /// zoom on what it was on.
    public var center: CGPoint
    /// Whether the region rides along with the recorded pointer rather than
    /// staying on `center`.
    public var followsCursor: Bool
    /// The stretch of the pointer's path this zoom follows, taken from the
    /// recording's record when following was turned on (`bakeCursor`). Kept
    /// here rather than read from beside the file, so an export, a copy of the
    /// document and a machine without the record all draw the same thing.
    public var cursor: PointerTrack?
    /// True on every zoom aimed at the part of the clip that is seen: its spot
    /// a point of the recording and its scale against the picture seen. Nil
    /// on a zoom written before, whose numbers were fractions of the clip's
    /// whole frame; a document is read into these on opening
    /// (`PhotonzDocument.aimingZoomsAtWhatIsSeen`).
    public var aimedAtWhatIsSeen: Bool?

    public init(id: UUID = UUID(), startMS: Int, endMS: Int,
                easeInMS: Int = ClipZoom.defaultEaseMS, easeOutMS: Int = ClipZoom.defaultEaseMS,
                scale: Double = ClipZoom.defaultScale, center: CGPoint = CGPoint(x: 0.5, y: 0.5),
                followsCursor: Bool = false, cursor: PointerTrack? = nil) {
        self.id = id
        self.startMS = startMS
        self.endMS = endMS
        self.easeInMS = easeInMS
        self.easeOutMS = easeOutMS
        self.scale = scale
        self.center = center
        self.followsCursor = followsCursor
        self.cursor = cursor
        self.aimedAtWhatIsSeen = true
    }

    // MARK: The numbers

    /// How long a zoom added at the playhead runs: long enough to read what
    /// it shows, short enough that the next thing is not missed.
    public static let defaultLengthMS = 3000
    /// How long the way in and out take: a camera leaning in, not a cut.
    public static let defaultEaseMS = 700
    /// The longest an ease may be set to by its handle.
    public static let longestEaseMS = 3000
    /// The shortest a zoom may be: below this it reads as a jolt.
    public static let shortestMS = 500
    /// Twice: enough to read a button, not so far that the context is lost.
    public static let defaultScale = 2.0
    /// As far in as a zoom goes; past this there is nothing left to see.
    public static let mostScale = 8.0
    /// How close to the edge of the frame the pointer may come, as a share of
    /// the frame, before a following zoom moves to keep it in.
    public static let followMargin: CGFloat = 0.15
    /// How softly a following zoom moves: the spread, either side of the
    /// moment, that the pointer's path is averaged over.
    public static let followSmoothingMS = 300
    /// How far either side of the zoom its baked path reaches, so the average
    /// at its first and last moments has something to average.
    public static let cursorReachMS = 1000
    /// How often a baked path keeps a point: about thirty a second, which is
    /// plenty under the averaging and keeps the document small.
    public static let cursorStepMS = 33

    public var lengthMS: Int { endMS - startMS }

    /// The spot itself on a clip seen whole, as fractions of the picture.
    public var region: CGRect { region(on: .whole) }

    /// The spot itself, as fractions of the picture SEEN: square in those
    /// fractions, which is the seen picture's own shape once it is laid over
    /// it, and slid back inside it where the middle is too near an edge.
    public func region(on stage: ZoomStage) -> CGRect {
        Self.region(scale: scale, center: stage.toStage(center))
    }

    public static func region(scale: Double, center: CGPoint) -> CGRect {
        let size = CGFloat(1 / max(1, scale))
        let half = size / 2
        let x = min(max(center.x, half), 1 - half)
        let y = min(max(center.y, half), 1 - half)
        return CGRect(x: x - half, y: y - half, width: size, height: size)
    }

    /// The zoom that shows all of a box drawn on the picture (fractions of
    /// it): the smaller of the two fits, so nothing inside the box falls off
    /// the edge, the same rule `ClipReframe.scalePercent` uses. Nil for a box
    /// too small to be anything but a slip of the hand.
    public static func fitting(_ box: CGRect) -> (scale: Double, center: CGPoint)? {
        let box = box.standardized
        guard box.width >= 0.01, box.height >= 0.01 else { return nil }
        let fit = Double(min(1 / box.width, 1 / box.height))
        guard fit.isFinite else { return nil }
        return (min(max(fit, 1), mostScale), CGPoint(x: box.midX, y: box.midY))
    }

    /// The two eases, shared out where together they are longer than the zoom.
    public var eases: (inMS: Int, outMS: Int) {
        let easeIn = max(0, easeInMS)
        let easeOut = max(0, easeOutMS)
        let total = easeIn + easeOut
        guard total > lengthMS, total > 0 else { return (easeIn, easeOut) }
        let shareIn = Int((Double(lengthMS) * Double(easeIn) / Double(total)).rounded())
        return (shareIn, max(0, lengthMS) - shareIn)
    }

    // MARK: At a moment

    /// How far in at a moment of the clip's clock: nought outside the zoom,
    /// one while it holds, and eased in between.
    public func amount(atMS ms: Int) -> Double {
        guard ms >= startMS, ms < endMS else { return 0 }
        let (easeIn, easeOut) = eases
        if easeIn > 0, ms < startMS + easeIn {
            return Self.eased(Double(ms - startMS) / Double(easeIn))
        }
        if easeOut > 0, ms > endMS - easeOut {
            return Self.eased(Double(endMS - ms) / Double(easeOut))
        }
        return 1
    }

    /// Slow off the mark and slow to settle, with no jolt at either end.
    static func eased(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    /// The part of the picture shown at a moment, as fractions of it, or nil
    /// when the whole picture is.
    ///
    /// On the way in the frame closes on the spot as a straight dolly: every
    /// window between the whole picture and the region is the whole picture
    /// shrunk about ONE fixed point, the one the two line up on, so the spot
    /// never slides sideways as it arrives. The size closes geometrically, so
    /// the zoom feels as quick at the end as at the start.
    public func window(atMS ms: Int, on stage: ZoomStage = .whole) -> CGRect? {
        let progress = amount(atMS: ms)
        guard progress > 0, scale > 1.001 else { return nil }
        let goal = target(atMS: ms, on: stage)
        let factor = pow(scale, progress)
        let shrink = 1 - 1 / CGFloat(scale)
        guard shrink > 0 else { return nil }
        let anchor = CGPoint(x: goal.minX / shrink, y: goal.minY / shrink)
        let size = 1 / CGFloat(factor)
        return CGRect(x: anchor.x * (1 - size), y: anchor.y * (1 - size), width: size, height: size)
    }

    /// The region the zoom is on at a moment once it has arrived, as
    /// fractions of the picture seen: where a following zoom has the pointer,
    /// and the spot otherwise. This is the box the picture shows when the zoom
    /// is picked.
    public func target(atMS ms: Int, on stage: ZoomStage = .whole) -> CGRect {
        followsCursor ? (followedRegion(atMS: ms, on: stage) ?? region(on: stage)) : region(on: stage)
    }

    // MARK: Following the pointer

    /// Keep the stretch of `track` this zoom needs, thinned, in the recording's
    /// own pixels.
    public mutating func bakeCursor(from track: PointerTrack?) {
        guard let track, !track.samples.isEmpty else {
            cursor = nil
            return
        }
        let from = startMS - Self.cursorReachMS
        let to = endMS + Self.cursorReachMS
        var kept: [PointerSample] = []
        var ms = from
        while ms <= to {
            if let p = track.position(atMS: ms) { kept.append(PointerSample(ms: ms, x: p.x, y: p.y)) }
            ms += Self.cursorStepMS
        }
        cursor = PointerTrack(pixelSize: track.pixelSize, samples: kept, clicks: [])
    }

    /// Where the pointer was, as fractions of the recording.
    func pointer(atMS ms: Int) -> CGPoint? {
        guard let cursor, cursor.pixelSize.width > 0, cursor.pixelSize.height > 0,
              let p = cursor.position(atMS: ms) else { return nil }
        return CGPoint(x: p.x / cursor.pixelSize.width, y: p.y / cursor.pixelSize.height)
    }

    /// The region at a moment of a following zoom: centred on the pointer's
    /// path averaged over a moment either side, so the frame glides through
    /// the pointer's jitters instead of copying them, then pushed only as far
    /// as keeps the pointer itself clear of the frame's edge.
    func followedRegion(atMS ms: Int, on stage: ZoomStage = .whole) -> CGRect? {
        guard let now = pointer(atMS: ms).map(stage.toStage) else { return nil }
        let sigma = Double(Self.followSmoothingMS)
        var sum = CGPoint.zero
        var weights = 0.0
        for step in -8...8 {
            let offset = Double(step) * sigma / 4
            guard let p = pointer(atMS: ms + Int(offset.rounded())).map(stage.toStage) else { continue }
            let w = exp(-(offset * offset) / (2 * sigma * sigma))
            sum.x += p.x * w
            sum.y += p.y * w
            weights += w
        }
        guard weights > 0 else { return nil }
        var middle = CGPoint(x: sum.x / weights, y: sum.y / weights)
        let size = CGFloat(1 / max(1, scale))
        let reach = size * (0.5 - Self.followMargin)
        middle.x = min(max(middle.x, now.x - reach), now.x + reach)
        middle.y = min(max(middle.y, now.y - reach), now.y + reach)
        return Self.region(scale: scale, center: middle)
    }

    // MARK: Suggesting

    /// Clicks closer together than this are one thing being done, and get one zoom.
    public static let clusterGapMS = 2500
    /// How long before the first click a suggested zoom sets off, so it has
    /// arrived by the time the click lands.
    public static let suggestedLeadMS = 900
    /// How long after the last click it stays, so what the click did is seen.
    public static let suggestedTailMS = 1500
    /// How tight a suggestion frames: never past twice, never under this.
    public static let suggestedScales = 1.3...2.0
    /// How much room round the clicks a suggestion leaves, a share of the picture.
    public static let suggestedPadding: CGFloat = 0.08

    /// Zooms around the clicks of a recording: one for each run of clicks
    /// close together in time, framing all of them, arriving just before the
    /// first and leaving after the last. None lands on a zoom already in
    /// `existing`, and every one stays inside `sourceRange`.
    ///
    /// Framed on the picture seen (`stage`): the box fits round the clicks as
    /// they are on screen, at the picture seen's shape.
    public static func suggestions(clicks: [PointerClick], pixelSize: CGSize,
                                   sourceRange: ClosedRange<Int>,
                                   keepingClearOf existing: [ClipZoom],
                                   on stage: ZoomStage = .whole) -> [ClipZoom] {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return [] }
        let sorted = clicks.filter { sourceRange.contains($0.downMS) }.sorted { $0.downMS < $1.downMS }
        var runs: [[PointerClick]] = []
        for click in sorted {
            if let last = runs.last?.last, click.downMS - last.downMS <= clusterGapMS {
                runs[runs.count - 1].append(click)
            } else {
                runs.append([click])
            }
        }
        var taken = existing
        var made: [ClipZoom] = []
        for run in runs {
            guard let first = run.first, let last = run.last else { continue }
            let points = run.map {
                stage.toStage(CGPoint(x: $0.point.x / pixelSize.width, y: $0.point.y / pixelSize.height))
            }
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            let box = CGRect(x: (xs.min() ?? 0.5) - suggestedPadding,
                             y: (ys.min() ?? 0.5) - suggestedPadding,
                             width: (xs.max() ?? 0.5) - (xs.min() ?? 0.5) + 2 * suggestedPadding,
                             height: (ys.max() ?? 0.5) - (ys.min() ?? 0.5) + 2 * suggestedPadding)
            let fit = fitting(box)?.scale ?? suggestedScales.upperBound
            let scale = min(max(fit, suggestedScales.lowerBound), suggestedScales.upperBound)
            let start = max(sourceRange.lowerBound, first.downMS - suggestedLeadMS)
            let end = min(sourceRange.upperBound, last.downMS + suggestedTailMS)
            guard end - start >= shortestMS else { continue }
            let middle = region(scale: scale, center: CGPoint(x: box.midX, y: box.midY))
            let zoom = ClipZoom(startMS: start, endMS: end, scale: scale,
                                center: stage.fromStage(CGPoint(x: middle.midX, y: middle.midY)))
            guard !taken.contains(where: { $0.startMS < zoom.endMS && zoom.startMS < $0.endMS }) else { continue }
            taken.append(zoom)
            made.append(zoom)
        }
        return made
    }
}

// MARK: - On the clip

extension Layer {

    /// Whether this layer can take a zoom: it plays a recording.
    public var takesAZoom: Bool { movie != nil && time != nil }

    /// The stretch of the recording this clip plays, on its own clock.
    public var zoomSourceRange: ClosedRange<Int>? {
        guard let pieces = clipPieces else { return nil }
        let playing = pieces.pieces.filter { !$0.isHeld }
        guard let low = playing.map(\.sourceInMS).min(),
              let high = playing.map(\.sourceOutMS).max(), high > low else { return nil }
        return low...high
    }

    /// The zoom playing at a moment of the clip's own clock.
    public func zoom(atSourceMS ms: Int) -> ClipZoom? {
        zooms?.first { ms >= $0.startMS && ms < $0.endMS }
    }

    /// The part of the clip's picture a zoom fills its frame with at a moment
    /// of the DOCUMENT's clock, or nil when the clip shows its whole picture
    /// then. `stage` is the part of the clip seen at that moment, which is
    /// what the zoom's box is drawn on and fills (`ZoomStage.swift`).
    public func zoomWindow(atDocumentTimeMS ms: Int, on stage: ZoomStage = .whole) -> CGRect? {
        guard let zooms, !zooms.isEmpty, takesAZoom else { return nil }
        let clock = motionClockMS(atDocumentTimeMS: ms)
        return zoom(atSourceMS: clock)?.window(atMS: clock, on: stage).map(stage.pictureWindow(forStageWindow:))
    }

    /// How much bigger than its share of the frame the picture is drawn at a
    /// moment: what a frame is worth reading at to stay sharp.
    public func zoomFactor(atDocumentTimeMS ms: Int) -> Double {
        guard let window = zoomWindow(atDocumentTimeMS: ms), window.width > 0 else { return 1 }
        return Double(1 / window.width)
    }

    /// The same, at a moment of the clip's own clock: what a frame of the
    /// recording read for that moment is worth reading at.
    public func zoomFactor(atSourceMS ms: Int) -> Double {
        guard takesAZoom, let window = zoom(atSourceMS: ms)?.window(atMS: ms), window.width > 0 else { return 1 }
        return Double(1 / window.width)
    }

    /// Where a zoom lands on the DOCUMENT's timeline: the first moment each
    /// of its ends plays. Nil where the clip never plays that stretch.
    public func timelineSpanMS(of id: UUID?) -> (start: Int, end: Int)? {
        guard let id, let zoom = zooms?.first(where: { $0.id == id }),
              let time, let pieces = clipPieces else { return nil }
        guard let start = pieces.offsetMS(ofSourceMS: zoom.startMS, leaning: .forward),
              let end = pieces.offsetMS(ofSourceMS: zoom.endMS, leaning: .backward),
              end > start else { return nil }
        return (time.inMS + start, time.inMS + end)
    }

    /// The clip with the window its zoom shows at a moment of the document's
    /// clock put on it, for drawing. This is the clip as DRAWN at that moment,
    /// put at `origin` by its parents on a canvas `canvas` big, which is what
    /// says how much of it is seen.
    func withZoomShown(atDocumentTimeMS ms: Int, origin: CGPoint, canvas: CGSize) -> Layer {
        var shown = self
        if isVisible, zooms?.isEmpty == false, takesAZoom,
           let window = zoomWindow(atDocumentTimeMS: ms, on: ZoomStage.of(self, origin: origin, canvas: canvas)) {
            shown.zoomWindow = window
        }
        if shown.isGroup {
            let inside = CGPoint(x: origin.x + frame.origin.x, y: origin.y + frame.origin.y)
            shown.children = shown.children.map {
                $0.withZoomShown(atDocumentTimeMS: ms, origin: inside, canvas: canvas)
            }
        }
        return shown
    }
}

extension ClipPieces {

    /// Which way a moment of the recording that falls on a cut is read.
    public enum Leaning: Sendable { case forward, backward }

    /// The first moment of the clip at which a moment of its recording plays:
    /// the way back from `sourceMS(atMS:)`. A moment the clip has cut out is
    /// read as the nearest moment it does play, onward for a start and back
    /// for an end, so a stretch partly cut away still lands on what is left.
    public func offsetMS(ofSourceMS source: Int, leaning: Leaning) -> Int? {
        var elapsed = 0
        var best: (distance: Int, offset: Int)?
        for piece in pieces {
            defer { elapsed += piece.lengthMS }
            guard !piece.isHeld, piece.sourceLengthMS > 0 else { continue }
            let speed = Double(max(1, piece.speedPercent)) / 100
            if source >= piece.sourceInMS, source <= piece.sourceOutMS {
                let inside = Int((Double(source - piece.sourceInMS) / speed).rounded())
                return elapsed + min(inside, piece.lengthMS)
            }
            // Nearest playing moment in the way it leans.
            switch leaning {
            case .forward where piece.sourceInMS > source:
                let distance = piece.sourceInMS - source
                if best == nil || distance < (best?.distance ?? .max) { best = (distance, elapsed) }
            case .backward where piece.sourceOutMS < source:
                let distance = source - piece.sourceOutMS
                if best == nil || distance < (best?.distance ?? .max) {
                    best = (distance, elapsed + piece.lengthMS)
                }
            default:
                break
            }
        }
        return best?.offset
    }
}

// MARK: - Making and changing them

extension PhotonzDocument {

    /// Whether anything in this document zooms.
    var hasZooms: Bool {
        allLayers.contains { $0.zooms?.isEmpty == false }
    }

    /// Add a zoom to a clip, starting at a moment of the document and running
    /// `ClipZoom.defaultLengthMS`, cut short where the clip or the next zoom
    /// comes first. Centred on `around` (fractions of the picture) when given,
    /// the middle otherwise. Nil where the playhead is not on the clip, is
    /// already inside a zoom, or there is no room for one.
    @discardableResult
    public mutating func addZoom(toClip id: UUID, atTimeMS ms: Int, around point: CGPoint?) -> ClipZoom? {
        guard let layer = layer(id: id), layer.takesAZoom, let time = layer.time,
              time.contains(ms: ms), let range = layer.zoomSourceRange,
              let pieces = layer.clipPieces,
              let pieceIndex = pieces.pieceIndex(atMS: ms - time.inMS),
              let piece = pieces.piece(at: pieceIndex), !piece.isHeld else { return nil }
        let start = layer.motionClockMS(atDocumentTimeMS: ms)
        let zooms = layer.zooms ?? []
        guard layer.zoom(atSourceMS: start) == nil else { return nil }
        let nextStart = zooms.map(\.startMS).filter { $0 > start }.min() ?? Int.max
        let end = min(start + ClipZoom.defaultLengthMS, piece.sourceOutMS, range.upperBound, nextStart)
        guard end - start >= ClipZoom.shortestMS else { return nil }
        var zoom = ClipZoom(startMS: start, endMS: end)
        // On the pointer where it was, or the middle of what is seen.
        let stage = zoomStage(ofClip: id, atTimeMS: ms) ?? .whole
        zoom.center = zoom.keptOn(stage, center: point ?? stage.fromStage(CGPoint(x: 0.5, y: 0.5)))
        updateLayer(id: id) { $0.zooms = (zooms + [zoom]).sorted { $0.startMS < $1.startMS } }
        return zoom
    }

    /// Change a zoom, and keep it sensible: inside the stretch the clip plays,
    /// clear of the zooms either side of it, at least `ClipZoom.shortestMS`
    /// long, with its spot inside the picture.
    ///
    /// A zoom that moved keeps its length where it can, so carrying a bar into
    /// a neighbour stops it against the neighbour rather than squashing it.
    public mutating func updateZoom(onClip id: UUID, id zoomID: UUID, cursorTrack: PointerTrack? = nil,
                                    _ change: (inout ClipZoom) -> Void) {
        guard let layer = layer(id: id), var zooms = layer.zooms,
              let index = zooms.firstIndex(where: { $0.id == zoomID }),
              let range = layer.zoomSourceRange else { return }
        let before = zooms[index]
        var zoom = before
        change(&zoom)
        let others = zooms.enumerated().filter { $0.offset != index }.map(\.element)
        let floor = max(range.lowerBound,
                        others.filter { $0.startMS < before.startMS }.map(\.endMS).max() ?? Int.min)
        let ceiling = min(range.upperBound,
                          others.filter { $0.startMS > before.startMS }.map(\.startMS).min() ?? Int.max)
        let moved = zoom.startMS != before.startMS && zoom.endMS != before.endMS
        if moved {
            let length = min(max(ClipZoom.shortestMS, zoom.lengthMS), ceiling - floor)
            zoom.startMS = min(max(zoom.startMS, floor), ceiling - length)
            zoom.endMS = zoom.startMS + length
        } else {
            zoom.startMS = min(max(zoom.startMS, floor), ceiling)
            zoom.endMS = min(max(zoom.endMS, floor), ceiling)
            if zoom.endMS - zoom.startMS < ClipZoom.shortestMS {
                if zoom.endMS != before.endMS {
                    zoom.endMS = min(ceiling, zoom.startMS + ClipZoom.shortestMS)
                    zoom.startMS = min(zoom.startMS, zoom.endMS - ClipZoom.shortestMS)
                } else {
                    zoom.startMS = max(floor, zoom.endMS - ClipZoom.shortestMS)
                    zoom.endMS = max(zoom.endMS, zoom.startMS + ClipZoom.shortestMS)
                }
            }
        }
        zoom.easeInMS = min(max(0, zoom.easeInMS), ClipZoom.longestEaseMS)
        zoom.easeOutMS = min(max(0, zoom.easeOutMS), ClipZoom.longestEaseMS)
        zoom.scale = min(max(1, zoom.scale), ClipZoom.mostScale)
        // Its box inside the picture seen where it starts.
        let start = layer.timelineSpanMS(of: zoomID).map(\.start)
        let stage = zoomStage(ofClip: id, atTimeMS: start) ?? .whole
        zoom.center = zoom.keptOn(stage, center: zoom.center)
        if zoom.followsCursor, let cursorTrack,
           !before.followsCursor || zoom.startMS != before.startMS || zoom.endMS != before.endMS
            || zoom.cursor == nil {
            zoom.bakeCursor(from: cursorTrack)
        }
        if !zoom.followsCursor { zoom.cursor = nil }
        zooms[index] = zoom
        updateLayer(id: id) { $0.zooms = zooms.sorted { $0.startMS < $1.startMS } }
    }

    /// Take a zoom off a clip.
    @discardableResult
    public mutating func removeZoom(onClip id: UUID, id zoomID: UUID) -> Bool {
        guard let zooms = layer(id: id)?.zooms, zooms.contains(where: { $0.id == zoomID }) else { return false }
        let kept = zooms.filter { $0.id != zoomID }
        updateLayer(id: id) { $0.zooms = kept.isEmpty ? nil : kept }
        return true
    }

    /// Add the zooms `ClipZoom.suggestions` proposes for a clip's clicks.
    /// Answers the ones added.
    @discardableResult
    public mutating func addSuggestedZooms(toClip id: UUID, clicks: [PointerClick]) -> [ClipZoom] {
        guard let layer = layer(id: id), layer.takesAZoom, let movie = layer.movie,
              let range = layer.zoomSourceRange else { return [] }
        let made = ClipZoom.suggestions(clicks: clicks, pixelSize: movie.pixelSize,
                                        sourceRange: range, keepingClearOf: layer.zooms ?? [],
                                        on: zoomStage(ofClip: id, atTimeMS: layer.time?.inMS) ?? .whole)
        guard !made.isEmpty else { return [] }
        updateLayer(id: id) { $0.zooms = (($0.zooms ?? []) + made).sorted { $0.startMS < $1.startMS } }
        return made
    }
}

extension ClipZoom {
    /// `center` (a point of the recording) moved as little as keeps this
    /// zoom's box inside the picture seen.
    func keptOn(_ stage: ZoomStage, center: CGPoint) -> CGPoint {
        let box = Self.region(scale: scale, center: stage.toStage(center))
        return stage.fromStage(CGPoint(x: box.midX, y: box.midY))
    }
}
