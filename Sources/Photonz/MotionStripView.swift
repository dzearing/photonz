import PhotonzCore
import SwiftUI

/// **The timing strip** across the bottom of the window (`next-motion-strip`,
/// `MotionStrip.swift`).
///
/// One lap of the animation, measured in milliseconds, with a bar for every
/// moving property grouped under the layer it belongs to.
///
/// It is across the BOTTOM and not in the side column, and that is the whole
/// design rather than a placement. The Motion list in the column can say what
/// changes and by how much, and it can print a start and a duration as two
/// numbers. What it cannot say is how two parts of one drawing sit against each
/// other in time, because that is a comparison and a comparison needs width:
/// the bell swings, the knob hanging off it swings a tenth of a second later,
/// and the only way to see that is both bars on one ruler at once.
///
/// Three things here are deliberately not what the mock drew, each argued in
/// the task log:
///
///  - **No Fit button.** The ruler is always the lap plus a third, so it always
///    fits the width and Fit would be a button that does nothing.
///  - **The gap is measured from the NEAREST OTHER BAR and named.** The mock
///    drew one bracket from the left edge of the strip, which only reads as a
///    lag because in its example the bell happens to start at nought.
///  - **The lap's length is a number you can see and set.** A lap that always
///    grew to fit its longest motion could never have a bar running past the
///    point it starts over, which is exactly what the dashed line is for.
struct MotionStripView: View {
    @Environment(EditorState.self) private var editorState

    /// The column down the left holding the lane names.
    static let labelWidth: CGFloat = 92
    /// One lane, and the bar in it.
    static let laneHeight: CGFloat = 22
    static let barHeight: CGFloat = 18
    /// The labelled hairline over each layer's lanes.
    static let layerRowHeight: CGFloat = 16
    /// Air round the whole strip.
    private static let inset: CGFloat = 12
    /// Past which the strip scrolls instead of growing. Six or seven lanes fit
    /// before it does, which is more than any icon has.
    private static let bodyCeiling: CGFloat = 188

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            header
            GeometryReader { geo in
                // The reader sits INSIDE the strip's own horizontal inset, so
                // its width is already the content width: taking the inset off
                // again here would make every bar two dozen points short of the
                // ruler drawn above it.
                let laneWidth = max(1, geo.size.width - Self.labelWidth)
                VStack(spacing: 0) {
                    MotionStripRulerView(ruler: editorState.motionStripRuler)
                        .padding(.leading, Self.labelWidth)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(editorState.motionStripGroups) { group in
                                MotionStripGroupView(group: group, laneWidth: laneWidth)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Room over the top lane for the bracket a drag draws,
                        // which otherwise sits under the ruler and is clipped
                        // away by the scrolling area.
                        .padding(.top, 11)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                // The dashed repeats line and the playhead sit OVER the lanes
                // in the lanes' own coordinates, so they land on the same pixel
                // a time on the ruler above them does.
                .overlay(alignment: .topLeading) {
                    MotionStripMarksView(laneWidth: laneWidth)
                        .padding(.leading, Self.labelWidth)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: bodyHeight)
            .padding(.horizontal, Self.inset)
            .padding(.bottom, Self.inset)
        }
        .background(.regularMaterial)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// As tall as it has to be for the lanes it holds, and no taller.
    private var bodyHeight: CGFloat {
        let groups = editorState.motionStripGroups
        let lanes = groups.reduce(0) { $0 + $1.lanes.count }
        let content = MotionStripRulerView.height
            + CGFloat(groups.count) * Self.layerRowHeight
            + CGFloat(lanes) * Self.laneHeight
            // Room over the top lane for the bracket a drag draws.
            + 10
        return min(Self.bodyCeiling, content)
    }

    // MARK: The bar along the top

    private var header: some View {
        HStack(spacing: 8) {
            Text(MotionStripCopy.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.7)
                .foregroundStyle(.tertiary)
            cycleField
            Spacer(minLength: 0)
            Button { editorState.toggleMotionStrip() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Hide the timing strip")
            .panelHelp("Hide the timing strip (⌥⌘T)")
            .playtestControl("Hide Timing", detail: "Timing strip")
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// How long one lap is. Typed, or left alone to follow the longest motion,
    /// which is what it does until somebody says otherwise.
    private var cycleField: some View {
        HStack(spacing: 6) {
            MotionNumberField(text: String(editorState.motionStripCycleMS),
                              label: "Cycle Length", suffix: "ms") { typed in
                editorState.setMotionCycleMS(Int(typed.rounded()))
            }
            if editorState.motionCycleIsAutomatic {
                Text("follows the longest")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Button { editorState.clearMotionCycle() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Follow the longest motion")
                .panelHelp("Go back to a lap as long as the longest motion")
                .playtestControl("Cycle Auto", detail: "Timing strip")
            }
        }
        .panelReadout("cycle \(editorState.motionStripCycleMS) ms"
                      + (editorState.motionCycleIsAutomatic ? " (automatic)" : " (set)"))
    }
}

// MARK: - The numbers along the top

/// The ruler: one lap and a third, so a bar that overruns the restart has
/// somewhere to be drawn.
private struct MotionStripRulerView: View {
    let ruler: MotionStripRuler

    static let height: CGFloat = 15

    var body: some View {
        GeometryReader { geo in
            ForEach(ruler.ticks, id: \.ms) { tick in
                Text(tick.label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .padding(.leading, 3)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(.separator)
                            .frame(width: 1)
                    }
                    .offset(x: geo.size.width * ruler.fraction(ofMS: tick.ms))
            }
        }
        .frame(height: Self.height)
        .clipped()
    }
}

// MARK: - One layer and its lanes

/// A layer is a labelled HAIRLINE, never a bar. The layer itself does not
/// occupy time; the properties on it do, so drawing it as a bar would be a bar
/// with no start and no duration.
private struct MotionStripGroupView: View {
    @Environment(EditorState.self) private var editorState
    let group: MotionStripGroup
    let laneWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(group.layerName)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isPicked ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(width: MotionStripView.labelWidth - 6, alignment: .leading)
                Rectangle().fill(.separator).frame(height: 1)
            }
            .frame(height: MotionStripView.layerRowHeight)
            .playtestField("Timing \(group.layerName)")
            ForEach(group.lanes) { lane in
                MotionStripLaneView(lane: lane, layerName: group.layerName, laneWidth: laneWidth)
            }
        }
    }

    private var isPicked: Bool { editorState.selectedLayerID == group.layerID }
}

/// One lane: the property's name, and the bar that says when it happens.
private struct MotionStripLaneView: View {
    @Environment(EditorState.self) private var editorState
    let lane: MotionStripLane
    let layerName: String
    let laneWidth: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            // Indented under its layer's heading. The indent lives INSIDE the
            // fixed width, so every lane starts at exactly the point the ruler
            // and the dashed line count from.
            Text(lane.title)
                .font(.system(size: 10))
                .lineLimit(1)
                .foregroundStyle(lane.isOn ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .padding(.leading, 10)
                .frame(width: MotionStripView.labelWidth - 6, alignment: .leading)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.quaternary.opacity(0.5))
                    .frame(height: MotionStripView.barHeight)
                MotionStripBar(lane: lane, layerName: layerName, laneWidth: laneWidth)
            }
            .frame(width: laneWidth, alignment: .leading)
        }
        .frame(height: MotionStripView.laneHeight)
        .playtestField("Timing \(layerName) \(lane.title)")
    }
}

