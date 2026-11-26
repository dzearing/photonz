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
struct TimelineDock: View, Equatable {
    @Environment(EditorState.self) private var editorState

    /// Equal while the window is as tall: everything else the dock shows it
    /// reads for itself. Without this every run of the closure that lays the
    /// window out built the dock and its whole grid again, because a value
    /// holding a stored setting never compares equal on its own.
    nonisolated static func == (lhs: TimelineDock, rhs: TimelineDock) -> Bool {
        lhs.windowHeight == rhs.windowHeight
    }

    /// The Blade: a click on a clip cuts it there, rather than picking it.
    /// Kept by the editor, because B picks it from the keyboard.
    private var isBlade: Bool { editorState.isTimelineBlade }
    /// How far a pinch in flight has got, so each move zooms by the CHANGE.
    @State private var pinchedTo: CGFloat?

    /// The editor window's height, which caps how tall the top edge can pull
    /// the dock (`TimelineDockHeight`).
    let windowHeight: CGFloat
    /// The tracks area's height as the top edge last left it, or 0 for the
    /// height the dock always had. The person's, across every recording.
    @StoredSetting(EditorState.timelineHeightKey) private var storedHeight = TimelineDockHeight.defaultStored
    /// The tracks area's height while the edge is in hand: live, and only
    /// written to the settings when the drag ends.
    @State private var draggedBody: CGFloat?
    /// Where it was when the drag began.
    @State private var dragStartBody: CGFloat?
    /// The transport and the timeline's bar, measured: the part of the dock a
    /// drag on its edge never changes.
    @State private var transportHeight: CGFloat = 0
    /// The tracks as last drawn, for the pass of an edit that catches up on
    /// the next one (`LateTrackRows`).
    @State private var lateTrackRows = LateTrackRows()
    @State private var localBarHeight: CGFloat = 0
    /// How tall the tracks' scroller is, so the empty space under the last
    /// track reaches its foot and a box can start anywhere in it.
    @State private var tracksViewportHeight: CGFloat = 0

