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
    /// The copy drawn lifted while its track is carried, which must not say
    /// where the lanes are.
    var isLifted = false

    /// A box being drawn round keys, in the lanes' own space (the first
    /// lane's top left is nought).
    @State private var box: CGRect?

    /// `.kfl{height:18px}`.
    static let laneHeight: CGFloat = 18
    /// A lane opened into its curve.
    static let graphHeight: CGFloat = 88
    /// Room above and below the range on an open graph.
    static let graphPad: CGFloat = 8
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
                                isLocked: isLocked, isLifted: isLifted) { rect, done in
                        drawBox(rect, done: done, lanes: lanes)
                    }
                }
                .playtestField("Key lane \(layerName) \(lane.title)")
                // Where the lane is down the tracks, for a box drawn over
                // them (`EditorState+TrackRange`).
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(TimelineDock.tracksSpace))
                } action: { frame in
                    guard !isLifted else { return }
                    editorState.keyLaneRows[KeyLaneRowID(layerID: layerID, motionID: lane.motionID)] =
                        frame.minY...frame.maxY
                }
                .onDisappear {
                    guard !isLifted else { return }
                    editorState.keyLaneRows[KeyLaneRowID(layerID: layerID, motionID: lane.motionID)] = nil
                }
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
        let picked = editorState.isKeyRowPicked(layerID: layerID, motionID: lane.motionID)
        HStack(spacing: 2) {
            Text(lane.title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(picked || isHovered ? VideoKit.Palette.ink : VideoKit.Palette.dim)
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
        // Picked by a click on its name, the mock's `.va-pr.pick .tl`.
        .background(alignment: .leading) {
            if picked {
                RoundedRectangle(cornerRadius: 5)
                    .fill(VideoKit.Palette.accent.opacity(0.18))
                    .padding(.leading, 8 + indent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editorState.pickKeyRow(layerID: layerID, motionID: lane.motionID) }
        .playtestHover("Key lane \(lane.title)") { isHovered = $0 }
        .contextMenu { MenuRowsView(rows: editorState.keyLaneMenuRows(layerID: layerID, motionID: lane.motionID)) }
        .playtestControl("Row \(lane.title)", detail: "Timeline")
        .panelReadout("lane \(lane.title): \(lane.keys.count) key\(lane.keys.count == 1 ? "" : "s")"
                      + (graphed ? ", curve open" : "") + (picked ? ", picked" : ""))
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
    let isLifted: Bool
    /// A box being drawn from this lane, in the lanes' own space; nil when
    /// it is called off, and `done` when the hand lets go.
    let onBox: (CGRect?, _ done: Bool) -> Void

    /// A handle in the hand: which, and where on the curve it is, with the
    /// range the curve was drawn in when it was taken hold of, so the curve
    /// does not rescale under the hand as it overshoots.
    @State private var handleDrag: HandleDrag?
    /// A point in the hand on the graph: how far in time and to what value,
    /// with the range the curve was drawn in when it was taken hold of.
    @State private var pointDrag: PointDrag?
    /// What the pointer rests on along the line, brightened a little so the
    /// hand sees what a click will take.
    @State private var hovered: AnimatedLineHit?

    struct HandleDrag {
        var ref: KeyRef
        var side: KeyHandleSide
        var point: CGPoint
        var low: Double
        var high: Double
    }

    struct PointDrag {
        var ref: KeyRef
        var startValue: Double
        var byMS: Int
        var value: Double?
        var low: Double
        var high: Double
    }

    /// Past this a press on the bare lane is a box rather than a click.
    private static let boxThreshold: CGFloat = 3
    /// How near the playhead a dragged key lands on it.
    private static let keySnap: CGFloat = 6
    private static var graphPad: CGFloat { KeyLanesView.graphPad }

    private var graphed: Bool { editorState.isKeyLaneGraphed(lane.motionID) }
    private var rowID: KeyLaneRowID { KeyLaneRowID(layerID: layerID, motionID: lane.motionID) }
    private var height: CGFloat { graphed ? KeyLanesView.graphHeight : KeyLanesView.laneHeight }

    var body: some View {
        let ruler = editorState.motionStripRuler
        let graph = graphed ? editorState.keyGraph(layerID: layerID, motionID: lane.motionID,
                                                   handle: handleDrag.map { ($0.ref, $0.side, $0.point) },
                                                   point: pointDrag.map { ($0.ref, $0.byMS, $0.value) })
                            : nil
        // Open or shut, the lane is one animated line (`AnimatedLine`): a
        // click picks a dot or the segment between two, ⌘-click adds.
        let line = graph.map { animatedLine($0, ruler: ruler) } ?? closedLine(ruler)
        let keys = lineKeys(graph)
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
                curve(graph, line: line, ruler: ruler)
                    .frame(width: laneWidth, height: height)
                    // The whole graph, for a walk to turn the wheel over.
                    .playtestControl("Value graph \(lane.title)", detail: layerName)
                lineSurface(keys, line: line, ruler: ruler)
                handles(graph, ruler: ruler)
            } else {
                segments(line, keys: keys)
                lineSurface(keys, line: line, ruler: ruler)
            }
            self.keys(graph: graph, ruler: ruler)
        }
        .frame(width: laneWidth, height: height, alignment: .topLeading)
        // Zoomed, the curve runs past the graph's top and bottom: it stops
        // at them rather than over the rows either side.
        .clipShape(TimelineEdgeClip(slack: graphed ? 0 : 400))
        // Where it is, for ⌥ and the wheel over it.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(TimelineDock.wheelSpace))
        } action: { frame in
            guard !isLifted else { return }
            editorState.keyGraphFrames[rowID] = graphed ? frame : nil
        }
        .onChange(of: graphed) { _, open in
            if !open, !isLifted { editorState.keyGraphFrames[rowID] = nil }
        }
        .onDisappear {
            if !isLifted { editorState.keyGraphFrames[rowID] = nil }
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let at): hovered = line.hit(at)
            case .ended: hovered = nil
            }
        }
        .popover(isPresented: drawingHere, attachmentAnchor: .rect(.rect(drawingAnchor(line))),
                 arrowEdge: .top) {
            CurveEditor(curve: editorState.pickedSegmentsCurve(layerID: layerID) ?? .easeInOut, saves: true) {
                editorState.finishDrawingStretchCurve($0)
            }
        }
        .allowsHitTesting(!isLocked)
    }

    // MARK: Draw a Curve, from a segment's right click

    /// Whether this lane holds the segments a Draw a Curve is drawing for.
    private var drawingHere: Binding<Bool> {
        Binding(get: {
            guard let drawing = editorState.drawingStretchCurve, drawing.layerID == layerID else { return false }
            return drawing.segments.contains { $0.motionID == lane.motionID }
        }, set: { open in
            if !open { editorState.finishDrawingStretchCurve(nil) }
        })
    }

    /// Where the editor points: the first segment it is drawing for.
    private func drawingAnchor(_ line: AnimatedLine) -> CGRect {
        guard let graph = editorState.keyGraph(layerID: layerID, motionID: lane.motionID),
              let drawing = editorState.drawingStretchCurve,
              let index = graph.keys.dropLast().firstIndex(where: { drawing.segments.contains($0.ref) }),
              line.segments.indices.contains(index) else {
            return CGRect(x: laneWidth / 2, y: height / 2, width: 1, height: 1)
        }
        let middle = Self.middle(of: line.segments[index])
        return CGRect(x: middle.x - 4, y: middle.y - 4, width: 8, height: 8)
    }

    // MARK: Where things sit

    private var drag: KeyLaneDrag? {
        guard let drag = editorState.keyLaneDrag, drag.layerID == layerID else { return nil }
        return drag
    }

    private var picked: Set<KeyRef> {
        editorState.pickedKeys(layerID: layerID).union(editorState.keysLitByBox(layerID: layerID))
    }

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

    /// The values drawn top to bottom: held still while a handle is in the
    /// hand, else the graph's zoom or its fit
    /// (`EditorState+KeyGraphZoom`).
    private func range(_ graph: KeyGraph) -> (Double, Double) {
        if let handleDrag { return (handleDrag.low, handleDrag.high) }
        let shown = editorState.keyGraphRange(motionID: lane.motionID, fit: graph)
        return (shown.low, shown.high)
    }

    // MARK: The lane closed: diamonds joined by a line

    /// The lane shut, as the line rule sees it: its keys along the middle.
    private func closedLine(_ ruler: MotionStripRuler) -> AnimatedLine {
        AnimatedLine(flatThrough: lane.keys.map { x(shownMS($0), ruler) }, atY: height / 2)
    }

    /// The keys the line's dots stand for, first to last.
    private func lineKeys(_ graph: KeyGraph?) -> [LineKey] {
        if let graph { return graph.keys.map { LineKey(ref: $0.ref, ms: $0.documentMS) } }
        return lane.keys.sorted { $0.documentMS < $1.documentMS }.map { LineKey(ref: $0.ref, ms: $0.documentMS) }
    }

    /// `.kfseg`: the accent line between each pair of keys, faint, so the
    /// stretch where the value is changing reads at a glance. A picked segment
    /// is white on an accent edge, as on the graph; the one under the pointer
    /// brightens.
    private func segments(_ line: AnimatedLine, keys: [LineKey]) -> some View {
        let pickedSegments = editorState.pickedSegments(layerID: layerID)
        let picked = keys.indices.filter { pickedSegments.contains(keys[$0].ref) }
        let hoveredSegment: Int? = if case let .segment(index) = hovered { index } else { nil }
        let accent = Color.accentColor
        return Canvas { context, _ in
            for (index, segment) in line.segments.enumerated() {
                guard let a = segment.first, let b = segment.last else { continue }
                var stretch = Path()
                stretch.move(to: a)
                stretch.addLine(to: b)
                if picked.contains(index) {
                    context.stroke(stretch, with: .color(accent), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    context.stroke(stretch, with: .color(.white), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                } else if index == hoveredSegment {
                    context.stroke(stretch, with: .color(accent.mix(with: .white, by: 0.3)),
                                   style: StrokeStyle(lineWidth: 3, lineCap: .round))
                } else {
                    context.stroke(stretch, with: .color(accent.opacity(0.45)), lineWidth: 2)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: The lane opened: its curve

    private func curve(_ graph: KeyGraph, line: AnimatedLine, ruler: MotionStripRuler) -> some View {
        let (low, high) = range(graph)
        let points = graph.points.map {
            CGPoint(x: x(Int(Double($0.x).rounded()), ruler), y: y(Double($0.y), low: low, high: high))
        }
        let ink = VideoKit.Palette.faint.color(colorScheme)
        let accent = Color.accentColor
        let pickedSegments = editorState.pickedSegments(layerID: layerID)
        let picked = graph.keys.dropLast().indices.filter { pickedSegments.contains(graph.keys[$0].ref) }
        let hoveredSegment: Int? = if case let .segment(index) = hovered { index } else { nil }
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
                context.fill(fill, with: .color(accent.opacity(0.08)))
                // The line held either side of the keys is no segment: dashed.
                for held in [line.before, line.after] where held.count > 1 {
                    context.stroke(Self.path(held), with: .color(accent.opacity(0.55)),
                                   style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                }
                for (index, segment) in line.segments.enumerated() {
                    let stretch = Self.path(segment)
                    if picked.contains(index) {
                        // Picked: white, on an accent edge so it reads on a
                        // light lane as well as a dark one.
                        context.stroke(stretch, with: .color(accent), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        context.stroke(stretch, with: .color(.white), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    } else if index == hoveredSegment {
                        context.stroke(stretch, with: .color(accent.mix(with: .white, by: 0.3)),
                                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    } else {
                        context.stroke(stretch, with: .color(accent), lineWidth: 1.5)
                    }
                }
            }
            .allowsHitTesting(false)
            // The range, where the mock's axis puts it (`.kfaxis`). ⌥ and the
            // wheel over the graph zoom it; a double click on a reading goes
            // back to the fit (`EditorState+KeyGraphZoom`).
            VStack(alignment: .leading, spacing: 0) {
                rangeReading(high, edge: "top")
                Spacer(minLength: 0)
                rangeReading(low, edge: "bottom")
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(zoomed ? VideoKit.Palette.dim : VideoKit.Palette.faint)
            .padding(.leading, 4)
            .padding(.vertical, 1)
            .frame(height: height)
        }
        .panelReadout("curve \(lane.title): \(reading(low)) to \(reading(high)), "
                      + "\(graph.keys.filter { $0.ease == .bezier }.count) Bezier key(s)"
                      + (zoomed ? ", zoomed" : ", fitted"))
    }

    private var zoomed: Bool { editorState.isKeyGraphZoomed(lane.motionID) }

    /// One end of the range: only the words take a press, so the line beside
    /// them still picks and scrubs.
    private func rangeReading(_ value: Double, edge: String) -> some View {
        Text(reading(value))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { editorState.fitKeyGraph(lane.motionID) }
            .help("Double-click to fit")
            .panelReadout(reading(value))
            .playtestField("Graph \(edge) \(lane.title)")
            .playtestControl("Graph \(edge) \(lane.title)", detail: layerName)
    }

    private func reading(_ value: Double) -> String {
        switch lane.property {
        case .position: return "\(Int(value.rounded())) pt"
        default: return lane.property.format(.number((value * 10).rounded() / 10))
        }
    }

    /// The handles: both of a picked key's, and the two that shape a picked
    /// segment (the mock: "a picked segment turns blue and shows its
    /// handles"), since dragging one is how a stretch takes a drawn curve.
    @ViewBuilder
    private func handles(_ graph: KeyGraph, ruler: MotionStripRuler) -> some View {
        let (low, high) = range(graph)
        let segments = editorState.pickedSegments(layerID: layerID)
        let sides: [KeyRef: Set<KeyHandleSide>] = graph.keys.indices.reduce(into: [:]) { sides, index in
            let key = graph.keys[index]
            if picked.contains(key.ref) { sides[key.ref, default: []].formUnion([.arriving, .leaving]) }
            if segments.contains(key.ref) { sides[key.ref, default: []].insert(.leaving) }
            if index > 0, segments.contains(graph.keys[index - 1].ref) { sides[key.ref, default: []].insert(.arriving) }
        }
        let shown = graph.keys.filter { sides[$0.ref] != nil }
        ForEach(shown, id: \.ref) { key in
            let at = CGPoint(x: x(key.documentMS, ruler), y: y(key.value, low: low, high: high))
            ForEach([KeyHandleSide.arriving, .leaving], id: \.self) { side in
                if sides[key.ref]?.contains(side) == true, let point = side == .arriving ? key.arriving : key.leaving {
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
                let (low, high) = handleDrag.map { ($0.low, $0.high) } ?? range(graph)
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
            if let graph {
                graphKeyView(key, index: index, graph: graph, ruler: ruler,
                             y: keyY(key, heights, low, high), low: low, high: high)
            } else {
                keyView(key, index: index, ruler: ruler, y: keyY(key, heights, low, high))
            }
        }
    }

    private func keyY(_ key: LaneKey, _ heights: [KeyRef: Double], _ low: Double, _ high: Double) -> CGFloat {
        if let pointDrag, pointDrag.ref == key.ref, let value = pointDrag.value {
            return y(value, low: low, high: high)
        }
        guard graphed, let value = heights[key.ref] else { return height / 2 }
        return y(value, low: low, high: high)
    }

    private func keyView(_ key: LaneKey, index: Int, ruler: MotionStripRuler, y keyY: CGFloat) -> some View {
        let isPicked = picked.contains(key.ref)
        let at = x(shownMS(key), ruler)
        return placed(KeyGlyph(ease: key.ease, isPicked: isPicked, isHovered: hovered == .dot(index))
            .scaleEffect(isPicked && drag != nil ? 1.25 : 1)
            .frame(width: Self.grab, height: Self.grab)
            .contentShape(Rectangle())
            .gesture(keyDrag(key, ruler: ruler))
            .onTapGesture { dotClick(key, index: index) },
            key, index: index, isPicked: isPicked, x: at, y: keyY)
    }

    /// A click on a dot, open lane or shut: the line rule picks it, Shift or
    /// Command adding it to the pick or taking it out.
    private func dotClick(_ key: LaneKey, index: Int) {
        let flags = Self.clickFlags
        guard !flags.contains(.control),
              case let .pickDot(_, extending) = AnimatedLine.action(for: .dot(index),
                                                                    command: flags.contains(.command),
                                                                    shift: flags.contains(.shift))
        else { return }
        editorState.pickKey(layerID: layerID, key.ref, atMS: key.documentMS, extending: extending)
        // The popover to type its value opens above it (`KeyValuesPopover`).
        editorState.openKeyValues(layerID: layerID, at: key.ref)
    }

    /// A point on the open graph: a click picks it (the line rule,
    /// `AnimatedLine`), a drag carries it in time and value.
    private func graphKeyView(_ key: LaneKey, index: Int, graph: KeyGraph, ruler: MotionStripRuler,
                              y keyY: CGFloat, low: Double, high: Double) -> some View {
        let isPicked = picked.contains(key.ref)
        var at = x(shownMS(key), ruler)
        if let pointDrag, pointDrag.ref == key.ref { at = x(key.documentMS + pointDrag.byMS, ruler) }
        let start = graph.keys.first { $0.ref == key.ref }?.value ?? 0
        // Zoomed past it, a point is off the graph: not pinned to its edge.
        let onGraph = keyY >= 0 && keyY <= height
        return placed(KeyGlyph(ease: key.ease, isPicked: isPicked, isHovered: hovered == .dot(index))
            .scaleEffect(isPicked && (drag != nil || pointDrag != nil) ? 1.25 : 1)
            .frame(width: Self.grab, height: Self.grab)
            .contentShape(Rectangle())
            .gesture(graphKeyDrag(key, index: index, startValue: start, ruler: ruler, low: low, high: high))
            .onTapGesture { dotClick(key, index: index) }
            .opacity(onGraph ? 1 : 0)
            .allowsHitTesting(onGraph),
            // Held at the edge it went past, so it never stretches the lane.
            key, index: index, isPicked: isPicked, x: at,
            y: onGraph ? keyY : min(max(keyY, Self.grab / 2), height - Self.grab / 2))
    }

    private static let grab: CGFloat = 14

    /// What every key carries, wherever it is drawn: its menu, its name for a
    /// walk, and its place on the lane.
    private func placed(_ glyph: some View, _ key: LaneKey, index: Int, isPicked: Bool,
                        x at: CGFloat, y keyY: CGFloat) -> some View {
        glyph
            // The key the value popover hangs from says where it is drawn,
            // so the popover follows it (`KeyValuesPopover`).
            .modifier(KeyValuesAnchorReport(isAnchor: editorState.keyValuesAnchor
                                                == KeyValuesAnchor(layerID: layerID, ref: key.ref)))
            .contextMenu {
                TimelineKeyMenu(layerID: layerID, refs: [key.ref], atMS: key.documentMS, lane: lane.motionID) {
                    editorState.keyMenuRows(layerID: layerID, key.ref, atMS: key.documentMS)
                }
            }
            .help("\(lane.title) \(key.reading) at \(MotionStripRuler.timecode(Double(key.documentMS))), "
                  + key.ease.title)
            .playtestControl("Key \(lane.title) \(index + 1)", detail: layerName)
            .panelReadout("key \(lane.title) \(index + 1): \(key.reading) at "
                          + "\(MotionStripRuler.timecode(Double(key.documentMS))), \(key.ease.title)"
                          + (isPicked ? ", picked" : ""))
            // Placed by padding, so the key's frame is where it is drawn and a
            // right click lands on it.
            .padding(.leading, max(0, at - Self.grab / 2))
            .padding(.top, max(0, keyY - Self.grab / 2))
    }

    /// A point of the graph carried by the hand (a click on it is its tap,
    /// which picks it). One point in
    /// the hand moves in time and value, snapping to frames, the playhead and
    /// the layer's other keys, Shift keeping it to one direction; a point that
    /// is one of several picked carries them all along in time, as on a lane.
    private func graphKeyDrag(_ key: LaneKey, index: Int, startValue: Double, ruler: MotionStripRuler,
                              low: Double, high: Double) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: ClipPiecesBar.handSpace)
            .onChanged { value in
                let flags = Self.clickFlags
                let carriesSeveral = picked.count > 1 && picked.contains(key.ref)
                if carriesSeveral || editorState.keyLaneDrag != nil {
                    if editorState.keyLaneDrag == nil { editorState.beginKeyDrag(layerID: layerID, grabbing: key.ref) }
                    let moved = snappedMove(key, by: value.translation.width, ruler: ruler)
                    editorState.updateKeyDrag(byMS: moved, copying: flags.contains(.option))
                    return
                }
                if pointDrag == nil {
                    editorState.keySelection = KeySelection(layerID: layerID, refs: [key.ref])
                }
                var across = value.translation.width
                var down = value.translation.height
                if flags.contains(.shift) {
                    if abs(across) >= abs(down) { down = 0 } else { across = 0 }
                }
                let fixed = pointDrag.map { ($0.low, $0.high) } ?? (low, high)
                let span = fixed.1 - fixed.0
                let perPoint = (span > 1e-9 ? span : 1) / Double(max(1, height - Self.graphPad * 2))
                let number = lane.property == .position ? nil : startValue - Double(down) * perPoint
                pointDrag = PointDrag(ref: key.ref, startValue: startValue,
                                      byMS: across == 0 ? 0 : snappedMove(key, by: across, ruler: ruler),
                                      value: number, low: fixed.0, high: fixed.1)
            }
            .onEnded { _ in
                if editorState.keyLaneDrag != nil {
                    editorState.commitKeyDrag()
                    return
                }
                if let drag = pointDrag {
                    pointDrag = nil
                    editorState.moveGraphKey(layerID: layerID, drag.ref, byMS: drag.byMS, toValue: drag.value)
                }
            }
    }

    /// How far a key moves for a hand `across` points along the lane: onto
    /// the playhead or another key as it comes near, else onto a frame.
    private func snappedMove(_ key: LaneKey, by across: CGFloat, ruler: MotionStripRuler) -> Int {
        let landing = key.documentMS + Int(ruler.msSpanning(fraction: Double(across / laneWidth)).rounded())
        let reach = editorState.keySnapReachMS(laneWidth: laneWidth)
        let caught = KeySnap.snapped(landing, to: editorState.graphKeySnapMoments(layerID: layerID, leaving: key.ref),
                                     withinMS: reach)
        if caught != landing { return caught - key.documentMS }
        let frame = MovieRef.frameStepMS
        return Int((Double(landing) / Double(frame)).rounded()) * frame - key.documentMS
    }

    // MARK: The line on the open graph

    /// The graph as the line rule sees it, in the lane's own points.
    private func animatedLine(_ graph: KeyGraph, ruler: MotionStripRuler) -> AnimatedLine {
        let (low, high) = range(graph)
        func drawn(_ points: [CGPoint]) -> [CGPoint] {
            points.map { CGPoint(x: x(Int(Double($0.x).rounded()), ruler), y: y(Double($0.y), low: low, high: high)) }
        }
        return AnimatedLine(dots: graph.keys.map { CGPoint(x: x($0.documentMS, ruler), y: y($0.value, low: low, high: high)) },
                            segments: graph.stretches.map(drawn), before: drawn(graph.before), after: drawn(graph.after))
    }

    static func path(_ points: [CGPoint]) -> Path { KeyLaneViewPath.path(points) }

    /// Half way along a drawn stretch, by its samples.
    static func middle(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        if points.count % 2 == 1 { return points[points.count / 2] }
        let a = points[points.count / 2 - 1], b = points[points.count / 2]
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// The line itself, as something to click: only the strip along it takes
    /// a press, so the lane around it still scrubs and draws boxes. A click
    /// picks a segment, ⌘-click adds a point there, and a right click opens
    /// the segment's own menu.
    private func lineSurface(_ keys: [LineKey], line: AnimatedLine, ruler: MotionStripRuler) -> some View {
        let strokes = line.segments + [line.before, line.after]
        let pickedSegments = editorState.pickedSegments(layerID: layerID)
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: laneWidth, height: height)
                .contentShape(LineStrip(lines: strokes, width: AnimatedLine.lineReach * 2))
                .onTapGesture(coordinateSpace: .local) { at in lineClick(at, keys, line: line, ruler: ruler) }
                // A press that travels draws a box round keys, as it does
                // from the bare lane either side.
                .gesture(DragGesture(minimumDistance: Self.boxThreshold, coordinateSpace: .named(space))
                    .onChanged { onBox(rect($0), false) }
                    .onEnded { onBox(rect($0), true) })
                .contextMenu {
                    // Read so every right click builds the menu afresh, from
                    // where it landed (`EditorState+TimelinePointing`).
                    let _ = editorState.timelineRightPresses
                    BuiltAsItOpens { lineMenuRows(keys, line: line, ruler: ruler) }
                }
            // A name for each segment, at its middle, for a walk to aim at.
            ForEach(Array(line.segments.enumerated()), id: \.offset) { index, segment in
                let middle = Self.middle(of: segment)
                let ref = keys[index].ref
                let curve = editorState.document?.stretchesCurve(layerID: layerID, [ref])
                Color.clear
                    .frame(width: 6, height: 6)
                    .playtestControl("Segment \(lane.title) \(index + 1)", detail: layerName)
                    .panelReadout("segment \(lane.title) \(index + 1): "
                                  + (curve.map { StretchCurve.title($0) } ?? "Mixed")
                                  + (pickedSegments.contains(ref) ? ", picked" : ""))
                    .offset(x: middle.x - 3, y: middle.y - 3)
                    .allowsHitTesting(false)
            }
        }
    }

    private func lineClick(_ at: CGPoint, _ keys: [LineKey], line: AnimatedLine, ruler: MotionStripRuler) {
                let flags = Self.clickFlags
                guard !flags.contains(.control) else { return }
                let ms = msAt(at.x, ruler)
                switch AnimatedLine.action(for: line.hit(at), command: flags.contains(.command),
                                           shift: flags.contains(.shift)) {
                case let .pickDot(index, extending):
                    let key = keys[index]
                    editorState.pickKey(layerID: layerID, key.ref, atMS: key.ms, extending: extending)
                    editorState.openKeyValues(layerID: layerID, at: key.ref)
                case let .pickSegment(index, extending):
                    editorState.pickSegment(layerID: layerID, keys[index].ref, atMS: ms, extending: extending)
                case .addDot:
                    editorState.addKeyOnGraph(layerID: layerID, motionID: lane.motionID,
                                              atMS: msAt(line.nearestPoint(to: at).x, ruler))
                case .clear:
                    editorState.clearKeySelection()
                    editorState.scrubDocument(toMS: ms)
                }
    }

    /// The keys held with the click being handled: the click's own, which is
    /// what a person held as they clicked, and what a walk's posted click says.
    static var clickFlags: NSEvent.ModifierFlags { KeyClick.flags }

    private func msAt(_ laneX: CGFloat, _ ruler: MotionStripRuler) -> Int {
        Int(ruler.ms(atFraction: Double(min(max(0, laneX / laneWidth), 1))).rounded())
    }

    /// The right click on the line: built as the menu opens, from where the
    /// press landed (`TimelineRightPress`), so it is the menu of the segment
    /// or the point under the pointer.
    private func lineMenuRows(_ keys: [LineKey], line: AnimatedLine, ruler: MotionStripRuler) -> [MenuRow] {
        guard let ms = editorState.timelineLastRightPressMS,
              let row = editorState.keyLaneRows[KeyLaneRowID(layerID: layerID, motionID: lane.motionID)] else {
            return editorState.keyLaneMenuRows(layerID: layerID, motionID: lane.motionID)
        }
        let at = CGPoint(x: x(ms, ruler), y: editorState.timelineRightPressY - row.lowerBound)
        switch line.hit(at) {
        case let .segment(index):
            return editorState.segmentMenuRows(layerID: layerID, motionID: lane.motionID,
                                               keys[index].ref, atMS: ms)
        case let .dot(index):
            let key = keys[index]
            editorState.keyMenuOpened(layerID: layerID, [key.ref], atMS: key.ms, lane: lane.motionID)
            return editorState.keyMenuRows(layerID: layerID, key.ref, atMS: key.ms)
        case .beyond, nil:
            return editorState.keyLaneMenuRows(layerID: layerID, motionID: lane.motionID)
        }
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

/// Reports where the key the value popover hangs from is drawn, in window
/// points; nothing at all on every other key.
private struct KeyValuesAnchorReport: ViewModifier {
    @Environment(EditorState.self) private var editorState
    let isAnchor: Bool

    func body(content: Content) -> some View {
        if isAnchor {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                editorState.keyValuesAnchorFrame = $0
            }
        } else {
            content
        }
    }
}

/// One key, drawn so how the value moves through it shows on the key itself,
/// the way Premiere draws it. Always the mock's diamond (`.kfd`): a corner is
/// sharp on a side that is linear and softened on a side that eases, a Hold
/// leaves square, and a Bezier key is Premiere's hourglass. Left is how it
/// arrives, right how it leaves.
struct KeyGlyph: View {
    let ease: KeyEase
    let isPicked: Bool
    /// The pointer resting on it: a little brighter, so the hand sees what a
    /// click will take.
    var isHovered = false

    /// `.kfd{width:9px;height:9px}` turned 45°: twelve points corner to
    /// corner.
    static let size: CGFloat = 12

    var body: some View {
        KeyGlyphShape(ease: ease)
            .fill(isPicked ? AnyShapeStyle(Color.white)
                  : isHovered ? AnyShapeStyle(Color.accentColor.mix(with: .white, by: 0.3))
                  : AnyShapeStyle(VideoKit.Palette.accent))
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

/// A key on an animated line, as the line rule names it.
private struct LineKey {
    let ref: KeyRef
    let ms: Int
}

/// The keys held with a click being handled: the click's own, which is what
/// a person held as they clicked, and what a walk's posted click says.
enum KeyClick {
    static var flags: NSEvent.ModifierFlags {
        NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
    }
}

/// A key's right click menu, on a lane or on its clip: built as it opens,
/// and picking the keys it is about unless they already are, the playhead
/// staying where it was parked (`EditorState+TimelinePointing`).
struct TimelineKeyMenu: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let refs: Set<KeyRef>
    let atMS: Int
    /// The lane it is on, or nil on the clip's own bar.
    let lane: UUID?
    let rows: @MainActor () -> [MenuRow]

    var body: some View {
        let _ = editorState.timelineRightPresses
        let _ = editorState.keyMenuOpened(layerID: layerID, refs, atMS: atMS, lane: lane)
        MenuRowsView(rows: rows())
    }
}

/// A menu whose rows are worked out as it opens, not when the view around it
/// is drawn: SwiftUI runs a menu's own body inside `menu(for:)`, so the rows
/// read the right click that opened it (`EditorState+TimelinePointing`).
private struct BuiltAsItOpens: View {
    let rows: @MainActor () -> [MenuRow]

    var body: some View { MenuRowsView(rows: rows()) }
}

/// A strip of the given width along some lines: what takes a press on a
/// graph's line, and nothing either side of it.
private struct LineStrip: Shape {
    let lines: [[CGPoint]]
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for line in lines where line.count > 1 { path.addPath(KeyLaneViewPath.path(line)) }
        return path.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

private enum KeyLaneViewPath {
    static func path(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
}

