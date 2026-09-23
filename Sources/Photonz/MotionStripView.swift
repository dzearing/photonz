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

    /// How far a pinch in flight has got, so each move opens the strip out by
    /// the CHANGE rather than by the whole gesture again.
    @State private var pinchedTo: CGFloat?

    /// The column down the left holding the lane names.
    static let labelWidth: CGFloat = 92
    /// One lane, and the bar in it.
    static let laneHeight: CGFloat = 22
    static let barHeight: CGFloat = 18
    /// A bar carrying a WAVEFORM is taller, and the level line drawn across it
    /// is why: a dot you drag up and down needs somewhere to go
    /// (`docs/design/video-audio.md`).
    static let soundBarHeight: CGFloat = 36
    static let soundLaneHeight: CGFloat = 42
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
            // The transport, for a document that finishes. It is the top row of
            // the bottom dock and the timeline is under it, which is where
            // UX-PATTERNS D8 puts them (`docs/design/video-surface.md` §2).
            if editorState.motionStripMeasuresADocument {
                DocumentTransportBar()
                    .padding(.horizontal, Self.inset)
                    .padding(.bottom, 6)
            }
            GeometryReader { geo in
                // The reader sits INSIDE the strip's own horizontal inset, so
                // its width is already the content width: taking the inset off
                // again here would make every bar two dozen points short of the
                // ruler drawn above it.
                let laneWidth = max(1, geo.size.width - Self.labelWidth)
                VStack(spacing: 0) {
                    // Where you are in the whole recording, and the way to
                    // move along it. Only while the strip is showing less than
                    // all of it (`TimelineZoomBar.swift`).
                    if editorState.isTimelineOpenedOut {
                        TimelineOverviewBar(laneWidth: laneWidth)
                            .padding(.leading, Self.labelWidth)
                            .padding(.bottom, 3)
                    }
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
                        .clipShape(TimelineEdgeClip())
                        .padding(.leading, Self.labelWidth)
                        .allowsHitTesting(false)
                }
                // A document's playhead is a different thing from a loop's: it
                // is always up, it can be taken hold of, and where it is is
                // what the canvas is drawing.
                .overlay(alignment: .topLeading) {
                    if editorState.motionStripMeasuresADocument {
                        DocumentPlayheadView(laneWidth: laneWidth)
                            .clipShape(TimelineEdgeClip())
                            .padding(.leading, Self.labelWidth)
                    }
                }
                // A pinch opens the strip out about the point under the
                // fingers, which is the gesture a trackpad already means by it
                // everywhere else in this app. Simultaneous, so it never takes
                // a drag on a bar away from the bar.
                .simultaneousGesture(pinch(laneWidth: laneWidth))
                }
            }
            .frame(height: bodyHeight)
            .padding(.horizontal, Self.inset)
            .padding(.bottom, Self.inset)
        }
        .background(.regularMaterial)
        // The Icons track's phase guide rings the whole strip rather than one
        // bar: a lag is a comparison, so what it is talking about is both lanes
        // and the ruler over them.
        .tutorialAnchor(.timingStrip)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// What the strip is measuring: one lap of something that repeats, or a
    /// document that finishes.
    private var stripTitle: String {
        editorState.motionStripMeasuresADocument
            ? MotionStripCopy.documentTitle : MotionStripCopy.title
    }

    /// A pinch on the lanes: the scale follows the fingers, about the moment
    /// under the point they started from. That moment is worked out against
    /// the ruler as it is NOW rather than as it was when the pinch began, so
    /// it is the moment the zoom is keeping still and the strip cannot creep
    /// out from under the hand.
    private func pinch(laneWidth: CGFloat) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard editorState.canOpenOutTheTimeline else { return }
                let x = value.startLocation.x - Self.labelWidth
                let fraction = min(max(0, x / laneWidth), 1)
                let anchorMS = editorState.motionStripRuler.ms(atFraction: Double(fraction))
                let previous = pinchedTo ?? 1
                editorState.zoomTimeline(by: value.magnification / previous, anchorMS: anchorMS)
                pinchedTo = value.magnification
            }
            .onEnded { _ in pinchedTo = nil }
    }

    /// As tall as it has to be for the lanes it holds, and no taller.
    private var bodyHeight: CGFloat {
        let groups = editorState.motionStripGroups
        let lanes = groups.reduce(0) { $0 + $1.lanes.count }
        // A row with a bar in it is as tall as a lane; a bare heading is the
        // short hairline row it always was.
        let headings = groups.reduce(CGFloat(0)) {
            $0 + ($1.bar == nil ? Self.layerRowHeight
                                : ($1.isSound ? Self.soundLaneHeight : Self.laneHeight))
        }
        let content = MotionStripRulerView.height
            + headings
            + CGFloat(lanes) * Self.laneHeight
            // Room over the top lane for the bracket a drag draws.
            + 10
        // The overview is added OUTSIDE the ceiling, so opening the timeline
        // out never costs a lane its room.
        let overview = editorState.isTimelineOpenedOut ? TimelineOverviewBar.height + 3 : 0
        return overview + min(Self.bodyCeiling, content)
    }

    // MARK: The bar along the top

    private var header: some View {
        HStack(spacing: 8) {
            Text(stripTitle.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.7)
                .foregroundStyle(.tertiary)
            // How long a LAP is, which is a number only a thing that repeats
            // has. A document's length is what it is made of, so there is
            // nothing here to type.
            if !editorState.motionStripMeasuresADocument { cycleField }
            Spacer(minLength: 0)
            // The zoom, in the timeline's OWN bar rather than in the transport
            // above it: what it scopes is this strip, which is where
            // UX-PATTERNS D8 and `docs/design/video-surface.md` put it.
            if editorState.canOpenOutTheTimeline { TimelineZoomControl() }
            // How fast the playhead below crosses this ruler. It belongs on the
            // strip as well as on the previews card because motion is on every
            // layer, not only on icons: a lag dragged out on this ruler has to
            // be judgeable in a document that has no icon frame to preview.
            // How fast the LOOP runs, which is a question only a thing that
            // repeats has. A recording plays at the rate it was recorded at.
            if !editorState.motionStripMeasuresADocument {
                MotionSpeedMenu(name: "Loop Speed")
                    .disabled(!editorState.canPlayMotion)
            }
            // The same × the side dock's header wears, and it puts the strip
            // away the same way: down to the one row below, never to nothing.
            Button { editorState.toggleMotionStrip() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Put the timing strip away")
            .panelHelp("Put the timing strip away (⌥⌘T)")
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
            MotionNumberField(value: Double(editorState.motionStripCycleMS),
                              label: "Cycle Length", suffix: "ms",
                              floor: 1, wholeNumbers: true) { typed in
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

// MARK: - The row it leaves behind

/// **The strip put away**: one row across the bottom saying what is still
/// moving, and opening the strip again when it is clicked.
///
/// The strip used to close to NOTHING. Once it was away the screen said neither
/// that it existed nor how to get it back, so the only ways were the View menu
/// and knowing ⌥⌘T — and a way back you have to already know is not a way back.
/// Every other thing in this app that can be pushed aside leaves a control on
/// screen the whole time it is away: the side dock's toggle sits in the title
/// bar so it cannot go away with the dock it collapses. The bottom of the
/// window has no title bar to put one in, so the dock leaves a row instead,
/// which is what `UX-PATTERNS.md` D9 asks a bottom dock for.
///
/// It is the SAME collapse idiom as the dock above it and deliberately not a
/// second one: the × on the surface's own header puts it away, one visible
/// control brings it back, and it comes back the size it was. That last one is
/// free here, because the strip is exactly as tall as the lanes it holds
/// (`bodyHeight`), so reopening it can only produce the height it left with.
///
/// The row leads with WHAT IS MOVING rather than with the strip's name,
/// because the reason you put the strip away was to look at the picture, so
/// the question you have while it is away is "what am I still editing".
struct MotionStripRailView: View {
    @Environment(EditorState.self) private var editorState
    @State private var isPointedAt = false

    /// One row, and the row is the whole height: a collapse that gives no
    /// canvas back is theatre. Thirty points is what the mock's own collapsed
    /// timeline is and what the decision this strip was built from promised.
    static let height: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button { editorState.toggleMotionStrip() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(MotionStripCopy.stripName.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.7)
                        .foregroundStyle(.tertiary)
                    Text(editorState.motionStripSummary)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(MotionStripCopy.showAgain)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: Self.height)
            .background(isPointedAt ? AnyShapeStyle(.quaternary.opacity(0.5))
                                    : AnyShapeStyle(.clear))
            .playtestHover { isPointedAt = $0 }
            .accessibilityLabel("Open the timing strip: \(editorState.motionStripSummary)")
            .panelHelp("Open the timing strip (⌥⌘T)")
            // What the row SAYS is what a walk claims, so the summary is the
            // detail rather than a note about where the row lives: there is
            // only one of these and it is across the bottom of the window.
            .playtestControl("Show Timing", detail: editorState.motionStripSummary)
        }
        .background(.regularMaterial)
        // A tutorial that points at the timing strip has something to point at
        // either way round, rather than losing its anchor the moment somebody
        // puts the strip away.
        .tutorialAnchor(.timingStrip)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .panelReadout("timing put away: \(editorState.motionStripSummary)")
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
                if let bar = group.bar {
                    clipBar(bar)
                } else {
                    Rectangle().fill(.separator).frame(height: 1)
                }
            }
            .frame(height: rowHeight)
            .playtestField("Timing \(group.layerName)")
            ForEach(group.lanes) { lane in
                MotionStripLaneView(lane: lane, layerName: group.layerName, laneWidth: laneWidth)
            }
        }
    }

    /// A layer that occupies time gets a bar, and it needs the same room a lane
    /// gets to draw one in. A layer that does not keeps the labelled hairline
    /// it has always had (`docs/design/video-surface.md` §2).
    private var rowHeight: CGFloat {
        guard group.bar != nil else { return MotionStripView.layerRowHeight }
        return group.isSound ? MotionStripView.soundLaneHeight : MotionStripView.laneHeight
    }

    /// The stretch of the document this layer occupies, drawn where it happens.
    ///
    /// The accent means SELECTED and nothing else, which is the one rule the
    /// shipped recording strip broke: there it ringed the range being kept in
    /// trim and the piece being held on the strip, so the same colour meant
    /// keep in one place and drop in the other.
    @ViewBuilder private func clipBar(_ bar: LayerTime) -> some View {
        if editorState.trimmingLayerID == group.layerID {
            ClipTrimBar(bar: bar, layerName: group.layerName, laneWidth: laneWidth)
        } else {
            plainClipBar(bar)
        }
    }

    private func plainClipBar(_ bar: LayerTime) -> some View {
        ClipPiecesBar(layerID: group.layerID, layerName: group.layerName,
                      bar: bar, laneWidth: laneWidth, isSound: group.isSound)
    }

    private var isPicked: Bool { editorState.selectedLayerID == group.layerID }
}