    /// The track name column and the gap after it. The mock's
    /// `#tlDock{--gutter:84px}` left no room for a header's switches, so the
    /// column is the person's to drag wider or narrower by its right edge
    /// (`TrackColumn`, user 2026-10-03), and every row reads it live.
    static var gutter: CGFloat { TrackColumnWidth.shared.width }
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
            // Its own view: it reads the playhead, and read in this body every
            // step of the playhead and every frame of playback rebuilt the
            // whole timeline under it (`first-long-jump-when-zoomed-in-walk`).
            TimelineTransport()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { transportHeight = $0 }
            // In View mode the transport is all there is: a player's bar, and
            // the tracks go with the rest of the editing (`ViewEditMode`). One
            // view either way, so Edit grows the tracks out from under it.
            // Kept behind View once built, folded to no height under the
            // transport, so Edit only has to open it out (`EditModeArrival`).
            let open = editorState.isMotionStripOpen
            if open || editorState.areTracksKeptBehindView {
                // Asleep behind View: the tracks out of sight sit out every
                // frame of playback (`editPiecesAsleep`).
                AsleepBehindView(asleep: editorState.editPiecesAsleep) {
                    VStack(spacing: 0) {
                        localBar
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { localBarHeight = $0 }
                        grid
                    }
                }
                .equatable()
                .frame(height: open ? nil : 0, alignment: .top)
                .accessibilityHidden(editorState.editPiecesOutOfReach)
                .environment(\.editPiecesOutOfReach, editorState.editPiecesOutOfReach)
                .environment(\.editPiecesAsleep, editorState.editPiecesAsleep)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .clipped()
        .background(VideoKit.Palette.panel)
        // A press anywhere in here hands the timeline the keyboard, and the
        // keys reach it through here (`EditorState+TimelineKeys`). Which of
        // the two has it is not drawn: the mock draws no ring round the dock,
        // and the one that stood here read as a stray blue outline round the
        // whole timeline (user 2026-09-28).
        .background { TimelineKeyboard(editorState: editorState) }
        // The top edge, a drag handle like the right panel's leading edge.
        // Only with tracks: in View the dock is a player's bar, one height.
        .overlay(alignment: .top) {
            if editorState.isMotionStripOpen {
                TimelineResizeEdge(onDrag: dragEdge(pointerMovedDown:),
                                   onEnd: endEdgeDrag,
                                   onReset: resetHeight)
                    #if PHOTONZ_PLAYTEST
                    .background { TimelineHeightReadout(fit: fit) }
                    #endif
            }
        }
        .zIndex(1)
        .panelReadout(editorState.timelineHasKeyboard ? "keyboard on the timeline" : "keyboard on the canvas")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            editorState.timelineDockFrame = $0
        }
        .tutorialAnchor(.timingStrip)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        // Read the shape of every sound, so an export holds the mix down by
        // what the files really peak at rather than by the safe guess of full
        // scale (`AudioHeadroom`). The mix meter used to ask for this. And
        // have the sound engine made, so the first press of play is not the
        // moment it gets built.
        .background { TimelineSoundShapesReader() }
    }

    // MARK: - The transport

    static func speakerSymbol(_ tier: PlayerVolume.Tier) -> String {
        switch tier {
        case .off: "speaker.slash.fill"
        case .low: "speaker.fill"
        case .medium: "speaker.wave.1.fill"
        case .high: "speaker.wave.2.fill"
        }
    }

    /// Where the playhead is in the WHOLE document. The scrubber always
    /// measures all of it, whatever the timeline below is zoomed to: that is
    /// what makes it the way to get anywhere in one move.
    private var documentFraction: Double {
        let length = editorState.documentLengthMS
        guard length > 0 else { return 0 }
        return Double(editorState.documentTimeMS) / Double(length)
    }


    // MARK: - The timeline's own bar

    private var localBar: some View {
        HStack(spacing: 4) {
            toolButton("cursorarrow", name: "Select", help: "Select (V)",
                       isOn: editorState.timelineTool == .select) {
                editorState.timelineTool = .select
            }
            // Premiere's A, between Select and the Blade as Premiere's own
            // tool bar has it. Beyond the mock, which draws only the two: the
            // same size and face, so it reads as one of them.
            toolButton("rectangle.righthalf.inset.filled.arrow.right", name: "Track Select Forward",
                       help: "Track Select Forward (A)",
                       isOn: editorState.timelineTool == .trackSelectForward) {
                editorState.timelineTool = editorState.timelineTool == .trackSelectForward
                    ? .select : .trackSelectForward
            }
            // Final Cut's Range tool (R): a drag on the tracks picks a
            // stretch of time on the tracks it crosses. ⌥-drag on empty track
            // space does the same without it.
            toolButton("arrow.left.and.right.square", name: "Range", help: "Range (R)",
                       isOn: editorState.timelineTool == .range) {
                editorState.timelineTool = editorState.timelineTool == .range ? .select : .range
            }
            toolButton("scissors", name: "Blade", help: "Blade (B), split at playhead (⌘B)",
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
            // No zoom buttons (user 2026-09-28: "super weird as buttons"). A
            // pinch on the tracks zooms, = and - step, ⇧Z fits, and the
            // ruler's right-click has Zoom to Fit.
            // The stretch on screen, at the bar's end. On its own, so a scroll
            // along time redraws this label and not the bar round it, and laid
            // over the bar's empty middle, so it is not asked how wide it is
            // on every frame of one (`TimelineSlot`).
            Spacer(minLength: 8)
                .overlay(alignment: .trailing) {
                    if editorState.timelineFileHover == nil, editorState.timelineTransitionHover == nil {
                        DrawnOnItsOwn {
                            if editorState.isTimelineOpenedOut {
                                Text(editorState.timelineWindowReading)
                                    .font(.system(size: 10, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(VideoKit.Palette.faint)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                    }
                }
            if let hover = editorState.timelineFileHover {
                // What letting go does, as a label, and the one key that
                // changes it.
                Text(hover.note)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VideoKit.Palette.ink)
                    .lineLimit(1)
                // A title tile names its kind instead of an edit, and ⌘ does
                // nothing to it: it never cuts into what is there.
                if hover.landing.allowed, hover.landing.edit == .overwrite, hover.verb == nil {
                    Text("⌘ Insert")
                        .font(.system(size: 11))
                        .foregroundStyle(VideoKit.Palette.faint)
                        .fixedSize()
                }
            } else if let hover = editorState.timelineTransitionHover {
                // What letting go of a transition tile does: which one, at
                // which cut.
                Text(hover.note)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VideoKit.Palette.ink)
                    .lineLimit(1)
                    .playtestField("Transition drop")
            }
            if editorState.timelineFileHover == nil, editorState.timelineTransitionHover == nil { keyBar }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(VideoKit.Palette.edgeLo).frame(height: 1)
        }
        .background {
            DrawnOnItsOwn {
                Color.clear
                    .panelReadout("timeline \(editorState.timelineWindowReading)"
                                  + ", " + Self.toolReading(editorState.timelineTool)
                                  + (editorState.isTimelineSnapping ? ", snapping" : ", snapping off"))
            }
        }
    }

    static func toolReading(_ tool: TimelineTool) -> String {
        switch tool {
        case .select: return "select"
        case .trackSelectForward: return "track select forward"
        case .range: return "range"
        case .blade: return "blade"
        }
    }

    /// The right end of the bar: Easing (`#easeSel`), only while keys or
    /// segments are picked, because it is the curve THEY move through. For
    /// keys alone, the same six eases a key's right-click offers; once any
    /// segment is picked, the shared curve list a segment's right click
    /// offers (task `the-value-graph-zooms-its-value-range-and-the-ti`), set
    /// for everything picked, points included (task
    /// `the-timeline-bar-easing-sets-picked-segments-too`).
    /// The mock's playhead readout (`.kfread`) stood before it until the user
    /// turned it down on 2026-09-25: the time is in the transport, the value
    /// in the panel, and a bar of controls carries no sentence about state.
    @ViewBuilder private var keyBar: some View {
        let picked = editorState.keySelection.flatMap { !$0.refs.isEmpty || !$0.segments.isEmpty ? $0 : nil }
        // A diamond picked on the Camera row eases from here too, as a key does.
        if picked != nil || editorState.easesPickedCameraKey {
            HStack(spacing: 4) {
                Text("EASING")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(VideoKit.Palette.faint)
                    .fixedSize()
                if let picked, !picked.segments.isEmpty {
                    segmentEasingMenu(picked)
                } else {
                    easingMenu
                }
            }
            .playtestField("Easing")
        }
    }

    /// The ease whose name is widest. The face is sized by a hidden copy of
    /// itself showing this one, so it reads every ease whole and keeps one
    /// width whatever the picked keys read. It was a fixed 124 until
    /// 2026-09-27, a few points short of "Ease In and Out" ("Ease In and...").
    static let widestEase: String = {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        return (KeyEase.allCases.map(\.title) + EasingCurve.named.map(\.title) + ["Mixed"])
            .max { ($0 as NSString).size(withAttributes: [.font: font]).width
                < ($1 as NSString).size(withAttributes: [.font: font]).width } ?? "Mixed"
    }()

    /// The Easing face's width: the face showing its widest ease, whole.
    private static let easingWidth: CGFloat = MainActor.assumeIsolated {
        NSHostingView(rootView: VideoKit.SelectFace(value: widestEase, size: .small)).fittingSize.width
    }

    private var easingMenu: some View {
        let shown = editorState.pickedKeysEase?.title ?? "Mixed"
        return VideoKit.Dropdown(
            label: "Easing", value: shown,
            choices: .picking(KeyEase.allCases, current: editorState.pickedKeysEase, title: \.title) {
                editorState.easePickedKeys($0)
            })
            .frame(width: Self.easingWidth)
            .panelHelp("The curve the picked keys move through")
            .playtestControl("Easing", detail: "Timeline")
    }

    /// Segments picked, with or without points: the curve they share, Mixed
    /// where they differ, and every one of them takes the curve chosen, each
    /// picked point as the segment it starts, as one undo step.
    private func segmentEasingMenu(_ picked: KeySelection) -> some View {
        let current = editorState.pickedSegmentsCurve(layerID: picked.layerID)
        let saved = SavedCurveStore.shared.curves
        return VideoKit.Dropdown(
            label: "Easing", value: CurveRow.value(current, saved: saved),
            choices: CurveRow.menu(current: current, saved: saved, offersHold: true, pick: { curve in
                editorState.curvePickedSegments(curve)
            }, draw: {
                editorState.drawCurveForPickedSegments()
            }))
            .frame(width: Self.easingWidth)
            .panelHelp("The curve the picked segments run on")
            .playtestControl("Easing", detail: "Timeline")
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

    // MARK: - The grid

    /// Whether a Captions track has captions on it, which is when its bar is up.
    private var showsCaptionTrackBar: Bool { Self.showsCaptionTrackBar(editorState) }

    static func showsCaptionTrackBar(_ editorState: EditorState) -> Bool {
        editorState.timelineTrackRows.contains { $0.isCaptions && !$0.clips.isEmpty }
    }

    private var grid: some View {
        #if PHOTONZ_PLAYTEST
        ViewBuildMeter.shared.built(.timelineGrid)
        #endif
        // Edit mode arriving from View holds this space empty for a pass
        // (`EditModeArrival`); its height is the tracks' own, so nothing moves.
        return Group {
        if editorState.editArrival.showsTimeline {
        GeometryReader { geo in buildingALatePass {
            // The rows' scroller lives in the dock's right hand margin, always,
            // so it coming and going never narrows the lanes.
            let laneWidth = max(1, geo.size.width - Self.lanesLeading)
            VStack(alignment: .leading, spacing: 0) {
                // The Caption track's bar, over the ruler as the captions
                // mock draws its dock's bar, so the playhead never runs
                // through its words.
                if showsCaptionTrackBar {
                    CaptionTrackBarView()
                        .padding(.bottom, 4)
                }
                VStack(alignment: .leading, spacing: 0) {
                    // The ruler is drawn on every frame of a scroll along
                    // time, and in a slot of its own size it asks nothing of
                    // the rows under it (`TimelineSlot`).
                    TimelineSlot(height: Self.rulerHeight) { rulerRow(laneWidth: laneWidth) }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                            editorState.timelineRulerFrame = $0
                        }
                    // The camera's keys, under the ruler and over every track,
                    // where `video-depth.html` puts them; it stays put while
                    // the tracks scroll, as the ruler does.
                    if editorState.showsCameraRow {
                        TimelineCameraRow(laneWidth: laneWidth)
                            .padding(.top, Self.rowSpacing)
                    }
                    ScrollView(.vertical) {
                        // The tracks a new title brings arrive a frame after
                        // its words (`readingALatePass`).
                        let trackRows = lateTrackRows.read(editorState) { editorState.timelineRows }
                        VStack(alignment: .leading, spacing: Self.rowSpacing) {
                            let rows = editorState.timelineRowZoom
                            // Edit mode arriving from View draws its rows a
                            // pass after the dock starts to slide
                            // (`EditModeArrival`).
                            let carry = editorState.trackRowDrag
                            let drawn = editorState.editArrival.showsTrackRows
                                ? trackRows : []
                            // What of the pick lands on each track, worked out
                            // here and handed to its row, so a pick builds only
                            // the rows it reaches (`TrackPickShare`).
                            let picks = editorState.timelinePickShares
                            // While captions are being written, their stand-in
                            // row stands where the Captions track will land:
                            // under the picture, over the sound.
                            let listening = editorState.isWritingCaptions
                            // A tall edit builds only the rows near the part
                            // of it on screen (`TimelineRowInSight`).
                            let gates = drawn.count > TimelineRowsInSight.tallEdit
                            let firstRows = gates ? Set(drawn.prefix(TimelineRowsInSight.builtAtFirst).map(\.id)) : []
                            let listeningBefore = listening
                                ? editorState.captionsListeningRowID(in: drawn) : nil
                            // A file in the air has a new track to go on at
                            // the top (`TimelineNewTrackSlot`).
                            if editorState.timelineDropRoomMS != nil {
                                TimelineNewTrackSlot(laneWidth: laneWidth)
                            }
                            ForEach(drawn) { row in
                                if listening, row.id == listeningBefore {
                                    TimelineCaptionsListeningRow(laneWidth: laneWidth)
                                }
                                // Equal rows are the same row, so an edit or a
                                // pick builds only the ones it reaches
                                // (`TimelineGridRow`).
                                TimelineGridRow(row: row, laneWidth: laneWidth, isBlade: isBlade, rows: rows,
                                                pick: row.trackRow.map { picks.share(of: $0) } ?? .none,
                                                gates: gates, startsNear: firstRows.contains(row.id),
                                                session: carry)
                                    .equatable()
                            }
                            if listening, listeningBefore == nil {
                                TimelineCaptionsListeningRow(laneWidth: laneWidth)
                            }
                            TimelineAddTrackRow(laneWidth: laneWidth)
                        }
                        // Down to the scroller's foot, all of it empty space a
                        // box can start in (`EditorState+TrackRange`).
                        .frame(minHeight: max(0, tracksViewportHeight - 2 * Self.rowSpacing), alignment: .top)
                        .background(alignment: .topLeading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(TimelineLaneMarquee.gesture(editorState, ruler: editorState.motionStripRuler,
                                                                     laneWidth: laneWidth,
                                                                     in: .named(Self.tracksSpace),
                                                                     leading: Self.lanesLeading) { 0 })
                                .padding(.leading, Self.lanesLeading)
                        }
                        .padding(.vertical, Self.rowSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // A track carried by its header: the gap it will land
                        // in under the rows, and the track itself over them.
                        .background(alignment: .topLeading) { TrackDragGap(session: editorState.trackRowDrag) }
                        .overlay(alignment: .topLeading) { liftedTrack(laneWidth: laneWidth) }
                        .coordinateSpace(.named(Self.tracksSpace))
                        // A box being drawn over the tracks, and a range on
                        // some of them (`EditorState+TrackRange`), in the
                        // tracks' own space so they scroll with them.
                        .overlay(alignment: .topLeading) {
                            TimelineLaneBoxView(laneWidth: laneWidth, leading: Self.lanesLeading)
                        }
                        .overlay(alignment: .topLeading) {
                            TimelineNewTrackGhost(laneWidth: laneWidth, leading: Self.lanesLeading)
                        }
                        .onDrop(of: TimelineFileDropDelegate.types, delegate: TimelineFileDropDelegate(editorState: editorState))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                            editorState.timelineTracksFrame = frame
                            editorState.timelineLaneWidth = laneWidth
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    // The part of the tracks on screen: a right click in it
                    // moves the playhead (`EditorState+TimelinePointing`).
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        editorState.timelineTracksViewport = $0
                    }
                    // Its own scroller, in the column kept for it, rather than
                    // the system's: an overlay scroller that comes and goes in
                    // space nothing else is using can never move a row.
                    .scrollIndicators(.never)
                    .scrollPosition(tracksScroll)
                    // The rows a pick or a key opens scroll inside the
                    // timeline rather than growing it, so the timeline
                    // scrolls them on screen (`TimelineRowReveal`).
                    .onChange(of: editorState.pickedTimelineRow) { before, now in
                        editorState.notePickedTimelineRow(now, after: before)
                    }
                    .onScrollGeometryChange(for: TimelineTracksScrollGeometry.self) { geometry in
                        TimelineTracksScrollGeometry(offsetY: geometry.contentOffset.y + geometry.contentInsets.top,
                                                     contentHeight: geometry.contentSize.height,
                                                     viewportHeight: geometry.containerSize.height)
                    } action: { _, now in
                        editorState.timelineTracksScrollGeometry = now
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in
                        tracksViewportHeight = height
                    }
                    .overlay(alignment: .trailing) {
                        TimelineRowsScroller()
                            .frame(width: Self.scrollerWidth)
                            .offset(x: Self.scrollerWidth + 1)
                    }
                }
                .overlay(alignment: .topLeading) {
                    rangeWash(laneWidth: laneWidth)
                        .padding(.leading, Self.lanesLeading)
                }
                .overlay(alignment: .topLeading) {
                    TimelinePlayheadLine(laneWidth: laneWidth)
                        .padding(.leading, Self.lanesLeading)
                }
                // The track names' right edge: the gap between them and the
                // lanes, from the ruler down, is its grab strip.
                .overlay(alignment: .topLeading) {
                    TrackColumnEdge()
                        .padding(.leading, Self.gutter)
                }
                // The ruler and the tracks under it: where a video guide
                // points when it means "on the timeline" rather than the
                // transport above.
                .tutorialAnchor(.timelineTracks)
                .simultaneousGesture(pinch(laneWidth: laneWidth))
                .coordinateSpace(.named(Self.wheelSpace))
                .background {
                    TimelineWheel(handle: { event, point in wheel(event, at: point, laneWidth: laneWidth) },
                                  touched: { editorState.timelinePinchTouched($0) })
                }
                // Time's scroller, under the lanes, in a strip that is always
                // there: at Fit it is empty, opened out it carries the window.
                TimelineSlot(height: Self.scrollerStrip) {
                    TimelineTimeScroller(laneWidth: laneWidth)
                        .padding(.leading, Self.lanesLeading)
                        .frame(height: Self.scrollerStrip, alignment: .bottom)
                }
            }
            .panelReadout(editorState.timelineRowsReading)
            .onAppear { editorState.arriveAfterTheWindowDraws() }
        } }
        } else {
            // A window that opened straight into Edit draws this empty
            // first, and the ruler and rows come in once it has.
            Color.clear
                .onAppear { editorState.arriveAfterTheWindowDraws() }
        }
        }
        .modifier(TimelineGridHeight(fit: fit))
        .padding(.horizontal, 12)
        .padding(.top, 6)
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

    /// A press on the ruler (`EditorState+RulerRange`): on the playhead it
    /// scrubs, on an end of the marked stretch it moves that end, on a marker
    /// it moves the marker, anywhere else a drag draws a range and a click
    /// moves the playhead.
    private func rulerScrub(laneWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let ruler = editorState.motionStripRuler
                let start = Self.rulerMS(value.startLocation.x, laneWidth, ruler)
                // A new press, or one left behind by a gesture the system
                // cancelled without an end.
                if editorState.rulerPress?.atMS != start {
                    editorState.beginRulerPress(atMS: start, reachMS: Self.rulerGrabMS(laneWidth, ruler))
                }
                editorState.dragRulerPress(toMS: Self.rulerMS(value.location.x, laneWidth, ruler),
                                           moved: abs(value.translation.width) >= EditorState.rulerClickSlop,
                                           snapMS: editorState.keySnapReachMS(laneWidth: laneWidth))
            }
            .onEnded { value in
                editorState.endRulerPress(atMS: Self.rulerMS(value.location.x, laneWidth,
                                                             editorState.motionStripRuler),
                                          moved: abs(value.translation.width) >= EditorState.rulerClickSlop,
                                          clicks: NSApp.currentEvent?.clickCount ?? 1)
            }
    }

    /// The moment under a point on the ruler.
    static func rulerMS(_ x: CGFloat, _ laneWidth: CGFloat, _ ruler: MotionStripRuler) -> Int {
        let fraction = min(max(0, x / max(1, laneWidth)), 1)
        return Int(ruler.ms(atFraction: Double(fraction)).rounded())
    }

    /// How near the playhead or an end of the band a press has to land to
    /// take hold of it: six points of ruler, in time.
    static func rulerGrabMS(_ laneWidth: CGFloat, _ ruler: MotionStripRuler) -> Int {
        Int((ruler.ms(atFraction: Double(6 / max(1, laneWidth))) - ruler.ms(atFraction: 0)).rounded())
    }

    /// A range drawn on the ruler washed down through the tracks while it is
    /// in hand, so it reads as a stretch of every track. It stays over the
    /// clips when one is picked under it, since the range then acts on that
    /// pick (`EditorState+RangeSection`). Marks set with I and O stay on the
    /// ruler alone, as in Premiere.
    @ViewBuilder private func rangeWash(laneWidth: CGFloat) -> some View {
        if let range = editorState.rulerRangeDraft ?? editorState.rulerRangeKept {
            let ruler = editorState.motionStripRuler
            let x0 = laneWidth * ruler.fraction(ofMS: Double(range.lowerBound))
            let x1 = laneWidth * ruler.fraction(ofMS: Double(range.upperBound))
            let lo = max(0, min(laneWidth, x0))
            let hi = max(0, min(laneWidth, x1))
            if hi > lo {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .overlay { Rectangle().fill(VideoKit.Palette.good.opacity(0.12)) }
                    .overlay(alignment: .leading) {
                        if x0 >= 0 { Rectangle().fill(VideoKit.Palette.good).frame(width: 1.5) }
                    }
                    .overlay(alignment: .trailing) {
                        if x1 <= laneWidth { Rectangle().fill(VideoKit.Palette.good).frame(width: 1.5) }
                    }
                    .frame(width: hi - lo)
                    .padding(.top, Self.rulerHeight)
                    .offset(x: lo)
                    .frame(width: laneWidth, alignment: .leading)
                    .allowsHitTesting(false)
                    .panelReadout("range \(range.lowerBound)ms to \(range.upperBound)ms")
            }
        }
    }

    /// A pinch zooms about the spot under the fingers, the way they spread:
    /// side to side opens out time about the moment under them, up and down
    /// grows the rows about the row under them, on the slant both. ⌥ keeps it
    /// to time, ⇧ to the rows (user 2026-09-28). The fingers themselves come
    /// in through `TimelineWheel`.
    private func pinch(laneWidth: CGFloat) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                if pinchedTo == nil { editorState.beginTimelinePinch() }
                let previous = pinchedTo ?? 1
                pinchedTo = value.magnification
                guard previous > 0 else { return }
                let flags = NSEvent.modifierFlags
                editorState.steerTimelinePinch(by: Double(value.magnification / previous),
                                               laneX: value.startLocation.x - Self.lanesLeading,
                                               laneWidth: laneWidth,
                                               viewportY: value.startLocation.y - Self.rulerHeight,
                                               forced: .forced(option: flags.contains(.option),
                                                               shift: flags.contains(.shift)))
            }
            .onEnded { value in
                pinchedTo = nil
                editorState.endTimelinePinch(laneX: value.startLocation.x - Self.lanesLeading,
                                             laneWidth: laneWidth,
                                             viewportY: value.startLocation.y - Self.rulerHeight)
            }
    }

    /// Two fingers sideways (or a mouse wheel with ⇧) slide an opened out
    /// timeline along; ⌥ and the wheel zoom time about the pointer, as in
    /// Premiere, and ⌘ and the wheel grow the rows about it. Over an open
    /// value graph ⌥ and the wheel zoom its values instead
    /// (`EditorState+KeyGraphZoom`). Anything else is left to the tracks,
    /// which scroll up and down.
    private func wheel(_ event: NSEvent, at point: CGPoint, laneWidth: CGFloat) -> Bool {
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        let dx = event.scrollingDeltaX * scale
        let dy = event.scrollingDeltaY * scale
        let flags = event.modifierFlags
        if flags.contains(.option), !flags.contains(.command), dy != 0,
           editorState.wheelOverKeyGraph(at: point, deltaY: Double(dy)) {
            return true
        }
        if flags.contains(.option) || flags.contains(.command) {
            let factor = exp(Double(dy) / 200)
            editorState.pinchTimeline(by: factor, laneX: point.x - Self.lanesLeading, laneWidth: laneWidth,
                                      viewportY: point.y - Self.rulerHeight,
                                      axes: flags.contains(.command) ? .rows : .time)
            return true
        }
        let sideways = abs(dx) > abs(dy) ? dx : (event.modifierFlags.contains(.shift) ? dy : 0)
        guard sideways != 0, editorState.canScrollTimeline else { return false }
        let ms = editorState.motionStripRuler.msSpanning(fraction: Double(-sideways / laneWidth))
        editorState.panTimeline(byMS: ms)
        return true
    }

    /// What the tracks area's height is worked out from that this view holds
    /// itself: the window, the top edge and the chrome above the grid. The
    /// part worked out from the tracks is read by `TimelineGridHeight`, its
    /// own view, so an edit that changes no track's height (a trim, an undo)
    /// re-runs that and not this whole body with the grid under it
    /// (`a-long-edit-with-transitions-plays-scrubs-and-ed`, pass 25).
    private var fit: TimelineDockFit {
        TimelineDockFit(windowHeight: windowHeight,
                        chosen: draggedBody ?? TimelineDockHeight.chosen(stored: storedHeight),
                        isChosen: TimelineDockHeight.chosen(stored: storedHeight) != nil,
                        chrome: transportHeight + localBarHeight + 6)
    }

    /// The tracks area's height now, for a drag on the top edge.
    private var bodyHeight: CGFloat { fit.bodyHeight(editorState) }

    private var sizing: TimelineDockHeight { fit.sizing(editorState) }

    private func dragEdge(pointerMovedDown dy: CGFloat) {
        let base = dragStartBody ?? bodyHeight
        if dragStartBody == nil { dragStartBody = base }
        draggedBody = sizing.dragged(fromBody: base, pointerMovedDown: dy)
    }

    private func endEdgeDrag() {
        if let draggedBody { storedHeight = Double(draggedBody) }
        draggedBody = nil
        dragStartBody = nil
    }

    private func resetHeight() {
        draggedBody = nil
        dragStartBody = nil
        withAnimation(.spring(duration: 0.28)) { storedHeight = TimelineDockHeight.defaultStored }
    }

    /// As tall as the tracks it holds, and no taller.
    ///
    /// **A pick or a key never resizes the timeline.** What counts is each
    /// track's own lane: the rows that open INSIDE a track (a picked title's
    /// parts, the key lanes of what moves, a clip's zooms) scroll inside the
    /// timeline rather than growing it, so picking a title or keying a value
    /// never re-zooms the picture above and never moves the panel beside it,
    /// the way Premiere's program monitor holds still (2026-10-15, the card on
    /// keying a property recommends the same). Folding a group and opening a
    /// track's words are commands on the tracks themselves, so they still
    /// count. It rides the timeline's own zoom, which is what lets taller rows
    /// scroll inside it.
    static func naturalBodyHeight(_ editorState: EditorState) -> CGFloat {
        let ownLanesOnly = Experiments.shared.timelineZoomEnabled
        var rows: CGFloat = 0
        for row in editorState.timelineRows {
            switch row {
            case .group(_, let isCollapsed, _):
                rows += (isCollapsed ? TimelineGroupRow.foldedHeight : TimelineGroupRow.openHeight)
                    + Self.rowSpacing
            case .track(let track, _):
                // Compact whatever the rows are zoomed to: the dock keeps its
                // height through a pinch and the taller rows scroll inside
                // it, so nothing above it ever moves.
                let wordsOpen = editorState.isKeyTrackOpen(track.id)
                rows += (ownLanesOnly ? Self.ownHeight(of: track, wordsOpen: wordsOpen)
                                      : Self.height(of: track, wordsOpen: wordsOpen))
                    + Self.rowSpacing
            }
        }
        rows += TimelineAddTrackRow.height + Self.rowSpacing
        let content = Self.rulerHeight + rows + Self.rowSpacing
        let captionBar = showsCaptionTrackBar(editorState) ? CaptionTrackBarView.height + 4 : 0
        return captionBar + cameraRow(editorState) + min(Self.bodyCeiling, content) + Self.scrollerStrip
    }

    /// The Camera row and the space over it, where the camera is keyed.
    static func cameraRow(_ editorState: EditorState) -> CGFloat {
        editorState.showsCameraRow ? TimelineCameraRow.height + Self.rowSpacing : 0
    }

    /// One track and no less: the ruler, one lane, and the scroller strip.
    static func bodyFloor(_ editorState: EditorState) -> CGFloat {
        let captionBar = showsCaptionTrackBar(editorState) ? CaptionTrackBarView.height + 4 : 0
        return captionBar + cameraRow(editorState) + Self.rulerHeight + Self.soundLaneHeight + 2 * Self.rowSpacing
            + Self.scrollerStrip
    }

    /// One track's full height: its lane, the lanes of anything moving on
    /// its clips, and the rows of the parts inside them.
    static func height(of track: TimelineTrackRowModel, wordsOpen: Bool = true,
                       rows: TimelineRowZoom = .compact) -> CGFloat {
        let lane = rows.height(track.restingLaneHeight)
        let motionLanes = track.clips.reduce(0) { $0 + $1.lanes.count }
        let inner = track.inner.reduce(CGFloat(0)) { total, group in
            total + 3 + rows.height(group.isSound ? soundLaneHeight : laneHeight)
                + CGFloat(group.lanes.count) * (MotionStripView.laneHeight + 3)
        }
        let words = track.isCaptions && !track.clips.isEmpty && wordsOpen ? CaptionWordsLane.height + 3 : 0
        // One Zoom lane holds every zoomed clip on the track.
        let zooms = track.zoomedClips.isEmpty ? 0 : ZoomLane.height + 3
        let curves = CGFloat(track.rampedClips.count) * (SpeedCurveLane.height + 3)
        let expanded = track.expandsCut ? ExpandedCutRows.height + 3 : 0
        return lane + CGFloat(motionLanes) * (MotionStripView.laneHeight + 3) + inner + words + zooms + curves
            + expanded
    }

    /// One track's lane and its words, without the rows that open inside its
    /// clips: what the timeline fits itself to (`naturalBodyHeight`).
    static func ownHeight(of track: TimelineTrackRowModel, wordsOpen: Bool = true) -> CGFloat {
        let lane = track.restingLaneHeight
        let words = track.isCaptions && !track.clips.isEmpty && wordsOpen ? CaptionWordsLane.height + 3 : 0
        // The open cut's rows are part of the track itself, right under its
        // lane, so the timeline grows to show them.
        let expanded = track.expandsCut ? ExpandedCutRows.height + 3 : 0
        return lane + words + expanded
    }

    /// Whether a track's row is its lane and nothing under it, so how tall it
    /// stands is known without building it.
    static func isOneLane(_ track: TimelineTrackRowModel, _ editor: EditorState) -> Bool {
        track.inner.isEmpty && track.zoomedClips.isEmpty && track.rampedClips.isEmpty && !track.expandsCut
            && !track.isCaptions && track.clips.allSatisfy(\.lanes.isEmpty)
            && !(editor.isKeyTrackOpen(track.id) && editor.trackHasKeyLanes(track.clips.map(\.layerID)))
            && editor.renamingTrackID != track.id && editor.trackRowDrag.grabbedID != track.id
    }

    /// The track lifted by its header, drawn over the others: the real row,
    /// built again for the drag, never answering the pointer.
    @ViewBuilder private func liftedTrack(laneWidth: CGFloat) -> some View {
        let carry = editorState.trackRowDrag
        if let id = carry.grabbedID,
           let track = editorState.timelineTrackRows.first(where: { $0.id == id }) {
            LiftedTrackRow(session: carry,
                           row: TimelineTrackRow(row: track, inGroup: carry.grabbedInGroup,
                                                 laneWidth: laneWidth,
                                                 isBlade: isBlade, rows: editorState.timelineRowZoom,
                                                 isLifted: true,
                                                 pick: editorState.timelinePickShares.share(of: track))
                               .equatable())
        }
    }

    /// The space the tracks are laid out in, which is what a clip carried up
    /// or down measures its pointer against.
    nonisolated static let tracksSpace = "timelineTracks"
    /// The ruler and tracks, as the wheel sees them: where an open graph
    /// says it is, so ⌥ and the wheel over it zoom its values.
    nonisolated static let wheelSpace = "timelineWheel"

    // MARK: - The scrollers

    /// The column at the right the rows' scroller lives in, and the strip
    /// under the lanes time's lives in: the dock's own right and bottom
    /// margins, which were always there. So a scroller coming, going or
    /// changing size moves nothing, and the dock is the height it always was
    /// (user 2026-09-28).
    static let scrollerWidth: CGFloat = 10
    static let scrollerGap: CGFloat = 1
    static var scrollerStrip: CGFloat { TimelineTimeScroller.height + scrollerGap }

    /// Each row of the tracks' scroll, top and height, at a row zoom: the
    /// same stack the grid lays out, worked out rather than measured, so a
    /// zoom can say where the rows WILL be before they are drawn there.
    static func rowExtents(of editor: EditorState, rows: TimelineRowZoom) -> [TimelineRowExtent] {
        var extents: [TimelineRowExtent] = []
        var top = rowSpacing
        func add(_ height: CGFloat) {
            extents.append(TimelineRowExtent(top: top, height: height))
            top += height + rowSpacing
        }
        if editor.isWritingCaptions { add(laneHeight) }
        for row in editor.timelineRows {
            switch row {
            case .group(_, let isCollapsed, _):
                add(isCollapsed ? TimelineGroupRow.foldedHeight : TimelineGroupRow.openHeight)
            case .track(let track, _):
                add(height(of: track, wordsOpen: editor.isKeyTrackOpen(track.id), rows: rows))
            }
        }
        add(TimelineAddTrackRow.height)
        return extents
    }

    private var tracksScroll: Binding<ScrollPosition> {
        Binding(get: { editorState.timelineTracksScroll },
                set: { editorState.timelineTracksScroll = $0 })
    }
}

// MARK: - The wheel

/// A view that takes the window's wheel through a monitor rather than its own
/// `scrollWheel`, so a walk's wheel, which names no window, can be handed to
/// it at a point instead (`PlaytestHarness.turnWheel`).
@MainActor protocol PlaytestWheelTaker: NSView {
    func takeWheel(_ event: NSEvent, atWindowPoint windowPoint: CGPoint) -> Bool
}

/// Hands the timeline the scroll wheel while the pointer is over it, and the
/// fingers on the trackpad.
///
/// SwiftUI has no wheel event of its own, so this watches the window's wheel
/// events and offers each one that lands inside its own frame. Returning true
/// keeps it; false lets it carry on to the tracks' own vertical scroll.
///
/// Nor does a pinch say which way the fingers spread: SwiftUI and the magnify
/// event both carry one number. The trackpad's touches do, so this view asks
/// the window for them (accepting indirect touches is what makes AppKit send
/// them at all) and hands over every set, in the trackpad's points, for the
/// pinch to steer by (`TimelinePinchSteer`). It never keeps a touch: they go
/// on to wherever they were going.
private struct TimelineWheel: NSViewRepresentable {
    /// The event, and where it landed measured from the top left of the view.
    let handle: (NSEvent, CGPoint) -> Bool
    /// The fingers resting on the trackpad now, in its points.
    let touched: ([CGPoint]) -> Void

    func makeNSView(context: Context) -> WheelView {
        let view = WheelView()
        view.handle = handle
        view.touched = touched
        return view
    }

    func updateNSView(_ view: WheelView, context: Context) {
        view.handle = handle
        view.touched = touched
    }

    static func dismantleNSView(_ view: WheelView, coordinator: ()) { view.stop() }

    final class WheelView: NSView, PlaytestWheelTaker {
        var handle: ((NSEvent, CGPoint) -> Bool)?
        var touched: (([CGPoint]) -> Void)?
        private var monitor: Any?
        private var touchMonitor: Any?

        override init(frame: NSRect) {
            super.init(frame: frame)
            allowedTouchTypes = [.indirect]
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            allowedTouchTypes = [.indirect]
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            touchMonitor = NSEvent.addLocalMonitorForEvents(matching: .gesture) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                self.touched?(Self.fingers(of: event))
                return event
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                let fromTop = CGPoint(x: point.x, y: self.isFlipped ? point.y : self.bounds.height - point.y)
                return self.handle?(event, fromTop) == true ? nil : event
            }
        }

        /// A wheel a walk turns (`PlaytestWheelTaker`): the same handling the
        /// window's monitor gives a person's, at a point in the window.
        func takeWheel(_ event: NSEvent, atWindowPoint windowPoint: CGPoint) -> Bool {
            let point = convert(windowPoint, from: nil)
            guard bounds.contains(point) else { return false }
            let fromTop = CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
            return handle?(event, fromTop) == true
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let touchMonitor { NSEvent.removeMonitor(touchMonitor) }
            monitor = nil
            touchMonitor = nil
        }

        /// The fingers down on the trackpad, a thumb resting on it left out,
        /// placed on the trackpad's own face in its points so a spread across
        /// and a spread down are measured alike on a pad wider than it is tall.
        static func fingers(of event: NSEvent) -> [CGPoint] {
            event.touches(matching: .touching, in: nil)
                .filter { !$0.isResting }
                .map { touch in
                    let size = touch.deviceSize
                    let scale = size.width > 0 && size.height > 0 ? size : CGSize(width: 100, height: 100)
                    return CGPoint(x: touch.normalizedPosition.x * scale.width,
                                   y: touch.normalizedPosition.y * scale.height)
                }
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
    /// The left-right arrows are up because the pointer is on an end of the band.
    @State private var edgeCursorUp = false

    private func showEdgeCursor(_ show: Bool) {
        guard show != edgeCursorUp else { return }
        edgeCursorUp = show
        if show { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
    }

    var body: some View {
        let ruler = editorState.motionStripRuler
        let x = { (ms: Int) in laneWidth * ruler.fraction(ofMS: Double(ms)) }
        VideoKit.TimeRuler(ticks: ruler.ticks(display: editorState.timeDisplay).map {
            VideoKit.RulerTick(fraction: ruler.fraction(ofMS: $0.ms), label: $0.label)
        }, height: height)
        .frame(width: laneWidth)
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if let range = editorState.rulerRangeShown {
                    let drawing = editorState.rulerRangeDraft != nil
                    TimelineInOutSpan(x0: x(range.lowerBound), x1: x(range.upperBound), height: height,
                                      hasIn: drawing || editorState.document?.markInMS != nil,
                                      hasOut: drawing || editorState.document?.markOutMS != nil)
                }
                // A marker in the hand is drawn where it would land.
                let draft = editorState.rulerMarkerDraft
                ForEach(editorState.document?.markers ?? []) { marker in
                    TimelineMarkerFlag()
                        .offset(x: x(draft?.id == marker.id ? draft?.atMS ?? marker.atMS : marker.atMS)
                                    - TimelineMarkerFlag.width / 2)
                }
            }
            .frame(width: laneWidth, height: height, alignment: .topLeading)
            .clipped()
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(scrub)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                let ms = TimelineDock.rulerMS(point.x, laneWidth, ruler)
                pointerMS = ms
                // A hand over the ruler is about to drag the playhead, often:
                // its sound is started now rather than at the press.
                editorState.getScrubSoundReady()
                // Over an end of the band or a marker the pointer says it can
                // be dragged.
                let grip = RulerRange.grip(atMS: ms, playheadMS: editorState.documentTimeMS,
                                           markInMS: editorState.document?.markInMS,
                                           markOutMS: editorState.document?.markOutMS,
                                           markers: editorState.document?.markers ?? [],
                                           reachMS: TimelineDock.rulerGrabMS(laneWidth, ruler))
                switch grip {
                case .inEdge, .outEdge, .marker: showEdgeCursor(true)
                case .playhead, .newRange: showEdgeCursor(false)
                }
            case .ended:
                showEdgeCursor(false)
            }
        }
        .onDisappear { showEdgeCursor(false) }
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
        // The playhead is read inside the bar's own island, never here
        // (`VideoKit.Island`, `docs/design/video.md` 8f).
        VideoKit.Scrubber(fraction: 0, marks: marks,
                          liveFraction: { [editorState] in Double(editorState.documentTimeMS) / length },
                          onScrub: onScrub)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onContinuousHover { phase in
                if case .active(let point) = phase {
                    pointerMS = Int((VideoKit.Scrubber.travel(width).fraction(atX: point.x) * length).rounded())
                    editorState.getScrubSoundReady()
                }
            }
            .contextMenu {
                TimelineRulerMenu(atMS: pointerMS,
                                  reachMS: Int(length * 6 / Double(max(1, VideoKit.Scrubber.travel(width).travel))))
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
/// mark that is set, in the colour the scrub bar's marks wear. Each bracket
/// carries a grip at its foot: the handle that end is dragged by.
private struct TimelineInOutSpan: View {
    let x0: CGFloat
    let x1: CGFloat
    let height: CGFloat
    let hasIn: Bool
    let hasOut: Bool

    static let gripWidth: CGFloat = 6
    static let gripHeight: CGFloat = 11

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(VideoKit.Palette.good.opacity(0.18))
            if hasIn {
                bracket.frame(maxWidth: .infinity, alignment: .leading)
            }
            if hasOut {
                bracket.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: max(2, x1 - x0), height: height)
        .offset(x: x0)
    }

    private var bracket: some View {
        Rectangle().fill(VideoKit.Palette.good).frame(width: 2)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(VideoKit.Palette.good)
                    .frame(width: Self.gripWidth, height: Self.gripHeight)
            }
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
                    // A right click (or a Control-click) on the tracks is
                    // noted, so the menu it opens picks what it landed on.
                    // It never moves the playhead.
                    if event.type == .rightMouseDown || EditorState.isControlClick(event) {
                        TimelineRightPress.offer(at: event.locationInWindow, in: window)
                    }
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


// MARK: - The volume slider

/// The transport's volume slider, beside the speaker: a short track with a
/// knob, styled as a smaller sibling of the scrubber. A click anywhere on it
/// jumps there, a drag is heard as it moves, and the wheel over it turns it
/// up and down (`PlayerVolume`).
///
/// Neutral rather than accent, so it stays quieter than the scrubber it sits
/// in front of; the fill greys out while muted, and the knob sits at the foot.
struct TransportVolumeSlider: View {
    let volume: PlayerVolume
    let onSet: (Double) -> Void
    let onNudge: (Double) -> Void

    @State private var isHovering = false
    @State private var isDragging = false

    static let width: CGFloat = 64
    static let hitHeight: CGFloat = 24
    static let knobWidth: CGFloat = 14
    static let knobHeight: CGFloat = 10

    var body: some View {
        let lifted = isHovering || isDragging
        let x = PlayerVolume.knobCentre(forFraction: volume.sliderFraction,
                                        width: Self.width, knob: Self.knobWidth)
        ZStack(alignment: .leading) {
            Capsule()
                .fill(VideoKit.Palette.lineStrong)
                .frame(height: lifted ? 5 : 4)
            Capsule()
                .fill(VideoKit.Palette.dim)
                .frame(width: max(0, x), height: lifted ? 5 : 4)
            Capsule()
                .fill(LinearGradient(colors: [.white, Color(white: 0.9)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(VideoKit.Palette.edgeLo))
                .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
                .frame(width: Self.knobWidth, height: Self.knobHeight)
                .scaleEffect(lifted ? 1.12 : 1)
                .offset(x: x - Self.knobWidth / 2)
        }
        .frame(width: Self.width, height: Self.hitHeight)
        // The press, the drag and the wheel are taken in AppKit rather than
        // by a SwiftUI drag, which only starts in the app in front: this way
        // the first click on a window you were not in already sets the level,
        // the way the zoom readout answers one (`ZoomReadoutClickLid`).
        .overlay {
            VolumeTrackSurface(
                onPress: { x in
                    isDragging = true
                    onSet(PlayerVolume.fraction(atX: x, width: Self.width, knob: Self.knobWidth))
                },
                onRelease: { isDragging = false },
                onWheel: { event in
                    // Up and right are louder whichever way the Mac scrolls.
                    let sign: Double = event.isDirectionInvertedFromDevice ? -1 : 1
                    let step = PlayerVolume.wheelStep(dx: -sign * Double(event.scrollingDeltaX),
                                                      dy: sign * Double(event.scrollingDeltaY),
                                                      precise: event.hasPreciseScrollingDeltas)
                    if step != 0 { onNudge(step) }
                })
        }
        // What a walk presses is the knob's travel, so "20% across" lands the
        // knob at 20%, which is where a person aiming for it would click.
        .overlay {
            Color.clear
                .playtestControl("Volume Level", detail: "Transport")
                .padding(.horizontal, Self.knobWidth / 2)
                .allowsHitTesting(false)
        }
        .kitHover("Volume Level") { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: lifted)
        .panelHelp("Volume")
        .panelReadout("volume \(volume.percent)%")
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(volume.percent) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onNudge(0.1)
            case .decrement: onNudge(-0.1)
            @unknown default: break
            }
        }
    }
}

/// The slider's hand: presses, drags and the wheel, straight from AppKit.
private struct VolumeTrackSurface: NSViewRepresentable {
    let onPress: (CGFloat) -> Void
    let onRelease: () -> Void
    let onWheel: (NSEvent) -> Void

    func makeNSView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.setAccessibilityElement(false)
        update(view)
        return view
    }

    func updateNSView(_ view: SurfaceView, context: Context) { update(view) }

    private func update(_ view: SurfaceView) {
        view.onPress = onPress
        view.onRelease = onRelease
        view.onWheel = onWheel
    }

    final class SurfaceView: NSView {
        var onPress: ((CGFloat) -> Void)?
        var onRelease: (() -> Void)?
        var onWheel: ((NSEvent) -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { press(event) }
        override func mouseDragged(with event: NSEvent) { press(event) }
        override func mouseUp(with event: NSEvent) { onRelease?() }
        override func scrollWheel(with event: NSEvent) { onWheel?(event) }

        private func press(_ event: NSEvent) {
            onPress?(convert(event.locationInWindow, from: nil).x)
        }
    }
}

/// What a drag on empty track space draws while the hand is down, and the
/// range on some tracks it leaves in hand (`EditorState+TrackRange`): a box
/// with a thin outline for the clips it will pick, or a green band over only
/// the tracks a range crosses, the way the ruler's range is drawn.
struct TimelineLaneBoxView: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat
    let leading: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let box = editorState.laneBoxDraft {
                if box.drawsRange {
                    band(box.range, tracks: box.tracks)
                } else {
                    marquee(box)
                }
            } else if let held = editorState.trackRangeKept {
                band(held.range, tracks: Array(held.trackIDs))
                    .panelReadout("track range \(held.range.lowerBound)ms to \(held.range.upperBound)ms on "
                                  + "\(held.trackIDs.count) tracks")
            } else if let gap = editorState.timelineGapHeld {
                // A picked gap wears the range's band: it is a stretch of
                // time picked on one track (`EditorState+TimelineGap`).
                band(gap.range, tracks: [gap.trackID])
                    .panelReadout("gap \(gap.range.lowerBound)ms to \(gap.range.upperBound)ms")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func x(_ ms: Int) -> CGFloat {
        let fraction = editorState.motionStripRuler.fraction(ofMS: Double(ms))
        return leading + max(0, min(laneWidth, laneWidth * fraction))
    }

    /// The box, from where the hand went down to where it is.
    private func marquee(_ box: EditorState.LaneBox) -> some View {
        let x0 = x(box.range.lowerBound), x1 = x(box.range.upperBound)
        return Rectangle()
            .fill(VideoKit.Palette.accent.opacity(0.10))
            .overlay(Rectangle().strokeBorder(VideoKit.Palette.accent.opacity(0.9), lineWidth: 1))
            .frame(width: max(1, x1 - x0), height: max(1, box.maxY - box.minY))
            .offset(x: x0, y: box.minY)
    }

    /// The range, one green band per track it covers, with its ends marked.
    @ViewBuilder private func band(_ range: Range<Int>, tracks: [UUID]) -> some View {
        let x0 = x(range.lowerBound), x1 = x(range.upperBound)
        ForEach(tracks, id: \.self) { id in
            if let row = editorState.trackDropRows[id], x1 > x0 {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .overlay { Rectangle().fill(VideoKit.Palette.good.opacity(0.16)) }
                    .overlay(alignment: .leading) { Rectangle().fill(VideoKit.Palette.good).frame(width: 1.5) }
                    .overlay(alignment: .trailing) { Rectangle().fill(VideoKit.Palette.good).frame(width: 1.5) }
                    .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(VideoKit.Palette.good.opacity(0.6), lineWidth: 1) }
                    .frame(width: x1 - x0, height: row.maxY - row.minY)
                    .offset(x: x0, y: row.minY)
            }
        }
    }
}

/// **The timeline toggle** at the far right of the transport: the tracks open
/// and closed (`TimelineToggle`), the vertical twin of the title bar's panel
/// toggle, which it matches in size, weight, hover and on/off look. It sits
/// where the panel toggle does, at the trailing edge, so the two read as one
/// family: one puts away the column at the side, this one the tracks below.
/// It replaced the × on the timeline's bar (user 2026-09-29), which went to
/// View mode rather than just putting the tracks down.
private struct TimelineToggleButton: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let isOn = editorState.isMotionStripOpen
        Button {
            editorState.pressTimelineToggle()
        } label: {
            Image(systemName: "rectangle.bottomthird.inset.filled")
                .font(.system(size: 14, weight: .medium))
        }
        .buttonStyle(IconActionButtonStyle(diameter: TitlebarPanelToggle.diameter,
                                           restingTint: isOn ? .primary : .secondary,
                                           keepsLabelFont: true,
                                           squareHitTarget: true))
        .frame(width: TitlebarPanelToggle.diameter, height: TitlebarPanelToggle.diameter)
        .accessibilityLabel(TimelineToggle.tooltip(isOn: isOn))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .toolTip(TimelineToggle.tooltip(isOn: isOn), key: TimelineToggle.shortcut)
        .playtestControl("Timeline Toggle",
                         detail: isOn ? "the transport's timeline toggle, tracks open"
                                      : "the transport's timeline toggle, tracks closed")
        .panelReadout(isOn ? "timeline toggle on" : "timeline toggle off")
    }
}

