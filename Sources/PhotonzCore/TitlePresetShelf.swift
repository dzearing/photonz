import CoreGraphics
import Foundation

// Title pages and name cards on the Library shelf (`docs/design/video-titles.md`,
// "On the Library shelf", task `title-page-and-name-card-presets-are-tiles-on-th`).
//
// The mock places a lower third by dragging it out of the Library at scope
// Components onto a track (`video-title-wt.html`, step 10). So every preset,
// the app's and the person's own, is a tile there: a picture of it at rest,
// double clicked to land at the playhead exactly as Sequence > Insert does,
// or dragged onto a track to land under the pointer. What lands is the same
// group of ordinary layers either way (`TitlePresets.swift`).

/// A preset as the Library holds it: one of the app's, or one a person saved.
public enum TitlePreset: Hashable, Sendable, Identifiable {
    case builtIn(BuiltInTitle)
    case saved(SavedTitlePreset)
    /// One of the charts (`AnimatedChart.swift`), drawn from its sample data.
    case chart(ChartKind)

    /// The tile's id on the shelf, and what a drag carries. Never a bare
    /// UUID, so it can never be read as a component's.
    public var id: String {
        switch self {
        case .builtIn(let preset): "title.builtIn.\(preset.rawValue)"
        case .saved(let saved): Self.id(ofSaved: saved.id)
        case .chart(let kind): "title.chart.\(kind.rawValue)"
        }
    }

    /// The shelf id of a person's own preset, from its id alone.
    public static func id(ofSaved id: UUID) -> String { "title.saved.\(id.uuidString)" }

    public var name: String {
        switch self {
        case .builtIn(let preset): preset.name
        case .saved(let saved): saved.name
        case .chart(let kind): kind.name
        }
    }

    public var kind: TitleKind {
        switch self {
        case .builtIn(let preset): preset.kind
        case .saved(let saved): saved.kind
        case .chart: .chart
        }
    }

    /// How long it runs once it lands, which is how long its ghost is drawn.
    public var lengthMS: Int {
        switch self {
        case .builtIn(let preset): preset.kind.lengthMS
        case .saved(let saved): saved.lengthMS
        case .chart: TitleKind.chart.lengthMS
        }
    }

    public var isOwn: Bool {
        if case .saved = self { return true }
        return false
    }

    /// The tile on the shelf: its name, and under it the kind, said as yours
    /// when it is.
    public var entry: LibraryEntry {
        LibraryEntry(id: id, scope: .components, name: name,
                     detail: isOwn ? "Your \(kind.name)" : kind.name)
    }

    /// Every preset on the shelf: title pages, then name cards, each kind with
    /// the person's own first, the order the Insert menus list them in.
    public static func shelf(saved: [SavedTitlePreset], movingBackdrops: Bool = true,
                             charts: Bool = true) -> [TitlePreset] {
        TitleKind.offered(charts: charts).flatMap { kind in
            saved.filter { $0.kind == kind }.map(TitlePreset.saved) + builtIn(of: kind, movingBackdrops: movingBackdrops)
        }
    }

    /// The app's own presets of one kind, in shelf order.
    public static func builtIn(of kind: TitleKind, movingBackdrops: Bool = true) -> [TitlePreset] {
        kind == .chart
            ? ChartKind.allCases.map(TitlePreset.chart)
            : BuiltInTitle.presets(of: kind, movingBackdrops: movingBackdrops).map(TitlePreset.builtIn)
    }

    /// The preset a tile id or a drag names, nil when it names none, or names
    /// one of the person's own that has since been forgotten.
    public init?(entryID: String, saved: [SavedTitlePreset]) {
        let builtInPrefix = "title.builtIn.", savedPrefix = "title.saved.", chartPrefix = "title.chart."
        if entryID.hasPrefix(chartPrefix),
           let kind = ChartKind(rawValue: String(entryID.dropFirst(chartPrefix.count))) {
            self = .chart(kind)
        } else if entryID.hasPrefix(builtInPrefix),
           let preset = BuiltInTitle(rawValue: String(entryID.dropFirst(builtInPrefix.count))) {
            self = .builtIn(preset)
        } else if entryID.hasPrefix(savedPrefix),
                  let id = UUID(uuidString: String(entryID.dropFirst(savedPrefix.count))),
                  let found = saved.first(where: { $0.id == id }) {
            self = .saved(found)
        } else {
            return nil
        }
    }

