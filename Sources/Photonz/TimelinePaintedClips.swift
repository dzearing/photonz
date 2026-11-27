import AppKit
import PhotonzCore
import SwiftUI

/// The plain clips on a busy lane, painted as one layer: the same fill, edge,
/// name, waveform, level line and fade diamonds `ClipPiecesBar` draws for
/// them, with a click, a drag and a right click of their own, and none of the
/// cost of a view each (`TimelinePaint`).
///
/// On the 60 minute reference edit about 800 bars are in sight near the
/// whole-hour view, and a zoom built every one of them again on every frame:
/// about 570 ms a frame (2026-11-14). Painted, a lane is two views however
/// many clips it holds.
///
/// A clip anybody is working on is drawn as its full bar instead: picked, in
/// a hand, being trimmed or renamed, and the clip under the pointer, so a
/// grip, a fade diamond or the level line is always the real one by the time
/// a hand reaches it. What is painted reads nothing of the document: its row
/// hands it every bar, as `CaptionCuesLayer` is handed its cues.
struct TimelinePaintedClips: View, Equatable {
    struct Bar: Equatable {
        let layerID: UUID
        let name: String
        let bar: LayerTime
        let kind: VideoKit.ClipKind
        /// Which part of the clip's rectangle this is.
        let half: ClipHalf
        /// Where it sits down the lane, and how tall it is.
        let top: CGFloat
        let height: CGFloat
        /// A sound: a waveform inside and a level line across.
        let isSound: Bool
        let isLinkedSound: Bool
        let soundTint: Color
        let level: AudioLevel
        /// The one piece, for the stretch of the file its waveform is read from.
        let piece: ClipPiece?
        let waveform: Waveform?
        /// The picture's fades, drawn as a shade at each end.
        var pictureFadeInMS = 0
        var pictureFadeOutMS = 0
        var pictureFadeCurve: EasingCurve = .linear
        /// The recording, and how strongly its pictures show along the clip
        /// (`ClipPiecesBar.picturesOpacity`): nought draws none.
        var movie: MovieRef?
        var pictures: Double = 0
        /// A sound of its own on the panel's ground
        /// (`ClipPiecesBar.soundOnThePanelGround`): this fill, an edge in the
        /// lane's colour, no lit top edge, and its name in a tag above its
        /// level line (`ClipPiecesBar.soundTag`) rather than across it.
        var ground: Color?
        /// The clip may run off the lane's left edge in this stretch, so its
        /// name is drawn against the window by `TimelinePaintedNames`, not
        /// on the canvas (`TimelinePaint.nameFollowsTheEdge`).
        var nameFollowsEdge = false
    }

    let bars: [Bar]
    /// The gaps between clips on the drawn stretch, painted under the clips
    /// as `TimelineGapSlot` draws one: the lane builds a view only for the
    /// gap under the pointer, for its press and menu (`TimelinePaint.gapViews`).
    var gaps: [Range<Int>] = []
    /// The gap's stripes and dashed edge, in the lane's own scheme.
    var gapInk = GapInk(stripe: .clear, edge: .clear)
    /// What it is painted on: the drawn stretch, measured from where it
    /// starts, which a scroll inside one stretch leaves alone. The lane
    /// slides it into place (`TimelinePaint.Canvas`).
    let canvas: TimelinePaint.Canvas
    /// The stretch either side of the window a bar is drawn across
    /// (`EditorState.timelineDrawnMS`), cut the same way the bar cuts itself.
    let drawnMS: ClosedRange<Double>
    let laneWidth: CGFloat
    let laneHeight: CGFloat
    /// Where the lane's gridlines fall on the drawn stretch, and their ink
    /// in the lane's scheme: drawn first, under everything, so a scroll
    /// slides them with the clips rather than drawing a layer of lines
    /// again on every frame (`MotionStripRuler.secondTickMS(across:)`).
    var gridlines: [Double] = []
    var gridInk: Color = .clear

    /// Pictures that landed or strips that came into view a moment ago, and
    /// when, so each fades in as a full bar's does (`ClipFilmstripTile`).
    @State private var fades: [Fade: TimeInterval] = [:]
    /// What was painted last time, kept without painting again.
    @State private var painted = Painted()
    @Environment(EditorState.self) private var editorState

    /// The clips painted last time, and which of them showed pictures: a
    /// strip that comes in with a zoom on a clip already painted fades in
    /// rather than popping. Kept out of sight of the view's updates: a clip
    /// sliding in with a scroll or a zoom out brings its strip with it,
    /// drawn at once, and noting it is no reason to paint again. Each one
    /// was a fade, which painted the whole canvas on every frame for a
    /// fifth of a second: on a fast scroll of the hour-long reference edit,
    /// clips with pictures came onto the stretch every other frame, so the
    /// painting a scroll only slides was painted on every frame (2026-11-16).
    private final class Painted {
        var clips: Set<UUID>?
        var strips: Set<UUID> = []
        /// Pictures that landed while the timeline moved, painted together.
        var landing: Task<Void, Never>?
    }

    private struct Showing: Hashable {
        let clips: Set<UUID>
        let strips: Set<UUID>
    }
    /// Bumped each time a picture lands, which paints it.
    @State private var landed = 0
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    enum Fade: Hashable {
        case tile(ClipFilmstripFrames.Key)
        case strip(UUID)
    }

    struct GapInk: Equatable {
        let stripe: Color
        let edge: Color
    }

