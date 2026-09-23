import AppKit
import PhotonzCore
import SwiftUI

/// **The timeline dock** under a document with time
/// (`docs/design/mocks/pages/video.html`, the `.transport` and `#tlDock`).
///
/// Three rows, top to bottom, as the mock draws them: the transport (volume,
/// start, play, end, the time, a scrubber the width of the window, the
/// length), the timeline's own bar (Select and Blade, the zoom), and the grid:
/// a ruler in seconds, a named track per clip, and a red playhead standing
/// across all of them.
///
/// It is assembled from the video kit (`Sources/Photonz/VideoKit`) and drives
/// the same state the icon timing strip does, so every gesture a clip already
/// had (carry, trim at an edge, pick a piece, drag a transition, the trim
/// session, the sound's level line) is the same gesture here. An icon keeps
/// `MotionStripView`: it has a lap, not a length, and none of this.
struct TimelineDock: View {
    @Environment(EditorState.self) private var editorState

    /// The Blade: a click on a clip cuts it there, rather than picking it.
    @State private var isBlade = false
    /// How far a pinch in flight has got, so each move zooms by the CHANGE.
    @State private var pinchedTo: CGFloat?

    /// The track name column (`#tlDock{--gutter:84px}`) and the gap after it.
    static let gutter: CGFloat = 84
    static let gap: CGFloat = VideoKit.Metrics.trackGap
    /// Where the lanes start. Equal to the timing strip's label column, which
    /// is why a motion's lane under a track lines up without a second layout.
    static var lanesLeading: CGFloat { gutter + gap }
    /// `.tlgrid .track .lane{height:28px}`; a lane carrying sound is the kit's
    /// full 34, because its level line needs somewhere to be dragged.
    static let laneHeight: CGFloat = VideoKit.Metrics.compactLaneHeight
    static let soundLaneHeight: CGFloat = VideoKit.Metrics.laneHeight
    static let rowSpacing: CGFloat = VideoKit.Metrics.trackSpacing
    static let rulerHeight: CGFloat = 20
    /// Past which the tracks scroll rather than eating the picture
    /// (`#tlDock{max-height:58%}` in the mock, a fixed height here).
    private static let bodyCeiling: CGFloat = 236