    // MARK: The picture on the tile

    /// What a name card is pictured over: a quiet dark frame, the way Final
    /// Cut's title browser shows a title over a sample, so white words and
    /// a white card both read.
    static let backdrop = Paint(hex: "#2B3242", kind: .linear,
                                stops: [GradientStop(hex: "#3A4358", position: 0),
                                        GradientStop(hex: "#1C212C", position: 1)],
                                angle: 160)

    /// The shape of a tile's picture well (`LibraryShelfLayout.Sizing.card`).
    static let tileAspect: CGFloat = 16.0 / 10.0

    /// The picture on the preset's tile, about `width` pixels across (a name
    /// card's corner lands within a tenth of it), for a document
    /// whose frame is `frame`: the preset at rest, landed the way an insert
    /// lands it and drawn at the moment it has finished arriving, as a still.
    ///
    /// A title page is the whole frame. A name card on the whole frame is a
    /// speck in its corner, so its picture is the bottom left of the frame
    /// it sits in, in the tile's own shape, over a backdrop: big enough to
    /// read, still plainly low in the frame. Nil only when the preset has no
    /// words to land.
    ///
    /// `recording` is a frame of the person's own recording, filed under that
    /// ref: where the style uses the recording (glass over it, or a name card
    /// that lies over it) it is pictured over that instead of a stand-in.
    public func preview(frame: CGSize, width: CGFloat, recording: ImageRef? = nil) -> PhotonzDocument? {
        pictures(frame: frame, width: width, recording: recording) { _ in [] }?.first
    }

    /// The tile playing: the preset drawn at a run of moments `fps` a second,
    /// from its first frame until a moment after every part has arrived, then
    /// its way off, then a beat of nothing, as `TitleTileReel`.
    public func reel(frame: CGSize, width: CGFloat, recording: ImageRef? = nil, fps: Int = 20) -> TitleTileReel? {
        var moments: [Int] = []
        let step = 1000 / max(1, fps)
        guard let drawn = pictures(frame: frame, width: width, recording: recording, rest: false, at: { doc in
            guard let layer = doc.layers.last, let time = layer.time else { return [] }
            let arrived = doc.titleArrivalMS(layerID: layer.id)
            let length = time.lengthMS
            let leaving = max(doc.titleRecipe(layerID: layer.id)?.compiled.outLengthMS ?? 0,
                              layer.pictureFadeMS(.out))
            let held = min(arrived + TitleTileReel.holdMS, length)
            let away = max(held, length - leaving - step)
            var at = 0
            while at < held { moments.append(at); at += step }
            at = away
            while at < length { moments.append(at); at += step }
            moments.append(max(0, length - 1))
            return moments.map { time.inMS + $0 }
        }), !drawn.isEmpty else { return nil }
        // The way back to the start: a beat of the last frame, nothing up.
        let frames = drawn.count
        let lap = frames * step + TitleTileReel.gapMS
        let keyTimes = (0..<frames).map { Double($0 * step) / Double(lap) } + [1]
        return TitleTileReel(pictures: drawn, keyTimes: keyTimes, lapMS: lap)
    }

    /// The preset landed, then drawn at each moment `at` names (at rest when
    /// it names none), each picture with no time left in it.
    private func pictures(frame: CGSize, width: CGFloat, recording: ImageRef?, rest: Bool = true,
                          at moments: (PhotonzDocument) -> [Int]) -> [PhotonzDocument]? {
        guard frame.width > 0, frame.height > 0, width > 0 else { return nil }
        let canvas = CGSize(width: width, height: max(1, (width * frame.height / frame.width).rounded()))
        guard kind == .nameCard else {
            guard let landed = land(on: canvas, under: usesTheRecording ? recording : nil) else { return nil }
            return drawn(landed, at: moments(landed))
        }
        // Drawn once to find the corner, then again large enough that the
        // corner alone is `width` across, so the words are drawn at the size
        // they are seen rather than blown up.
        guard let first = land(on: canvas, under: nil), let card = Self.atRest(first)?.layers.last?.localBounds
        else { return nil }
        let scale = canvas.width / max(1, Self.corner(around: card, in: canvas).width)
        let large = CGSize(width: (canvas.width * scale).rounded(), height: (canvas.height * scale).rounded())
        guard let landed = land(on: large, under: nil), let rested = Self.atRest(landed),
              let box = rested.layers.last?.localBounds else { return nil }
        let region = Self.corner(around: box, in: large)
        return drawn(landed, at: moments(landed)).map { picture in
            var picture = picture
            for index in picture.layers.indices {
                picture.layers[index].frame.origin.x -= region.minX
                picture.layers[index].frame.origin.y -= region.minY
            }
            picture.canvasSize = region.size
            let behind: Layer
            if let recording {
                behind = Layer(name: "Recording", content: .image(recording),
                               frame: CGRect(x: -region.minX, y: -region.minY,
                                             width: large.width, height: large.height))
            } else {
                behind = TitlePen(canvas: region.size).fullFrame(Self.backdrop)
            }
            picture.layers.insert(behind, at: 0)
            return picture
        }
    }