/// The clip's bar while it is being TRIMMED (`docs/design/video-surface.md`
/// §10.2).
///
/// The whole recording is laid out — that is what `openedForTrim` hands the
/// strip — and the part being kept is drawn bright between two handles, with
/// the frames outside them drawn as spare at each end, labelled with how long
/// they are. Nothing is thrown away by a trim, and this is the drawing that
/// says so: the spare is what Reset, or a second trim, gives back.
///
/// Both handles are up without hover, because a trim is a session and the two
/// ends are the whole of what it is about.
struct ClipTrimBar: View {
    @Environment(EditorState.self) private var editorState
    let bar: LayerTime
    let layerName: String
    let laneWidth: CGFloat
    /// How tall the bar is drawn: the strip's own, or a timeline lane's.
    var height: CGFloat = MotionStripView.barHeight

    /// How wide the grab zone on a handle is. The same seven points a motion
    /// bar's ends use, so a hand that has learned one has learned both.
    private static let gripWidth: CGFloat = 9

    var body: some View {
        let ruler = editorState.motionStripRuler
        let session = editorState.trimSession
        let start = Double(bar.inMS)
        let keepIn = start + Double(session?.keepInMS ?? 0)
        let keepOut = start + Double(session?.keepOutMS ?? bar.lengthMS)
        let x0 = laneWidth * ruler.fraction(ofMS: start)
        let xIn = laneWidth * ruler.fraction(ofMS: keepIn)
        let xOut = laneWidth * ruler.fraction(ofMS: keepOut)
        let xEnd = laneWidth * ruler.fraction(ofMS: start + Double(bar.lengthMS))
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(.quaternary.opacity(0.5))
                .frame(height: height)
            spare(width: xIn - x0, reading: session.map { Self.reading($0.spareBeforeMS) })
                .offset(x: x0)
            spare(width: xEnd - xOut, reading: session.map { Self.reading($0.spareAfterMS) })
                .offset(x: xOut)
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: max(2, xOut - xIn), height: height)
                .offset(x: xIn)
            handle(atX: xIn, isStart: true)
            handle(atX: xOut, isStart: false)
        }
        .frame(width: laneWidth, alignment: .leading)
        .clipShape(TimelineEdgeClip())
        .panelReadout("\(layerName) trimming, \(editorState.trimReadout)")
    }

    /// The frames outside the handles: still in the document, not being
    /// played, and drawn faintly with how long they are.
    @ViewBuilder private func spare(width: CGFloat, reading: String?) -> some View {
        if width > 1 {
            RoundedRectangle(cornerRadius: 5)
                .fill(.secondary.opacity(0.18))
                .frame(width: width, height: height)
                .overlay {
                    if let reading, width > 34 {
                        Text(reading)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
        }
    }

    private func handle(atX x: CGFloat, isStart: Bool) -> some View {
        Capsule()
            .fill(Color.accentColor)
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
            }
            .frame(width: Self.gripWidth, height: height)
            .offset(x: x - (isStart ? 0 : Self.gripWidth))
            .contentShape(Rectangle().inset(by: -6))
            .gesture(drag(isStart: isStart))
            .playtestField(isStart ? "Trim in handle" : "Trim out handle")
            .panelHelp(isStart ? "Where the trim starts keeping. Drag it."
                               : "Where the trim stops keeping. Drag it.")
    }

    private func drag(isStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let ms = Int(editorState.motionStripRuler
                    .ms(atFraction: Double(value.location.x / laneWidth)).rounded())
                isStart ? editorState.dragTrimIn(toMS: ms) : editorState.dragTrimOut(toMS: ms)
            }
    }

    /// `2.0s`, the way the spare says how much there is of it. Seconds with
    /// one decimal rather than a timecode, because what it answers is how much
    /// there is rather than when it happens.
    static func reading(_ ms: Int) -> String {
        String(format: "%.1fs", Double(ms) / 1000)
    }
}