    var body: some View {
        VStack(spacing: 0) {
            transport
            localBar
            grid
        }
        .background(VideoKit.Palette.panel)
        .tutorialAnchor(.timingStrip)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - The transport

    private var transport: some View {
        VideoKit.TransportBar(current: editorState.documentTimecode,
                              duration: editorState.documentLengthTimecode) {
            VideoKit.TransportButton(
                symbol: editorState.isDocumentMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: editorState.isDocumentMuted ? "Unmute" : "Mute") {
                    editorState.toggleDocumentMute()
                }
                .panelHelp(editorState.isDocumentMuted ? "Turn the sound back on" : "Turn the sound off")
                .playtestControl("Volume", detail: "Transport")
                .panelReadout(editorState.isDocumentMuted ? "sound off" : "sound on")
            MixMeter()
        } controls: {
            VideoKit.TransportButton(symbol: "backward.end.fill", label: "Go to Start") {
                editorState.goToDocumentStart()
            }
            .panelHelp("Go to the start (Home)")
            .playtestControl("Go to Start", detail: "Transport")
            VideoKit.TransportButton(symbol: editorState.isDocumentPlaying ? "pause.fill" : "play.fill",
                                     label: editorState.isDocumentPlaying ? "Pause" : "Play",
                                     role: .primary) {
                editorState.toggleDocumentPlayback()
            }
            .panelHelp(editorState.isDocumentPlaying ? "Pause (space)" : "Play (space)")
            .playtestControl(editorState.isDocumentPlaying ? "Pause" : "Play", detail: "Transport")
            VideoKit.TransportButton(symbol: "forward.end.fill", label: "Go to End") {
                editorState.goToDocumentEnd()
            }
            .panelHelp("Go to the end (End)")
            .playtestControl("Go to End", detail: "Transport")
        } scrubber: {
            VideoKit.Scrubber(fraction: documentFraction) { fraction, phase in
                scrub(toDocumentFraction: fraction, phase: phase)
            }
            .playtestControl("Scrub", detail: "Transport")
        }
        .tutorialAnchor(.video(.transport))
    }

    /// Where the playhead is in the WHOLE document. The scrubber always
    /// measures all of it, whatever the timeline below is zoomed to: that is
    /// what makes it the way to get anywhere in one move.
    private var documentFraction: Double {
        let length = editorState.documentLengthMS
        guard length > 0 else { return 0 }
        return Double(editorState.documentTimeMS) / Double(length)
    }

    private func scrub(toDocumentFraction fraction: Double, phase: VideoKit.ScrubPhase) {
        let ms = Int((fraction * Double(editorState.documentLengthMS)).rounded())
        switch phase {
        case .began:
            editorState.beginPlayheadDrag()
            editorState.dragPlayhead(toMS: ms)
        case .changed:
            editorState.dragPlayhead(toMS: ms)
        case .ended:
            editorState.dragPlayhead(toMS: ms)
            editorState.endPlayheadDrag()
        }
    }

    // MARK: - The timeline's own bar

    private var localBar: some View {
        HStack(spacing: 4) {
            toolButton("cursorarrow", name: "Select", help: "Select (V)", isOn: !isBlade) {
                isBlade = false
            }
            toolButton("scissors", name: "Blade", help: "Blade: click a clip to cut it there (B cuts at the playhead)",
                       isOn: isBlade) {
                isBlade.toggle()
            }
            if !editorState.timelineZoomSteps.isEmpty {
                Rectangle().fill(VideoKit.Palette.line).frame(width: 1, height: 18)
                    .padding(.horizontal, 5)
                zoomSegments
                zoomStepButton("plus.magnifyingglass", name: "Timeline Zoom In",
                               help: "Open out around the playhead",
                               enabled: editorState.canZoomTimelineIn) { editorState.zoomTimelineIn() }
            }
            Spacer(minLength: 8)
            if editorState.isTimelineOpenedOut {
                Text(editorState.timelineWindowReading)
                    .font(.system(size: 10, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(VideoKit.Palette.faint)
                    .lineLimit(1)
                    .fixedSize()
            }
            closeButton
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(VideoKit.Palette.edgeLo).frame(height: 1)
        }
        .panelReadout("timeline \(editorState.timelineWindowReading)"
                      + (isBlade ? ", blade" : ", select"))
    }

    /// A tool in the timeline's bar (`.tool`, `.tool.on`): 28 high, the accent
    /// face when it is the one in hand.
    private func toolButton(_ symbol: String, name: String, help: String, isOn: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(VideoKit.Palette.dim))
                .frame(width: 30, height: 26)
                .background {
                    if isOn {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(LinearGradient(colors: [VideoKit.Palette.accent.mix(with: .white, by: 0.12),
                                                          VideoKit.Palette.accent],
                                                 startPoint: .top, endPoint: .bottom))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .panelHelp(help)
        .playtestControl("Timeline \(name)", detail: "Timeline")
    }

    /// `#zoomSeg`: Fit and the doubling steps, the one on screen lifted.
    private var zoomSegments: some View {
        let current = editorState.timelineWindow.scale
        return HStack(spacing: 2) {
            ForEach(editorState.timelineZoomSteps, id: \.self) { step in
                let isOn = abs(current - step) < 0.01
                Button { editorState.setTimelineScale(step) } label: {
                    Text(step <= 1 ? "Fit" : "\(Int(step))x")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isOn ? AnyShapeStyle(VideoKit.Palette.ink)
                                              : AnyShapeStyle(VideoKit.Palette.dim))
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background {
                            if isOn {
                                Capsule().fill(VideoKit.Palette.panel)
                                    .overlay(Capsule().strokeBorder(VideoKit.Palette.edgeLo))
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(step <= 1 ? "Fit The Timeline" : "Zoom \(Int(step)) times")
                .panelHelp(step <= 1 ? "The whole recording across the width"
                                     : "Open the timeline out \(Int(step)) times")
                .playtestControl(step <= 1 ? "Timeline Fit" : "Timeline \(Int(step))x", detail: "Timeline")
            }
        }
        .padding(2)
        .frame(height: 24)
        .background(Capsule().fill(VideoKit.Palette.glassThin))
        .overlay(Capsule().strokeBorder(VideoKit.Palette.edgeLo))
    }

    private func zoomStepButton(_ symbol: String, name: String, help: String, enabled: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? AnyShapeStyle(VideoKit.Palette.dim) : AnyShapeStyle(VideoKit.Palette.lineStrong))
        .disabled(!enabled)
        .accessibilityLabel(name)
        .panelHelp(help)
        .playtestControl(name, detail: "Timeline")
    }

    /// `.tlbar .tl-close`: the × that puts the timeline down to one row.
    private var closeButton: some View {
        Button { editorState.toggleMotionStrip() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(VideoKit.Palette.faint)
        .accessibilityLabel("Put the timeline away")
        .panelHelp("Put the timeline away (⌥⌘T)")
        .playtestControl("Hide Timing", detail: "Timeline")
    }

    // MARK: - The grid

    private var grid: some View {
        GeometryReader { geo in
            let laneWidth = max(1, geo.size.width - Self.lanesLeading)
            VStack(alignment: .leading, spacing: 0) {
                if editorState.isTimelineOpenedOut {
                    TimelineOverviewBar(laneWidth: laneWidth)
                        .padding(.leading, Self.lanesLeading)
                        .padding(.bottom, 4)
                }
                VStack(alignment: .leading, spacing: 0) {
                    rulerRow(laneWidth: laneWidth)
                    ScrollView(.vertical) {
                        let order = editorState.timelineTrackRows.map(\.id)
                        VStack(alignment: .leading, spacing: Self.rowSpacing) {
                            ForEach(editorState.timelineRows) { row in
                                switch row {
                                case .group(let group, let isCollapsed, let tracks):
                                    TimelineGroupRow(group: group, isCollapsed: isCollapsed,
                                                     tracks: tracks, laneWidth: laneWidth)
                                case .track(let track, let inGroup):
                                    TimelineTrackRow(row: track, inGroup: inGroup,
                                                     index: order.firstIndex(of: track.id) ?? 0,
                                                     trackCount: order.count,
                                                     laneWidth: laneWidth, isBlade: isBlade)
                                }
                            }
                            TimelineAddTrackRow(laneWidth: laneWidth)
                        }
                        .padding(.vertical, Self.rowSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .coordinateSpace(.named(Self.tracksSpace))
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .overlay(alignment: .topLeading) {
                    playhead(laneWidth: laneWidth)
                        .padding(.leading, Self.lanesLeading)
                }
                .simultaneousGesture(pinch(laneWidth: laneWidth))
                .background {
                    TimelineWheel { event in wheel(event, laneWidth: laneWidth) }
                }
            }
        }
        .frame(height: bodyHeight)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    /// `.rlane`: "Time" in the gutter and the seconds over the lanes. A press
    /// or a drag anywhere on it puts the playhead there.
    private func rulerRow(laneWidth: CGFloat) -> some View {
        let ruler = editorState.motionStripRuler
        return HStack(spacing: Self.gap) {
            VideoKit.TrackHeader(title: "Time", width: Self.gutter, uppercase: false)
            VideoKit.TimeRuler(ticks: ruler.secondTicks.map {
                VideoKit.RulerTick(fraction: ruler.fraction(ofMS: $0.ms), label: $0.label)
            }, height: Self.rulerHeight)
            .frame(width: laneWidth)
            .contentShape(Rectangle())
            .gesture(rulerScrub(laneWidth: laneWidth))
            .playtestField("Timeline ruler")
        }
        .frame(height: Self.rulerHeight)
    }

    private func rulerScrub(laneWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !editorState.isAuditioningScrub { editorState.beginPlayheadDrag() }
                let fraction = min(max(0, value.location.x / laneWidth), 1)
                let ms = editorState.motionStripRuler.ms(atFraction: Double(fraction))
                editorState.dragPlayhead(toMS: Int(ms.rounded()))
            }
            .onEnded { _ in editorState.endPlayheadDrag() }
    }

    /// The red line across every track, and only while its moment is on
    /// screen: a zoomed timeline with the playhead elsewhere has no playhead
    /// to draw, rather than one pinned to its edge.
    @ViewBuilder private func playhead(laneWidth: CGFloat) -> some View {
        let fraction = editorState.motionStripRuler.fraction(ofMS: Double(editorState.documentTimeMS))
        if fraction >= -0.001, fraction <= 1.001 {
            VideoKit.Playhead(fraction: fraction)
                .frame(width: laneWidth)
                .panelReadout("playhead \(editorState.documentTimecode)")
        }
    }

    /// A pinch zooms about the moment under the fingers.
    private func pinch(laneWidth: CGFloat) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard editorState.canOpenOutTheTimeline else { return }
                let x = value.startLocation.x - Self.lanesLeading
                let fraction = min(max(0, x / laneWidth), 1)
                let anchorMS = editorState.motionStripRuler.ms(atFraction: Double(fraction))
                let previous = pinchedTo ?? 1
                editorState.zoomTimeline(by: value.magnification / previous, anchorMS: anchorMS)
                pinchedTo = value.magnification
            }
            .onEnded { _ in pinchedTo = nil }
    }

    /// Two fingers sideways (or a mouse wheel with ⇧) slide an opened out
    /// timeline along; ⌥ and the wheel zoom it, as in Premiere. Anything else
    /// is left to the tracks, which scroll up and down.
    private func wheel(_ event: NSEvent, laneWidth: CGFloat) -> Bool {
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        let dx = event.scrollingDeltaX * scale
        let dy = event.scrollingDeltaY * scale
        if event.modifierFlags.contains(.option), editorState.canOpenOutTheTimeline {
            let factor = exp(Double(dy) / 200)
            editorState.zoomTimeline(by: factor, anchorMS: editorState.timelineZoomAnchorMS)
            return true
        }
        let sideways = abs(dx) > abs(dy) ? dx : (event.modifierFlags.contains(.shift) ? dy : 0)
        guard sideways != 0, editorState.isTimelineOpenedOut else { return false }
        let ms = editorState.motionStripRuler.msSpanning(fraction: Double(-sideways / laneWidth))
        editorState.panTimeline(byMS: ms)
        return true
    }

    /// As tall as the tracks it holds, and no taller.
    private var bodyHeight: CGFloat {
        var rows: CGFloat = 0
        for row in editorState.timelineRows {
            switch row {
            case .group(_, let isCollapsed, _):
                rows += (isCollapsed ? TimelineGroupRow.foldedHeight : TimelineGroupRow.openHeight)
                    + Self.rowSpacing
            case .track(let track, _):
                rows += Self.height(of: track) + Self.rowSpacing
            }
        }
        rows += TimelineAddTrackRow.height + Self.rowSpacing
        let content = Self.rulerHeight + rows + Self.rowSpacing
        let overview = editorState.isTimelineOpenedOut ? TimelineOverviewBar.height + 4 : 0
        return overview + min(Self.bodyCeiling, content)
    }

    /// One track's full height: its lane, the lanes of anything moving on
    /// its clips, and the rows of the parts inside them.
    static func height(of track: TimelineTrackRowModel) -> CGFloat {
        let lane = track.carriesSound ? soundLaneHeight : laneHeight
        let motionLanes = track.clips.reduce(0) { $0 + $1.lanes.count }
        let inner = track.inner.reduce(CGFloat(0)) { total, group in
            total + 3 + (group.isSound ? soundLaneHeight : laneHeight)
                + CGFloat(group.lanes.count) * (MotionStripView.laneHeight + 3)
        }
        return lane + CGFloat(motionLanes) * (MotionStripView.laneHeight + 3) + inner
    }

    /// The space the tracks are laid out in, which is what a clip carried up
    /// or down measures its pointer against.
    nonisolated static let tracksSpace = "timelineTracks"
}

// MARK: - The wheel

/// Hands the timeline the scroll wheel while the pointer is over it.
///
/// SwiftUI has no wheel event of its own, so this watches the window's wheel
/// events and offers each one that lands inside its own frame. Returning true
/// keeps it; false lets it carry on to the tracks' own vertical scroll.
private struct TimelineWheel: NSViewRepresentable {
    let handle: (NSEvent) -> Bool

    func makeNSView(context: Context) -> WheelView {
        let view = WheelView()
        view.handle = handle
        return view
    }

    func updateNSView(_ view: WheelView, context: Context) { view.handle = handle }

    static func dismantleNSView(_ view: WheelView, coordinator: ()) { view.stop() }

    final class WheelView: NSView {
        var handle: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                return self.handle?(event) == true ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
