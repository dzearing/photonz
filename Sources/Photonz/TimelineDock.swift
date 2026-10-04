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

    /// The editor window's height, which caps how tall the top edge can pull
    /// the dock (`TimelineDockHeight`).
    let windowHeight: CGFloat
    /// The tracks area's height as the top edge last left it, or 0 for the
    /// height the dock always had. The person's, across every recording.
    @AppStorage(EditorState.timelineHeightKey) private var storedHeight = TimelineDockHeight.defaultStored
    /// The tracks area's height while the edge is in hand: live, and only
    /// written to the settings when the drag ends.
    @State private var draggedBody: CGFloat?
    /// Where it was when the drag began.
    @State private var dragStartBody: CGFloat?
    /// The transport and the timeline's bar, measured: the part of the dock a
    /// drag on its edge never changes.
    @State private var transportHeight: CGFloat = 0
    @State private var localBarHeight: CGFloat = 0

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
                    .panelReadout("timeline \(Int(bodyHeight.rounded())) tall, "
                                  + (TimelineDockHeight.chosen(stored: storedHeight) == nil ? "default" : "chosen"))
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
        .task(id: editorState.audioPlan.count) {
            if editorState.documentHasAudio {
                editorState.loadSoundShapes()
                editorState.readyAudio()
            }
        }
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
            // No zoom buttons (user 2026-09-28: "super weird as buttons"). A
            // pinch on the tracks zooms, = and - step, ⇧Z fits, and the
            // ruler's right-click has Zoom to Fit.
            Spacer(minLength: 8)
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
            } else if editorState.isTimelineOpenedOut {
                Text(editorState.timelineWindowReading)
                    .font(.system(size: 10, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(VideoKit.Palette.faint)
                    .lineLimit(1)
                    .fixedSize()
            }
            if editorState.timelineFileHover == nil, editorState.timelineTransitionHover == nil { keyBar }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(VideoKit.Palette.edgeLo).frame(height: 1)
        }
        .panelReadout("timeline \(editorState.timelineWindowReading)"
                      + ", " + Self.toolReading(editorState.timelineTool)
                      + (editorState.isTimelineSnapping ? ", snapping" : ", snapping off"))
    }

    static func toolReading(_ tool: TimelineTool) -> String {
        switch tool {
        case .select: return "select"
        case .trackSelectForward: return "track select forward"
        case .range: return "range"
        case .blade: return "blade"
        }
    }

    /// The right end of the bar: Easing (`#easeSel`), only while keys are
    /// picked, because it is the curve THEY move through. The same six eases
    /// a key's right-click offers, so the question has one list of answers.
    /// The mock's playhead readout (`.kfread`) stood before it until the user
    /// turned it down on 2026-09-25: the time is in the transport, the value
    /// in the panel, and a bar of controls carries no sentence about state.
    @ViewBuilder private var keyBar: some View {
        if editorState.keySelection != nil {
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
    }

    /// The ease whose name is widest. The face is sized by a hidden copy of
    /// itself showing this one, so it reads every ease whole and keeps one
    /// width whatever the picked keys read. It was a fixed 124 until
    /// 2026-09-27, a few points short of "Ease In and Out" ("Ease In and...").
    static let widestEase: String = {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        return (KeyEase.allCases.map(\.title) + ["Mixed"])
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
    private var showsCaptionTrackBar: Bool {
        editorState.timelineTrackRows.contains { $0.isCaptions && !$0.clips.isEmpty }
    }

    private var grid: some View {
        // Edit mode arriving from View holds this space empty for a pass
        // (`EditModeArrival`); its height is the tracks' own, so nothing moves.
        Group {
        if editorState.editArrival.showsTimeline {
        GeometryReader { geo in
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
                    rulerRow(laneWidth: laneWidth)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                            editorState.timelineRulerFrame = $0
                        }
                    ScrollView(.vertical) {
                        let order = editorState.timelineTrackRows.map(\.id)
                        VStack(alignment: .leading, spacing: Self.rowSpacing) {
                            if editorState.isWritingCaptions {
                                TimelineCaptionsListeningRow(laneWidth: laneWidth)
                            }
                            let rows = editorState.timelineRowZoom
                            // Edit mode arriving from View draws its rows a
                            // pass after the dock starts to slide
                            // (`EditModeArrival`).
                            let carry = editorState.trackRowDrag
                            ForEach(editorState.editArrival.showsTrackRows
                                    ? editorState.timelineRows : []) { row in
                                Group {
                                    switch row {
                                    case .group(let group, let isCollapsed, let tracks):
                                        TimelineGroupRow(group: group, isCollapsed: isCollapsed,
                                                         tracks: tracks, laneWidth: laneWidth)
                                    case .track(let track, let inGroup):
                                        TimelineTrackRow(row: track, inGroup: inGroup,
                                                         index: order.firstIndex(of: track.id) ?? 0,
                                                         trackCount: order.count,
                                                         laneWidth: laneWidth, isBlade: isBlade,
                                                         rows: rows)
                                        .equatable()
                                    }
                                }
                                // Where each row stands, measured before it is
                                // moved aside, for a track carried by its header.
                                .onGeometryChange(for: CGRect.self) { proxy in
                                    proxy.frame(in: .named(Self.tracksSpace))
                                } action: { frame in
                                    if !carry.isCarrying { carry.rowFrames[row.id] = frame }
                                }
                                .modifier(TrackRowDragPlacement(id: row.id, session: carry))
                            }
                            TimelineAddTrackRow(laneWidth: laneWidth)
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
                        .onDrop(of: TimelineFileDropDelegate.types, delegate: TimelineFileDropDelegate(editorState: editorState))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                            editorState.timelineTracksFrame = frame
                            editorState.timelineLaneWidth = laneWidth
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    // Its own scroller, in the column kept for it, rather than
                    // the system's: an overlay scroller that comes and goes in
                    // space nothing else is using can never move a row.
                    .scrollIndicators(.never)
                    .scrollPosition(tracksScroll)
                    .onScrollGeometryChange(for: TimelineTracksScrollGeometry.self) { geometry in
                        TimelineTracksScrollGeometry(offsetY: geometry.contentOffset.y + geometry.contentInsets.top,
                                                     contentHeight: geometry.contentSize.height,
                                                     viewportHeight: geometry.containerSize.height)
                    } action: { _, now in
                        editorState.timelineTracksScrollGeometry = now
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
                .background {
                    TimelineWheel(handle: { event, point in wheel(event, at: point, laneWidth: laneWidth) },
                                  touched: { editorState.timelinePinchTouched($0) })
                }
                // Time's scroller, under the lanes, in a strip that is always
                // there: at Fit it is empty, opened out it carries the window.
                TimelineTimeScroller(laneWidth: laneWidth)
                    .padding(.leading, Self.lanesLeading)
                    .frame(height: Self.scrollerStrip, alignment: .bottom)
            }
            .panelReadout(editorState.timelineRowsReading)
        }
        } else {
            Color.clear
        }
        }
        .frame(height: bodyHeight)
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
    /// scrubs, on an end of the marked stretch it moves that end, anywhere
    /// else a drag draws a range and a click moves the playhead.
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
    /// the thing in hand, so it reads as a stretch of every track. Marks set
    /// with I and O stay on the ruler alone, as in Premiere.
    @ViewBuilder private func rangeWash(laneWidth: CGFloat) -> some View {
        if let range = editorState.rulerRangeDraft ?? editorState.rulerRangeHeld {
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
    /// Premiere, and ⌘ and the wheel grow the rows about it. Anything else is
    /// left to the tracks, which scroll up and down.
    private func wheel(_ event: NSEvent, at point: CGPoint, laneWidth: CGFloat) -> Bool {
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        let dx = event.scrollingDeltaX * scale
        let dy = event.scrollingDeltaY * scale
        let flags = event.modifierFlags
        if flags.contains(.option) || flags.contains(.command) {
            let factor = exp(Double(dy) / 200)
            editorState.pinchTimeline(by: factor, laneX: point.x - Self.lanesLeading, laneWidth: laneWidth,
                                      viewportY: point.y - Self.rulerHeight,
                                      axes: flags.contains(.command) ? .rows : .time)
            return true
        }
        let sideways = abs(dx) > abs(dy) ? dx : (event.modifierFlags.contains(.shift) ? dy : 0)
        guard sideways != 0, editorState.isTimelineOpenedOut else { return false }
        let ms = editorState.motionStripRuler.msSpanning(fraction: Double(-sideways / laneWidth))
        editorState.panTimeline(byMS: ms)
        return true
    }

    /// The tracks area's height: where the top edge left it, or with nothing
    /// chosen, as tall as the tracks it holds and no taller. Inside one track
    /// and about 70% of the window either way (`TimelineDockHeight`).
    private var bodyHeight: CGFloat {
        guard windowHeight > 0 else { return naturalBodyHeight }
        return sizing.body(chosen: draggedBody ?? TimelineDockHeight.chosen(stored: storedHeight),
                           natural: naturalBodyHeight)
    }

    private var sizing: TimelineDockHeight {
        // The grid sits 6 under the bar (`grid`'s top padding).
        TimelineDockHeight(chrome: transportHeight + localBarHeight + 6,
                           floor: bodyFloor, windowHeight: windowHeight)
    }

    /// One track and no less: the ruler, one lane, and the scroller strip.
    private var bodyFloor: CGFloat {
        let captionBar = showsCaptionTrackBar ? CaptionTrackBarView.height + 4 : 0
        return captionBar + Self.rulerHeight + Self.soundLaneHeight + 2 * Self.rowSpacing + Self.scrollerStrip
    }

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
    private var naturalBodyHeight: CGFloat {
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
                rows += Self.height(of: track, wordsOpen: editorState.isKeyTrackOpen(track.id))
                    + Self.rowSpacing
            }
        }
        rows += TimelineAddTrackRow.height + Self.rowSpacing
        let content = Self.rulerHeight + rows + Self.rowSpacing
        let captionBar = showsCaptionTrackBar ? CaptionTrackBarView.height + 4 : 0
        return captionBar + min(Self.bodyCeiling, content) + Self.scrollerStrip
    }

    /// One track's full height: its lane, the lanes of anything moving on
    /// its clips, and the rows of the parts inside them.
    static func height(of track: TimelineTrackRowModel, wordsOpen: Bool = true,
                       rows: TimelineRowZoom = .compact) -> CGFloat {
        let lane = rows.height(track.carriesSound ? soundLaneHeight : laneHeight)
        let motionLanes = track.clips.reduce(0) { $0 + $1.lanes.count }
        let inner = track.inner.reduce(CGFloat(0)) { total, group in
            total + 3 + rows.height(group.isSound ? soundLaneHeight : laneHeight)
                + CGFloat(group.lanes.count) * (MotionStripView.laneHeight + 3)
        }
        let words = track.isCaptions && !track.clips.isEmpty && wordsOpen ? CaptionWordsLane.height + 3 : 0
        let zooms = CGFloat(track.zoomedClips.count) * (ZoomLane.height + 3)
        return lane + CGFloat(motionLanes) * (MotionStripView.laneHeight + 3) + inner + words + zooms
    }

    /// The track lifted by its header, drawn over the others: the real row,
    /// built again for the drag, never answering the pointer.
    @ViewBuilder private func liftedTrack(laneWidth: CGFloat) -> some View {
        let carry = editorState.trackRowDrag
        if let id = carry.grabbedID,
           let track = editorState.timelineTrackRows.first(where: { $0.id == id }) {
            let order = editorState.timelineTrackRows.map(\.id)
            LiftedTrackRow(session: carry,
                           row: TimelineTrackRow(row: track, inGroup: carry.grabbedInGroup,
                                                 index: order.firstIndex(of: id) ?? 0,
                                                 trackCount: order.count, laneWidth: laneWidth,
                                                 isBlade: isBlade, rows: editorState.timelineRowZoom,
                                                 isLifted: true)
                               .equatable())
        }
    }

    /// The space the tracks are laid out in, which is what a clip carried up
    /// or down measures its pointer against.
    nonisolated static let tracksSpace = "timelineTracks"

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

    final class WheelView: NSView {
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
        VideoKit.TimeRuler(ticks: ruler.secondTicks.map {
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
            switch phase {
            case .active(let point):
                let ms = TimelineDock.rulerMS(point.x, laneWidth, ruler)
                pointerMS = ms
                // Over an end of the band the pointer says it can be dragged.
                let grip = RulerRange.grip(atMS: ms, playheadMS: editorState.documentTimeMS,
                                           markInMS: editorState.document?.markInMS,
                                           markOutMS: editorState.document?.markOutMS,
                                           reachMS: TimelineDock.rulerGrabMS(laneWidth, ruler))
                showEdgeCursor(grip == .inEdge || grip == .outEdge)
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
            } else if let held = editorState.trackRangeHeld {
                band(held.range, tracks: Array(held.trackIDs))
                    .panelReadout("track range \(held.range.lowerBound)ms to \(held.range.upperBound)ms on "
                                  + "\(held.trackIDs.count) tracks")
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

/// The dock's transport (`.transport`): the timecode, play, the scrubber and
/// the volume. A view of its own because it reads the playhead every frame:
/// read by the dock, that rebuilt every track under it.
private struct TimelineTransport: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VideoKit.TransportBar(current: editorState.documentTimecode
                                  + (editorState.shuttleReading.map { "  \($0)" } ?? ""),
                              duration: editorState.documentLengthTimecode) {
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
                VideoKit.TransportButton(symbol: "arrow.up.left.and.arrow.down.right",
                                         label: "Full Screen") {
                    editorState.hostWindow?.toggleFullScreen(nil)
                }
                .panelHelp("Full screen (⌃⌘F)")
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
/// inside the dock's tracks, each step rebuilt all of them.
private struct TimelinePlayheadLine: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat

    var body: some View {
        // Not read at all behind View, so playing there never draws the
        // tracks out of sight again (`AsleepBehindView`).
        let fraction = editorState.editPiecesAsleep
            ? -1 : editorState.motionStripRuler.fraction(ofMS: Double(editorState.documentTimeMS))
        if fraction >= -0.001, fraction <= 1.001 {
            VideoKit.Playhead(fraction: fraction)
                .frame(width: laneWidth)
                .panelReadout("playhead \(editorState.documentTimecode)")
        }
    }
}