/// The transport's speed menu, beside play: the seven speeds QuickTime and
/// the web players offer, 1x in every new window (`PlaybackSpeed`). A round
/// button like Go to End beside it, so the bar stays compact (the user,
/// 2026-11-14: "i want it to take less horiz space"), that says the speed the
/// way the web players do: "1x" quiet at rest, and any other speed in a short
/// badge on glass: the speed it is playing at, a J/K/L shuttle's included, and
/// the one Space will play at while stopped. A speaker struck through says
/// that speed plays without sound. It said 1x with a speedometer until
/// 2026-11-15, which the user found "illegible" beside the solid symbols.
private struct PlaybackSpeedMenu: View {
    @Environment(EditorState.self) private var editorState

    /// In front of a speed that plays without sound.
    static let silentSymbol = "speaker.slash.fill"

    var body: some View {
        let chosen = editorState.chosenPlaybackSpeed
        let shuttling = editorState.isDocumentPlaying && editorState.documentPlaybackRate != chosen
        let row = { (speed: Double) in
            VideoKit.Choice.item(PlaybackSpeed.label(speed), isOn: !shuttling && speed == chosen) {
                editorState.setPlaybackSpeed(speed)
            }
        }
        // The speeds that play silent sit under their own heading.
        let choices = PlaybackSpeed.choices.filter { PlaybackSpeed.playsSound(atRate: $0) }.map(row)
            + [.divider, .heading("Without Sound")]
            + PlaybackSpeed.choices.filter { !PlaybackSpeed.playsSound(atRate: $0) }.map(row)
        let reading = editorState.playbackSpeedReading
        return VideoKit.Dropdown(label: "Playback Speed", value: reading,
                                 help: "Playback speed (⇧. faster, ⇧, slower)",
                                 round: .init(text: reading,
                                              isDefault: reading == PlaybackSpeed.label(1),
                                              leadSymbol: editorState.playbackSpeedIsSilent
                                                  ? Self.silentSymbol : nil),
                                 choices: choices)
            .fixedSize()
            .playtestControl("Playback Speed", detail: "Transport")
            .panelReadout("speed \(editorState.playbackSpeedReading)"
                          + (editorState.playbackSpeedIsSilent ? ", silent" : ""))
    }
}