    var body: some View {
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.clipBar)
        #endif
        let _ = landed
        let gaps = self.gaps
        let gapInk = self.gapInk
        let ruler = canvas.ruler
        let canvasWidth = canvas.width
        let laneWidth = self.laneWidth
        let laneHeight = self.laneHeight
        let gridlines = self.gridlines
        let gridInk = self.gridInk
        let placed = bars.compactMap { Self.place($0, ruler: canvas.ruler, drawnMS: drawnMS, laneWidth: laneWidth) }
        let strips = placed.map { Self.strip(of: $0) }
        // Every picture the strips show, in the order they come, as the key
        // the asking below is started again by. Put in the order they are
        // asked for only when the asking runs: sorted on every rebuild, as a
        // fast scroll of the hour-long edit rebuilds the painting every
        // other frame, the order was a sixth of the painted clips' time.
        let wanted = Self.wantedKeys(strips)
        let before = painted.clips
        let seen = painted.strips
        let showing = Showing(clips: Set(placed.map(\.bar.layerID)),
                              strips: Set(zip(placed, strips).compactMap { $1 == nil ? nil : $0.bar.layerID }))
        // Nothing fades while the timeline moves: a fade paints its lane again
        // on every frame, and a zoom brings strips and pictures on to every
        // lane in sight at once. Seven lanes of it were most of a late zoom
        // frame on a 50 track timeline (2026-11-24). What lands is painted
        // whole instead, and a zoom stretches it with the rest. Read where
        // reading it wakes nothing (`EditorState.timelineMovesNow`).
        let moves = editorState.timelineMovesNow
        let fades = moves ? [:] : self.fades
        // Side by side rather than one over the other as an overlay: the
        // painting takes no presses, and a hit-testing switch on a view is
        // inherited by anything overlaid on it.
        let paint: (inout GraphicsContext, TimeInterval) -> Void = { context, now in
            Self.paintGridlines(gridlines, ruler: ruler, laneWidth: laneWidth, height: laneHeight,
                                ink: gridInk, in: &context)
            Self.paintGaps(gaps, ruler: ruler, laneWidth: laneWidth, height: laneHeight, across: canvasWidth,
                           ink: gapInk, in: &context)
            for (one, strip) in zip(placed, strips) {
                var alpha: (Fade) -> Double = { _ in 1 }
                if !moves, !fades.isEmpty || before != nil {
                    alpha = { fade in
                        // New on a clip painted last time: clear
                        // until its fade starts.
                        if case .strip(let id) = fade, let before, before.contains(id), !seen.contains(id),
                           fades[fade] == nil {
                            return 0
                        }
                        return Self.faded(since: fades[fade], now: now)
                    }
                }
                Self.paint(one, strip: strip, alpha: alpha, in: &context)
            }
        }
        // An edit's bars the last painting did not hold, few enough to draw
        // over it while the new one is laid.
        let follows = editorState.drawsALateEdit && before != nil
        let newcomers = follows ? zip(placed, strips).filter { before?.contains($0.0.bar.layerID) != true } : []
        ZStack(alignment: .topLeading) {
            Group {
                if fades.isEmpty {
                    // Laid into a picture once, which a scroll slides and a
                    // zoom holding it stretches without drawing it again
                    // (`TimelinePaintedPicture`).
                    TimelinePaintedPicture(width: canvas.width, height: laneHeight, scale: displayScale,
                                           scheme: colorScheme, canvas: canvas, laneWidth: laneWidth,
                                           asked: TimelinePaintedPicture.ask(),
                                           followsAnEdit: follows && newcomers.count <= 4,
                                           newcomers: newcomers.isEmpty ? nil : { context in
                        for (one, strip) in newcomers { Self.paint(one, strip: strip, alpha: { _ in 1 }, in: &context) }
                    }) { context in
                        paint(&context, Date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    // A picture or strip fading in is painted on every frame
                    // until it is in.
                    TimelineView(.animation(minimumInterval: nil, paused: false)) { timeline in
                        let now = timeline.date.timeIntervalSinceReferenceDate
                        Canvas { context, _ in paint(&context, now) }
                    }
                }
            }
            .frame(width: canvas.width, height: laneHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            TimelinePaintedHands(placed: placed, canvas: canvas, laneWidth: laneWidth, laneHeight: laneHeight)
        }
        .frame(width: canvas.width, height: laneHeight, alignment: .topLeading)
        // A strip new on a clip already painted fades in; one already here
        // when the lane started painting, or one that comes in with its
        // clip, does not.
        .onChange(of: showing, initial: true) { _, now in
            let painted = self.painted
            guard let clips = painted.clips else {
                painted.clips = now.clips
                painted.strips = now.strips
                return
            }
            let fresh = now.strips.subtracting(painted.strips).intersection(clips)
            painted.clips = now.clips
            painted.strips = now.strips
            guard !fresh.isEmpty, !editorState.timelineMovesNow else { return }
            let at = Date.timeIntervalSinceReferenceDate
            for id in fresh { self.fades[.strip(id)] = at }
            clearFades()
        }
        // The pictures not read yet, asked for once the stretch has held
        // still a moment, so a fling along the timeline asks for nothing it
        // has already passed (`ClipFilmstripFrames`). Keyed by every picture
        // the strips show, so one landing does not start the asking over.
        .task(id: wanted) {
            guard !wanted.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(40))
            let missing = Self.wanted(strips, middle: canvas.width / 2)
                .filter { ClipFilmstripFrames.shared.cached($0.key) == nil }
            guard !Task.isCancelled, !missing.isEmpty else { return }
            await withTaskGroup(of: ClipFilmstripFrames.Key?.self) { group in
                for want in missing {
                    group.addTask { await Self.read(want) }
                }
                for await key in group {
                    guard let key, !Task.isCancelled else { continue }
                    if editorState.timelineMovesNow {
                        landTogether()
                        continue
                    }
                    self.fades[.tile(key)] = Date.timeIntervalSinceReferenceDate
                    landed &+= 1
                    clearFades()
                }
            }
        }
        #if PHOTONZ_PLAYTEST
        .onChange(of: Self.report(placed, strips), initial: true) { old, now in
            for gone in Set(old.keys).subtracting(now.keys) {
                DrawnFilmstrips.shared.gone(gone, piece: Self.paintedPiece)
            }
            for (id, strip) in now {
                DrawnFilmstrips.shared.showing(id, piece: Self.paintedPiece, keys: strip.keys, opacity: strip.opacity)
            }
        }
        .onDisappear {
            for id in Self.report(placed, strips).keys { DrawnFilmstrips.shared.gone(id, piece: Self.paintedPiece) }
        }
        #endif
    }

    nonisolated static func == (a: TimelinePaintedClips, b: TimelinePaintedClips) -> Bool {
        a.bars == b.bars && a.canvas == b.canvas && a.drawnMS == b.drawnMS && a.laneWidth == b.laneWidth
            && a.laneHeight == b.laneHeight && a.gaps == b.gaps && a.gapInk == b.gapInk
            && a.gridlines == b.gridlines && a.gridInk == b.gridInk
    }

    // MARK: Pictures along a clip

    /// How long a picture or a strip takes to fade in, as a full bar's does.
    static let fadeSeconds: TimeInterval = 0.22

    private static func faded(since: TimeInterval?, now: TimeInterval) -> Double {
        guard let since else { return 1 }
        let t = min(1, max(0, (now - since) / fadeSeconds))
        // Ease out.
        return 1 - (1 - t) * (1 - t)
    }

    /// Lets go of fades that have finished, once they have, so the canvas
    /// stops being drawn on every frame.
    private func clearFades() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.fadeSeconds + 0.05))
            let now = Date.timeIntervalSinceReferenceDate
            let done = fades.filter { now - $0.value >= Self.fadeSeconds }.map(\.key)
            guard !done.isEmpty else { return }
            for key in done { fades[key] = nil }
        }
    }

    /// Paints the pictures landing while the timeline moves a tenth of a
    /// second at a time, rather than the lane again for each.
    private func landTogether() {
        guard painted.landing == nil else { return }
        painted.landing = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            painted.landing = nil
            landed &+= 1
        }
    }

    struct Tile {
        let key: ClipFilmstripFrames.Key
        let movie: MovieRef
        /// Where it is drawn, on the canvas.
        let rect: CGRect
        let image: CGImage?
    }

    /// The row of pictures inside one painted clip, as `ClipFilmstripStrip`
    /// lays them out: under a band of the clip's colour, anchored to the
    /// clip's start, cut to what is drawn.
    struct Strip {
        let rect: CGRect
        let tiles: [Tile]
        let opacity: Double
    }

    private static func strip(of placed: Placed) -> Strip? {
        let bar = placed.bar
        guard bar.pictures > 0, let movie = bar.movie, let piece = bar.piece, !bar.isSound,
              !piece.isHeld, !piece.pictureHidden else { return nil }
        let height = max(1, bar.height - ClipFilmstripStrip.band)
        let aspect = movie.pixelSize.height > 0 ? movie.pixelSize.width / movie.pixelSize.height : 16.0 / 9
        let nominal = ClipFilmstrip.tileWidth(height: height, aspect: aspect)
        let from = placed.shown.startFraction * placed.whole
        let tiles = ClipFilmstrip.tiles(of: piece, pieceWidth: placed.whole,
                                        visible: from...(from + placed.shown.width), nominalWidth: nominal)
        let top = bar.top + ClipFilmstripStrip.band
        return Strip(
            rect: CGRect(x: placed.shown.x, y: top, width: placed.shown.width, height: height),
            tiles: tiles.map { tile in
                let key = ClipFilmstripFrames.Key(movie: movie.id, sourceMS: tile.sourceMS)
                return Tile(key: key, movie: movie,
                            rect: CGRect(x: placed.shown.x + tile.x - from, y: top, width: tile.width, height: height),
                            image: ClipFilmstripFrames.shared.cached(key))
            },
            opacity: bar.pictures)
    }

    struct Wanted: Hashable, Sendable {
        let key: ClipFilmstripFrames.Key
        let movie: MovieRef
    }

    /// Every picture the strips show, furthest from the middle of the canvas
    /// first: the newest asked is read first (`ClipFilmstripFrames`), and the
    /// window is in the middle of the drawn stretch, the margins either side.
    /// Every picture the strips show, once each, in the order they come.
    private static func wantedKeys(_ strips: [Strip?]) -> [ClipFilmstripFrames.Key] {
        var seen = Set<ClipFilmstripFrames.Key>()
        var keys: [ClipFilmstripFrames.Key] = []
        for strip in strips {
            for tile in strip?.tiles ?? [] where seen.insert(tile.key).inserted { keys.append(tile.key) }
        }
        return keys
    }

    private static func wanted(_ strips: [Strip?], middle: CGFloat) -> [Wanted] {
        var seen = Set<ClipFilmstripFrames.Key>()
        var wanted: [(Wanted, CGFloat)] = []
        for strip in strips {
            for tile in strip?.tiles ?? [] where seen.insert(tile.key).inserted {
                wanted.append((Wanted(key: tile.key, movie: tile.movie), abs(tile.rect.midX - middle)))
            }
        }
        return wanted.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Reads one picture; its key when it came.
    @MainActor private static func read(_ want: Wanted) async -> ClipFilmstripFrames.Key? {
        await ClipFilmstripFrames.shared.picture(of: want.movie, atSourceMS: want.key.sourceMS) == nil ? nil : want.key
    }

    #if PHOTONZ_PLAYTEST
    /// Painted strips are reported under a piece of their own, so a clip that
    /// turns into its full bar under the pointer never has its strip's report
    /// taken away by the painting letting go of it.
    static let paintedPiece = -1

    private static func report(_ placed: [Placed], _ strips: [Strip?]) -> [UUID: DrawnFilmstrips.Strip] {
        var report: [UUID: DrawnFilmstrips.Strip] = [:]
        for (one, strip) in zip(placed, strips) {
            guard let strip else { continue }
            report[one.bar.layerID] = DrawnFilmstrips.Strip(keys: strip.tiles.map(\.key), opacity: strip.opacity)
        }
        return report
    }
    #endif

    // MARK: Where one goes

    struct Placed {
        let bar: Bar
        /// The whole bar along the lane, unclipped: where its fades and level
        /// line are measured from.
        let x0: CGFloat
        let whole: CGFloat
        /// The piece as the bar draws it, cut to the drawn stretch.
        let shown: TimelineSpan
        /// The level line's own cut, across the whole bar.
        let lineShown: TimelineSpan

        var rect: CGRect { CGRect(x: shown.x, y: bar.top, width: shown.width, height: bar.height) }
    }

    static func place(_ bar: Bar, ruler: MotionStripRuler, drawnMS: ClosedRange<Double>,
                      laneWidth: CGFloat) -> Placed? {
        let x0 = laneWidth * ruler.fraction(ofMS: Double(bar.bar.inMS))
        let whole = laneWidth * ruler.fraction(spanningMS: Double(bar.bar.outMS - bar.bar.inMS))
        let low = laneWidth * ruler.fraction(ofMS: drawnMS.lowerBound)
        let high = laneWidth * ruler.fraction(ofMS: drawnMS.upperBound)
        // A bar in one piece is never narrower than something a pointer can
        // take hold of (`ClipPiecesBar.piece`).
        let shown = TimelineSpan.drawn(x: x0, width: max(6, whole), from: low, to: high)
        guard shown.width > 0 else { return nil }
        return Placed(bar: bar, x0: x0, whole: whole, shown: shown,
                      lineShown: TimelineSpan.drawn(x: x0, width: whole, from: low, to: high))
    }

    /// The clip a point in the lane lands on.
    static func clip(at point: CGPoint, in placed: [Placed]) -> Placed? {
        placed.last { $0.rect.contains(point) }
    }

    // MARK: Painting one

    private static func paint(_ placed: Placed, strip: Strip?, alpha: (Fade) -> Double,
                              in context: inout GraphicsContext) {
        let bar = placed.bar
        let (rect, shape) = outline(placed, scale: context.environment.displayScale)
        if let ground = bar.ground {
            context.fill(shape, with: .color(ground))
        } else {
            context.fill(shape, with: .style(bar.kind.fill))
        }
        var inside = context
        inside.clip(to: shape)
        if let strip {
            paintStrip(strip, layerID: bar.layerID, alpha: alpha, in: &inside)
        }
        if bar.ground != nil {
            inside.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius - 0.5),
                          with: .color(bar.soundTint.opacity(0.35)), lineWidth: 1)
        } else if let border = bar.kind.border {
            // A whole rectangle's border, run past the join and cut off there.
            let framed = CGRect(x: rect.minX, y: rect.minY - (bar.half.isSound ? 2 * radius : 0),
                                width: rect.width,
                                height: rect.height + (bar.half.isSound || bar.half.isPicture ? 2 * radius : 0))
            inside.stroke(Path(roundedRect: framed.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius - 0.5),
                          with: .color(border), lineWidth: 1)
        }
        // The lit top edge every clip in the mock has, but a sound on the
        // panel's ground.
        if bar.ground == nil {
            inside.fill(Path(CGRect(x: rect.minX + radius / 2, y: rect.minY,
                                    width: max(0, rect.width - radius), height: 1)),
                        with: .color(.white.opacity(0.18)))
        }
        if !bar.nameFollowsEdge {
            paintName(bar, rect: rect, hidden: max(0, -rect.minX),
                      pictures: strip.map { $0.opacity * alpha(.strip(bar.layerID)) } ?? 0,
                      in: &inside)
        }
        if bar.isSound, let piece = bar.piece, piece.playsSound, let wave = bar.waveform, rect.width >= 2 {
            paintWaveform(wave, piece: piece, placed: placed, rect: rect, in: &inside)
        }
        if bar.isSound {
            paintLevelLine(placed, in: &context)
            paintFadeDiamonds(placed, in: &context)
        }
        if bar.ground != nil, !bar.nameFollowsEdge {
            paintSoundTag(placed, off: 0, in: &context)
        }
        paintPictureFades(placed, in: &context)
    }

    /// A one point line down the whole lane at each gridline, as
    /// `TimelineGridlines` draws them on a lane that does not paint.
    private static func paintGridlines(_ lines: [Double], ruler: MotionStripRuler, laneWidth: CGFloat,
                                       height: CGFloat, ink: Color, in context: inout GraphicsContext) {
        guard !lines.isEmpty else { return }
        var path = Path()
        for ms in lines {
            path.addRect(CGRect(x: laneWidth * ruler.fraction(ofMS: ms), y: 0, width: 1, height: height))
        }
        context.fill(path, with: .color(ink))
    }

    /// The gaps between clips as `TimelineGapSlot` draws each: stripes five
    /// points across inside the clip's corner, under a dashed edge. All of a
    /// lane's stripes are one clip and one fill; each edge is stroked on its
    /// own, since one dashed path through every gap carries its dashes on
    /// from one edge to the next where a gap's own starts afresh. Near the
    /// whole-hour view of the hour-long reference edit about seventy gaps
    /// were each a striped canvas, an edge, a press and a menu, about 5 ms
    /// of every frame of a zoom (2026-11-17).
    ///
    /// Only the stripes the canvas, `across` wide, shows are drawn: zoomed
    /// right in, a long gap is hundreds of screens across, and drawing every
    /// stripe of it was 3 to 6 ms of a zoom's frame on a 50 track timeline
    /// (2026-11-25).
    private static func paintGaps(_ gaps: [Range<Int>], ruler: MotionStripRuler, laneWidth: CGFloat,
                                  height: CGFloat, across: CGFloat, ink: GapInk, in context: inout GraphicsContext) {
        guard !gaps.isEmpty else { return }
        let scale = context.environment.displayScale
        let corner = RoundedRectangle(cornerRadius: radius)
        let edge = corner.inset(by: 0.5)
        // `TimelineStripes`: across the stripes is 45 degrees, so along the
        // lane a stripe and its gap each take its width times root 2.
        let step = TimelineGapSlot.stripeWidth * 2.squareRoot()
        var slots = Path()
        var edges: [Path] = []
        var stripes = Path()
        for gap in gaps {
            let x0 = laneWidth * ruler.fraction(ofMS: Double(gap.lowerBound))
            let x1 = laneWidth * ruler.fraction(ofMS: Double(gap.upperBound))
            guard x1 - x0 >= 1 else { continue }
            let rect = snapped(CGRect(x: x0, y: 0, width: x1 - x0, height: height), scale: scale)
            slots.addPath(corner.path(in: rect))
            edges.append(edge.path(in: rect))
            // Each stripe cut to its own gap's ends, so under the one clip
            // a stripe never reaches into the gap beside it.
            var x = TimelinePaint.firstStripe(gapFrom: rect.minX, reach: rect.height + step, pitch: step * 2,
                                              canvasFrom: 0, lean: rect.height)
            let end = min(rect.maxX, across)
            while x < end {
                let stripe = Self.cut([CGPoint(x: x, y: rect.minY), CGPoint(x: x + step, y: rect.minY),
                                       CGPoint(x: x + step + rect.height, y: rect.maxY),
                                       CGPoint(x: x + rect.height, y: rect.maxY)],
                                      fromX: rect.minX, toX: rect.maxX)
                if stripe.count > 2 {
                    stripes.addLines(stripe)
                    stripes.closeSubpath()
                }
                x += step * 2
            }
        }
        var inside = context
        inside.clip(to: slots)
        inside.fill(stripes, with: .color(ink.stripe))
        let dashed = StrokeStyle(lineWidth: 1, dash: [4, 3])
        for one in edges { context.stroke(one, with: .color(ink.edge), style: dashed) }
    }

    /// A shape cut to the stretch from `fromX` to `toX` across.
    static func cut(_ points: [CGPoint], fromX: CGFloat, toX: CGFloat) -> [CGPoint] {
        func keep(_ points: [CGPoint], inside: (CGPoint) -> Bool, edge: CGFloat) -> [CGPoint] {
            guard let last = points.last else { return [] }
            var kept: [CGPoint] = []
            var before = last
            for point in points {
                if inside(point) != inside(before) {
                    let t = (edge - before.x) / (point.x - before.x)
                    kept.append(CGPoint(x: edge, y: before.y + t * (point.y - before.y)))
                }
                if inside(point) { kept.append(point) }
                before = point
            }
            return kept
        }
        return keep(keep(points, inside: { $0.x >= fromX }, edge: fromX), inside: { $0.x <= toX }, edge: toX)
    }

    /// A sound's name, in a dark tag at the top left of the clip over its
    /// waveform and level line, clear of the fade in diamond
    /// (`ClipPiecesBar.soundTag`). `off` is how far the clip runs off the
    /// lane's left edge.
    static func paintSoundTag(_ placed: Placed, off: CGFloat, in context: inout GraphicsContext) {
        let bar = placed.bar
        let shown = placed.lineShown
        let start = max(shown.x, placed.x0 + max(0, off - TimelineSpan.slack))
        let width = shown.x + shown.width - start
        guard width > 40 else { return }
        let leading = off == 0 ? SoundFadeDiamond.reach + 4 : 4
        let words = fitted(bar.name, width: max(0, width - leading - 8 - 14), size: 9, in: context, ink: .white)
        let size = words.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        let tag = CGRect(x: start + leading, y: bar.top + 3, width: size.width + 14, height: size.height + 4)
        var inside = context
        inside.clip(to: Path(CGRect(x: shown.x, y: bar.top, width: shown.width, height: bar.height)))
        inside.fill(Path(roundedRect: tag, cornerRadius: 4), with: .color(.black.opacity(0.4)))
        inside.draw(words, at: CGPoint(x: tag.minX + 7, y: tag.minY + 2), anchor: .topLeading)
    }

    private static let radius = VideoKit.Metrics.clipCornerRadius

    /// The clip's rectangle on the screen's pixels, and its shape: square
    /// where the clip's other half meets it, so the two read as one
    /// rectangle (`ClipPiecesBar.pieceShape`).
    static func outline(_ placed: Placed, scale: CGFloat) -> (CGRect, Path) {
        let bar = placed.bar
        // On the screen's pixels, as a view's frame is laid out: drawn where
        // it falls, an edge between two pixels is a blur the bar never has.
        let rect = snapped(placed.rect, scale: scale)
        let top = bar.half.isSound ? 0 : radius
        let bottom = bar.half.isPicture ? 0 : radius
        let shape = UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                           bottomTrailingRadius: bottom, topTrailingRadius: top).path(in: rect)
        return (rect, shape)
    }

    /// The name, kept in sight while the clip runs `hidden` points off the
    /// lane's left edge. Over pictures it sits in a dark pill, as the full
    /// bar's does, so it reads on a white window as well as on a dark one.
    static func paintName(_ bar: Bar, rect: CGRect, hidden: CGFloat, pictures: Double,
                          in context: inout GraphicsContext) {
        let room = rect.width - hidden
        guard room > 40, !bar.isLinkedSound, !bar.isSound else { return }
        let ink = bar.kind.ink(context.environment.colorScheme)
        guard pictures > 0 else {
            let words = fitted(bar.name, width: max(0, room - 4 - 16), in: context, ink: ink)
            var type = context
            type.addFilter(.shadow(color: .black.opacity(0.35), radius: 1))
            type.draw(words, at: CGPoint(x: rect.minX + hidden + 8, y: rect.midY), anchor: .leading)
            return
        }
        // `.padding(.horizontal, 5)`, `.padding(.vertical, 1)` in a capsule,
        // four in from the edge and eight short of the far end.
        let words = fitted(bar.name, width: max(0, room - 4 - 4 - 10 - 8), in: context, ink: ink)
        let size = words.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        let pill = CGRect(x: rect.minX + hidden + 4, y: rect.midY - size.height / 2 - 1,
                          width: size.width + 10, height: size.height + 2)
        context.fill(Capsule().path(in: pill), with: .color(.black.opacity(0.55 * pictures)))
        var type = context
        type.addFilter(.shadow(color: .black.opacity(0.35), radius: 1))
        type.draw(words, at: CGPoint(x: pill.minX + 5, y: rect.midY), anchor: .leading)
    }

    /// How wide a name is set whole, and cut short after each count of its
    /// letters with an ellipsis, measured once per name: set afresh on every
    /// frame of a zoom, a lane's names were a tenth of the frame.
    private static var nameWidths: [String: (whole: CGFloat, cut: [CGFloat])] = [:]
    private static var tagWidths: [String: (whole: CGFloat, cut: [CGFloat])] = [:]

    /// Words as set for a canvas, by what decides how they look.
    private struct SetName: Hashable {
        let words: String
        let size: CGFloat
        let ink: Color
        let scheme: ColorScheme
        let scale: CGFloat
    }
    private static var setNames: [SetName: GraphicsContext.ResolvedText] = [:]

    /// How `fitted` sets a name in `width`: how many of its letters it keeps
    /// before the ellipsis (nil when the whole name fits) and how wide that
    /// is, or nil while the name has never been set (`NameShot`).
    static func cut(of name: String, width: CGFloat, size: CGFloat = 9.5) -> (count: Int?, width: CGFloat)? {
        guard let widths = size != 9.5 ? tagWidths[name] : nameWidths[name] else { return nil }
        guard widths.whole > width else { return (nil, widths.whole) }
        let count = widths.cut.lastIndex { $0 <= width } ?? 0
        return (count, widths.cut.isEmpty ? 0 : widths.cut[count])
    }

    /// The name as the full bar sets it on one line, as `CaptionCuesLayer.fitted`
    /// sets it, from widths measured once.
    static func fitted(_ name: String, width: CGFloat, size: CGFloat = 9.5, in context: GraphicsContext,
                       ink: Color) -> GraphicsContext.ResolvedText {
        // Set once per name, cut, ink and screen, and kept: resolving the
        // same words again on every frame of a zoom was about a twentieth of
        // the frame on the hour-long edit.
        func resolved(_ words: String) -> GraphicsContext.ResolvedText {
            let key = SetName(words: words, size: size, ink: ink, scheme: context.environment.colorScheme,
                              scale: context.environment.displayScale)
            if let kept = setNames[key] { return kept }
            if setNames.count > 4000 { setNames.removeAll() }
            let made = context.resolve(Text(words).font(.system(size: size, weight: .semibold)).foregroundStyle(ink))
            setNames[key] = made
            return made
        }
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let letters = Array(name)
        let widths: (whole: CGFloat, cut: [CGFloat])
        let isTag = size != 9.5
        if let known = isTag ? tagWidths[name] : nameWidths[name] {
            widths = known
        } else {
            if nameWidths.count > 4000 { nameWidths.removeAll() }
            if tagWidths.count > 4000 { tagWidths.removeAll() }
            let whole = resolved(name).measure(in: unbounded).width
            let cut = (0..<letters.count).map { count in
                resolved(String(letters.prefix(count)) + "…").measure(in: unbounded).width
            }
            widths = (whole, cut)
            if isTag { tagWidths[name] = widths } else { nameWidths[name] = widths }
        }
        guard widths.whole > width else { return resolved(name) }
        let count = widths.cut.lastIndex { $0 <= width } ?? 0
        return resolved(String(letters.prefix(count)).trimmingCharacters(in: .whitespaces) + "…")
    }

    /// The pictures, each filling its tile and cut to it, with a hairline
    /// between them (`ClipFilmstripTile`), the whole row as strong as the
    /// zoom says.
    private static func paintStrip(_ strip: Strip, layerID: UUID, alpha: (Fade) -> Double,
                                   in context: inout GraphicsContext) {
        let opacity = strip.opacity * alpha(.strip(layerID))
        guard opacity > 0 else { return }
        var row = context
        row.clip(to: Path(strip.rect))
        // As one layer at the row's strength, as the bar's `.opacity` is.
        row.opacity = opacity
        row.drawLayer { layer in
            for tile in strip.tiles {
                if let image = tile.image, image.width > 0, image.height > 0 {
                    var one = layer
                    one.clip(to: Path(tile.rect))
                    one.opacity = alpha(.tile(tile.key))
                    // Filled, as `.aspectRatio(contentMode: .fill)` does.
                    let width = CGFloat(image.width)
                    let height = CGFloat(image.height)
                    let fill = max(tile.rect.width / width, tile.rect.height / height)
                    let drawn = CGSize(width: width * fill, height: height * fill)
                    one.draw(Image(decorative: image, scale: 1).interpolation(.medium),
                             in: CGRect(x: tile.rect.midX - drawn.width / 2, y: tile.rect.midY - drawn.height / 2,
                                        width: drawn.width, height: drawn.height))
                }
                // A hairline between pictures, so a row of near identical
                // frames still reads as a row.
                layer.fill(Path(CGRect(x: tile.rect.maxX - 0.5, y: tile.rect.minY, width: 0.5,
                                       height: tile.rect.height)),
                           with: .color(.black.opacity(0.35)))
            }
        }
    }

    /// The picture's fade at each end, a shade darkest where the picture is
    /// furthest down (`ClipPiecesBar.pictureFadeRamps`).
    private static func paintPictureFades(_ placed: Placed, in context: inout GraphicsContext) {
        let bar = placed.bar
        let length = bar.bar.outMS - bar.bar.inMS
        guard length > 0, bar.pictureFadeInMS > 0 || bar.pictureFadeOutMS > 0 else { return }
        let perMS = placed.whole / CGFloat(length)
        let scale = context.environment.displayScale
        let shade = GraphicsContext.Shading.color(.black.opacity(0.4))
        // Laid on the pixels as the bar's own shade is: one a fraction of a
        // point wide is a pixel's line or nothing, by where it falls.
        func wedge(isIn: Bool, x: CGFloat, width: CGFloat) {
            let rect = CGRect(x: x, y: bar.top, width: width, height: bar.height)
            let minX = (rect.minX * max(1, scale)).rounded() / max(1, scale)
            let maxX = (rect.maxX * max(1, scale)).rounded() / max(1, scale)
            guard maxX > minX else { return }
            context.fill(FadeWedge(isIn: isIn, curve: bar.pictureFadeCurve)
                .path(in: CGRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height)), with: shade)
        }
        if bar.pictureFadeInMS > 0 {
            wedge(isIn: true, x: placed.x0, width: CGFloat(bar.pictureFadeInMS) * perMS)
        }
        if bar.pictureFadeOutMS > 0 {
            let width = CGFloat(bar.pictureFadeOutMS) * perMS
            wedge(isIn: false, x: placed.x0 + placed.whole - width, width: width)
        }
    }

    private static func snapped(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let scale = max(1, scale)
        let minX = (rect.minX * scale).rounded() / scale
        let maxX = (rect.maxX * scale).rounded() / scale
        return CGRect(x: minX, y: rect.minY, width: max(1 / scale, maxX - minX), height: rect.height)
    }

    /// The sound itself, read across the part of the file the drawn stretch
    /// shows, at the level it plays at (`ClipPiecesBar.piece`).
    private static func paintWaveform(_ wave: Waveform, piece: ClipPiece, placed: Placed, rect: CGRect,
                                      in context: inout GraphicsContext) {
        let shown = placed.shown
        let file = Double(piece.sourceOutMS - piece.sourceInMS)
        let span = Double(piece.lengthMS)
        let heights = Waveform.drawnHeights(
            ofPeaks: wave.columns(count: Int(shown.width),
                                  fromSourceMS: piece.sourceInMS + Int(file * Double(shown.startFraction)),
                                  toSourceMS: piece.sourceInMS + Int(file * Double(shown.endFraction))),
            level: placed.bar.level,
            fromLayerMS: Int(span * Double(shown.startFraction)),
            toLayerMS: Int(span * Double(shown.endFraction)))
        let outline = SoundLaneShape.outline(heights: heights, width: rect.width, height: rect.height)
        guard !outline.isEmpty else { return }
        // Laid down in one go, already where it is drawn: a point at a time,
        // each one a write to the path's buffer, the waveforms were a third
        // of the painted clips' time on a fast scroll of the hour-long edit.
        var path = Path()
        path.addLines(Self.moved(outline, byX: rect.minX, y: rect.minY))
        path.closeSubpath()
        context.fill(path, with: .color(placed.bar.soundTint.opacity(0.55)))
    }

    /// `points` moved across by `x` and down by `y`. A plain loop, off the
    /// main actor: the same move as a closure handed to `map` inside the
    /// view checked it was on the main thread once a point, a third of the
    /// waveforms' time near the whole-hour view (2026-11-17).
    nonisolated static func moved(_ points: [CGPoint], byX x: CGFloat, y: CGFloat) -> [CGPoint] {
        var moved = [CGPoint]()
        moved.reserveCapacity(points.count)
        for point in points { moved.append(CGPoint(x: point.x + x, y: point.y + y)) }
        return moved
    }

    /// The level, across the whole bar, as `SoundLevelLine` draws it at rest.
    private static func paintLevelLine(_ placed: Placed, in context: inout GraphicsContext) {
        let shown = placed.lineShown
        guard shown.width > 4 else { return }
        let bar = placed.bar
        let length = bar.bar.outMS - bar.bar.inMS
        let points = SoundLevelLine.shape(of: bar.level, lengthMS: length,
                                          fromMS: Int(Double(length) * Double(shown.startFraction)),
                                          toMS: Int(Double(length) * Double(shown.endFraction)),
                                          width: shown.width, height: bar.height)
        guard !points.isEmpty else { return }
        var path = Path()
        path.addLines(points)
        var line = context
        // The bar masks its line to the line's own frame, shadow and all.
        line.clip(to: Path(CGRect(x: shown.x, y: bar.top, width: shown.width, height: bar.height)))
        line.translateBy(x: shown.x, y: bar.top)
        line.addFilter(.shadow(color: SoundLevelLine.restingShadow.color, radius: SoundLevelLine.restingShadow.radius))
        line.stroke(path, with: .color(bar.soundTint.opacity(0.95)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    /// A diamond at each end, where its fade in and fade out are dragged from
    /// (`ClipPiecesBar.fadeHandles`).
    private static func paintFadeDiamonds(_ placed: Placed, in context: inout GraphicsContext) {
        let reach = SoundFadeDiamond.reach
        let whole = placed.whole
        guard whole >= reach * 2 + 4 else { return }
        let bar = placed.bar
        let length = bar.bar.outMS - bar.bar.inMS
        let half = reach / 2
        let perMS = length > 0 ? whole / CGFloat(length) : 0
        let inWidth = CGFloat(bar.level.fadeInMS) * perMS
        let outWidth = CGFloat(bar.level.fadeOutMS(lengthMS: length)) * perMS
        let ins = placed.x0 + min(max(half, inWidth), whole - half) - half
        let outs = placed.x0 + whole - min(max(half, outWidth), whole - half) - half
        for x in [ins, outs] {
            let centre = CGPoint(x: x + half, y: bar.top + SoundFadeDiamond.centreY - half + half)
            let side = SoundFadeDiamond.side
            let face = Path(roundedRect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side),
                            cornerRadius: 2)
            let edge = Path(roundedRect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
                .insetBy(dx: 0.75, dy: 0.75), cornerRadius: 1.25)
            let turn = CGAffineTransform(translationX: centre.x, y: centre.y).rotated(by: .pi / 4)
            var shadowed = context
            shadowed.addFilter(.shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1))
            shadowed.drawLayer { layer in
                layer.fill(face.applying(turn), with: .color(.white))
                layer.stroke(edge.applying(turn), with: .color(bar.soundTint), lineWidth: 1.5)
            }
        }
    }
}