    /// Whether this preset is pictured over the recording rather than over a
    /// frame of its own: one whose background is glass.
    public var usesTheRecording: Bool {
        switch self {
        case .builtIn(let preset): preset.usesTheRecording
        case .saved(let saved): saved.layer.group?.titleRecipe?.background == .glass
        case .chart: false
        }
    }

    /// The bottom left of `canvas` holding `card` with room round it, in the
    /// tile's shape.
    static func corner(around card: CGRect, in canvas: CGSize) -> CGRect {
        let margin = max(card.minX, canvas.width * 0.04)
        var width = min(canvas.width, card.maxX + margin)
        var height = (width / tileAspect).rounded()
        // Tall enough for the card, the room under it, and more than the card
        // again above it, so it reads as sitting low in the frame.
        let needed = canvas.height - card.minY + card.height * 1.4
        if height < needed {
            height = min(canvas.height, needed)
            width = min(canvas.width, (height * tileAspect).rounded())
        }
        return CGRect(x: 0, y: canvas.height - height, width: width, height: height)
    }

    /// The preset landed on a frame this size at its start, over the
    /// recording's frame where one is given.
    private func land(on canvas: CGSize, under recording: ImageRef?) -> PhotonzDocument? {
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.durationMS = lengthMS
        if let recording {
            var picture = Layer(name: "Recording", content: .image(recording),
                                frame: CGRect(origin: .zero, size: canvas))
            picture.time = LayerTime(inMS: 0, outMS: lengthMS, sourceInMS: 0, sourceLengthMS: lengthMS)
            doc.layers = [picture]
        }
        let inserted: InsertedTitle?
        switch self {
        case .builtIn(let preset): inserted = doc.insertTitle(preset, atTimeMS: 0)
        case .saved(let saved): inserted = doc.insertTitle(saved, atTimeMS: 0)
        case .chart(let kind): inserted = doc.insertTitle(chart: kind, atTimeMS: 0)
        }
        guard let inserted, doc.layer(id: inserted.layerID)?.time != nil,
              doc.layers.last?.id == inserted.layerID else { return nil }
        return doc
    }

    /// The moment a landed preset has every part arrived, not half way
    /// through one.
    private static func restingMS(_ doc: PhotonzDocument) -> Int? {
        guard let layer = doc.layers.last, let time = layer.time else { return nil }
        return min(time.inMS + doc.titleArrivalMS(layerID: layer.id), max(time.inMS, time.outMS - 1))
    }

    private static func atRest(_ doc: PhotonzDocument) -> PhotonzDocument? {
        restingMS(doc).map { stilled(doc, at: $0) }
    }

    private func drawn(_ doc: PhotonzDocument, at moments: [Int]) -> [PhotonzDocument] {
        if moments.isEmpty { return Self.atRest(doc).map { [$0] } ?? [] }
        return moments.map { Self.stilled(doc, at: $0) }
    }

    /// The document as it is drawn at one moment, with no time left in it.
    private static func stilled(_ doc: PhotonzDocument, at ms: Int) -> PhotonzDocument {
        var still = doc.drawn(atTimeMS: ms)
        still.durationMS = nil
        still.tracks = []
        still.layers = still.layers.map(Self.stilled)
        return still
    }

    /// A layer and everything in it as it is drawn at one moment, with no
    /// stretch of time, keys or fade left to move it.
    private static func stilled(_ layer: Layer) -> Layer {
        var still = layer
        still.time = nil
        still.motions = nil
        still.pictureFade = nil
        still.trackID = nil
        if !still.children.isEmpty { still.children = still.children.map(stilled) }
        return still
    }
}