/// The dock's transport (`.transport`): the timecode, play, the scrubber and
/// the volume. A view of its own because it reads the playhead every frame:
/// read by the dock, that rebuilt every track under it.
private struct TimelineTransport: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        // The time is read in an island of its own on every frame; the bar
        // only knows how wide it can be (`VideoKit.Island`).
        VideoKit.TransportBar(current: VideoKit.Timecode.shape(of: editorState.documentLengthTimecode),
                              duration: editorState.documentLengthTimecode,
                              liveCurrent: { [editorState] in editorState.documentTimecode }) {
            // QuickTime's speaker and slider. How loud YOU are listening,
            // not the document's own levels, which are the clips' Volume in
            // the panel. There is no mix meter: the user found it did
            // nothing for them (2026-09-29), and a mix too loud for a file is
            // still held down and said so at export.
            VideoKit.TransportButton(
                symbol: TimelineDock.speakerSymbol(editorState.playerVolume.tier),
                label: editorState.playerVolume.isSilent ? "Unmute" : "Mute") {
                    editorState.toggleDocumentMute()
                }
                .panelHelp(editorState.playerVolume.isSilent ? "Turn the sound back on" : "Turn the sound off")
                .playtestControl("Volume", detail: "Transport")
                .panelReadout(editorState.playerVolume.isSilent ? "sound off" : "sound on")
            TransportVolumeSlider(volume: editorState.playerVolume,
                                  onSet: { editorState.setPlayerVolumeLevel($0) },
                                  onNudge: { editorState.nudgePlayerVolume(by: $0) })
        } controls: {
            VideoKit.TransportButton(symbol: "backward.end.fill", label: "Go to Start") {
                editorState.goToDocumentStart()
            }
            .panelHelp("Go to the start (Home)")
            .playtestControl("Go to Start", detail: "Transport")
            VideoKit.TransportButton(symbol: editorState.showsDocumentPlaying ? "pause.fill" : "play.fill",
                                     label: editorState.showsDocumentPlaying ? "Pause" : "Play",
                                     role: .primary) {
                editorState.toggleDocumentPlayback()
            }
            .panelHelp(editorState.showsDocumentPlaying ? "Pause (space)" : "Play (space)")
            .playtestControl(editorState.showsDocumentPlaying ? "Pause" : "Play", detail: "Transport")
            VideoKit.TransportButton(symbol: "forward.end.fill", label: "Go to End") {
                editorState.goToDocumentEnd()
            }
            .panelHelp("Go to the end (End)")
            .playtestControl("Go to End", detail: "Transport")
            PlaybackSpeedMenu()
        } scrubber: {
            TransportScrubber { fraction, phase in
                scrub(toDocumentFraction: fraction, phase: phase)
                // A double-click beside the marks lets them go, as on the ruler.
                if phase == .ended, (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                    editorState.clearMarksForADoubleClick(atMS: Int((fraction * Double(editorState.documentLengthMS))
                        .rounded()))
                }
            }
            .playtestControl("Scrub", detail: "Transport")
        } trailing: {
            // A player's far end: full screen, as QuickTime has it. Only in
            // View, the player; the editor's transport is the mock's.
            if editorState.isWatching {
                // The arrows point the way a press goes: out to the edges, or
                // back in once the window fills the screen.
                VideoKit.TransportButton(symbol: editorState.isWindowFullScreen
                                            ? "arrow.down.right.and.arrow.up.left"
                                            : "arrow.up.left.and.arrow.down.right",
                                         label: "Full Screen") {
                    editorState.toggleWindowFullScreen()
                }
                .panelHelp(PlayerFullScreen.tooltip)
                .playtestControl("Full Screen", detail: "Transport")
                .transition(.opacity)
            }
            TimelineToggleButton()
        }
        .tutorialAnchor(.video(.transport))
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
}