/// The names of painted clips that may run off the lane's left edge, drawn
/// against the window on every frame of a scroll so each stays in sight
/// while its clip runs off (`TimelinePaint.nameFollowsTheEdge`). Every other
/// name rides on the canvas, which a scroll only slides.
///
/// **Each name is a picture, laid once and slid.** Drawn as a Canvas, the
/// names were a drawn layer redrawn on every frame of a zoom or scroll, and
/// each redraw sent the system's drawing cleanup to ask the window server
/// whether the last one was on screen yet: 950 asks in 360 frames of a
/// scroll along the 50 track edit, 3,150 in 648 frames of a zoom near Fit.
/// When the window server was slow to answer, that cleanup held a queue the
/// main thread needed at the end of its frame for 20 to 40 ms (task
/// `no-frame-of-a-50-track-zoom-is-held-up-by-the-sy`, 2026-11-26). A
/// picture is a plain layer's contents and asks nothing. Each name is laid
/// cut to its own reach (`NameShot`), so a frame that only slides it, or a
/// zoom that only makes its clip wider, shows the picture already laid.
struct TimelinePaintedNames: View, Equatable {
    let bars: [TimelinePaintedClips.Bar]
    let ruler: MotionStripRuler
    let drawnMS: ClosedRange<Double>
    let laneWidth: CGFloat
    let laneHeight: CGFloat

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let scale = max(1, displayScale)
        let shots = bars.compactMap { bar -> (place: CGPoint, picture: CGImage, size: CGSize)? in
            guard let one = TimelinePaintedClips.place(bar, ruler: ruler, drawnMS: drawnMS, laneWidth: laneWidth),
                  let shot = NameShot(one, scale: scale, scheme: colorScheme),
                  let picture = shot.picture() else { return nil }
            return (shot.place, picture, shot.size)
        }
        ZStack(alignment: .topLeading) {
            ForEach(shots.indices, id: \.self) { index in
                let shot = shots[index]
                Image(decorative: shot.picture, scale: scale)
                    .frame(width: shot.size.width, height: shot.size.height)
                    .offset(x: shot.place.x, y: shot.place.y)
            }
        }
        .frame(width: laneWidth, height: laneHeight, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    nonisolated static func == (a: TimelinePaintedNames, b: TimelinePaintedNames) -> Bool {
        a.bars == b.bars && a.ruler == b.ruler && a.drawnMS == b.drawnMS && a.laneWidth == b.laneWidth
            && a.laneHeight == b.laneHeight
    }
}

/// One edge name as a picture: the stretch of its clip the name can reach,
/// from where it is drawn, and what is drawn there. Two frames whose names
/// look the same in that stretch have the same `Look` and share a picture.
///
/// The name is painted exactly as the lane's canvas paints it
/// (`TimelinePaintedClips.paintName`, `paintSoundTag`), in the clip's own
/// place, and the picture is cut to the stretch, so it is the same pixels the
/// canvas drew there. The stretch reaches as far as the name can, its whole
/// width and its padding, so while the clip runs further than that, how far
/// it runs changes nothing in it.
@MainActor struct NameShot {
    struct Look: Hashable {
        let name: String
        let kind: VideoKit.ClipKind
        let isTag: Bool
        let top: CGFloat
        let height: CGFloat
        let topRadius: CGFloat
        let bottomRadius: CGFloat
        /// How strongly the pictures under a name show, which darkens its
        /// pill, in fiftieths.
        let pictures: Int
        /// How far the clip runs off the left edge, in pixels, as far as a
        /// rounded corner could show.
        let hidden: Int
        /// How the name is cut short: how many letters it keeps (-1 when it
        /// is whole), or while it has never been set, how much of the clip is
        /// left from where it starts, in pixels, past -1.
        let room: Int
        /// A tag's start between two pixels, in eighths of one.
        let fraction: Int
        /// The tag's lead: past the fade in diamond, or not.
        let leadsPastTheDiamond: Bool
        let scheme: ColorScheme
        let scale: CGFloat
    }