/// A title tile playing: its pictures in order, where in the lap each one
/// starts (a last `1` closing the lap), and how long the lap lasts.
public struct TitleTileReel: Sendable {
    public var pictures: [PhotonzDocument]
    public var keyTimes: [Double]
    public var lapMS: Int

    /// How long a tile holds once every part has arrived, before it plays
    /// the way off.
    public static let holdMS = 900
    /// The beat of nothing between one lap and the next.
    public static let gapMS = 350
}

extension PhotonzDocument {

    /// Put any preset on the timeline: at `ms` on a track of its own, or where
    /// `landing` says when it was let go over the timeline.
    ///
    /// A title page landed by an insert onto a track is put INTO the sequence
    /// there (`TitleBeforeClip.swift`): it carries no fade out, and the join
    /// into the clip it went in front of gets `join`.
    @discardableResult
    public mutating func insertTitle(_ preset: TitlePreset, atTimeMS ms: Int,
                                     landing: ClipLanding? = nil, motionBlur: Bool = false,
                                     join: ClipTransitionKind = .usualDefault) -> InsertedTitle? {
        var sequence: (track: UUID, arriving: UUID?, carried: ClipTransition?)?
        if let landing, landing.edit == .insert, preset.goesInFrontOfAClip, case .onto(let id) = landing.target {
            let arriving = clipIDs(onTrack: id).first { layer(id: $0)?.time?.inMS == landing.startMS }
            sequence = (id, arriving, arriving.flatMap { layer(id: $0)?.arrivalTransition })
        }
        let inserted: InsertedTitle? = switch preset {
        // A saved title carries whatever it was saved wearing.
        case .builtIn(let builtIn): insertTitle(builtIn, atTimeMS: ms, landing: landing, motionBlur: motionBlur)
        case .saved(let saved): insertTitle(saved, atTimeMS: ms, landing: landing)
        case .chart(let kind): insertTitle(chart: kind, atTimeMS: ms, landing: landing, motionBlur: motionBlur)
        }
        if let inserted, let sequence {
            settleTitleInSequence(inserted.layerID, trackID: sequence.track, carried: sequence.carried,
                                  formerlyArriving: sequence.arriving, join: join)
        }
        return inserted
    }

    /// Where a preset let go over the timeline lands: on the track under the
    /// pointer when that track takes pictures, is not locked and is free for
    /// the whole of it; otherwise on a new track of its own just above that
    /// one. Between two tracks it makes one there, and nowhere near a track
    /// it goes on top. So a drop never covers or cuts a clip: a title is laid
    /// over the picture, not edited into it.
    ///
    /// A new track is named for what it carries (`video-title-wt.html`: Title
    /// and Gfx beside V1), numbered where that name is taken; nil for the
    /// plain V2, V3.
    public func titleLanding(lengthMS: Int, atMS ms: Int, over pointed: TrackDrop?,
                             newTrackNamed name: String? = DocumentTrack.titleTrackName) -> ClipLanding {
        let tracks = timelineTracks
        let start = max(0, ms)
        let length = max(LayerTime.shortestMS, lengthMS)
        func newTrack(at index: Int) -> ClipLanding {
            let used = Set(tracks.map(\.name))
            return ClipLanding(target: .newTrack(at: min(max(0, index), tracks.count)), startMS: start,
                               lengthMS: length, edit: .overwrite,
                               trackName: name.map { Self.freeNamedTrackName($0, used: used) }
                                   ?? Self.freeTrackName(.video, used: used),
                               allowed: true)
        }
        guard let pointed else { return newTrack(at: 0) }
        switch pointed {
        case .newTrack(let index):
            return newTrack(at: index)
        case .onto(let id):
            guard let index = tracks.firstIndex(where: { $0.id == id }) else { return newTrack(at: 0) }
            let track = tracks[index]
            let span = start..<(start + length)
            let busy = clipIDs(onTrack: id).contains { other in
                let range = layer(id: other)?.time.map { $0.inMS..<max($0.inMS + 1, $0.outMS) }
                    ?? 0..<Int.max
                return span.overlaps(range)
            }
            guard track.accepts(.video), !track.isLocked, !busy else { return newTrack(at: index) }
            return ClipLanding(target: .onto(id), startMS: start, lengthMS: length, edit: .overwrite,
                               trackName: track.name, allowed: true)
        }
    }
}
