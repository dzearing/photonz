import AppKit
import PhotonzCore
import SwiftUI

// A layer's track opens into one lane per keyed value
// (task `a-layer-s-track-opens-into-one-lane-per-keyed-va`, `KeyLanes.swift`).
//
// The mock draws it in `video-move-wt.html` step 5: under the layer's track, a
// row per keyed value with its name in the gutter and, in the lane, a diamond
// per key joined by a faint line (`.kfl`, `.kfd`, `.kfseg`). Everything a
// Premiere editor does to keys is done here: click, Shift-click, a box drawn
// round several, drag, Option-drag to copy, ⌫, and a right click for how the
// value moves through the key. A lane opens into its curve (`video.html`,
// THE GRAPH), on the timeline's own clock, where a Bezier key's handles are
// dragged.

/// Every lane of one clip.
struct KeyLanesView: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let layerName: String
    let laneWidth: CGFloat
    var indent: CGFloat = 0
    var isLocked = false

    /// A box being drawn round keys, in the lanes' own space (the first
    /// lane's top left is nought).
    @State private var box: CGRect?

    /// `.kfl{height:18px}`.
    static let laneHeight: CGFloat = 18
    /// A lane opened into its curve.
    static let graphHeight: CGFloat = 88
    static let spacing: CGFloat = 3

    private var space: String { "key-lanes-\(layerID.uuidString)" }

    var body: some View {
        let lanes = editorState.keyLanes(layerID: layerID)
        VStack(alignment: .leading, spacing: Self.spacing) {
            ForEach(lanes) { lane in
                HStack(spacing: TimelineDock.gap) {
                    KeyLaneLabel(layerID: layerID, lane: lane, indent: indent)
                    KeyLaneView(layerID: layerID, layerName: layerName, lane: lane,
                                laneWidth: laneWidth, space: space,
                                isLocked: isLocked) { rect, done in
                        drawBox(rect, done: done, lanes: lanes)
                    }
                }
                .playtestField("Key lane \(layerName) \(lane.title)")
            }
        }
        .coordinateSpace(.named(space))
        .overlay(alignment: .topLeading) {
            if let box {
                Rectangle()
                    .fill(VideoKit.Palette.accent.opacity(0.12))
                    .overlay(Rectangle().strokeBorder(VideoKit.Palette.accent.opacity(0.8), lineWidth: 1))
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX + TimelineDock.lanesLeading, y: box.minY)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The box, as the hand draws it; on letting go, every key inside it is
    /// picked.
    private func drawBox(_ rect: CGRect?, done: Bool, lanes: [KeyLane]) {
        guard let rect else {
            box = nil
            return
        }
        box = done ? nil : rect
        guard done else { return }
        let ruler = editorState.motionStripRuler
        var picked = Set<KeyRef>()
        var top: CGFloat = 0
        for lane in lanes {
            let height = editorState.isKeyLaneGraphed(lane.motionID) ? Self.graphHeight : Self.laneHeight
            if rect.maxY >= top, rect.minY <= top + height {
                for key in lane.keys {
                    let x = laneWidth * ruler.fraction(ofMS: Double(key.documentMS))
                    if x >= rect.minX - 4, x <= rect.maxX + 4 { picked.insert(key.ref) }
                }
            }
            top += height + Self.spacing
        }
        let flags = NSEvent.modifierFlags
        editorState.pickKeys(layerID: layerID, picked,
                             extending: flags.contains(.shift) || flags.contains(.command))
    }
}

// MARK: - The name in the gutter

/// A lane's name, indented under its track, and the button that opens its
/// curve.
private struct KeyLaneLabel: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let lane: KeyLane
    let indent: CGFloat

    @State private var isHovered = false

    var body: some View {
        let graphed = editorState.isKeyLaneGraphed(lane.motionID)
        let canGraph = lane.property != .color
        HStack(spacing: 2) {
            Text(lane.title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(VideoKit.Palette.dim)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if canGraph, isHovered || graphed {
                Button {
                    editorState.toggleKeyGraph(lane.motionID)
                } label: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(graphed ? AnyShapeStyle(VideoKit.Palette.accent)
                                                 : AnyShapeStyle(VideoKit.Palette.faint))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(graphed ? "Hide the curve" : "Show the curve")
                .playtestControl("Graph \(lane.title)", detail: "Timeline")
            }
        }
        .padding(.leading, 12 + indent)
        .padding(.trailing, 2)
        .padding(.top, graphed ? 3 : 0)
        .frame(width: TimelineDock.gutter, alignment: .leading)
        .frame(height: graphed ? KeyLanesView.graphHeight : KeyLanesView.laneHeight,
               alignment: graphed ? .top : .center)
        .contentShape(Rectangle())
        .playtestHover("Key lane \(lane.title)") { isHovered = $0 }
        .contextMenu { MenuRowsView(rows: editorState.keyLaneMenuRows(layerID: layerID, motionID: lane.motionID)) }
        .panelReadout("lane \(lane.title): \(lane.keys.count) key\(lane.keys.count == 1 ? "" : "s")"
                      + (graphed ? ", curve open" : ""))
    }
}

// MARK: - One lane

/// One lane: its keys joined by a faint line, or, opened, the curve they
/// make.
private struct KeyLaneView: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.colorScheme) private var colorScheme
    let layerID: UUID
    let layerName: String
    let lane: KeyLane
    let laneWidth: CGFloat
    let space: String
    let isLocked: Bool
    /// A box being drawn from this lane, in the lanes' own space; nil when
    /// it is called off, and `done` when the hand lets go.
    let onBox: (CGRect?, _ done: Bool) -> Void

    /// A handle in the hand: which, and where on the curve it is, with the
    /// range the curve was drawn in when it was taken hold of, so the curve
    /// does not rescale under the hand as it overshoots.
    @State private var handleDrag: HandleDrag?

    struct HandleDrag {
        var ref: KeyRef
        var side: KeyHandleSide
        var point: CGPoint
        var low: Double
        var high: Double
    }

    /// Past this a press on the bare lane is a box rather than a click.
    private static let boxThreshold: CGFloat = 3
    /// How near the playhead a dragged key lands on it.
    private static let keySnap: CGFloat = 6
    private static let graphPad: CGFloat = 8

    private var graphed: Bool { editorState.isKeyLaneGraphed(lane.motionID) }
    private var height: CGFloat { graphed ? KeyLanesView.graphHeight : KeyLanesView.laneHeight }

    var body: some View {
        let ruler = editorState.motionStripRuler
        let graph = graphed ? editorState.keyGraph(layerID: layerID, motionID: lane.motionID,
                                                   handle: handleDrag.map { ($0.ref, $0.side, $0.point) })
                            : nil
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(VideoKit.Palette.panel2)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(VideoKit.Palette.line, lineWidth: 1))
            Color.clear
                .contentShape(Rectangle())
                .gesture(bareLane(ruler: ruler))
                .contextMenu {
                    MenuRowsView(rows: editorState.keyLaneMenuRows(layerID: layerID, motionID: lane.motionID))
                }
            if let graph {
                curve(graph, ruler: ruler)
                handles(graph, ruler: ruler)
            } else {
                segments(ruler: ruler)
            }
            keys(graph: graph, ruler: ruler)
        }
        .frame(width: laneWidth, height: height, alignment: .topLeading)
        .clipShape(TimelineEdgeClip())
        .allowsHitTesting(!isLocked)
    }

    // MARK: Where things sit

    private var drag: KeyLaneDrag? {
        guard let drag = editorState.keyLaneDrag, drag.layerID == layerID else { return nil }
        return drag
    }

    private var picked: Set<KeyRef> { editorState.pickedKeys(layerID: layerID) }

    /// Where a key is drawn: carried by the drag in the air when it is picked.
    private func shownMS(_ key: LaneKey) -> Int {
        guard let drag, picked.contains(key.ref) else { return key.documentMS }
        return key.documentMS + drag.byMS
    }

    private func x(_ ms: Int, _ ruler: MotionStripRuler) -> CGFloat {
        laneWidth * ruler.fraction(ofMS: Double(ms))
    }

    private func y(_ value: Double, low: Double, high: Double) -> CGFloat {
        let span = high - low
        let unit = span > 1e-9 ? (value - low) / span : 0.5
        return Self.graphPad + (1 - CGFloat(unit)) * (height - Self.graphPad * 2)
    }

    private func value(atY y: CGFloat, low: Double, high: Double) -> Double {
        let unit = 1 - (y - Self.graphPad) / max(1, height - Self.graphPad * 2)
        return low + Double(unit) * (high - low)
    }

    private func range(_ graph: KeyGraph) -> (Double, Double) {
        if let handleDrag { return (handleDrag.low, handleDrag.high) }
        return (graph.low, graph.high)
    }

    // MARK: The lane closed: diamonds joined by a line

    /// `.kfseg`: the accent line between each pair of keys, faint, so the
    /// stretch where the value is changing reads at a glance.
    private func segments(ruler: MotionStripRuler) -> some View {
        let spots = lane.keys.map { x(shownMS($0), ruler) }.sorted()
        return Canvas { context, size in
            guard spots.count > 1, let first = spots.first, let last = spots.last else { return }
            let rect = CGRect(x: first, y: size.height / 2 - 1, width: last - first, height: 2)
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.accentColor.opacity(0.45)))
        }
        .allowsHitTesting(false)
    }

    // MARK: The lane opened: its curve

    private func curve(_ graph: KeyGraph, ruler: MotionStripRuler) -> some View {
        let (low, high) = range(graph)
        let points = graph.points.map {
            CGPoint(x: x(Int(Double($0.x).rounded()), ruler), y: y(Double($0.y), low: low, high: high))
        }
        let ink = VideoKit.Palette.faint.color(colorScheme)
        return ZStack(alignment: .topLeading) {
            Canvas { context, size in
                // Gridlines at the top, middle and bottom of the range.
                for fraction in [0.0, 0.5, 1.0] {
                    let lineY = Self.graphPad + CGFloat(fraction) * (size.height - Self.graphPad * 2)
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: lineY))
                    line.addLine(to: CGPoint(x: size.width, y: lineY))
                    context.stroke(line, with: .color(ink.opacity(0.18)), lineWidth: 1)
                }
                guard let first = points.first, let last = points.last else { return }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                var fill = path
                fill.addLine(to: CGPoint(x: last.x, y: size.height))
                fill.addLine(to: CGPoint(x: first.x, y: size.height))
                fill.closeSubpath()
                context.fill(fill, with: .color(.accentColor.opacity(0.08)))
                context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
            }
            .allowsHitTesting(false)
            // The range, where the mock's axis puts it (`.kfaxis`).
            VStack(alignment: .leading, spacing: 0) {
                Text(reading(high))
                Spacer(minLength: 0)
                Text(reading(low))
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(VideoKit.Palette.faint)
            .padding(.leading, 4)
            .padding(.vertical, 1)
            .frame(height: height)
            .allowsHitTesting(false)
        }
        .panelReadout("curve \(lane.title): \(reading(low)) to \(reading(high)), "
                      + "\(graph.keys.filter { $0.ease == .bezier }.count) Bezier key(s)")
    }

    private func reading(_ value: Double) -> String {
        switch lane.property {
        case .position: return "\(Int(value.rounded())) pt"
        default: return lane.property.format(.number((value * 10).rounded() / 10))
        }
    }

    /// The handles: on every Bezier key, and on every picked key, since
    /// dragging one is how a key becomes a Bezier key.
    @ViewBuilder
    private func handles(_ graph: KeyGraph, ruler: MotionStripRuler) -> some View {
        let (low, high) = range(graph)
        let shown = graph.keys.filter { $0.ease == .bezier || picked.contains($0.ref) }
        ForEach(shown, id: \.ref) { key in
            let at = CGPoint(x: x(key.documentMS, ruler), y: y(key.value, low: low, high: high))
            ForEach([KeyHandleSide.arriving, .leaving], id: \.self) { side in
                if let point = side == .arriving ? key.arriving : key.leaving {
                    let spot = CGPoint(x: x(Int(Double(point.x).rounded()), ruler),
                                       y: y(Double(point.y), low: low, high: high))
                    Path { path in
                        path.move(to: at)
                        path.addLine(to: spot)
                    }
                    .stroke(VideoKit.Palette.accent.opacity(0.7), lineWidth: 1)
                    .allowsHitTesting(false)
                    Circle()
                        .fill(VideoKit.Palette.panel)
                        .overlay(Circle().strokeBorder(VideoKit.Palette.accent, lineWidth: 1.5))
                        .frame(width: 8, height: 8)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                        .gesture(handleGesture(key.ref, side, graph: graph, ruler: ruler))
                        .offset(x: spot.x - 7, y: spot.y - 7)
                        .help(side == .arriving ? "How it arrives at this key" : "How it leaves this key")
                }
            }
        }
    }

    private func handleGesture(_ ref: KeyRef, _ side: KeyHandleSide, graph: KeyGraph,
                               ruler: MotionStripRuler) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let (low, high) = handleDrag.map { ($0.low, $0.high) } ?? (graph.low, graph.high)
                let ms = ruler.ms(atFraction: Double(value.location.x / laneWidth))
                let point = CGPoint(x: ms, y: self.value(atY: value.location.y, low: low, high: high))
                handleDrag = HandleDrag(ref: ref, side: side, point: point, low: low, high: high)
            }
            .onEnded { _ in
                if let drag = handleDrag {
                    editorState.setKeyHandle(layerID: layerID, drag.ref, drag.side, toGraphPoint: drag.point)
                }
                handleDrag = nil
            }
    }

    // MARK: The keys

    @ViewBuilder
    private func keys(graph: KeyGraph?, ruler: MotionStripRuler) -> some View {
        let (low, high) = graph.map(range) ?? (0, 0)
        let heights = Dictionary(graph?.keys.map { ($0.ref, $0.value) } ?? [], uniquingKeysWith: { a, _ in a })
        // A copy in the air leaves the originals where they are.
        if let drag, drag.copying {
            ForEach(lane.keys.filter { picked.contains($0.ref) }, id: \.ref) { key in
                KeyGlyph(ease: key.ease, isPicked: false)
                    .opacity(0.5)
                    .offset(x: x(key.documentMS, ruler) - KeyGlyph.size / 2,
                            y: keyY(key, heights, low, high) - KeyGlyph.size / 2)
                    .allowsHitTesting(false)
            }
        }
        ForEach(Array(lane.keys.enumerated()), id: \.element.ref) { index, key in
            keyView(key, index: index, ruler: ruler, y: keyY(key, heights, low, high))
        }
    }

    private func keyY(_ key: LaneKey, _ heights: [KeyRef: Double], _ low: Double, _ high: Double) -> CGFloat {
        guard graphed, let value = heights[key.ref] else { return height / 2 }
        return y(value, low: low, high: high)
    }

    private func keyView(_ key: LaneKey, index: Int, ruler: MotionStripRuler, y keyY: CGFloat) -> some View {
        let isPicked = picked.contains(key.ref)
        let at = x(shownMS(key), ruler)
        let grab: CGFloat = 14
        return KeyGlyph(ease: key.ease, isPicked: isPicked)
            .scaleEffect(isPicked && drag != nil ? 1.25 : 1)
            .frame(width: grab, height: grab)
            .contentShape(Rectangle())
            .gesture(keyDrag(key, ruler: ruler))
            .onTapGesture {
                let flags = NSEvent.modifierFlags
                editorState.pickKey(layerID: layerID, key.ref, atMS: key.documentMS,
                                    extending: flags.contains(.shift) || flags.contains(.command))
            }
            .contextMenu {
                MenuRowsView(rows: editorState.keyMenuRows(layerID: layerID, key.ref, atMS: key.documentMS))
            }
            .help("\(lane.title) \(key.reading) at \(MotionStripRuler.timecode(Double(key.documentMS))), "
                  + key.ease.title)
            .playtestControl("Key \(lane.title) \(index + 1)", detail: layerName)
            .panelReadout("key \(lane.title) \(index + 1): \(key.reading) at "
                          + "\(MotionStripRuler.timecode(Double(key.documentMS))), \(key.ease.title)"
                          + (isPicked ? ", picked" : ""))
            // Placed by padding, so the key's frame is where it is drawn and a
            // right click lands on it.
            .padding(.leading, max(0, at - grab / 2))
            .padding(.top, max(0, keyY - grab / 2))
    }

    private func keyDrag(_ key: LaneKey, ruler: MotionStripRuler) -> some Gesture {
        // A key is drawn where the drag has it, so the hand is read in a space
        // that does not move with it (`ClipPiecesBar.handSpace`).
        DragGesture(minimumDistance: 2, coordinateSpace: ClipPiecesBar.handSpace)
            .onChanged { value in
                if editorState.keyLaneDrag == nil { editorState.beginKeyDrag(layerID: layerID, grabbing: key.ref) }
                var moved = Int(ruler.msSpanning(fraction: Double(value.translation.width / laneWidth)).rounded())
                // The key in the hand lands on the playhead as it comes near,
                // the way a clip's edge does.
                let playhead = editorState.documentTimeMS
                let landing = key.documentMS + moved
                if laneWidth * ruler.fraction(spanningMS: Double(abs(landing - playhead))) <= Self.keySnap {
                    moved = playhead - key.documentMS
                }
                editorState.updateKeyDrag(byMS: moved, copying: NSEvent.modifierFlags.contains(.option))
            }
            .onEnded { _ in
                editorState.updateKeyDrag(byMS: editorState.keyLaneDrag?.byMS ?? 0,
                                          copying: NSEvent.modifierFlags.contains(.option))
                editorState.commitKeyDrag()
            }
    }

    // MARK: The bare lane

    /// A press on the lane between keys: a click puts the playhead there and
    /// lets go of the picked keys; a drag draws a box round keys.
    private func bareLane(ruler: MotionStripRuler) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                let travel = hypot(value.translation.width, value.translation.height)
                guard travel >= Self.boxThreshold else { return }
                onBox(rect(value), false)
            }
            .onEnded { value in
                let travel = hypot(value.translation.width, value.translation.height)
                if travel >= Self.boxThreshold {
                    onBox(rect(value), true)
                    return
                }
                onBox(nil, false)
                editorState.clearKeySelection()
                let laneX = value.location.x - TimelineDock.lanesLeading
                let fraction = min(max(0, laneX / laneWidth), 1)
                editorState.scrubDocument(toMS: Int(ruler.ms(atFraction: Double(fraction)).rounded()))
            }
    }

    /// The box, in the lanes' own space, lanes starting at nought across.
    private func rect(_ value: DragGesture.Value) -> CGRect {
        let a = CGPoint(x: value.startLocation.x - TimelineDock.lanesLeading, y: value.startLocation.y)
        let b = CGPoint(x: value.location.x - TimelineDock.lanesLeading, y: value.location.y)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

// MARK: - A key

/// One key, drawn so how the value moves through it shows on the key itself,
/// the way Premiere draws it. Always the mock's diamond (`.kfd`): a corner is
/// sharp on a side that is linear and softened on a side that eases, a Hold
/// leaves square, and a Bezier key is Premiere's hourglass. Left is how it
/// arrives, right how it leaves.
struct KeyGlyph: View {
    let ease: KeyEase
    let isPicked: Bool

    /// `.kfd{width:9px;height:9px}` turned 45°: twelve points corner to
    /// corner.
    static let size: CGFloat = 12

    var body: some View {
        KeyGlyphShape(ease: ease)
            .fill(isPicked ? AnyShapeStyle(Color.white) : AnyShapeStyle(VideoKit.Palette.accent))
            .overlay(KeyGlyphShape(ease: ease)
                .stroke(isPicked ? AnyShapeStyle(VideoKit.Palette.accent) : AnyShapeStyle(VideoKit.Palette.panel),
                        lineWidth: 1))
            .frame(width: Self.size, height: Self.size)
            .shadow(color: isPicked ? VideoKit.Palette.accent.opacity(0.6) : .clear, radius: 2)
    }
}

struct KeyGlyphShape: Shape {
    let ease: KeyEase

    func path(in rect: CGRect) -> Path {
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: rect.midY)
        let right = CGPoint(x: rect.maxX, y: rect.midY)
        let soft = rect.width * 0.28
        var path = Path()
        if ease == .bezier {
            // The hourglass.
            path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - 1, y: rect.maxY), control: mid)
            path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX + 1, y: rect.minY), control: mid)
            path.closeSubpath()
            return path
        }
        path.move(to: top)
        // The right half: how it leaves.
        if ease == .hold {
            path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.maxY))
        } else if ease.easesOut {
            path.addArc(tangent1End: right, tangent2End: bottom, radius: soft)
        } else {
            path.addLine(to: right)
        }
        path.addLine(to: bottom)
        // The left half: how it arrives.
        if ease.easesIn {
            path.addArc(tangent1End: left, tangent2End: top, radius: soft)
        } else {
            path.addLine(to: left)
        }
        path.closeSubpath()
        return path
    }
}
