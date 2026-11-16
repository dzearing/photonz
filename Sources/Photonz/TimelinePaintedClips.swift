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
    /// What it is painted on: the drawn stretch, measured from where it
    /// starts, which a scroll inside one stretch leaves alone. The lane
    /// slides it into place (`TimelinePaint.Canvas`).
    let canvas: TimelinePaint.Canvas
    /// The stretch either side of the window a bar is drawn across
    /// (`EditorState.timelineDrawnMS`), cut the same way the bar cuts itself.
    let drawnMS: ClosedRange<Double>
    let laneWidth: CGFloat
    let laneHeight: CGFloat

    /// Pictures that landed or strips that came into view a moment ago, and
    /// when, so each fades in as a full bar's does (`ClipFilmstripTile`).
    @State private var fades: [Fade: TimeInterval] = [:]
    /// The clips whose strips have been seen, so a strip that comes in with
    /// a zoom fades in rather than popping.
    @State private var stripsSeen: Set<UUID>?
    /// Bumped each time a picture lands, which paints it.
    @State private var landed = 0

    enum Fade: Hashable {
        case tile(ClipFilmstripFrames.Key)
        case strip(UUID)
    }

    var body: some View {
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.clipBar)
        #endif
        let _ = landed
        let placed = bars.compactMap { Self.place($0, ruler: canvas.ruler, drawnMS: drawnMS, laneWidth: laneWidth) }
        let strips = placed.map { Self.strip(of: $0) }
        let wanted = Self.wanted(strips, middle: canvas.width / 2)
        let seen = stripsSeen
        let showing = Set(zip(placed, strips).compactMap { $1 == nil ? nil : $0.bar.layerID })
        let fades = self.fades
        // Side by side rather than one over the other as an overlay: the
        // painting takes no presses, and a hit-testing switch on a view is
        // inherited by anything overlaid on it.
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: nil, paused: fades.isEmpty)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, _ in
                    for (one, strip) in zip(placed, strips) {
                        var alpha: (Fade) -> Double = { _ in 1 }
                        if !fades.isEmpty || seen != nil {
                            alpha = { fade in
                                if case .strip(let id) = fade, let seen, !seen.contains(id), fades[fade] == nil {
                                    return 0
                                }
                                return Self.faded(since: fades[fade], now: now)
                            }
                        }
                        Self.paint(one, strip: strip, alpha: alpha, in: &context)
                    }
                }
            }
            .frame(width: canvas.width, height: laneHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            TimelinePaintedHands(placed: placed, canvas: canvas, laneWidth: laneWidth, laneHeight: laneHeight)
        }
        .frame(width: canvas.width, height: laneHeight, alignment: .topLeading)
        // A strip new to the lane fades in; one already here when the lane
        // started painting does not.
        .onChange(of: showing, initial: true) { _, now in
            guard let seen = stripsSeen else {
                stripsSeen = now
                return
            }
            let fresh = now.subtracting(seen)
            stripsSeen = now
            guard !fresh.isEmpty else { return }
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
            let missing = wanted.filter { ClipFilmstripFrames.shared.cached($0.key) == nil }
            guard !Task.isCancelled, !missing.isEmpty else { return }
            await withTaskGroup(of: ClipFilmstripFrames.Key?.self) { group in
                for want in missing {
                    group.addTask { await Self.read(want) }
                }
                for await key in group {
                    guard let key, !Task.isCancelled else { continue }
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
            && a.laneHeight == b.laneHeight
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

    /// The name as the full bar sets it on one line, as `CaptionCuesLayer.fitted`
    /// sets it, from widths measured once.
    static func fitted(_ name: String, width: CGFloat, size: CGFloat = 9.5, in context: GraphicsContext,
                       ink: Color) -> GraphicsContext.ResolvedText {
        func resolved(_ words: String) -> GraphicsContext.ResolvedText {
            context.resolve(Text(words).font(.system(size: size, weight: .semibold)).foregroundStyle(ink))
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
        guard let first = outline.first else { return }
        var path = Path()
        path.move(to: first)
        for point in outline.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        context.fill(path.offsetBy(dx: rect.minX, dy: rect.minY), with: .color(placed.bar.soundTint.opacity(0.55)))
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
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
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
struct TimelinePaintedNames: View, Equatable {
    let bars: [TimelinePaintedClips.Bar]
    let ruler: MotionStripRuler
    let drawnMS: ClosedRange<Double>
    let laneWidth: CGFloat
    let laneHeight: CGFloat

    var body: some View {
        let placed = bars.compactMap {
            TimelinePaintedClips.place($0, ruler: ruler, drawnMS: drawnMS, laneWidth: laneWidth)
        }
        Canvas { context, _ in
            for one in placed {
                let (rect, shape) = TimelinePaintedClips.outline(one, scale: context.environment.displayScale)
                var inside = context
                inside.clip(to: shape)
                if one.bar.ground != nil {
                    var whole = context
                    TimelinePaintedClips.paintSoundTag(one, off: max(0, -one.x0), in: &whole)
                    continue
                }
                TimelinePaintedClips.paintName(one.bar, rect: rect, hidden: max(0, -rect.minX),
                                               pictures: one.bar.movie == nil ? 0 : one.bar.pictures, in: &inside)
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

    @State private var carried: UUID?

    /// Where the canvas sits across the lane now, read when a hand arrives
    /// rather than on every frame of a scroll.
    private var offset: CGFloat {
        canvas.offset(in: editorState.motionStripRuler, laneWidth: laneWidth, scale: displayScale)
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
                editorState.playheadToTimelineClick(laneX: point.x + offset, laneWidth: laneWidth)
            }
            .contextMenu { TimelinePaintedClipMenu(placed: placed) }
    }

    /// A painted clip taken hold of and slid along, or up or down onto
    /// another track: `ClipPiecesBar.carry` for a clip of one piece.
    private var carry: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(TimelineDock.tracksSpace))
            .onChanged { value in
                if editorState.clipBarDrag == nil {
                    let start = CGPoint(x: value.startLocation.x - TimelineDock.lanesLeading - offset,
                                        y: value.startLocation.y)
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

    @Environment(\.colorScheme) private var colorScheme
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
        Canvas { context, _ in
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
            var shadowed = context
            shadowed.addFilter(.shadow(color: .black.opacity(0.4), radius: 5, x: 0, y: 4))
            shadowed.drawLayer { layer in
                let outline = shape.path(in: rect)
                layer.fill(outline, with: .color(VideoKit.Palette.transitionBase.color(scheme)))
                layer.fill(outline, with: .linearGradient(
                    Gradient(colors: [VideoKit.Palette.transitionFrom.color(scheme),
                                      VideoKit.Palette.transitionTo.color(scheme)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
                layer.stroke(shape.inset(by: 0.5).path(in: rect), with: .color(.white.opacity(0.55)), lineWidth: 1)
            }
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
