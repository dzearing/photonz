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
    }

    let bars: [Bar]
    let ruler: MotionStripRuler
    /// The stretch either side of the window a bar is drawn across
    /// (`EditorState.timelineDrawnMS`), cut the same way the bar cuts itself.
    let drawnMS: ClosedRange<Double>
    let laneWidth: CGFloat
    let laneHeight: CGFloat

    var body: some View {
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.clipBar)
        #endif
        let placed = bars.compactMap { Self.place($0, ruler: ruler, drawnMS: drawnMS, laneWidth: laneWidth) }
        // Side by side rather than one over the other as an overlay: the
        // painting takes no presses, and a hit-testing switch on a view is
        // inherited by anything overlaid on it.
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for one in placed { Self.paint(one, in: &context) }
            }
            .frame(width: laneWidth, height: laneHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            TimelinePaintedHands(placed: placed, laneWidth: laneWidth, laneHeight: laneHeight)
        }
    }

    nonisolated static func == (a: TimelinePaintedClips, b: TimelinePaintedClips) -> Bool {
        a.bars == b.bars && a.ruler == b.ruler && a.drawnMS == b.drawnMS && a.laneWidth == b.laneWidth
            && a.laneHeight == b.laneHeight
    }

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

    private static func paint(_ placed: Placed, in context: inout GraphicsContext) {
        let bar = placed.bar
        let radius = VideoKit.Metrics.clipCornerRadius
        // On the screen's pixels, as a view's frame is laid out: drawn where
        // it falls, an edge between two pixels is a blur the bar never has.
        let rect = snapped(placed.rect, scale: context.environment.displayScale)
        // Square where the clip's other half meets it, so the two read as one
        // rectangle (`ClipPiecesBar.pieceShape`).
        let top = bar.half.isSound ? 0 : radius
        let bottom = bar.half.isPicture ? 0 : radius
        let shape = UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                           bottomTrailingRadius: bottom, topTrailingRadius: top).path(in: rect)
        context.fill(shape, with: .style(bar.kind.fill))
        var inside = context
        inside.clip(to: shape)
        if let border = bar.kind.border {
            // A whole rectangle's border, run past the join and cut off there.
            let framed = CGRect(x: rect.minX, y: rect.minY - (bar.half.isSound ? 2 * radius : 0),
                                width: rect.width,
                                height: rect.height + (bar.half.isSound || bar.half.isPicture ? 2 * radius : 0))
            inside.stroke(Path(roundedRect: framed.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius - 0.5),
                          with: .color(border), lineWidth: 1)
        }
        // The lit top edge every clip in the mock has.
        inside.fill(Path(CGRect(x: rect.minX + radius / 2, y: rect.minY,
                                width: max(0, rect.width - radius), height: 1)),
                    with: .color(.white.opacity(0.18)))
        // The name, kept in sight while the clip runs off the lane's left edge.
        let hidden = max(0, -rect.minX)
        let room = rect.width - hidden
        if room > 40, !bar.isLinkedSound, !bar.isSound {
            let words = CaptionCuesLayer.fitted(bar.name, width: max(0, room - 4 - 16), in: inside,
                                                ink: bar.kind.ink(inside.environment.colorScheme))
            var type = inside
            type.addFilter(.shadow(color: .black.opacity(0.35), radius: 1))
            type.draw(words, at: CGPoint(x: rect.minX + hidden + 8, y: rect.midY), anchor: .leading)
        }
        if bar.isSound, let piece = bar.piece, piece.playsSound, let wave = bar.waveform, rect.width >= 2 {
            paintWaveform(wave, piece: piece, placed: placed, rect: rect, in: &inside)
        }
        if bar.isSound {
            paintLevelLine(placed, in: &context)
            paintFadeDiamonds(placed, in: &context)
        }
        paintPictureFades(placed, in: &context)
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

/// What a hand does to a painted clip: a click picks it, a drag carries it, a
/// right click opens its menu. Only the clips take a press; the lane between
/// them is still the lane. A pointer resting on a clip has it drawn as its
/// full bar before any of this is reached, so this is for a click that came
/// with no pointer move first.
private struct TimelinePaintedHands: View {
    @Environment(EditorState.self) private var editorState
    let placed: [TimelinePaintedClips.Placed]
    let laneWidth: CGFloat
    let laneHeight: CGFloat

    @State private var carried: UUID?

    var body: some View {
        Color.clear
            .frame(width: laneWidth, height: laneHeight)
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
                editorState.playheadToTimelineClick(laneX: point.x, laneWidth: laneWidth)
            }
            .contextMenu { TimelinePaintedClipMenu(placed: placed) }
    }

    /// A painted clip taken hold of and slid along, or up or down onto
    /// another track: `ClipPiecesBar.carry` for a clip of one piece.
    private var carry: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(TimelineDock.tracksSpace))
            .onChanged { value in
                if editorState.clipBarDrag == nil {
                    let start = CGPoint(x: value.startLocation.x - TimelineDock.lanesLeading,
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
    let ruler: MotionStripRuler
    let laneWidth: CGFloat
    let height: CGFloat

    var body: some View {
        // The view's own scheme: the timeline can be drawn dark in a light
        // window, and a Canvas's context does not always say so.
        let scheme = colorScheme
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
        .frame(width: laneWidth, height: height, alignment: .topLeading)
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
        a.marks == b.marks && a.ruler == b.ruler && a.laneWidth == b.laneWidth && a.height == b.height
    }
}