/// The red line across every track, and only while its moment is on
/// screen: a zoomed timeline with the playhead elsewhere has no playhead
/// to draw, rather than one pinned to its edge.
/// A view of its own, because it moves with every step of the playhead: drawn
/// inside the dock's tracks, each step rebuilt all of them. And drawn with
/// layers, because even as a view of its own every step was a pass over the
/// whole window (`VideoKit.LayerIsland`). It is `VideoKit.Playhead`, the same
/// line and head in the same colour.
private struct TimelinePlayheadLine: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat

    var body: some View {
        VideoKit.LayerIsland({ [editorState, laneWidth] in Spot(editorState, laneWidth: laneWidth) }) {
            [laneWidth] spot, canvas in
            Self.paint(spot, laneWidth: laneWidth, on: canvas)
        }
    }

    @MainActor private static func paint(_ spot: Spot, laneWidth: CGFloat, on canvas: VideoKit.IslandCanvas) {
        let line = canvas.layer("line") { CALayer() }
        let head = canvas.layer("head") { CAShapeLayer() }
        let width = VideoKit.Metrics.playheadWidth
        let height = canvas.bounds.height
        let x = laneWidth * CGFloat(min(max(0, spot.fraction ?? 0), 1))
        line.isHidden = spot.fraction == nil
        head.isHidden = spot.fraction == nil
        line.backgroundColor = canvas.color(VideoKit.Palette.crit)
        line.frame = CGRect(x: x - width / 2, y: 0, width: width, height: height)
        // The head stands 2pt proud of the top, point down, 12 by 6.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x - 6, y: height + 2))
        path.addLine(to: CGPoint(x: x + 6, y: height + 2))
        path.addLine(to: CGPoint(x: x, y: height - 4))
        path.closeSubpath()
        head.path = path
        head.fillColor = canvas.color(VideoKit.Palette.crit)
        #if PHOTONZ_PLAYTEST
        // Where a walk reads the line and its time (`PlaytestRulerMark`,
        // `panelReadout`), moved with it.
        guard PlaytestMarkers.areHung else { return }
        let mark = canvas.subviews.compactMap { $0 as? PlaytestRulerMarkView }.first ?? {
            let made = PlaytestRulerMarkView(role: .playhead(fraction: 0))
            canvas.addSubview(made)
            return made
        }()
        let readout = canvas.subviews.compactMap { $0 as? ReadoutAnchorView }.first ?? {
            let made = ReadoutAnchorView(text: "")
            canvas.addSubview(made)
            return made
        }()
        let frame = CGRect(x: x - 6, y: 0, width: 12, height: height)
        for view in [mark, readout] as [NSView] {
            view.isHidden = spot.fraction == nil
            if view.frame != frame { view.frame = frame }
        }
        mark.role = .playhead(fraction: spot.fraction ?? 0)
        readout.text = "playhead \(spot.timecode)"
        #endif
    }

    /// Where the line is, to the half point, or nil off screen; and the time
    /// it is at, as a walk reads it.
    private struct Spot: Equatable {
        var fraction: Double?
        var timecode: String

        @MainActor init(_ editorState: EditorState, laneWidth: CGFloat) {
            // Not read at all behind View, so playing there never draws the
            // tracks out of sight again (`AsleepBehindView`).
            if editorState.editPiecesAsleep {
                fraction = nil
                timecode = ""
                return
            }
            let now = editorState.motionStripRuler.fraction(ofMS: Double(editorState.documentTimeMS))
            let halves = max(1, Double(laneWidth) * 2)
            fraction = now >= -0.001 && now <= 1.001 ? (now * halves).rounded() / halves : nil
            #if PHOTONZ_PLAYTEST
            timecode = editorState.documentTimecode
            #else
            timecode = ""
            #endif
        }
    }
}