    /// Where the picture goes in the lane, and its size, in points.
    let place: CGPoint
    let size: CGSize
    let look: Look
    private let one: TimelinePaintedClips.Placed
    private let origin: CGFloat

    private static var laid: [Look: CGImage] = [:]
    private static var widths: [String: CGFloat] = [:]

    /// Nil when nothing of the name would be drawn.
    init?(_ one: TimelinePaintedClips.Placed, scale: CGFloat, scheme: ColorScheme) {
        let bar = one.bar
        self.one = one
        func pixels(_ v: CGFloat) -> Int { Int((v * scale).rounded()) }
        if bar.ground != nil {
            // `paintSoundTag`'s own sums.
            let off = max(0, -one.x0)
            let shown = one.lineShown
            let start = max(shown.x, one.x0 + max(0, off - TimelineSpan.slack))
            let left = shown.x + shown.width - start
            guard left > 40 else { return nil }
            let lead = off == 0 ? SoundFadeDiamond.reach + 4 : 4
            let from = (start * scale).rounded(.down) / scale
            let fraction = Int(((start - from) * scale * 8).rounded())
            // The tag ends at least eight points short of the clip's end
            // (`paintSoundTag`), so what it shows is decided by how its name
            // is cut, not by how much clip is left.
            let cut = TimelinePaintedClips.cut(of: bar.name, width: max(0, left - lead - 8 - 14), size: 9)
            let reach = lead + (cut?.width ?? Self.width(of: bar.name, size: 9)) + 14 + 4
            let width = (min(left + (start - from), reach) * scale).rounded(.up) / scale
            origin = from
            place = CGPoint(x: from, y: bar.top)
            size = CGSize(width: width, height: bar.height)
            look = Look(name: bar.name, kind: bar.kind, isTag: true, top: bar.top, height: bar.height,
                        topRadius: 0, bottomRadius: 0, pictures: 0, hidden: 0,
                        room: cut.map { $0.count ?? -1 } ?? -2 - pixels(left), fraction: fraction,
                        leadsPastTheDiamond: off == 0, scheme: scheme, scale: scale)
            return
        }
        guard !bar.isLinkedSound, !bar.isSound else { return nil }
        let (rect, _) = TimelinePaintedClips.outline(one, scale: scale)
        let hidden = max(0, -rect.minX)
        let room = rect.width - hidden
        guard room > 40 else { return nil }
        let pictures = bar.movie == nil ? 0 : bar.pictures
        // The name ends at least eight points short of the clip's end
        // (`paintName`), so what it shows is decided by how it is cut, not
        // by how much clip is left.
        let cut = TimelinePaintedClips.cut(of: bar.name, width: max(0, room - (pictures > 0 ? 26 : 20)))
        let reach = (cut?.width ?? Self.width(of: bar.name, size: 9.5)) + (pictures > 0 ? 4 + 10 + 4 : 8 + 4)
        // The clip's rect is on the screen's pixels already, and so is the
        // lane's left edge.
        let from = rect.minX + hidden
        let width = (min(room, reach) * scale).rounded(.up) / scale
        origin = from
        place = CGPoint(x: from, y: rect.minY)
        size = CGSize(width: width, height: rect.height)
        let radius = VideoKit.Metrics.clipCornerRadius
        look = Look(name: bar.name, kind: bar.kind, isTag: false, top: bar.top, height: rect.height,
                    topRadius: bar.half.isSound ? 0 : radius, bottomRadius: bar.half.isPicture ? 0 : radius,
                    pictures: Int((pictures * 50).rounded()),
                    hidden: pixels(min(hidden, radius + 2)), room: cut.map { $0.count ?? -1 } ?? -2 - pixels(room),
                    fraction: 0, leadsPastTheDiamond: false, scheme: scheme, scale: scale)
    }