/// One lane: the property's name, and the bar that says when it happens.
struct MotionStripLaneView: View {
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
            .clipShape(TimelineEdgeClip())
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

    /// Whether this bar is the one in hand. Kept beside the drag itself rather
    /// than read off it, because the two differ in exactly the case that
    /// matters: a drag called off by Escape is gone from `editorState` while
    /// the button is still down and the gesture is still reporting.
    @State private var carrying = false
    /// Escape happened part way through. Every report the gesture makes from
    /// here is ignored until the hand lifts: without this the next one would
    /// find no drag in flight and cheerfully start the whole thing again, so
    /// the bar would snap back and then leap to the pointer.
    @State private var calledOff = false

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
                        laneWidth * ruler.fraction(spanningMS: Double(lane.timing.durationMS)))
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
            .overlay(alignment: .leading) { marks(width: width) }
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

    /// The moments the value is NAILED TO between the bar's two ends, one mark
    /// each (`MotionStripKey`).
    ///
    /// Without these a punch in that pushes in, holds and pulls back out is
    /// four seconds of plain bar: it says something happens and nothing about
    /// where the camera arrives, how long it sits there, or when it leaves,
    /// while the row in the side column right above it reads
    /// "100% → 200% → 200% → 100%". A bar with nothing nailed down inside it
    /// has no marks and draws exactly as it always did.
    @ViewBuilder private func marks(width: CGFloat) -> some View {
        let ruler = editorState.motionStripRuler
        let barX = laneWidth * ruler.fraction(ofMS: Double(lane.timing.startMS))
        ForEach(Array(lane.keys.enumerated()), id: \.offset) { index, key in
            let x = min(max(laneWidth * ruler.fraction(ofMS: Double(key.ms)) - barX, 1),
                        width - 1)
            MotionStripKeyMark(lane: lane, layerName: layerName, key: key,
                               middle: index, laneWidth: laneWidth)
                .offset(x: x - MotionStripKeyMark.grabWidth / 2)
        }
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
                guard !calledOff else { return }
                if editorState.motionTimingDrag?.motionID != lane.motionID {
                    // Carrying already, and yet no drag: Escape took it
                    // (`watchForMotionTimingEscape`). The hand is still down,
                    // so the rest of this gesture is dropped on the floor.
                    guard !carrying else {
                        calledOff = true
                        return
                    }
                    carrying = true
                    editorState.beginMotionTimingDrag(motionID: lane.motionID,
                                                      grab: grab(at: value.startLocation.x,
                                                                 width: width))
                    // A bar the strip will not give up — it went away between
                    // the press and now — leaves nothing to drag.
                    guard editorState.motionTimingDrag?.motionID == lane.motionID else {
                        calledOff = true
                        return
                    }
                }
                editorState.updateMotionTimingDrag(byMS: ms(value.translation.width))
            }
            .onEnded { value in
                let carried = carrying && !calledOff
                carrying = false
                calledOff = false
                // Letting go of a drag that was already called off writes
                // nothing down: that is the whole point of calling it off.
                guard carried, editorState.motionTimingDrag?.motionID == lane.motionID else { return }
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
        // A sideways TRAVEL, which is a length rather than a moment: where the
        // window starts has nothing to do with how far a hand moved.
        Int((editorState.motionStripRuler.msSpanning(fraction: Double(points / laneWidth))).rounded())
    }
}