/// One row of the grid, a track or a group of them.
///
/// Built again only when something handed to it changes. Built straight in
/// the grid's list instead, every row of the list was made again whenever the
/// grid was: for every edit and every pick, and in the edit's own pass as
/// well, since what a list makes for each row is made outside the body that
/// holds it, where that body's late reading does not reach
/// (`readingALatePass`), and each asked the document whether its track has
/// key lanes. Fifty rows of it, on a 50 track timeline, were some 6 ms of an
/// edit's own pass and again of the one after (2026-11-24).
struct TimelineGridRow: View, Equatable {
    @Environment(EditorState.self) private var editorState
    let row: TimelineRowModel
    let laneWidth: CGFloat
    let isBlade: Bool
    let rows: TimelineRowZoom
    let pick: TrackPickShare
    let gates: Bool
    /// Built with the list; only asked as the row is made.
    let startsNear: Bool
    let session: TrackRowDragSession

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.row == b.row && a.laneWidth == b.laneWidth && a.isBlade == b.isBlade && a.rows == b.rows
            && a.pick == b.pick && a.gates == b.gates && a.session === b.session
    }

    var body: some View {
        Group {
            switch row {
            case .group(let group, let isCollapsed, let tracks):
                TimelineGroupRow(group: group, isCollapsed: isCollapsed, tracks: tracks, laneWidth: laneWidth)
            case .track(let track, let inGroup):
                TimelineRowInSight(row: track, height: TimelineDock.height(of: track, rows: rows),
                                   laneHeight: rows.height(track.restingLaneHeight),
                                   gates: gates && readingForATrackRow(track.id) {
                                       TimelineDock.isOneLane(track, editorState)
                                   },
                                   startsNear: startsNear,
                                   makesRoomFirst: gates
                                       && editorState.timelineRowChores.makesRoomFirst(track)) {
                    TimelineTrackRow(row: track, inGroup: inGroup, laneWidth: laneWidth, isBlade: isBlade,
                                     rows: rows, pick: pick)
                        .equatable()
                }
            }
        }
        // Where each row stands, measured before it is moved aside, for a
        // track carried by its header.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(TimelineDock.tracksSpace))
        } action: { frame in
            session.rowFrames[row.id] = frame
            editorState.revealOpenedTimelineRow(row.id, at: frame)
        }
        .modifier(TrackRowDragPlacement(id: row.id, session: session))
    }
}