    /// How wide a name is set whole, in the type the painting sets it in,
    /// measured once.
    private static func width(of name: String, size: CGFloat) -> CGFloat {
        let key = "\(size) \(name)"
        if let known = widths[key] { return known }
        if widths.count > 4000 { widths.removeAll() }
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        let measured = ceil((name as NSString).size(withAttributes: [.font: font]).width)
        widths[key] = measured
        return measured
    }

    /// The picture for this look, laid the first time it is asked for.
    func picture() -> CGImage? {
        if let kept = Self.laid[look] { return kept }
        guard size.width > 0, size.height > 0 else { return nil }
        #if PHOTONZ_PLAYTEST
        ViewBuildMeter.shared.built(.paintedPicture)
        #endif
        let one = self.one
        let origin = self.origin
        let size = self.size
        let laid = Canvas { context, _ in
            context.translateBy(x: -origin, y: -one.bar.top)
            context.clip(to: Path(CGRect(x: origin, y: one.bar.top, width: size.width, height: size.height)))
            if one.bar.ground != nil {
                TimelinePaintedClips.paintSoundTag(one, off: max(0, -one.x0), in: &context)
            } else {
                let (rect, shape) = TimelinePaintedClips.outline(one, scale: context.environment.displayScale)
                var inside = context
                inside.clip(to: shape)
                TimelinePaintedClips.paintName(one.bar, rect: rect, hidden: max(0, -rect.minX),
                                               pictures: one.bar.movie == nil ? 0 : one.bar.pictures, in: &inside)
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, look.scheme)
        .environment(\.displayScale, look.scale)
        let renderer = ImageRenderer(content: laid)
        renderer.scale = look.scale
        guard let picture = renderer.cgImage else { return nil }
        if Self.laid.count > 1200 { Self.laid.removeAll() }
        Self.laid[look] = picture
        return picture
    }
}

/// What a hand does to a painted clip: a click picks it, a drag carries it, a
/// right click opens its menu. Only the clips take a press; the lane between
/// them is still the lane. A pointer resting on a clip has it drawn as its
/// full bar before any of this is reached, so this is for a click that came
/// with no pointer move first.
private struct TimelinePaintedHands: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.displayScale) private var displayScale
    let placed: [TimelinePaintedClips.Placed]
    /// Everything here is on the canvas, which the lane slides into place.
    let canvas: TimelinePaint.Canvas
    let laneWidth: CGFloat
    let laneHeight: CGFloat