/// One key on a bar: a mark saying the value is nailed down here, and the one
/// thing on the strip a hand can move without moving the whole move.
///
/// Dragging the bar says "the whole thing happens later, or takes longer".
/// Dragging one of these says "it arrives here", or "it sits there a second
/// longer before it pulls out", which is the sentence the strip could not say
/// at all before.
private struct MotionStripKeyMark: View {
    @Environment(EditorState.self) private var editorState
    let lane: MotionStripLane
    let layerName: String
    let key: MotionStripKey
    /// Which of the keys between the bar's ends this is, from nought at the
    /// left, which is how the drag names it.
    let middle: Int
    let laneWidth: CGFloat

    /// How wide the part of it a hand can land on is. A mark is drawn as a
    /// hairline because a wide one would hide the bar it is on, and a hairline
    /// is not something anybody can aim at, so what is DRAWN and what can be
    /// GRABBED are two different widths.
    static let grabWidth: CGFloat = 13

    @State private var carrying = false
    /// Escape happened part way through, so the rest of this gesture is
    /// dropped on the floor (`MotionStripBar`).
    @State private var calledOff = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(lane.isOn ? 0.9 : 0.35))
                .frame(width: 1.5, height: MotionStripView.barHeight - 4)
            // The diamond, which is what every timeline anybody has used means
            // by a key. It is what makes the mark readable as something to take
            // hold of rather than as a join between two pieces.
            Rectangle()
                .fill(.white.opacity(lane.isOn ? 0.95 : 0.4))
                .frame(width: 5.5, height: 5.5)
                .rotationEffect(.degrees(45))
                .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
        }
        .frame(width: Self.grabWidth, height: MotionStripView.barHeight)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { readout }
        // High priority, because the bar underneath has a drag of its own and
        // the whole point of this mark is that landing on it means something
        // different from landing on the bar.
        .highPriorityGesture(drag)
        .panelHelp("\(lane.title) on \(layerName) is \(key.reading) at "
                   + "\(editorState.motionStripRuler.reading(ofMS: key.ms)). "
                   + "Drag it to move just this moment; the rest of the move stays put.")
        .accessibilityLabel("\(layerName) \(lane.title) key, \(key.reading) at \(key.ms) milliseconds")
        .playtestControl("Timing Key",
                         detail: "\(layerName) \(lane.title), \(key.reading) at \(key.ms) ms")
    }

    /// What the mark says while it is moving: the moment it is at, in the
    /// units the ruler above it is written in.
    @ViewBuilder private var readout: some View {
        if let drag = editorState.motionStopDrag, drag.motionID == lane.motionID,
           drag.middle == middle, let reading = editorState.motionStopDragReading {
            Text(reading)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .fixedSize()
                .padding(.horizontal, 4)
                .background(.regularMaterial, in: Capsule())
                .offset(y: -13)
                .panelReadout("key \(reading)")
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard !calledOff else { return }
                if editorState.motionStopDrag?.motionID != lane.motionID
                    || editorState.motionStopDrag?.middle != middle {
                    guard !carrying else {
                        calledOff = true
                        return
                    }
                    carrying = true
                    editorState.beginMotionStopDrag(motionID: lane.motionID, key: middle)
                    guard editorState.motionStopDrag != nil else {
                        calledOff = true
                        return
                    }
                }
                editorState.updateMotionStopDrag(byMS: ms(value.translation.width))
            }
            .onEnded { value in
                let carried = carrying && !calledOff
                carrying = false
                calledOff = false
                guard carried, editorState.motionStopDrag?.motionID == lane.motionID else { return }
                editorState.updateMotionStopDrag(byMS: ms(value.translation.width))
                editorState.commitMotionStopDrag()
            }
    }

    private func ms(_ points: CGFloat) -> Int {
        Int((editorState.motionStripRuler.msSpanning(fraction: Double(points / laneWidth))).rounded())
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
            if ruler.repeats {
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
            }
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


// MARK: - A document that finishes

/// The transport: where the playhead is, the buttons that move it, and how long
/// the whole thing runs for.
///
/// Only the controls that DO something. There is no volume and no loop button
/// because a recording finishes rather than repeating, and a control that only
/// promises a feature is a dead end. The meter is here rather than over the
/// canvas — where the mock drew it — because the canvas is the picture you are
/// judging and a meter parked on it is the one thing you cannot move out of the
/// way, and because this is where the eye already is while it plays.
struct DocumentTransportBar: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        HStack(spacing: 10) {
            Text(editorState.documentTimecode)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 38, alignment: .leading)
            Spacer(minLength: 0)
            MixMeter()
            button("backward.frame.fill", name: "Previous Frame",
                   help: "Back one frame (←)") { editorState.stepDocument(byFrames: -1) }
            button(editorState.isDocumentPlaying ? "pause.fill" : "play.fill",
                   name: editorState.isDocumentPlaying ? "Pause" : "Play",
                   help: editorState.isDocumentPlaying ? "Pause (space)" : "Play (space)",
                   size: 13) { editorState.toggleDocumentPlayback() }
            button("forward.frame.fill", name: "Next Frame",
                   help: "On one frame (→)") { editorState.stepDocument(byFrames: 1) }
            Spacer(minLength: 0)
            Text(editorState.documentLengthTimecode)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(minWidth: 38, alignment: .trailing)
        }
        .tutorialAnchor(.video(.transport))
    }

    private func button(_ symbol: String, name: String, help: String,
                        size: CGFloat = 11,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .panelHelp(help)
        .playtestControl(name, detail: "Transport")
    }
}

