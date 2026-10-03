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

    /// The tile's id on the shelf, and what a drag carries. Never a bare
    /// UUID, so it can never be read as a component's.
    public var id: String {
        switch self {
        case .builtIn(let preset): "title.builtIn.\(preset.rawValue)"
        case .saved(let saved): Self.id(ofSaved: saved.id)
        }
    }

    /// The shelf id of a person's own preset, from its id alone.
    public static func id(ofSaved id: UUID) -> String { "title.saved.\(id.uuidString)" }

    public var name: String {
        switch self {
        case .builtIn(let preset): preset.name
        case .saved(let saved): saved.name
        }
    }

    public var kind: TitleKind {
        switch self {
        case .builtIn(let preset): preset.kind
        case .saved(let saved): saved.kind
        }
    }

    /// How long it runs once it lands, which is how long its ghost is drawn.
    public var lengthMS: Int {
        switch self {
        case .builtIn(let preset): preset.kind.lengthMS
        case .saved(let saved): saved.lengthMS
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
    public static func shelf(saved: [SavedTitlePreset]) -> [TitlePreset] {
        TitleKind.allCases.flatMap { kind in
            saved.filter { $0.kind == kind }.map(TitlePreset.saved)
                + BuiltInTitle.presets(of: kind).map(TitlePreset.builtIn)
        }
    }

    /// The preset a tile id or a drag names, nil when it names none, or names
    /// one of the person's own that has since been forgotten.
    public init?(entryID: String, saved: [SavedTitlePreset]) {
        let builtInPrefix = "title.builtIn.", savedPrefix = "title.saved."
        if entryID.hasPrefix(builtInPrefix),
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
    public func preview(frame: CGSize, width: CGFloat) -> PhotonzDocument? {
        guard frame.width > 0, frame.height > 0, width > 0 else { return nil }
        let canvas = CGSize(width: width, height: max(1, (width * frame.height / frame.width).rounded()))
        guard kind == .nameCard else { return still(on: canvas) }
        // Drawn once to find the corner, then again large enough that the
        // corner alone is `width` across, so the words are drawn at the size
        // they are seen rather than blown up.
        guard let first = still(on: canvas), let card = first.layers.last?.localBounds else { return nil }
        let scale = canvas.width / max(1, Self.corner(around: card, in: canvas).width)
        let large = CGSize(width: (canvas.width * scale).rounded(), height: (canvas.height * scale).rounded())
        guard var picture = still(on: large), let index = picture.layers.indices.last else { return nil }
        let region = Self.corner(around: picture.layers[index].localBounds, in: large)
        picture.layers[index].frame.origin.x -= region.minX
        picture.layers[index].frame.origin.y -= region.minY
        picture.canvasSize = region.size
        picture.layers.insert(TitlePen(canvas: region.size).fullFrame(Self.backdrop), at: 0)
        return picture
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

    /// The preset landed on a frame this size and drawn at rest, with no time
    /// left in it.
    private func still(on canvas: CGSize) -> PhotonzDocument? {
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.durationMS = lengthMS
        let inserted: InsertedTitle?
        switch self {
        case .builtIn(let preset): inserted = doc.insertTitle(preset, atTimeMS: 0)
        case .saved(let saved): inserted = doc.insertTitle(saved, atTimeMS: 0)
        }
        guard let inserted, let time = doc.layer(id: inserted.layerID)?.time else { return nil }
        let rest = min(time.inMS + TitleAnimation.lengthMS, max(time.inMS, time.outMS - 1))
        var still = doc.drawn(atTimeMS: rest)
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

extension PhotonzDocument {

    /// Put any preset on the timeline: at `ms` on a track of its own, or where
    /// `landing` says when it was let go over the timeline.
    @discardableResult
    public mutating func insertTitle(_ preset: TitlePreset, atTimeMS ms: Int,
                                     landing: ClipLanding? = nil) -> InsertedTitle? {
        switch preset {
        case .builtIn(let builtIn): insertTitle(builtIn, atTimeMS: ms, landing: landing)
        case .saved(let saved): insertTitle(saved, atTimeMS: ms, landing: landing)
        }
    }

    /// Where a preset let go over the timeline lands: on the track under the
    /// pointer when that track takes pictures, is not locked and is free for
    /// the whole of it; otherwise on a new track of its own just above that
    /// one. Between two tracks it makes one there, and nowhere near a track
    /// it goes on top. So a drop never covers or cuts a clip: a title is laid
    /// over the picture, not edited into it.
    public func titleLanding(lengthMS: Int, atMS ms: Int, over pointed: TrackDrop?) -> ClipLanding {
        let tracks = timelineTracks
        let start = max(0, ms)
        let length = max(LayerTime.shortestMS, lengthMS)
        func newTrack(at index: Int) -> ClipLanding {
            ClipLanding(target: .newTrack(at: min(max(0, index), tracks.count)), startMS: start,
                        lengthMS: length, edit: .overwrite,
                        trackName: Self.freeTrackName(.video, used: Set(tracks.map(\.name))),
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
            guard track.kind.accepts(.video), !track.isLocked, !busy else { return newTrack(at: index) }
            return ClipLanding(target: .onto(id), startMS: start, lengthMS: length, edit: .overwrite,
                               trackName: track.name, allowed: true)
        }
    }
}