    /// The frame the lane lays out against while the timeline moves
    /// (`TimelineLaneFrame`).
    @Environment(\.timelineLaneFrame) private var laneFrame
    @State private var carried: UUID?

    /// Where the canvas sits across the lane now, in the lane's own points,
    /// read when a hand arrives rather than on every frame of a scroll.
    private var offset: CGFloat {
        canvas.offset(in: editorState.laneRuler(laneFrame), laneWidth: laneWidth, scale: displayScale)
    }

    var body: some View {
        Color.clear
            .frame(width: canvas.width, height: laneHeight)
            .contentShape(PaintedShapes(rects: placed.map(\.rect)))
            .gesture(carry)
            .onTapGesture(coordinateSpace: .local) { point in
                guard let hit = TimelinePaintedClips.clip(at: point, in: placed) else { return }
                editorState.clearKeySelection()
                let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                if flags.contains(.shift) || flags.contains(.command) {
                    editorState.selectedClipPieceIndex = nil
                    editorState.extendSelection(toLayer: hit.bar.layerID)
                } else {
                    editorState.selectClipPiece(layerID: hit.bar.layerID, index: nil)
                }
                // ...and the playhead to the moment clicked
                // (`EditorState+TimelinePointing`).
                editorState.playheadToTimelineClick(
                    laneX: editorState.windowX(ofLaneX: point.x + offset, frame: laneFrame, laneWidth: laneWidth),
                    laneWidth: laneWidth)
            }
            .contextMenu { TimelinePaintedClipMenu(placed: placed) }
    }

    /// A painted clip taken hold of and slid along, or up or down onto
    /// another track: `ClipPiecesBar.carry` for a clip of one piece.
    private var carry: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(TimelineDock.tracksSpace))
            .onChanged { value in
                if editorState.clipBarDrag == nil {
                    let laneX = editorState.laneX(ofWindowX: value.startLocation.x - TimelineDock.lanesLeading,
                                                  frame: laneFrame, laneWidth: laneWidth)
                    let start = CGPoint(x: laneX - offset, y: value.startLocation.y)
                    // Read across the lane only: a press in the lane is on
                    // the clip whose stretch it is in.
                    guard let hit = placed.last(where: {
                        start.x >= $0.rect.minX && start.x <= $0.rect.maxX
                    }) else { return }
                    carried = hit.bar.layerID
                    editorState.beginClipBarDrag(layerID: hit.bar.layerID, grab: .body,
                                                 copying: ClipPiecesBar.optionHeld)
                }
                guard let carried else { return }
                let travel = ClipPiecesBar.ms(value.translation.width, laneWidth: laneWidth,
                                              ruler: editorState.motionStripRuler)
                editorState.updateClipBarDrag(byMS: travel + editorState.timelineEdgePannedMS)
                let carriesTracks = !(placed.first { $0.bar.layerID == carried }?.bar.isLinkedSound ?? false)
                if carriesTracks {
                    editorState.updateClipTrackDrop(pointerY: value.location.y,
                                                    travelledY: value.translation.height
                                                        + editorState.timelineEdgeScroll.scrolledY)
                }
                editorState.clipBarDragHand(laneX: value.location.x - TimelineDock.lanesLeading,
                                            contentY: carriesTracks ? value.location.y : nil,
                                            handMS: travel, travelledY: value.translation.height)
            }
            .onEnded { _ in
                guard carried != nil else { return }
                carried = nil
                editorState.commitClipBarDrag()
            }
    }
}

/// Every painted clip, as the one shape a press can land on.
private struct PaintedShapes: Shape {
    let rects: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for one in rects { path.addRect(one) }
        return path
    }
}

/// A painted clip's right-click menu: the clip's own, for the clip the right
/// click landed on.
private struct TimelinePaintedClipMenu: View {
    @Environment(EditorState.self) private var editorState
    let placed: [TimelinePaintedClips.Placed]

    var body: some View {
        let _ = editorState.timelineRightPresses
        // The press is gone by the time a second build asks, so the last one
        // stands in for it.
        if let hit = clip(at: editorState.timelineRightPressMS) ?? clip(at: editorState.timelineLastRightPressMS) {
            TimelineClipMenu(layerID: hit.layerID, piece: 0, onTheSound: hit.isLinkedSound)
        }
    }

    private func clip(at ms: Int?) -> TimelinePaintedClips.Bar? {
        guard let ms else { return nil }
        return placed.last { $0.bar.bar.inMS <= ms && ms <= $0.bar.bar.outMS && !$0.bar.isLinkedSound }?.bar
    }
}

/// The cuts at rest on a busy lane, painted as one layer, in the order the
/// lane lists them so they overlap as their views did: the faint hairline
/// where two clips meet (`TimelineEditPointView.seam`), and the band of a
/// transition on one (`VideoKit.TransitionBand`). A cut picked, hovered,
/// holding on black or white, or with one of its clips in a hand is drawn as
/// its full view instead, which is the one a hand reaches.
struct TimelinePaintedCuts: View, Equatable {
    enum Mark: Equatable {
        /// A cut with nothing on it.
        case seam(atMS: Int)
        /// A transition's band, from where it starts for as long as it runs.
        case band(fromMS: Int, spanMS: Int, isDip: Bool, leadingGrip: Bool, trailingGrip: Bool)
    }

    @Environment(EditorState.self) private var editorState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    let marks: [Mark]
    /// Painted on the drawn stretch and slid into place by the lane, as the
    /// clips are (`TimelinePaint.Canvas`).
    let canvas: TimelinePaint.Canvas
    let laneWidth: CGFloat
    let height: CGFloat