/// **How loud the mix is coming out** (`AudioHeadroom.swift`).
///
/// A slim bar that rises and falls with the sound, and an amber mark when the
/// mix adds up to more than a file can hold. Two things about it are deliberate
/// and neither is what the mock drew:
///
/// * **It reads the plan, not the engine.** Every piece of sound under the
///   playhead, at the level its own line says, times how loud its file actually
///   is there. So it moves while you DRAG the playhead and not only while it
///   plays, which is how you find the loud moment by hand, and it says the same
///   thing the export will, because it is the same arithmetic.
/// * **It says when the mix is over, not just that it is loud.** A meter that
///   only pins at the top tells you something is wrong and not what. This one
///   carries the number of decibels it is over, which is the number that gets
///   taken off every layer before anything is written.
struct MixMeter: View {
    @Environment(EditorState.self) private var editorState

    /// How wide the bar is. Enough to read a rise and a fall in, short enough
    /// that it never crowds the buttons it sits beside.
    private static let width: CGFloat = 56

    var body: some View {
        if Experiments.shared.mixLoudnessEnabled, editorState.documentHasAudio {
            HStack(spacing: 5) {
                bar
                if editorState.isMixHeldDown { overMark }
            }
            .playtestField("Mix meter")
            .panelHelp(editorState.audioHeadroom.label)
            .help(editorState.audioHeadroom.label)
            // A file whose shape has not been read is counted at full scale,
            // which is the safe guess for the ceiling and a bad one to DRAW:
            // it pins the meter at the top the moment a document opens. So the
            // meter asks for the shapes itself, and the guess lasts about as
            // long as reading the file does.
            .task(id: editorState.audioPlan.count) { editorState.loadSoundShapes() }
        }
    }