// MARK: - The bar

/// One entry in the Motion list, drawn where it happens: its left edge is the
/// start, its width the duration, and its two ends are how each of them
/// changes.
///
/// It is the SAME TWO NUMBERS as the Start and Over fields in the side column.
/// Drag the bar and those numbers move with it; type in those numbers and the
/// bar moves with them. One model, two views.
private struct MotionStripBar: View {
    @Environment(EditorState.self) private var editorState
    let lane: MotionStripLane
    let layerName: String
    let laneWidth: CGFloat

    /// How wide the grab zone at each end is. Narrower than this and the ends
    /// are a thing you hunt for; wider and a short bar is nothing BUT ends.
    private static let gripWidth: CGFloat = 7
    /// No bar is ever drawn thinner than this, whatever its duration, because a
    /// bar you cannot take hold of is a bar you cannot edit.
    private static let minimumWidth: CGFloat = 16

    var body: some View {
        let ruler = editorState.motionStripRuler
        let x = laneWidth * ruler.fraction(ofMS: Double(lane.timing.startMS))
        let width = max(Self.minimumWidth,
                        laneWidth * ruler.fraction(ofMS: Double(lane.timing.durationMS)))
        RoundedRectangle(cornerRadius: 5)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isPicked ? AnyShapeStyle(Color.accentColor)
                                           : AnyShapeStyle(.separator),
                                  lineWidth: isPicked ? 1.5 : 1)
            }
            .overlay(alignment: .leading) { grip }
            .overlay(alignment: .trailing) { grip }
            .frame(width: width, height: MotionStripView.barHeight)
            .contentShape(Rectangle())
            .offset(x: x)
            .overlay(alignment: .topLeading) { bracket }
            .gesture(drag(width: width))
            .onTapGesture { editorState.selectLayer(lane.layerID) }
            .panelHelp("\(lane.title) on \(layerName): starts at \(lane.timing.startMS) ms "
                       + "and takes \(lane.timing.durationMS) ms. Drag it to move it, "
                       + "or drag either end to change how long it takes.")
            .accessibilityLabel("\(layerName) \(lane.title), "
                                + "\(lane.timing.startMS) to \(lane.timing.endMS) milliseconds")
            .playtestControl("Timing Bar",
                             detail: "\(layerName) \(lane.title), "
                                 + "\(lane.timing.startMS) → \(lane.timing.endMS) ms")
    }

    private var isPicked: Bool { editorState.selectedLayerID == lane.layerID }

    private var fill: AnyShapeStyle {
        guard lane.isOn else { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(
            LinearGradient(colors: [Color.accentColor.opacity(0.85),
                                    Color.accentColor.opacity(0.45)],
                           startPoint: .leading, endPoint: .trailing))
    }

    /// The pale handle at each end, which is what says the ends are draggable
    /// at all.
    private var grip: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(.white.opacity(lane.isOn ? 0.85 : 0.3))
            .frame(width: 3)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
    }

    /// The lag, drawn as itself while the bar is moving: a bracket from the
    /// nearest end of any other bar to this one's start, with the number and
    /// the name of what it is measured from over it.
    @ViewBuilder private var bracket: some View {
        if let drag = editorState.motionTimingDrag, drag.motionID == lane.motionID,
           let gap = drag.gap {
            let ruler = editorState.motionStripRuler
            let from = laneWidth * ruler.fraction(ofMS: Double(min(gap.fromMS, lane.timing.startMS)))
            let to = laneWidth * ruler.fraction(ofMS: Double(max(gap.fromMS, lane.timing.startMS)))
            MotionStripGapMark(reading: gap.reading, width: max(0, to - from))
                .offset(x: from - laneWidth * ruler.fraction(ofMS: Double(lane.timing.startMS)),
                        y: -11)
        }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if editorState.motionTimingDrag?.motionID != lane.motionID {
                    editorState.beginMotionTimingDrag(motionID: lane.motionID,
                                                      grab: grab(at: value.startLocation.x,
                                                                 width: width))
                }
                editorState.updateMotionTimingDrag(byMS: ms(value.translation.width))
            }
            .onEnded { value in
                editorState.updateMotionTimingDrag(byMS: ms(value.translation.width))
                editorState.commitMotionTimingDrag()
            }
    }

    /// Which part of the bar the hand came down on. A bar too short to hold
    /// three zones is all body: pulling the ends of a sliver is a gesture
    /// nobody can aim, and moving it and then stretching it is two easy ones.
    private func grab(at x: CGFloat, width: CGFloat) -> MotionStripDrag.Grab {
        guard width >= Self.gripWidth * 3 else { return .body }
        if x <= Self.gripWidth { return .start }
        if x >= width - Self.gripWidth { return .end }
        return .body
    }

    private func ms(_ points: CGFloat) -> Int {
        Int((editorState.motionStripRuler.ms(atFraction: Double(points / laneWidth))).rounded())
    }
}

