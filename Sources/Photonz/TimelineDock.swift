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
    /// Kept by the editor, because B picks it from the keyboard.
    private var isBlade: Bool { editorState.isTimelineBlade }
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
        // A press anywhere in here hands the timeline the keyboard, and the
        // keys reach it through here (`EditorState+TimelineKeys`).
        .background { TimelineKeyboard(editorState: editorState) }
        // Premiere's focused panel: a thin ring says which of the two, the
        // picture or the timeline, the keys are talking to.
        .overlay {
            if editorState.timelineHasKeyboard {
                Rectangle()
                    .strokeBorder(VideoKit.Palette.accent.opacity(0.75), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .panelReadout(editorState.timelineHasKeyboard ? "keyboard on the timeline" : "keyboard on the canvas")
        .tutorialAnchor(.timingStrip)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - The transport

    private var transport: some View {
        VideoKit.TransportBar(current: editorState.documentTimecode
                                  + (editorState.shuttleReading.map { "  \($0)" } ?? ""),
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
            TransportScrubber { fraction, phase in
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
                editorState.isTimelineBlade = false
            }
            toolButton("scissors", name: "Blade", help: "Blade (B), split at playhead (⌘K)",
                       isOn: isBlade) {
                editorState.isTimelineBlade.toggle()
            }
            Rectangle().fill(VideoKit.Palette.line).frame(width: 1, height: 18)
                .padding(.horizontal, 5)
            // Premiere's and Final Cut's magnet: lit while clips catch on the
            // playhead, the cuts and each other. A switch, not a third tool,
            // so it stands apart from Select and Blade.
            toolButton(name: "Snapping", help: "Snapping (S)", isOn: editorState.isTimelineSnapping) {
                editorState.toggleTimelineSnapping()
            } icon: {
                MagnetGlyph().frame(width: 13, height: 13)
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
            if let hover = editorState.timelineFileHover {
                // What letting go does, where the timeline's own words go,
                // and the one key that changes it.
                Text(hover.note)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VideoKit.Palette.ink)
                    .lineLimit(1)
                if hover.landing.allowed, hover.landing.edit == .overwrite {
                    Text("⌘ inserts")
                        .font(.system(size: 11))
                        .foregroundStyle(VideoKit.Palette.faint)
                        .fixedSize()
                }
            } else if editorState.isTimelineOpenedOut {
                Text(editorState.timelineWindowReading)
                    .font(.system(size: 10, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(VideoKit.Palette.faint)
                    .lineLimit(1)
                    .fixedSize()
            }
            if editorState.timelineFileHover == nil { keyBar }
            closeButton
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(VideoKit.Palette.edgeLo).frame(height: 1)
        }
        .panelReadout("timeline \(editorState.timelineWindowReading)"
                      + (isBlade ? ", blade" : ", select")
                      + (editorState.isTimelineSnapping ? ", snapping" : ", snapping off"))
    }

    /// The right end of the bar, as `video.html` draws it: the keyed value
    /// under the playhead (`.kfread`, "Playhead Opacity 100% @ 4.12s"), then
    /// Easing, the curve a NEW key is given (`#easeSel`). The same six eases
    /// a key's right-click offers, so the question has one list of answers.
    @ViewBuilder private var keyBar: some View {
        // A layer picked with nothing keyed still says so, as the mock does;
        // with nothing picked there is nothing to read.
        if editorState.keyLayer != nil {
            let reading = editorState.keyReadout ?? "no animated property"
            let time = PhotonzDocument.playheadSeconds(editorState.documentTimeMS)
            // Stepped aside when the bar has no room, as the mock's narrow
            // layout drops it (`@media ... .tlbar .kfread{display:none}`),
            // rather than pushing Easing off the end.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    readoutPill(reading, at: time)
                    Rectangle().fill(VideoKit.Palette.line).frame(width: 1, height: 18)
                        .padding(.horizontal, 5)
                }
                Color.clear.frame(width: 0, height: 0)
            }
        }
        HStack(spacing: 4) {
            Text("EASING")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(VideoKit.Palette.faint)
                .fixedSize()
            easingMenu
        }
        .playtestField("Easing")
    }

    private func readoutPill(_ reading: String, at time: String) -> some View {
        HStack(spacing: 6) {
            Text("Playhead").foregroundStyle(VideoKit.Palette.ink)
            Text(reading).fontWeight(.semibold).foregroundStyle(VideoKit.Palette.comp)
            Text("@ \(time)").foregroundStyle(VideoKit.Palette.ink)
        }
        .font(.system(size: 11, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(VideoKit.Palette.panel2))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(VideoKit.Palette.edgeLo))
        .panelReadout("Playhead \(reading) @ \(time)")
        .playtestField("Playhead Readout")
    }

    private var easingMenu: some View {
        VideoKit.SelectFace(value: editorState.newKeyEase.title, size: .small)
            .frame(width: 124)
            .overlay {
                Menu {
                    ForEach(KeyEase.allCases, id: \.self) { ease in
                        Toggle(ease.title, isOn: Binding(
                            get: { editorState.newKeyEase == ease },
                            set: { if $0 { editorState.newKeyEase = ease } }))
                    }
                } label: {
                    Text(editorState.newKeyEase.title).foregroundStyle(Color.clear)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.011)
                .accessibilityLabel("Easing")
                .accessibilityValue(editorState.newKeyEase.title)
                .panelHelp("The curve new keys are given")
                .playtestControl("Easing", detail: "Timeline")
            }
    }

    /// A tool in the timeline's bar (`.tool`, `.tool.on`): 28 high, the accent
    /// face when it is the one in hand.
    private func toolButton(_ symbol: String, name: String, help: String, isOn: Bool,
                            action: @escaping () -> Void) -> some View {
        toolButton(name: name, help: help, isOn: isOn, action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
        }
    }

    private func toolButton<Icon: View>(name: String, help: String, isOn: Bool,
                                        action: @escaping () -> Void,
                                        @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            // A tool picked here is a press in the dock, so the keys that
            // follow are the timeline's.
            editorState.takeTimelineKeyboard()
            action()
        } label: {
            icon()
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
                        .onDrop(of: FileDrop.types, delegate: TimelineFileDropDelegate(editorState: editorState))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                            editorState.timelineTracksFrame = frame
                            editorState.timelineLaneWidth = laneWidth
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .overlay(alignment: .topLeading) {
                    playhead(laneWidth: laneWidth)
                        .padding(.leading, Self.lanesLeading)
                }
                // The ruler and the tracks under it: where a video guide
                // points when it means "on the timeline" rather than the
                // transport above.
                .tutorialAnchor(.timelineTracks)
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
    /// or a drag anywhere on it puts the playhead there; a right click offers
    /// the markers, the In and Out, and a cut through everything
    /// (`TimelineRulerRow`).
    private func rulerRow(laneWidth: CGFloat) -> some View {
        HStack(spacing: Self.gap) {
            VideoKit.TrackHeader(title: "Time", width: Self.gutter, uppercase: false)
            TimelineRulerRow(laneWidth: laneWidth, height: Self.rulerHeight,
                             scrub: rulerScrub(laneWidth: laneWidth))
        }
        .frame(height: Self.rulerHeight)
    }

    private func rulerScrub(laneWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !editorState.isAuditioningScrub { editorState.beginPlayheadDrag() }
                let fraction = min(max(0, value.location.x / laneWidth), 1)
                let ms = editorState.motionStripRuler.ms(atFraction: Double(fraction))
                editorState.dragPlayhead(toMS: Int(ms.rounded()),
                                         snappingWithinMS: editorState.keySnapReachMS(laneWidth: laneWidth))
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
        let words = track.isCaptions && !track.clips.isEmpty ? CaptionWordsLane.height + 3 : 0
        return lane + CGFloat(motionLanes) * (MotionStripView.laneHeight + 3) + inner + words
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


// MARK: - The ruler and the scrub bar, with their marks and their menu

/// The ruler over the lanes: the seconds, the markers, the In and Out, and
/// the right-click menu that sets them.
///
/// Its own view, so following the pointer along it redraws the ruler and
/// nothing else.
private struct TimelineRulerRow<Scrub: Gesture>: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat
    let height: CGFloat
    let scrub: Scrub
    /// Where the pointer last was over the ruler, which is where a right click
    /// acts. The playhead, where nothing has hovered yet.
    @State private var pointerMS: Int?

    var body: some View {
        let ruler = editorState.motionStripRuler
        let x = { (ms: Int) in laneWidth * ruler.fraction(ofMS: Double(ms)) }
        VideoKit.TimeRuler(ticks: ruler.secondTicks.map {
            VideoKit.RulerTick(fraction: ruler.fraction(ofMS: $0.ms), label: $0.label)
        }, height: height)
        .frame(width: laneWidth)
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if let range = editorState.document?.markedRangeMS {
                    TimelineInOutSpan(x0: x(range.lowerBound), x1: x(range.upperBound), height: height,
                                      hasIn: editorState.document?.markInMS != nil,
                                      hasOut: editorState.document?.markOutMS != nil)
                }
                ForEach(editorState.document?.markers ?? []) { marker in
                    TimelineMarkerFlag()
                        .offset(x: x(marker.atMS) - TimelineMarkerFlag.width / 2)
                }
            }
            .frame(width: laneWidth, height: height, alignment: .topLeading)
            .clipped()
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(scrub)
        .onContinuousHover { phase in
            if case .active(let point) = phase {
                let fraction = min(max(0, point.x / max(1, laneWidth)), 1)
                pointerMS = Int(ruler.ms(atFraction: Double(fraction)).rounded())
            }
        }
        .contextMenu {
            TimelineRulerMenu(atMS: pointerMS, reachMS: Int(ruler.ms(atFraction: Double(6 / max(1, laneWidth)))
                                                             - ruler.ms(atFraction: 0)))
        }
        .playtestField("Timeline ruler")
        .panelReadout(TimelineRulerMenu.readout(editorState.document))
    }
}

/// The transport's scrub bar with the In and Out drawn on it, the way the mock
/// draws them, and the same right-click menu the ruler has.
private struct TransportScrubber: View {
    @Environment(EditorState.self) private var editorState
    let onScrub: (Double, VideoKit.ScrubPhase) -> Void
    @State private var pointerMS: Int?
    @State private var width: CGFloat = 1

    var body: some View {
        let length = Double(max(1, editorState.documentLengthMS))
        let marks = [editorState.document?.markInMS, editorState.document?.markOutMS]
            .compactMap { $0.map { Double($0) / length } }
        VideoKit.Scrubber(fraction: Double(editorState.documentTimeMS) / length, marks: marks,
                          onScrub: onScrub)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onContinuousHover { phase in
                if case .active(let point) = phase {
                    pointerMS = Int((min(max(0, point.x / max(1, width)), 1) * length).rounded())
                }
            }
            .contextMenu {
                TimelineRulerMenu(atMS: pointerMS, reachMS: Int(length * 6 / Double(max(1, width))))
            }
    }
}

/// What a right click on the ruler or the scrub bar offers
/// (`EditorState+TimelineMenus`).
struct TimelineRulerMenu: View {
    @Environment(EditorState.self) private var editorState
    /// Where the right click landed, or nil to act at the playhead.
    let atMS: Int?
    /// How near a marker the click has to be to be ON it.
    let reachMS: Int

    var body: some View {
        let ms = atMS ?? editorState.documentTimeMS
        let marker = editorState.document?.markers
            .filter { abs($0.atMS - ms) <= max(1, reachMS) }
            .min { abs($0.atMS - ms) < abs($1.atMS - ms) }
        MenuRowsView(rows: editorState.timelineRulerMenuRows(atMS: ms, markerHere: marker?.id))
    }

    /// What a walk reads off the ruler: where its markers and marks are.
    static func readout(_ document: PhotonzDocument?) -> String {
        guard let document else { return "ruler" }
        var words = "ruler: " + (document.markers.isEmpty ? "no markers"
            : "markers at " + document.markers.map { "\($0.atMS)ms" }.joined(separator: ", "))
        if let mark = document.markInMS { words += ", in at \(mark)ms" }
        if let mark = document.markOutMS { words += ", out at \(mark)ms" }
        return words
    }
}

/// A marker on the ruler: a small tab hanging from its top edge.
private struct TimelineMarkerFlag: View {
    static let width: CGFloat = 8

    var body: some View {
        MarkerTab()
            .fill(VideoKit.Palette.warn)
            .frame(width: Self.width, height: 9)
            .overlay(alignment: .top) {
                Rectangle().fill(VideoKit.Palette.warn).frame(width: 1, height: 16)
            }
    }

    private struct MarkerTab: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.6))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY * 0.6))
            path.closeSubpath()
            return path
        }
    }
}

