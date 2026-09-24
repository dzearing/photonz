import AppKit
import PhotonzCore
import SwiftUI

/// The caption cues on a Captions track that nobody is working on, painted
/// as one layer: the same bars `ClipPiecesBar` draws for them, with the same
/// click, drag, right click and tooltip, and none of the cost of a view each.
///
/// A five minute talk writes itself about 170 cues, and a half hour one a
/// thousand. Drawn as full clip bars, every one of them read the whole
/// document as it drew, so an edit anywhere (setting an In, a zoom) re-ran
/// all of them and froze the timeline for a sixth of a second
/// (`a-long-captioned-recording-walk`). This layer reads nothing of the
/// document: its row hands it where each cue sits and the ruler they sit on,
/// and an edit that moves neither leaves it alone. However many cues there
/// are, it is two views.
///
/// Picked, a cue leaves this layer and is drawn as the full bar, grips, name
/// field and all. A drag that starts here picks the cue as it begins, so the
/// cue stays here until the drag lets go (`EditorState.carriedCaptionCueID`),
/// or the gesture in the hand would be thrown away with the view holding it.
struct CaptionCuesLayer: View, Equatable {
    struct Cue: Equatable {
        let layerID: UUID
        let name: String
        let bar: LayerTime
    }

    let cues: [Cue]
    let ruler: MotionStripRuler
    let laneWidth: CGFloat
    let height: CGFloat