/// The tracks the timeline last drew, drawn again unchanged in the pass of an
/// edit marked by `EditorState.catchUpOnTheNextPass`, so a track that edit
/// brings (a new title's) arrives in the next pass with the rest of the
/// timeline rather than in the edit's own frame. Reading inside
/// `readingALatePass` alone does not hold it: the grid is drawn again in
/// that pass for other reasons too (the text editor closing), and a read
/// there sees the document as it is.
@Observable @MainActor final class LateTrackRows {
    @ObservationIgnored private var last: [TimelineRowModel]?
    /// Moved on when the sounds' new numbers are due to be drawn.
    private var numbersRevision = 0
    @ObservationIgnored private var numbersAreDue = false
    @ObservationIgnored private var numbersTask: Task<Void, Never>?

    func read(_ editorState: EditorState,
              _ fresh: () -> [TimelineRowModel]) -> [TimelineRowModel] {
        // Watched in every case, so the pass after brings the tracks round.
        _ = editorState.latePassRevision
        _ = numbersRevision
        if editorState.isCatchingUpOnTheNextPass, let last { return last }
        var now = readingALatePass(fresh)
        if let last, now.count > TimelineRowsInSight.tallEdit { keepNumbers(of: last, in: &now) }
        last = now
        return now
    }

    /// A clip with sound that comes or goes renumbers the sound of every
    /// track under it, which picks its colour: each of them was built again,
    /// in the same pass as the row that came, 17 to 22 ms on a 50 track
    /// timeline (2026-11-25). They wear the new one a few frames later.
    private func keepNumbers(of last: [TimelineRowModel], in now: inout [TimelineRowModel]) {
        guard !numbersAreDue else { return numbersAreDue = false }
        let before = Dictionary(last.compactMap { row in row.trackRow.map { ($0.id, $0.soundNumber) } },
                                uniquingKeysWith: { a, _ in a })
        var kept = false
        for index in now.indices {
            guard case .track(var row, let inGroup) = now[index], let was = before[row.id],
                  was != row.soundNumber else { continue }
            row.soundNumber = was
            now[index] = .track(row, inGroup: inGroup)
            kept = true
        }
        guard kept, numbersTask == nil else { return }
        numbersTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self else { return }
            self.numbersTask = nil
            self.numbersAreDue = true
            self.numbersRevision += 1
        }
    }
}