/// The bracket and its number.
private struct MotionStripGapMark: View {
    let reading: String
    let width: CGFloat

    var body: some View {
        Text(reading)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Color.accentColor)
            .fixedSize()
            .padding(.horizontal, 4)
            .background(.regularMaterial, in: Capsule())
            .frame(width: max(width, 1), alignment: .center)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: max(width, 1), height: 1)
                    .offset(y: 5)
            }
            .fixedSize(horizontal: true, vertical: false)
            .panelReadout("gap \(reading)")
    }
}

// MARK: - The dashed line, and where the preview has got to

/// Where the lap starts over, and where the preview is in it.
private struct MotionStripMarksView: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat

    var body: some View {
        let ruler = editorState.motionStripRuler
        ZStack(alignment: .topLeading) {
            // The restart. A bar is allowed to carry on past this, and when one
            // does, that is not a mess to tidy up: it is the motion still
            // finishing while the loop has already begun again, which is what a
            // lag in something that repeats IS.
            VStack(alignment: .leading, spacing: 0) {
                Text("repeats")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .padding(.leading, 3)
                Rectangle()
                    .fill(.tertiary)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .offset(x: laneWidth * ruler.repeatsFraction)
            if editorState.isMotionPlaying {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
                    .offset(x: laneWidth * ruler.fraction(
                        ofMS: Double(editorState.motionPlayheadMS % max(1, editorState.motionStripCycleMS))))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