    var body: some View {
        // The view's own scheme: the timeline can be drawn dark in a light
        // window, and a Canvas's context does not always say so.
        let scheme = colorScheme
        let ruler = canvas.ruler
        // Laid into a picture once, as the clips are (`TimelinePaintedPicture`).
        TimelinePaintedPicture(width: canvas.width, height: height, scale: displayScale, scheme: scheme,
                               canvas: canvas, laneWidth: laneWidth, asked: TimelinePaintedPicture.ask(),
                               followsAnEdit: editorState.drawsALateEdit) { context in
            let scale = max(1, context.environment.displayScale)
            func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
            for mark in marks {
                switch mark {
                case .seam(let ms):
                    let x = laneWidth * ruler.fraction(ofMS: Double(ms))
                    // `.editpt`'s capsule: two points wide, two in from each end.
                    let rect = CGRect(x: snap(x - 1), y: 2, width: 2, height: max(0, height - 4))
                    context.fill(Capsule().path(in: rect),
                                 with: .color(VideoKit.Palette.edgeLo.color(scheme)))
                case let .band(fromMS, spanMS, isDip, leadingGrip, trailingGrip):
                    let x = laneWidth * ruler.fraction(ofMS: Double(fromMS))
                    let width = max(6, laneWidth * ruler.fraction(spanningMS: Double(spanMS)))
                    let minX = snap(x)
                    let framed = CGRect(x: minX, y: 0, width: max(1 / scale, snap(x + width) - minX), height: height)
                    // Never narrower than its glyph: the band's view is laid
                    // out round its twelve point glyph, centred on a
                    // narrower frame.
                    let rect = framed.width >= 12 ? framed
                        : CGRect(x: snap(framed.midX - 6), y: 0, width: 12, height: height)
                    Self.paintBand(rect, isDip: isDip, leadingGrip: leadingGrip, trailingGrip: trailingGrip,
                                   scheme: scheme, in: &context)
                }
            }
        }
        .frame(width: canvas.width, height: height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private static func paintBand(_ rect: CGRect, isDip: Bool, leadingGrip: Bool, trailingGrip: Bool,
                                  scheme: ColorScheme, in context: inout GraphicsContext) {
        let shape = RoundedRectangle(cornerRadius: 6)
        if isDip {
            context.stroke(shape.inset(by: 0.5).path(in: rect), with: .color(.white.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        } else {
            // The shadow is cast by the band's base alone: the base is
            // opaque and the wash and edge lie inside it, so it is the same
            // shadow the whole band would cast, without a layer drawn on its
            // own for every band, three hundred of them near the whole-hour
            // view of the hour-long reference edit (2026-11-17).
            let outline = shape.path(in: rect)
            var shadowed = context
            shadowed.addFilter(.shadow(color: .black.opacity(0.4), radius: 5, x: 0, y: 4))
            shadowed.fill(outline, with: .color(VideoKit.Palette.transitionBase.color(scheme)))
            context.fill(outline, with: .linearGradient(
                Gradient(colors: [VideoKit.Palette.transitionFrom.color(scheme),
                                  VideoKit.Palette.transitionTo.color(scheme)]),
                startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
            context.stroke(shape.inset(by: 0.5).path(in: rect), with: .color(.white.opacity(0.55)), lineWidth: 1)
        }
        let glyph = VideoKit.TransitionGlyph().path(in: CGRect(x: rect.midX - 6, y: rect.midY - 6, width: 12, height: 12))
        if isDip {
            var lit = context
            lit.addFilter(.shadow(color: .black.opacity(0.9), radius: 1, x: 0, y: 1))
            lit.fill(glyph, with: .color(.white))
        } else {
            context.fill(glyph, with: .color(VideoKit.Palette.transitionInk.color(scheme)))
        }
        for (on, x) in [(leadingGrip, rect.minX - 2), (trailingGrip, rect.maxX - 5 + 2)] where on {
            context.fill(Path(roundedRect: CGRect(x: x, y: rect.midY - 8, width: 5, height: 16), cornerRadius: 2),
                         with: .color(.white.opacity(0.9)))
        }
    }

    nonisolated static func == (a: TimelinePaintedCuts, b: TimelinePaintedCuts) -> Bool {
        a.marks == b.marks && a.canvas == b.canvas && a.laneWidth == b.laneWidth && a.height == b.height
    }
}

/// A lane's painting laid once into a picture at the screen's scale, and the
/// picture shown. A Canvas is drawn again whenever it is moved by anything
/// but a whole pixel or stretched: a zoom that holds the last painting
/// (`EditorState.timelineHeldPainting`) stretched each lane's two canvases on
/// every frame, and drawing their five hundred clips again was about 1.2 ms of
/// a 10.5 ms frame near the whole-hour view of the hour-long reference edit
/// (2026-11-19). A picture is stretched as one image.
///
/// Laid with `margin` to spare on every side and placed back by it, since a
/// Canvas draws past its own frame (an edge's stroke, a band's shadow) and a
/// picture of the frame alone cut those off. A painting wider than a picture
/// can be is drawn as a Canvas, as before.
///
/// **While the timeline moves, a new picture is laid a frame late.** The
/// frame a zoom moves a lane on to a new canvas also builds the lane again, and
/// laying its pictures on top was 2.6 ms of a 10.6 ms pass near the
/// whole-hour view, every one of those frames late (2026-11-22, pass 21). So
/// while the lane has a frame (`TimelineLaneFrame`: the timeline is moving
/// and no hand is in a lane) and the picture moves to a canvas of another
/// scale, or to any other canvas on a zoom's frame, that frame shows the last picture placed on the new canvas
/// (`TimelinePaint.Canvas.place(ofPictureLaidOn:laneWidth:)`), as a held
/// zoom already shows it, and the new one is laid once the frame is out
/// (`AfterTheFrame`). At rest a picture is always laid on the frame that asks
/// for it, and one laid late is laid again when the timeline stops, so
/// nothing a late lay missed outlives the movement. A scroll's step lays
/// late too, where the last picture still holds the window and the next two
/// steps of the scroll (`EditorState.timelineSoonMS`): main thread p95 of a
/// fast scroll of the hour-long edit 8.8 to 9.2 ms down to 8.5 to 8.7
/// (2026-11-25, pass 24; on 2026-11-22, before the lanes took a new frame a
/// few at a time, laying late cost the frame after as much as it saved).
///
/// **An edit's picture may follow the edit by a pass more.** The timeline
/// draws an edit a pass after it landed (`EditorState.catchUpOnTheNextPass`),
/// and the last picture stands while the new one is laid between frames. The
/// few clips it does not hold, one whose full view just went among them, are
/// drawn over it meanwhile (`newcomers`), so no clip is drawn by nothing.
///
/// **A zoom's frame that changes nothing painted keeps the picture.** The lane
/// frame is read from the environment, so this body runs again when a zoom
/// begins even when the painting view above it did not change; `asked` says
/// so, and the picture laid for that painting stands (2026-11-22, pass 23).
struct TimelinePaintedPicture: View {
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let scheme: ColorScheme
    /// The canvas the picture is laid on and the lane's width, for showing
    /// the last picture on a new canvas while the new one lays. Nil lays
    /// every picture at once.
    var canvas: TimelinePaint.Canvas? = nil
    var laneWidth: CGFloat = 0
    /// Which build of the painting view asked for this picture
    /// (`TimelinePaintedPicture.ask()`): the same number when only the
    /// lane's frame changed and this body runs again for it, a new one when
    /// the painting was built again and may paint something else.
    var asked = 0
    /// The picture is of an edit the timeline draws a pass after it landed,
    /// and what it paints is in the last picture too, but for what
    /// `newcomers` paints, so the last one may stand for one pass more.
    var followsAnEdit = false
    /// The few bars the last picture does not hold, drawn over it meanwhile.
    var newcomers: ((inout GraphicsContext) -> Void)?
    let paint: (inout GraphicsContext) -> Void

    @Environment(EditorState.self) private var editorState
    @Environment(\.timelineLaneFrame) private var laneFrame
    @State private var kept = Kept()
    /// Moved on when a late picture lands, so the body shows it.
    @State private var landings = 0

    static let margin: CGFloat = 12
    @MainActor private static var asks = 0
    /// A new number for each build of a painting view, handed to its picture
    /// as `asked`.
    @MainActor static func ask() -> Int {
        asks &+= 1
        return asks
    }
    #if PHOTONZ_PLAYTEST
    /// How long laying pictures took, for the speed walk's line.
    @MainActor static var laidMS: Double = 0
    /// Pictures laid a frame late.
    @MainActor static var laidLate = 0
    #endif
    /// The widest picture laid, in pixels, inside what the GPU takes.
    static let widestPixels: CGFloat = 16_000

    /// The last picture laid and what it was laid for.
    @MainActor final class Kept {
        struct Shape: Equatable {
            let width: CGFloat
            let height: CGFloat
            let scale: CGFloat
            let scheme: ColorScheme
            let canvas: TimelinePaint.Canvas?
        }
        var picture: CGImage?
        var shape: Shape?
        /// The `asked` the picture was laid for.
        var asked: Int?
        /// The painting a late lay lays, the newest asked for.
        var waiting: (shape: Shape, asked: Int, paint: (inout GraphicsContext) -> Void)?
        /// A late picture landed and not shown yet.
        var landed = false
        /// The picture shown was laid late, so it is laid again at rest.
        var laidLate = false
        /// What laying it took last time, in seconds, so a late lay waits
        /// for a gap with that much room (`AfterTheFrame`).
        var layCost: Double = 0.001
    }

    var body: some View {
        let margin = Self.margin
        let shown = shownPicture
        if let picture = shown.picture {
            let place = shown.place
            Image(decorative: picture, scale: scale)
                .resizable()
                .frame(width: (CGFloat(picture.width) / max(1, scale)) * place.stretch,
                       height: height + margin * 2)
                .offset(x: place.x - margin * place.stretch, y: -margin)
                .frame(width: width, height: height, alignment: .topLeading)
                .overlay {
                    if shown.waits, let newcomers { Canvas { context, _ in newcomers(&context) } }
                }
        } else {
            Canvas { context, _ in paint(&context) }
                .frame(width: width, height: height)
        }
    }

    /// The picture to show this frame, and where on the canvas it goes.
    /// `waits` while it is the one from before an edit.
    private var shownPicture: (picture: CGImage?, place: (x: CGFloat, stretch: CGFloat), waits: Bool) {
        let _ = landings
        let shape = Kept.Shape(width: width, height: height, scale: scale, scheme: scheme, canvas: canvas)
        let unmoved: (x: CGFloat, stretch: CGFloat) = (0, 1)
        // A late picture that has landed, for the painting this frame asks for.
        if kept.landed {
            kept.landed = false
            if kept.shape == shape, kept.waiting == nil { return (kept.picture, unmoved, false) }
        }
        // A zoom beginning, or a frame that changes nothing this picture
        // paints: only the lane's frame moved, so the picture laid for this
        // same painting stands, slid and stretched with the lane. The first
        // frame of a zoom from rest laid every lane's picture again for the
        // same painting, about 9 ms on the hour-long reference edit
        // (2026-11-22, pass 23). Laid again at rest, like any other.
        if laneFrame?.isZoom == true, kept.asked == asked, kept.shape == shape, kept.waiting == nil,
           let picture = kept.picture {
            return (picture, unmoved, false)
        }
        if laneFrame?.isRest == false, let canvas, laneWidth > 0, let picture = kept.picture, let last = kept.shape,
           let lastCanvas = last.canvas, last.height == height, last.scale == scale, last.scheme == scheme,
           lastCanvas.ruler.spanMS != canvas.ruler.spanMS || (laneFrame?.isZoom == true && lastCanvas != canvas)
            || (laneFrame?.isZoom == false && lastCanvas != canvas
                && editorState.timelineSoonMS.map { lastCanvas.covers($0, laneWidth: laneWidth) } == true),
           fits {
            let first = kept.waiting == nil
            kept.waiting = (shape, asked, paint)
            if first { layLate() }
            #if PHOTONZ_PLAYTEST
            Self.laidLate += 1
            #endif
            return (picture, canvas.place(ofPictureLaidOn: lastCanvas, laneWidth: laneWidth), false)
        }
        // An edit a frame old already: its lanes are built in this pass, and
        // laying their pictures in it too was 2 to 4 ms of an 18 ms pass of a
        // trim of the hour-long reference edit (2026-11-25).
        // Never twice running: a second build lays at once, with the first's
        // newcomers.
        if followsAnEdit, kept.waiting == nil, kept.asked != asked, kept.shape == shape, let picture = kept.picture, fits {
            kept.waiting = (shape, asked, paint)
            layLate()
            return (picture, unmoved, true)
        }
        // Anything else lays at once, as it always has: a picture laid late
        // included, when the timeline stops, in case what it was laid from
        // moved on in the same pass it landed.
        let began = CACurrentMediaTime()
        let picture = lay(paint)
        kept.layCost = CACurrentMediaTime() - began
        kept.waiting = nil
        kept.laidLate = false
        kept.picture = picture
        kept.shape = shape
        kept.asked = asked
        return (picture, unmoved, false)
    }

    private var fits: Bool {
        width > 0 && height > 0 && (width + Self.margin * 2) * max(1, scale) <= Self.widestPixels
    }

    /// Lays the newest painting asked for once this frame is out.
    private func layLate() {
        let kept = self.kept
        let landings = $landings
        AfterTheFrame.run(cost: kept.layCost) {
            guard let waiting = kept.waiting else { return }
            kept.waiting = nil
            let s = waiting.shape
            let began = CACurrentMediaTime()
            kept.picture = Self.lay(waiting.paint, width: s.width, height: s.height, scale: s.scale, scheme: s.scheme)
            kept.layCost = CACurrentMediaTime() - began
            kept.shape = s
            kept.asked = waiting.asked
            kept.landed = true
            kept.laidLate = true
            LatePictures.land { if kept.landed { landings.wrappedValue &+= 1 } }
        }
    }

    private func lay(_ paint: @escaping (inout GraphicsContext) -> Void) -> CGImage? {
        Self.lay(paint, width: width, height: height, scale: scale, scheme: scheme)
    }

    private static func lay(_ paint: @escaping (inout GraphicsContext) -> Void, width: CGFloat, height: CGFloat,
                            scale: CGFloat, scheme: ColorScheme) -> CGImage? {
        let margin = Self.margin
        let scale = max(1, scale)
        guard width > 0, height > 0, (width + margin * 2) * scale <= Self.widestPixels else { return nil }
        #if PHOTONZ_PLAYTEST
        ViewBuildMeter.shared.built(.paintedPicture)
        let began = CACurrentMediaTime()
        defer { Self.laidMS += (CACurrentMediaTime() - began) * 1000 }
        #endif
        let laid = Canvas { context, _ in
            context.translateBy(x: margin, y: margin)
            // Cut where a Canvas of the frame cuts its drawing.
            context.clip(to: Path(CGRect(x: 0, y: 0, width: width, height: height)))
            paint(&context)
        }
        .frame(width: width + margin * 2, height: height + margin * 2)
        .environment(\.colorScheme, scheme)
        .environment(\.displayScale, scale)
        let renderer = ImageRenderer(content: laid)
        renderer.scale = scale
        return renderer.cgImage
    }
}

/// Work held until the frame being built is out: run when the main run loop
/// next wakes with room in the refresh it is in, which is after a pass's
/// drawing is handed over and before the next frame's update, so it fills the
/// gap between two frames rather than lengthening the one that asked for it.
/// A main queue block is not that: it can run in the same turn of the run
/// loop, before the frame is handed over (`TimelinePaintedPicture`,
/// 2026-11-22).
///
/// Room is read off the passes the run loop made in the last refresh, and a
/// piece of work is weighed by what it cost last time (`SpareFrameTime`): in
/// the first gap after the frame that built the hour-long edit's busiest lane
/// again, its picture made that refresh the late one (2026-11-25, pass 25).
@MainActor enum AfterTheFrame {
    private struct Held {
        let work: @MainActor () -> Void
        let cost: Double
        let since: CFTimeInterval
    }
    private static var waiting: [Held] = []
    private static var spare = SpareFrameTime()
    private static var watching = false
    /// A wake asked for while work waits, so it is not left for an event
    /// that may never come.
    private static var wakeAsked = false

    /// Holds `work` until a gap has room for it; `cost` is about what it
    /// took last time, in seconds.
    static func run(cost: Double = 0.001, _ work: @escaping @MainActor () -> Void) {
        watch()
        waiting.append(Held(work: work, cost: cost, since: CACurrentMediaTime()))
        askForAWake()
    }

    /// Watches every pass of the main run loop from the first held work on:
    /// two clock reads a pass.
    private static func watch() {
        guard !watching else { return }
        watching = true
        let moments = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        let observer = CFRunLoopObserverCreateWithHandler(nil, moments, true, 0) { _, activity in
            MainActor.assumeIsolated {
                let now = CACurrentMediaTime()
                if activity == .beforeWaiting {
                    AfterTheFrame.spare.passEnded(at: now)
                    return
                }
                AfterTheFrame.spare.passBegan(at: now)
                AfterTheFrame.runWhatFits(now: now)
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private static func runWhatFits(now: CFTimeInterval) {
        guard !waiting.isEmpty else { return }
        let chosen = spare.runs(costs: waiting.map(\.cost), waitedSince: waiting.map(\.since), now: now)
        guard !chosen.isEmpty else { return askForAWake() }
        let running = chosen.map { waiting[$0] }
        let taken = Set(chosen)
        waiting = waiting.indices.filter { !taken.contains($0) }.map { waiting[$0] }
        for held in running { held.work() }
        if !waiting.isEmpty { askForAWake() }
    }

    /// Wakes the run loop a refresh from now, so work that waits runs even
    /// if nothing else happens.
    private static func askForAWake() {
        guard !wakeAsked else { return }
        wakeAsked = true
        DispatchQueue.main.asyncAfter(deadline: .now() + spare.refresh) {
            MainActor.assumeIsolated { AfterTheFrame.wakeAsked = false }
        }
    }
}

/// Pictures laid late and not shown yet. Shown one by one as each landed, a
/// picture was a pass and a commit of its own: 3 ms of the frame after every
/// fresh one of a zoom on a 50 track timeline (2026-11-25). They are shown
/// with the timeline's next step, in the pass it makes anyway, or a moment
/// later when none comes.
@MainActor enum LatePictures {
    private static var waiting: [@MainActor () -> Void] = []
    private static var fallback: Task<Void, Never>?

    static func land(_ show: @escaping @MainActor () -> Void) {
        waiting.append(show)
        guard fallback == nil else { return }
        fallback = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(25))
            showAll()
        }
    }

    /// Called as the timeline steps.
    static func showAll() {
        fallback?.cancel()
        fallback = nil
        guard !waiting.isEmpty else { return }
        let all = waiting
        waiting = []
        for show in all { show() }
    }
}