    var body: some View {
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.clipBar)
        #endif
        let placed = Self.placed(cues, ruler: ruler, laneWidth: laneWidth)
        // Side by side rather than one over the other as an overlay: the
        // painting takes no presses, and a hit-testing switch on a view is
        // inherited by anything overlaid on it.
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for cue in placed { Self.paint(cue, height: height, in: &context) }
            }
            .frame(width: laneWidth, height: height, alignment: .topLeading)
            .allowsHitTesting(false)
            CaptionCuesHands(placed: placed, ruler: ruler, laneWidth: laneWidth, height: height)
        }
    }

    // MARK: Where they go

    struct Placed {
        let cue: Cue
        /// The part of the bar in the window (`TimelineSpan`), along x.
        let minX: CGFloat
        let width: CGFloat
        /// How much of it is off the left edge, so its name stays in sight.
        let hiddenLeading: CGFloat

        var maxX: CGFloat { minX + width }
    }

    static func placed(_ cues: [Cue], ruler: MotionStripRuler, laneWidth: CGFloat) -> [Placed] {
        cues.compactMap { cue in
            let x = laneWidth * ruler.fraction(ofMS: Double(cue.bar.inMS))
            let width = max(2, laneWidth * ruler.fraction(spanningMS: Double(cue.bar.outMS - cue.bar.inMS)))
            let shown = TimelineSpan.drawn(x: x, width: width, across: laneWidth)
            guard shown.width > 0 else { return nil }
            return Placed(cue: cue, minX: shown.x, width: shown.width, hiddenLeading: max(0, -shown.x))
        }
    }

    /// The cue a point in the lane lands on.
    static func cue(at point: CGPoint, in placed: [Placed]) -> Placed? {
        placed.last { point.x >= $0.minX && point.x <= $0.maxX }
    }

    // MARK: Painting one

    /// The kit's caption clip, as `ClipPiecesBar.kitFace` draws one piece:
    /// the fill, the border, the lit top edge, and the words when there is
    /// room for them.
    private static func paint(_ placed: Placed, height: CGFloat, in context: inout GraphicsContext) {
        let kind = VideoKit.ClipKind.caption
        let radius = VideoKit.Metrics.clipCornerRadius
        let rect = CGRect(x: placed.minX, y: 0, width: placed.width, height: height)
        let shape = Path(roundedRect: rect, cornerRadius: radius)
        context.fill(shape, with: .style(kind.fill))
        var inside = context
        inside.clip(to: shape)
        if let border = kind.border {
            inside.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius - 0.5),
                          with: .color(border), lineWidth: 1)
        }
        inside.fill(Path(CGRect(x: rect.minX + radius / 2, y: 0,
                                width: max(0, rect.width - radius), height: 1)),
                    with: .color(.white.opacity(0.18)))
        let room = rect.width - placed.hiddenLeading
        guard room > 40 else { return }
        let left = rect.minX + placed.hiddenLeading + 8
        let words = fitted(placed.cue.name, width: max(0, room - 4 - 16), in: inside, ink: kind.ink)
        var type = inside
        type.addFilter(.shadow(color: .black.opacity(0.35), radius: 1))
        type.draw(words, at: CGPoint(x: left, y: height / 2), anchor: .leading)
    }

    /// The name as the full bar sets it on one line: whole where it fits, and
    /// otherwise cut short with an ellipsis, the way `.truncationMode(.tail)`
    /// ends it.
    private static func fitted(_ name: String, width: CGFloat, in context: GraphicsContext,
                               ink: Color) -> GraphicsContext.ResolvedText {
        func resolved(_ words: String) -> GraphicsContext.ResolvedText {
            context.resolve(Text(words).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(ink))
        }
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let whole = resolved(name)
        guard whole.measure(in: unbounded).width > width else { return whole }
        let letters = Array(name)
        var low = 0
        var high = letters.count
        while low < high {
            let middle = (low + high + 1) / 2
            if resolved(String(letters.prefix(middle)) + "…").measure(in: unbounded).width <= width {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return resolved(String(letters.prefix(low)).trimmingCharacters(in: .whitespaces) + "…")
    }

    nonisolated static func == (a: CaptionCuesLayer, b: CaptionCuesLayer) -> Bool {
        a.cues == b.cues && a.ruler == b.ruler && a.laneWidth == b.laneWidth && a.height == b.height
    }
}

/// What a hand does to a painted cue: a click picks it, a drag carries it
/// along the timeline or onto another track, a right click opens its menu.
/// Only the cues themselves take a press; the lane between them is still the
/// lane, and a press there moves the playhead as it always has.
private struct CaptionCuesHands: View {
    @Environment(EditorState.self) private var editorState
    let placed: [CaptionCuesLayer.Placed]
    let ruler: MotionStripRuler
    let laneWidth: CGFloat
    let height: CGFloat

    /// The cue under the pointer: what a right click is about.
    @State private var hovered: UUID?
    /// The cue a drag took hold of, and where the lane sits among the tracks,
    /// so the drag can say which track the pointer is over.
    @State private var carried: UUID?
    @State private var laneTop: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: laneWidth, height: height)
                .contentShape(CueShapes(spans: placed.map { ($0.minX, $0.width) }))
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let point): hovered = CaptionCuesLayer.cue(at: point, in: placed)?.cue.layerID
                    case .ended: hovered = nil
                    }
                }
                .gesture(carry)
                .onTapGesture(coordinateSpace: .local) { point in
                    guard let hit = CaptionCuesLayer.cue(at: point, in: placed) else { return }
                    editorState.clearKeySelection()
                    editorState.selectClipPiece(layerID: hit.cue.layerID, index: nil)
                }
                .contextMenu {
                    if let hovered { TimelineClipMenu(layerID: hovered, piece: 0) }
                }
                .help(ClipPiecesBar.help(ClipPieces(single: LayerTime(inMS: 0, outMS: 1)), index: 0))
                // One name for the whole painted layer, so a walk can click a
                // cue for real: `press` with `across` lands on one of them.
                .playtestControl("Captions cues", detail: "Timeline")
            if let carried, editorState.clipBarDrag?.layerID == carried {
                if let snap = editorState.clipBarSnap {
                    ClipPiecesBar.snapLine(atMS: snap.ms, ruler: ruler, laneWidth: laneWidth,
                                           barHeight: height)
                }
                if let readout = editorState.clipBarReadout,
                   let at = placed.first(where: { $0.cue.layerID == carried }) {
                    ClipPiecesBar.capsule(readout, x: at.minX, laneWidth: laneWidth)
                        .frame(height: height)
                }
            }
        }
        .frame(width: laneWidth, height: height, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named(TimelineDock.tracksSpace)).minY
        } action: { laneTop = $0 }
    }

    /// A cue taken hold of and slid along, or up or down onto another track:
    /// `ClipPiecesBar.carry` for a clip of one piece.
    private var carry: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                if editorState.clipBarDrag == nil {
                    guard let hit = CaptionCuesLayer.cue(at: value.startLocation, in: placed) else { return }
                    carried = hit.cue.layerID
                    editorState.carriedCaptionCueID = hit.cue.layerID
                    editorState.beginClipBarDrag(layerID: hit.cue.layerID, grab: .body)
                }
                guard carried != nil else { return }
                editorState.updateClipBarDrag(
                    byMS: ClipPiecesBar.ms(value.translation.width, laneWidth: laneWidth,
                                           ruler: editorState.motionStripRuler))
                editorState.updateClipTrackDrop(pointerY: laneTop + value.location.y,
                                                travelledY: value.translation.height)
            }
            .onEnded { _ in
                guard carried != nil else { return }
                carried = nil
                editorState.commitClipBarDrag()
                editorState.carriedCaptionCueID = nil
            }
    }
}

/// Every painted cue, as the one shape a press can land on.
private struct CueShapes: Shape {
    let spans: [(minX: CGFloat, width: CGFloat)]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for span in spans { path.addRect(CGRect(x: span.minX, y: 0, width: span.width, height: rect.height)) }
        return path
    }
}