    private var bar: some View {
        let fraction = editorState.audioMeterFraction
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.10))
            Capsule()
                .fill(editorState.isMixHeldDown ? Color.orange : Color.accentColor)
                .frame(width: Self.width * CGFloat(fraction))
        }
        .frame(width: Self.width, height: 5)
        // No spring and no ballistics: the number under it is the truth at this
        // frame, and a meter that lags is a meter that lies about where the
        // loud moment was.
        .animation(.linear(duration: 0.05), value: fraction)
        .accessibilityLabel("Mix meter")
        .accessibilityValue(editorState.audioHeadroom.label)
    }

    /// What an over mix says, in the number that matters: how much is coming
    /// off every layer to make it fit.
    private var overMark: some View {
        Text(String(format: "%.1f dB over", editorState.audioHeadroom.overByDB ?? 0))
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Color.orange)
            .playtestField("Mix over")
    }
}

/// The playhead on a document's timeline: always up, and draggable.
///
/// Where it is is what the canvas is drawing, which is the whole of scrubbing:
/// there is no preview mode and no second picture, the document simply has a
/// moment and the canvas draws it.
private struct DocumentPlayheadView: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat

    var body: some View {
        // Against the RULER rather than against the document's length, so the
        // playhead lands on the same pixel as the moment under it once the
        // timeline is opened out (`TimelineZoom.swift`).
        let ruler = editorState.motionStripRuler
        let x = laneWidth * CGFloat(ruler.fraction(ofMS: Double(editorState.documentTimeMS)))
        ZStack(alignment: .topLeading) {
            // The whole width takes the click, so landing anywhere on the
            // timeline puts the playhead there rather than only landing on the
            // hairline itself.
            Color.clear
                .contentShape(Rectangle())
                .gesture(scrub)
            VStack(alignment: .leading, spacing: 0) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                    .offset(x: -3)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
            .offset(x: x)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // The first change IS the press: there is no onBegan on a drag,
                // so this is where the listening starts (`ScrubAudition.swift`).
                if !editorState.isAuditioningScrub { editorState.beginPlayheadDrag() }
                let fraction = min(max(0, value.location.x / max(1, laneWidth)), 1)
                let ms = editorState.motionStripRuler.ms(atFraction: Double(fraction))
                editorState.dragPlayhead(toMS: Int(ms.rounded()))
            }
            .onEnded { _ in editorState.endPlayheadDrag() }
    }
}