// MARK: - The tracks area's height, read on its own

/// What `TimelineDock` holds of the tracks area's height: the window, the top
/// edge where a hand or the settings left it, and the transport and bar above
/// the grid. The rest, how tall the tracks themselves are, is read from the
/// editor where the height is applied (`TimelineGridHeight`).
struct TimelineDockFit: Equatable {
    let windowHeight: CGFloat
    let chosen: CGFloat?
    let isChosen: Bool
    let chrome: CGFloat

    @MainActor
    func sizing(_ editorState: EditorState) -> TimelineDockHeight {
        TimelineDockHeight(chrome: chrome, floor: TimelineDock.bodyFloor(editorState), windowHeight: windowHeight)
    }

    /// Where the top edge left it, or with nothing chosen, as tall as the
    /// tracks it holds and no taller (`TimelineDockHeight`).
    @MainActor
    func bodyHeight(_ editorState: EditorState) -> CGFloat {
        let natural = TimelineDock.naturalBodyHeight(editorState)
        guard windowHeight > 0 else { return natural }
        return sizing(editorState).body(chosen: chosen, natural: natural)
    }
}

/// The grid's height, in a view of its own. It is worked out from the tracks,
/// which read the document, and read in the dock's body it re-ran that body
/// and its whole grid in the frame of every edit, a trim that changes no
/// track's height included. Here only this re-runs, and the grid it is
/// handed is the same value, so nothing under it is built again.
struct TimelineGridHeight: ViewModifier {
    @Environment(EditorState.self) private var editorState
    let fit: TimelineDockFit

    func body(content: Content) -> some View {
        // With the tracks themselves, a pass late for an edit marked so.
        content.frame(height: readingALatePass { fit.bodyHeight(editorState) })
    }
}

#if PHOTONZ_PLAYTEST
/// How tall the tracks area is and whether the person chose it, for a walk.
private struct TimelineHeightReadout: View {
    @Environment(EditorState.self) private var editorState
    let fit: TimelineDockFit

    var body: some View {
        Color.clear
            .panelReadout("timeline \(Int(readingALatePass { fit.bodyHeight(editorState) }.rounded())) tall, "
                          + (fit.isChosen ? "chosen" : "default"))
    }
}
#endif

/// Reads the shape of every sound, so an export holds the mix down by what
/// the files really peak at rather than by the safe guess of full scale
/// (`AudioHeadroom`), and has the sound engine made, so the first press of
/// play is not the moment it gets built. In a view of its own: the number of
/// sounds is worked out from the whole document, and read in the dock's body
/// it re-ran that body in the frame of every edit.
private struct TimelineSoundShapesReader: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        Color.clear
            // A pass late for an edit, which has its own frame to make: what
            // plays is worked out from every clip there is.
            .task(id: readingALatePass { editorState.audioPlan.count }) {
                if editorState.documentHasAudio {
                    editorState.loadSoundShapes()
                    editorState.readyAudio()
                }
            }
    }
}