/// The stretch between In and Out, washed on the ruler with a bracket at each
/// mark that is set, in the colour the scrub bar's marks wear.
private struct TimelineInOutSpan: View {
    let x0: CGFloat
    let x1: CGFloat
    let height: CGFloat
    let hasIn: Bool
    let hasOut: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(VideoKit.Palette.good.opacity(0.18))
            if hasIn {
                Rectangle().fill(VideoKit.Palette.good).frame(width: 2)
            }
            if hasOut {
                Rectangle().fill(VideoKit.Palette.good).frame(width: 2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: max(2, x1 - x0), height: height)
        .offset(x: x0)
    }
}


/// Hands the timeline the keyboard on a press anywhere over the dock, takes it
/// back on a press anywhere else in the window, and puts the window's presses
/// through `TimelineKeyRouter` while the dock is up.
///
/// A monitor rather than a gesture, so no press is taken away from the clip,
/// ruler or button it landed on: the dock only notices where it was.
private struct TimelineKeyboard: NSViewRepresentable {
    let editorState: EditorState

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.editorState = editorState
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.editorState = editorState }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) { view.stop() }

    final class CatcherView: NSView {
        weak var editorState: EditorState?
        private var monitor: Any?
        private weak var registeredWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window, let editorState else { return }
            TimelineKeyRouter.register(editorState, in: window)
            registeredWindow = window
            // The timeline shows up holding the keyboard, so a recording plays
            // on L the moment it opens, as in Premiere. A press on the canvas
            // is what hands the picture tools their letters back.
            editorState.takeTimelineKeyboard()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(point) {
                    self.editorState?.takeTimelineKeyboard()
                } else {
                    self.editorState?.releaseTimelineKeyboard()
                }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let registeredWindow { TimelineKeyRouter.unregister(registeredWindow) }
            registeredWindow = nil
            editorState?.releaseTimelineKeyboard()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// A horseshoe magnet, poles up: the timeline's Snapping switch, drawn because
/// the system's symbols have none. The pole tips are split off by a hairline,
/// which is what makes it read as a magnet rather than a U at 13 points.
struct MagnetGlyph: View {
    var body: some View {
        GeometryReader { box in
            let w = box.size.width, h = box.size.height
            let bar = (w * 0.30).rounded()
            let pole = (h * 0.26).rounded()
            let gap: CGFloat = 1.5
            ZStack(alignment: .topLeading) {
                MagnetArc(armWidth: bar, top: pole + gap)
                Rectangle().frame(width: bar, height: pole)
                Rectangle().frame(width: bar, height: pole).offset(x: w - bar)
            }
            .frame(width: w, height: h, alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }
}

/// The body of the magnet: two arms joined by a half ring, filled.
private struct MagnetArc: Shape {
    var armWidth: CGFloat
    /// Where the arms start, below the pole tips.
    var top: CGFloat

    func path(in rect: CGRect) -> Path {
        let outer = rect.width / 2
        let inner = max(0, outer - armWidth)
        let centre = CGPoint(x: rect.midX, y: rect.maxY - outer)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addLine(to: CGPoint(x: rect.minX, y: centre.y))
        path.addArc(center: centre, radius: outer, startAngle: .degrees(180), endAngle: .degrees(0),
                    clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + top))
        path.addLine(to: CGPoint(x: rect.maxX - armWidth, y: rect.minY + top))
        path.addLine(to: CGPoint(x: rect.maxX - armWidth, y: centre.y))
        path.addArc(center: centre, radius: inner, startAngle: .degrees(0), endAngle: .degrees(180),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + armWidth, y: rect.minY + top))
        path.closeSubpath()
        return path
    }
}
