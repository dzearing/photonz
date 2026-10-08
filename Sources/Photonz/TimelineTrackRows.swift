import AppKit
import PhotonzCore
import SwiftUI

// MARK: - One track

/// One track (`.track` in `docs/design/mocks/pages/video.html`): its name in
/// the gutter and every clip on it in the lane, with the lanes of anything
/// moving on those clips underneath.
///
/// The header is the mock's icon and name. Its switches (hide or mute, solo,
/// lock) come up while the pointer is over the track, and any that is ON stays
/// up, so a track that is not playing always says why. Picking a track does
/// not bring them up. Where each thing sits is `TrackHeaderLayout`: the
/// switches and the key keep to the right edge, 4 points apart, and the name
/// takes what is left and shortens before anything touches (user 2026-10-03).
/// Every one of them is also on the header's right-click menu, with rename,
/// group, add and delete, the way Premiere puts a track's verbs on its header.
struct TimelineTrackRow: View {
    @Environment(EditorState.self) private var editorState
    let row: TimelineTrackRowModel
    let inGroup: Bool
    /// Where this track is in the whole list, for the line a drop between two
    /// tracks draws.
    let index: Int
    let trackCount: Int
    let laneWidth: CGFloat
    let isBlade: Bool
    /// How tall the rows are zoomed to: the lane and its header grow together.
    var rows: TimelineRowZoom = .compact
    /// The copy of the track drawn lifted over the others while its header is
    /// carried (`TrackRowDragSession`). It says nothing about where the track
    /// is: the track itself, standing invisible in its slot, still does.
    var isLifted = false

    @State private var isHovered = false
    @State private var draftName = ""
    @FocusState private var isNaming: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var track: DocumentTrack { row.track }

    var body: some View {
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.trackRow)
        #endif
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: TimelineDock.gap) {
                header
                lane
            }
            .frame(height: laneHeight)
            .playtestField("Track \(track.name)")
            if row.isCaptions, !row.clips.isEmpty, editorState.isKeyTrackOpen(track.id) {
                HStack(spacing: TimelineDock.gap) {
                    CaptionWordsLane.header(indent: indent)
                    // Only the cues in the window: a word never leaves its
                    // cue, and reading all 170 cues' words on every step of
                    // the playhead to throw most of them away was a cost of
                    // every far jump (`first-long-jump-when-zoomed-in-walk`).
                    CaptionWordsLane(cueIDs: Self.cuesInSight(row.clips, ruler: editorState.motionStripRuler),
                                     laneWidth: laneWidth)
                }
                .frame(height: CaptionWordsLane.height)
            }
            // A picked clip played faster or slower than recorded shows how
            // long it was at 100%, right under it (`ClipSourceLane`). Only the
            // picked clips are asked, so a track of plain clips reads nothing.
            ForEach(row.clips.filter { editorState.isLayerSelected($0.layerID) }) { clip in
                ClipSourceLane(layerID: clip.layerID, laneWidth: laneWidth, indent: indent)
            }
            // A keyed value is a lane of keys, opened and closed by the arrow
            // on the header (`KeyLanesView`); anything else that moves keeps
            // its timing bar. Which values are keyed does not change while a
            // bar is dragged, so the row asks the document and is not woken by
            // every move of the hand. Only the clips with something under them
            // are walked: a Captions track's 170 cues have nothing, and an item
            // each for them was rebuilt on every far jump of the playhead.
            let keyedByClip = editorState.keyedMotionsAtRest(layerIDs: row.clips.map(\.layerID))
            ForEach(row.clips.filter {
                !$0.lanes.isEmpty || keyedByClip[$0.layerID] != nil || row.zoomedClips.contains($0.layerID)
            }) { clip in
                let keyed = keyedByClip[clip.layerID] ?? []
                if !keyed.isEmpty, editorState.isKeyTrackOpen(track.id) {
                    KeyLanesView(layerID: clip.layerID, layerName: clip.layerName, laneWidth: laneWidth,
                                 indent: indent, isLocked: track.isLocked)
                }
                ForEach(clip.lanes.filter { !keyed.contains($0.motionID) }) { lane in
                    MotionStripLaneView(lane: lane, layerName: clip.layerName, laneWidth: laneWidth,
                                        labelWidth: TimelineDock.lanesLeading)
                }
                // Its zooms, one bar each, under the clip they frame.
                if row.zoomedClips.contains(clip.layerID) {
                    ZoomLane(layerID: clip.layerID, laneWidth: laneWidth, indent: indent,
                             isLocked: track.isLocked)
                }
            }
            ForEach(row.inner) { group in
                TimelineInnerRow(group: group, laneWidth: laneWidth, isBlade: isBlade,
                                 isLocked: track.isLocked, rows: rows)
            }
        }
        .playtestHover("Track \(track.name)") { isHovered = $0 }
    }

    /// The clips whose bars reach into the timeline's window, and any without
    /// a bar.
    static func cuesInSight(_ clips: [MotionStripGroup], ruler: MotionStripRuler) -> [UUID] {
        let start = ruler.startMS
        let end = ruler.startMS + ruler.spanMS
        return clips.filter { clip in
            guard let bar = clip.bar else { return true }
            return Double(bar.outMS) >= start && Double(bar.inMS) <= end
        }.map(\.layerID)
    }

    /// The cues on a Captions track that nobody is working on: not picked
    /// (unless its drag began on the painted layer), not being retyped or
    /// trimmed, and nothing keyed or drifting on it that the full bar draws.
    private var paintedCues: [MotionStripGroup] {
        // A picked track lights up every cue on it, which the painted layer
        // cannot draw.
        guard row.isCaptions, row.cuesArePlain, !isHeld else { return [] }
        let carried = editorState.carriedCaptionCueID
        let picked = editorState.selectedLayerID
        let renaming = editorState.renamingClipID
        let trimming = editorState.trimmingLayerID
        return row.clips.filter { clip in
            guard clip.bar != nil, clip.lanes.isEmpty else { return false }
            if clip.layerID == carried { return true }
            return clip.layerID != picked && clip.layerID != renaming && clip.layerID != trimming
        }
    }

    /// Track Select Forward in hand (A): a press on a clip picks it and
    /// everything after it, and the edit points are no longer in the way.
    private var isTrackSelect: Bool { editorState.timelineTool == .trackSelectForward }
    private var isRangeTool: Bool { editorState.timelineTool == .range }

    private var laneHeight: CGFloat {
        rows.height(row.carriesSound ? TimelineDock.soundLaneHeight : TimelineDock.laneHeight)
    }

    /// This track is the thing in hand: picked on its header, nothing else
    /// picked. Its header and lane light up as one, with every clip on it.
    private var isHeld: Bool { editorState.tracksInHand.contains(track.id) }

    private var isPicked: Bool {
        editorState.selectedTrackIDs.contains(track.id)
            || row.clips.contains { editorState.isLayerSelected($0.layerID) }
            || row.linked.contains { editorState.isLayerSelected($0.layerID) }
    }

    // MARK: The header

    /// Where everything in the header goes at the column's width right now.
    private var layout: TrackHeaderLayout {
        TrackHeaderLayout(width: TimelineDock.gutter, inGroup: inGroup, hasTwist: hasKeyLanes || hasWordsLane,
                          switches: shownSwitches, hasKey: keyLayerID != nil, wantsIcon: !showsAllSwitches)
    }

    private var header: some View {
        let layout = layout
        return HStack(spacing: 0) {
            if editorState.renamingTrackID == track.id {
                nameField
            } else {
                // The name gives the switches room rather than sitting under
                // them, so a click on the name is always a click on the name.
                // A button rather than a pair of tap gestures: the first click
                // picks the track at once, and the second of a double click
                // (AppKit's own click count) opens the name for typing.
                Button {
                    let event = NSApp.currentEvent
                    if (event?.clickCount ?? 1) >= 2 {
                        beginRenaming()
                    } else {
                        let flags = event?.modifierFlags ?? NSEvent.modifierFlags
                        editorState.pickTrack(track.id,
                                              extending: flags.contains(.shift) || flags.contains(.command))
                    }
                } label: {
                    // While the switches are up the icon gives the name its
                    // room: the switches already say what kind of track it is.
                    // It gives way too when the column is too narrow for it.
                    VideoKit.TrackHeader(title: track.name, symbol: layout.showsIcon ? symbol : nil,
                                         width: layout.nameWidth,
                                         uppercase: false,
                                         // Written by the app off the sound: the
                                         // mock's sparkle and lavender.
                                         isAutomatic: row.isCaptions && layout.showsIcon,
                                         isSelected: isPicked)
                        .padding(.leading, layout.nameX)
                        .frame(height: laneHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .playtestControl("Track \(track.name)",
                                 detail: Self.nameFits(track.name, in: layout.textWidth)
                                     ? "Timeline" : "Timeline, name shortened")
                if !layout.switchXs.isEmpty {
                    Color.clear.frame(width: TrackHeaderLayout.gap)
                    switches
                }
                if let keyLayerID {
                    Color.clear.frame(width: TrackHeaderLayout.gap)
                    TrackKeyDiamond(layerID: keyLayerID, trackName: track.name)
                }
            }
        }
        .frame(width: TimelineDock.gutter, height: laneHeight, alignment: .leading)
        .overlay(alignment: .leading) { twist.padding(.leading, layout.twistX ?? indent) }
        .background { if isHeld { heldFill } }
        .contentShape(Rectangle())
        // Press and move: the whole track lifts and rides the pointer up and
        // down, and the others make room (`TrackRowDragSession`). Alongside
        // the name's button rather than under it: a button holds the press
        // until it is let go, and a plain gesture under one heard nothing of
        // the drag until the mouse came up, so the track jumped instead of
        // lifting. A press only becomes a carry once it moves four points, so
        // a click is still a click.
        .simultaneousGesture(carryGesture, including: Experiments.shared.draggedLayerLiftsEnabled && !isLifted
                             ? .all : .subviews)
        .contextMenu { TimelineTrackMenu(track: track, index: index) }
        .help(track.name)
        .accessibilityLabel("Track \(track.name)")
        .panelReadout(readout)
    }

    private var carryGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(TimelineDock.tracksSpace))
            .onChanged { value in
                let session = editorState.trackRowDrag
                if !session.isCarrying {
                    guard !session.refused, editorState.renamingTrackID == nil else { return }
                    guard session.pickUp(track.id, pointerY: value.startLocation.y, editor: editorState)
                    else { return }
                }
                session.move(pointerY: value.location.y)
            }
            .onEnded { _ in editorState.trackRowDrag.letGo() }
    }

    private var indent: CGFloat { inGroup ? TrackHeaderLayout.groupIndent : 0 }

    /// What a picked track wears, on its header and along its lane.
    private var heldFill: some View {
        RoundedRectangle(cornerRadius: 5).fill(VideoKit.Palette.accent.opacity(0.14))
    }

    /// Whether a name is drawn whole in the room it has, in the header's own
    /// font: the walk's `expectApart` reads "name shortened" off the control.
    static func nameFits(_ name: String, in room: CGFloat) -> Bool {
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        return (name as NSString).size(withAttributes: [.font: font, .kern: 0.2]).width <= room + 0.5
    }

    /// The picked layer, where it is on this track: the one the header's key
    /// diamond keys.
    private var keyLayerID: UUID? {
        guard !track.isLocked, editorState.renamingTrackID != track.id else { return nil }
        return editorState.headerKeyLayerID(onTrackWith: row.clips.map(\.layerID))
    }

    // MARK: The arrow that opens the lanes

    /// Whether anything on this track has a value keyed, which is what earns
    /// the header its arrow.
    private var hasKeyLanes: Bool {
        editorState.trackHasKeyLanes(row.clips.map(\.layerID))
    }

    /// A Captions track opens into its Words lane the same way, and starts
    /// open, the way the captions mock draws it.
    private var hasWordsLane: Bool { row.isCaptions && !row.clips.isEmpty }

    /// The arrow before the name, the way Premiere and After Effects open a
    /// track into its keyed values: pointing right while closed, down while
    /// open.
    @ViewBuilder private var twist: some View {
        if hasKeyLanes || hasWordsLane {
            let open = editorState.isKeyTrackOpen(track.id)
            let what = hasWordsLane ? "words" : "keyed values"
            Button {
                withAnimation(.snappy(duration: 0.18)) { editorState.toggleKeyTrack(track.id) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(VideoKit.Palette.faint)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: TrackHeaderLayout.twistWidth, height: laneHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? "Hide the \(what)" : "Show the \(what)")
            .accessibilityLabel(open ? "Hide the \(what) of \(track.name)"
                                     : "Show the \(what) of \(track.name)")
            .playtestControl(hasWordsLane ? "Words \(track.name)" : "Key Lanes \(track.name)",
                             detail: "Timeline")
            .panelReadout("\(track.name) \(what) \(open ? "open" : "closed")")
        }
    }

    private var readout: String {
        var said = "track \(track.name)"
        var flags: [String] = []
        if track.isHidden { flags.append("hidden") }
        if track.isMuted { flags.append("muted") }
        if track.isSolo { flags.append("solo") }
        if track.isLocked { flags.append("locked") }
        if !flags.isEmpty { said += ": " + flags.joined(separator: ", ") }
        let count = row.clips.count + row.linked.count
        return said + " (\(count) clip\(count == 1 ? "" : "s"))"
    }

    private var nameField: some View {
        TextField("", text: $draftName)
            .textFieldStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(VideoKit.Palette.ink)
            .padding(.horizontal, 4)
            .frame(width: TimelineDock.gutter - 4, height: 20)
            .background(RoundedRectangle(cornerRadius: 4).fill(VideoKit.Palette.glassThin))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(VideoKit.Palette.accent))
            .focused($isNaming)
            .onSubmit { editorState.renameTrack(track.id, to: draftName) }
            .onExitCommand { editorState.renamingTrackID = nil }
            .onChange(of: isNaming) { _, focused in
                if !focused, editorState.renamingTrackID == track.id {
                    editorState.renameTrack(track.id, to: draftName)
                }
            }
            .onAppear {
                draftName = track.name
                // A beat later, once the field is in the window: asked for in
                // the same pass that builds it, the canvas keeps the keyboard.
                DispatchQueue.main.async { isNaming = true }
            }
            .playtestControl("Track name", detail: "Timeline")
            .panelReadout("naming \(track.name): \(isNaming ? "typing" : "not holding the keyboard")")
    }

    private func beginRenaming() {
        draftName = track.name
        editorState.beginRenamingTrack(track.id)
        isNaming = true
    }

    private var showsAllSwitches: Bool { isHovered }
    private var isSound: Bool { track.kind == .audio }
    private var shownSwitches: Int {
        if showsAllSwitches { return 3 }
        return [isSound ? track.isMuted : track.isHidden, track.isSolo, track.isLocked].filter { $0 }.count
    }

    /// Hide (or mute), solo and lock: up while the pointer is over the track,
    /// and always up while on.
    private var switches: some View {
        let showAll = showsAllSwitches
        return HStack(spacing: TrackHeaderLayout.switchSpacing) {
            if showAll || (isSound ? track.isMuted : track.isHidden) {
                TrackSwitch(symbol: isSound ? (track.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                                            : (track.isHidden ? "eye.slash" : "eye"),
                            isOn: isSound ? track.isMuted : track.isHidden,
                            tint: VideoKit.Palette.crit,
                            label: isSound ? (track.isMuted ? "Unmute \(track.name)" : "Mute \(track.name)")
                                           : (track.isHidden ? "Show \(track.name)" : "Hide \(track.name)")) {
                    if isSound { editorState.toggleTrackMuted(track.id) } else { editorState.toggleTrackHidden(track.id) }
                }
                .playtestControl("Track \(track.name) \(isSound ? "Mute" : "Hide")", detail: "Timeline")
            }
            if showAll || track.isSolo {
                TrackSwitch(letter: "S", isOn: track.isSolo, tint: VideoKit.Palette.warn,
                            label: track.isSolo ? "Stop soloing \(track.name)" : "Solo \(track.name)") {
                    editorState.toggleTrackSolo(track.id)
                }
                .playtestControl("Track \(track.name) Solo", detail: "Timeline")
            }
            if showAll || track.isLocked {
                TrackSwitch(symbol: track.isLocked ? "lock.fill" : "lock.open", isOn: track.isLocked,
                            tint: VideoKit.Palette.accent,
                            label: track.isLocked ? "Unlock \(track.name)" : "Lock \(track.name)") {
                    editorState.toggleTrackLocked(track.id)
                }
                .playtestControl("Track \(track.name) Lock", detail: "Timeline")
            }
        }
    }

    /// The mock's track icons: the kind of the first clip on the track, or of
    /// the track itself while it is empty.
    private var symbol: String {
        if let first = row.clips.first { return Self.symbol(first.trackKind) }
        if !row.linked.isEmpty { return Self.symbol(.audio) }
        switch track.kind {
        case .video: return "photo"
        case .audio: return "music.note"
        case .captions: return "captions.bubble"
        }
    }

    // MARK: The lane

    /// The lane's own space, which a press on a gap is read in.
    static func laneSpace(_ track: UUID) -> String { "timeline-lane-\(track.uuidString)" }

    private var lane: some View {
        let ruler = editorState.motionStripRuler
        return ZStack(alignment: .topLeading) {
            // The same wash as the header's, so a picked track reads as one
            // thing from its name to the end of its lane.
            if isHeld { heldFill.allowsHitTesting(false) }
            TimelineGridlines(ruler: ruler, laneWidth: laneWidth, height: laneHeight)
            // An empty track says where a clip goes before anything is
            // carried (`TimelineEmptySlot`). A carried clip lights the whole
            // lane instead, as the mock swaps `.lane.empty` for `.lane.drop`.
            if row.showsEmptySlot, editorState.clipTrackDrop?.lights(track: track.id) == nil {
                TimelineEmptySlot()
            }
            // A click on the bare lane puts the playhead there; a drag draws a
            // box that picks the clips it touches, or with ⌥ a range on the
            // tracks it crosses (`EditorState+TrackRange`). A clip on top
            // takes its own presses first.
            Color.clear
                .contentShape(Rectangle())
                .gesture(TimelineLaneMarquee.gesture(editorState, ruler: ruler, laneWidth: laneWidth,
                                                     trackID: track.id))
                .contextMenu { TimelineTrackMenu(track: track, index: index) }
            // Each gap between two clips is the same empty space, with its own
            // right-click menu that leads with Ripple Delete, as Premiere's
            // does (`EditorState+TimelineGap`). The press is read in the
            // lane's space, so a click or a box starting here is the lane's.
            ForEach(editorState.timelineGaps(onTrack: track), id: \.range.lowerBound) { gap in
                let x0 = laneWidth * min(max(0, ruler.fraction(ofMS: Double(gap.range.lowerBound))), 1)
                let x1 = laneWidth * min(max(0, ruler.fraction(ofMS: Double(gap.range.upperBound))), 1)
                if x1 - x0 >= 1 {
                    // Drawn as an empty slot the height of a clip, so a hole
                    // left by a lift or a trim is plain to see.
                    TimelineGapSlot()
                        .frame(width: x1 - x0, height: laneHeight)
                        .offset(x: x0)
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: x1 - x0, height: laneHeight)
                        .offset(x: x0)
                        .gesture(TimelineLaneMarquee.gesture(editorState, ruler: ruler, laneWidth: laneWidth,
                                                             trackID: track.id,
                                                             in: .named(Self.laneSpace(track.id))))
                        .contextMenu { TimelineTrackMenu(track: track, index: index, gap: gap) }
                }
            }
            let alternates = alternateClips
            // A Captions track paints the cues nobody is working on as one
            // layer (`CaptionCuesLayer`) and draws only the rest as bars.
            let painted = paintedCues
            if !painted.isEmpty {
                CaptionCuesLayer(cues: painted.compactMap { group in
                    group.bar.map { CaptionCuesLayer.Cue(layerID: group.layerID, name: group.layerName, bar: $0) }
                }, ruler: ruler, laneWidth: laneWidth, height: laneHeight)
                .equatable()
                .allowsHitTesting(!track.isLocked)
            }
            let paintedIDs = Set(painted.map(\.id))
            ForEach(row.clips.filter { !paintedIDs.contains($0.id) }) { clip in
                TimelineClipView(group: clip, laneWidth: laneWidth, height: laneHeight,
                                 alternate: alternates.contains(clip.id), isCaptionCue: row.isCaptions,
                                 soundNumber: row.soundNumber)
                    .allowsHitTesting(!track.isLocked)
                    .modifier(TimingName(on: !row.isCaptions, name: "Timing \(clip.layerName)"))
            }
            // Each click of a recording, as a tick along the foot of its bar
            // (`ClickTicksView`).
            if editorState.canWorkWithClickEffects, !isBlade, !isTrackSelect, !row.isCaptions {
                ForEach(row.clips) { clip in
                    ClickTicksView(layerID: clip.layerID, laneWidth: laneWidth, height: laneHeight,
                                   isLocked: track.isLocked)
                }
            }
            if isBlade, !track.isLocked {
                ForEach(row.clips) { clip in
                    TimelineBlade(group: clip, laneWidth: laneWidth)
                }
            }
            if isTrackSelect, !track.isLocked {
                ForEach(row.clips) { clip in
                    TimelineTrackSelect(group: clip, laneWidth: laneWidth)
                }
            }
            // A clip's own sound: the clip's bar a second time, as sound, so
            // every drag on it is a drag on the clip and the two never part
            // until Detach Audio.
            ForEach(row.linked) { clip in
                TimelineClipView(group: clip, laneWidth: laneWidth, height: laneHeight,
                                 isLinkedSound: true, soundNumber: row.soundNumber)
                    .allowsHitTesting(!track.isLocked)
                    .playtestField("Timing \(clip.layerName) sound")
                if isBlade, !track.isLocked {
                    TimelineBlade(group: clip, laneWidth: laneWidth, isLinkedSound: true)
                }
                if isTrackSelect, !track.isLocked {
                    TimelineTrackSelect(group: clip, laneWidth: laneWidth, isLinkedSound: true)
                }
            }
            if !isBlade, !isTrackSelect {
                ForEach(editorState.document?.editPoints(onTrack: track.id) ?? []) { point in
                    TimelineSpareStrips(point: point, laneWidth: laneWidth, height: laneHeight)
                    TimelineEditPointView(point: point, laneWidth: laneWidth, height: laneHeight)
                        .allowsHitTesting(!track.isLocked)
                }
            }
            // The Range tool: a drag anywhere on the lane, over clips too,
            // picks a stretch of time, as Final Cut's R does.
            if isRangeTool {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(TimelineLaneMarquee.gesture(editorState, ruler: ruler, laneWidth: laneWidth,
                                                         trackID: track.id))
                    .contextMenu { TimelineTrackMenu(track: track, index: index) }
            }
            if track.isLocked { lockedHatch }
            dropMark
            if let hover = editorState.timelineFileHover, hover.landing.target == .onto(track.id) {
                TimelineFileGhost(hover: hover, laneWidth: laneWidth, height: laneHeight)
            }
            if let kind = editorState.transitionSpotsLitKind, track.kind == .video {
                TimelineTransitionSpots(kind: kind, trackID: track.id, laneWidth: laneWidth, height: laneHeight)
            }
            if let hover = editorState.timelineTransitionHover, hover.trackID == track.id {
                TimelineTransitionGhost(hover: hover, laneWidth: laneWidth, height: laneHeight)
            }
        }
        .frame(width: laneWidth, height: laneHeight, alignment: .topLeading)
        .coordinateSpace(name: Self.laneSpace(track.id))
        .opacity(row.isOff ? 0.4 : 1)
        .clipShape(TimelineEdgeClip())
        .overlay(alignment: .top) { insertionLine(atTop: true) }
        .overlay(alignment: .bottom) { insertionLine(atTop: false) }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(TimelineDock.tracksSpace))
        } action: { frame in
            guard !isLifted else { return }
            editorState.trackDropRows[track.id] = TrackDropRow(trackID: track.id, minY: frame.minY,
                                                               maxY: frame.maxY)
        }
        .onDisappear { if !isLifted { editorState.trackDropRows[track.id] = nil } }
    }

    /// Every other clip along the track, left to right, which wears the
    /// mock's second clip colour (`.clip.v2`) so two clips that meet read as
    /// two clips.
    private var alternateClips: Set<MotionStripGroup.ID> {
        let order = row.clips.sorted { ($0.bar?.inMS ?? 0) < ($1.bar?.inMS ?? 0) }
        return Set(order.enumerated().filter { $0.offset % 2 == 1 }.map(\.element.id))
    }

    /// A locked track's lane is striped, the way a locked track reads in every
    /// editor, so it is plain before anything is tried that nothing will move.
    private var lockedHatch: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 7
            }
            context.stroke(path, with: .color(VideoKit.Palette.ink.color(colorScheme).opacity(0.13)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    /// The lane lit as the place a carried clip would land, in red where it
    /// cannot. Several clips carried together light every lane one of them
    /// lands on, not only the one under the hand.
    @ViewBuilder private var dropMark: some View {
        if let lands = editorState.clipTrackDrop?.lights(track: track.id) {
            let tint = lands ? VideoKit.Palette.accent : VideoKit.Palette.crit.color(colorScheme)
            RoundedRectangle(cornerRadius: VideoKit.Metrics.clipCornerRadius)
                .fill(tint.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: VideoKit.Metrics.clipCornerRadius)
                    .strokeBorder(tint, lineWidth: 1.5))
                .allowsHitTesting(false)
        }
    }

    /// The line a drop BETWEEN tracks draws, where the new track would go.
    @ViewBuilder private func insertionLine(atTop: Bool) -> some View {
        let places = newTrackPlaces
        if atTop ? places.contains(index) : (places.contains(trackCount) && index == trackCount - 1) {
            Capsule()
                .fill(VideoKit.Palette.accent)
                .frame(height: 2)
                .offset(y: atTop ? -TimelineDock.rowSpacing / 2 - 1 : TimelineDock.rowSpacing / 2 + 1)
                .allowsHitTesting(false)
                .panelReadout("new track here")
        }
    }

    /// Where new tracks would be made by what is in the air: a clip carried
    /// between two tracks, several carried past either end, or a file let go
    /// there.
    private var newTrackPlaces: Set<Int> {
        var places = editorState.clipTrackDrop?.newTrackPlaces ?? []
        if let hover = editorState.timelineFileHover, case .newTrack(let at) = hover.landing.target {
            places.insert(at)
        }
        return places
    }

    // MARK: The mock's words for kinds

    /// The mock's track icons: `ic-image` for the picture, `ic-layers` for
    /// what sits over it, `ic-audio`, `ic-text`, `ic-component`.
    static func symbol(_ kind: TimelineTrackKind) -> String {
        switch kind {
        case .video: "photo"
        case .overlay: "square.3.layers.3d"
        case .audio: "music.note"
        case .text: "textformat"
        case .component: "square.on.square.dashed"
        }
    }

    static func clipKind(_ kind: TimelineTrackKind) -> VideoKit.ClipKind {
        switch kind {
        case .video: .video
        case .overlay: .overlay
        case .audio: .audio
        case .text: .text
        case .component: .component
        }
    }
}

// MARK: - A switch on a track's header

/// One of a header's switches: 14 points square, faint while off, its tint
/// while on.
/// The key diamond on a track's header, beside the picked layer's name: one
/// press keys where it is, its size, its angle and its opacity at the playhead,
/// the way After Effects keys a layer's Transform. Pressed on a key, those keys
/// go. Once it is keyed, a drag on the canvas somewhere else is the next key.
struct TrackKeyDiamond: View {
    static let width: CGFloat = TrackHeaderLayout.keySize
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let trackName: String
    @State private var isHovering = false

    var body: some View {
        let state = editorState.headerKeyDiamond(layerID)
        Button {
            editorState.toggleHeaderKey(layerID)
        } label: {
            VideoKit.KeyDiamond(state: kitState(state), isHovering: isHovering)
                .frame(width: Self.width, height: Self.width)
        }
        .buttonStyle(.plain)
        .playtestHover("Key \(trackName)") { isHovering = $0 }
        .help(help(state))
        .accessibilityLabel("Key \(trackName)")
        .playtestControl("Key \(trackName)", detail: word(state))
        .panelReadout(word(state))
    }

    private func kitState(_ state: KeyDiamond) -> VideoKit.KeyState {
        switch state {
        case .dormant: .dormant
        case .betweenKeys: .armed
        case .onKey: .onKey
        }
    }

    private func help(_ state: KeyDiamond) -> String {
        switch state {
        case .dormant, .betweenKeys: "Add Key"
        case .onKey: "Remove Key"
        }
    }

    private func word(_ state: KeyDiamond) -> String {
        switch state {
        case .dormant: "not keyed"
        case .betweenKeys: "between keys"
        case .onKey: "on a key"
        }
    }
}

private struct TrackSwitch: View {
    var symbol: String?
    var letter: String?
    let isOn: Bool
    let tint: AnyShapeStyle
    let label: String
    let action: () -> Void

    init(symbol: String, isOn: Bool, tint: some ShapeStyle, label: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.isOn = isOn
        self.tint = AnyShapeStyle(tint)
        self.label = label
        self.action = action
    }

    init(letter: String, isOn: Bool, tint: some ShapeStyle, label: String, action: @escaping () -> Void) {
        self.letter = letter
        self.isOn = isOn
        self.tint = AnyShapeStyle(tint)
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 8.5, weight: .semibold))
                } else if let letter {
                    Text(letter).font(.system(size: 8.5, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(VideoKit.Palette.dim))
            .frame(width: TrackHeaderLayout.switchSize, height: TrackHeaderLayout.switchSize)
            .background {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(isOn ? tint : AnyShapeStyle(VideoKit.Palette.glassThin))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help(label)
    }
}

// MARK: - The right-click menu on a track

/// Everything a track does, on its header and its bare lane.
struct TimelineTrackMenu: View {
    @Environment(EditorState.self) private var editorState
    let track: DocumentTrack
    let index: Int
    /// The gap between two clips the right click landed in, whose Ripple
    /// Delete leads (`EditorState+TimelineGap`).
    var gap: TimelineGap?

    var body: some View {
        let acted = editorState.tracksActedOn(from: track.id)
        let isEmpty = editorState.isTrackEmpty(track.id)
        if let gap {
            MenuRowsView(rows: editorState.timelineGapMenuRows(gap))
            Divider()
        }
        // A range on this track, or pieces a box picked: what they act on
        // leads (`EditorState+TrackRange`).
        if editorState.trackRangeHeld?.trackIDs.contains(track.id) == true
            || editorState.timelinePicksHeld != nil {
            MenuRowsView(rows: editorState.trackThingMenuRows())
            Divider()
        }
        if track.kind == .captions {
            MenuRowsView(rows: editorState.captionTrackMenuRows())
            Divider()
        }
        // An empty picture track is somewhere to put something, from the
        // playhead: a new shape, a title, what is on the clipboard, or a layer
        // that is on the canvas and on no track.
        if isEmpty, track.kind == .video, !track.isLocked {
            Button("Add Rectangle") { editorState.addRectangle(onTrack: track.id) }
            Button("Add Text") { editorState.addText(onTrack: track.id) }
            // A title page or a name card from its presets, on this track
            // from the playhead (`EditorState+TitlePresets`).
            MenuRowsView(rows: editorState.titleInsertMenuRows(verb: "Add", onTrack: track.id))
            Button("Paste Here") { editorState.paste(onTrack: track.id) }
                .disabled(!editorState.canPasteLayerOrPicture)
            let loose = editorState.layersOffTheTimeline
            if !loose.isEmpty {
                Menu("Put Layer Here") {
                    ForEach(loose) { layer in
                        Button(layer.name) { editorState.putLayerOnTimeline(layer.id, onTrack: track.id) }
                    }
                }
            }
            Divider()
        }
        Button("Rename…") { editorState.beginRenamingTrack(track.id) }
        Divider()
        if track.kind == .audio {
            Button(track.isMuted ? "Unmute Track" : "Mute Track") { editorState.toggleTrackMuted(track.id) }
        } else {
            Button(track.isHidden ? "Show Track" : "Hide Track") { editorState.toggleTrackHidden(track.id) }
        }
        Button(track.isSolo ? "Stop Soloing" : "Solo Track") { editorState.toggleTrackSolo(track.id) }
        Button(track.isLocked ? "Unlock Track" : "Lock Track") { editorState.toggleTrackLocked(track.id) }
        Divider()
        Button(acted.count > 1 ? "Group \(acted.count) Tracks" : "Group Track") {
            editorState.groupTracks(from: track.id)
        }
        if let group = track.groupID {
            Button("Ungroup") { editorState.ungroupTracks(group) }
        }
        Divider()
        // A track like this one, either side of it: where Premiere's Add
        // Track puts one. Another kind is the + at the foot of the gutter.
        Button("Add Track Above") { editorState.addTrack(track.kind, at: index) }
        Button("Add Track Below") { editorState.addTrack(track.kind, at: index + 1) }
        Divider()
        MenuRowsView(rows: editorState.timelineViewMenuRows())
        Divider()
        // ⌫ is printed, not answered: the press reaches the picked tracks
        // through the timeline (`liftInHand`), and a context menu is not up
        // to hear it anyway.
        let held = editorState.tracksInHand
        let deleting = held.contains(track.id) ? held.count : 1
        Button(deleting > 1 ? "Delete \(deleting) Tracks" : "Delete Track", role: .destructive) {
            if held.contains(track.id) { editorState.deleteTracksInHand() } else { editorState.deleteTrack(track.id) }
        }
        .keyboardShortcut(KeyEquivalent(DeleteKeyCharacters.menuRow(answersThePress: false)), modifiers: [])
        if editorState.hasEmptyTracks {
            Button("Delete Empty Tracks", role: .destructive) { editorState.deleteEmptyTracks() }
        }
    }
}

// MARK: - A clip on a lane

/// One clip in a lane: the pieces bar every clip gesture lives on, or, for a
/// layer that has no times of its own, one bar the length of the document.
struct TimelineClipView: View {
    @Environment(EditorState.self) private var editorState
    let group: MotionStripGroup
    let laneWidth: CGFloat
    let height: CGFloat
    var alternate = false
    /// This bar is a cue on a Captions track.
    var isCaptionCue = false
    /// This bar is a clip's own sound on the audio track under it.
    var isLinkedSound = false
    /// Which sound track the bar is on, for the colour its fades and level
    /// points wear.
    var soundNumber = 0

    var body: some View {
        let ruler = editorState.motionStripRuler
        let own = isCaptionCue ? .caption : TimelineTrackRow.clipKind(group.trackKind)
        let kind = alternate && own == .video ? VideoKit.ClipKind.videoAlternate : own
        if let bar = group.bar {
            // The trim session is drawn once, on the picture; the linked
            // sound under it follows the trim as it is shown.
            if editorState.trimmingLayerID == group.layerID, !isLinkedSound {
                ClipTrimBar(bar: bar, layerName: group.layerName, laneWidth: laneWidth, height: height)
            } else {
                ClipPiecesBar(layerID: group.layerID, layerName: group.layerName,
                              bar: bar, laneWidth: laneWidth, isSound: group.isSound,
                              kind: kind, height: height, isLinkedSound: isLinkedSound,
                              soundTint: VideoKit.Palette.soundTrack(soundNumber))
            }
        } else {
            // A layer that is there the whole way through: one clip the
            // length of the document. It has no ends to drag because it has
            // no times of its own; picking it is all a press does.
            let x0 = laneWidth * ruler.fraction(ofMS: 0)
            let x1 = laneWidth * ruler.fraction(ofMS: Double(editorState.documentLengthMS))
            VideoKit.ClipBar(title: group.layerName, kind: kind,
                             isSelected: editorState.isLayerSelected(group.layerID)
                                 || editorState.goesWithTracksInHand(group.layerID, asSound: isLinkedSound),
                             height: height)
                .frame(width: max(2, x1 - x0))
                .offset(x: x0)
                .onTapGesture {
                    let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                    if flags.contains(.shift) || flags.contains(.command) {
                        editorState.extendSelection(toLayer: group.layerID)
                    } else {
                        editorState.selectLayer(group.layerID)
                    }
                }
        }
    }
}

/// With the Blade in hand a clip is a place to cut: the playhead goes where
/// you clicked and the clip there is cut in two, the same cut B makes.
struct TimelineBlade: View {
    @Environment(EditorState.self) private var editorState
    let group: MotionStripGroup
    let laneWidth: CGFloat
    var isLinkedSound = false

    private var name: String { isLinkedSound ? "\(group.layerName) sound" : group.layerName }

    var body: some View {
        let ruler = editorState.motionStripRuler
        let startMS = Double(group.bar?.inMS ?? 0)
        let endMS = Double(group.bar?.outMS ?? editorState.documentLengthMS)
        let x0 = max(0, laneWidth * ruler.fraction(ofMS: startMS))
        let x1 = min(laneWidth, laneWidth * ruler.fraction(ofMS: endMS))
        Color.clear
            .frame(width: max(1, x1 - x0))
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                let fraction = min(max(0, (x0 + point.x) / laneWidth), 1)
                let ms = ruler.ms(atFraction: Double(fraction))
                editorState.selectLayer(group.layerID)
                editorState.dragPlayhead(toMS: Int(ms.rounded()))
                editorState.splitClipAtPlayhead()
            }
            .playtestHover("Blade \(name)") { inside in
                if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            .playtestControl("Blade \(name)", detail: "Timeline")
            .offset(x: x0)
    }
}

/// With Track Select Forward in hand (A) a clip is where a pick of it and
/// everything after it starts: the press picks the lot, on every track (⇧: this
/// track only), and a drag from the same press slides the lot, Premiere's way.
struct TimelineTrackSelect: View {
    @Environment(EditorState.self) private var editorState
    let group: MotionStripGroup
    let laneWidth: CGFloat
    var isLinkedSound = false
    @State private var isPressed = false

    private var name: String { isLinkedSound ? "\(group.layerName) sound" : group.layerName }

    var body: some View {
        let ruler = editorState.motionStripRuler
        let startMS = Double(group.bar?.inMS ?? 0)
        let endMS = Double(group.bar?.outMS ?? editorState.documentLengthMS)
        let x0 = max(0, laneWidth * ruler.fraction(ofMS: startMS))
        let x1 = min(laneWidth, laneWidth * ruler.fraction(ofMS: endMS))
        Color.clear
            .frame(width: max(1, x1 - x0))
            .contentShape(Rectangle())
            // Read in the tracks' own space: the bar moves under the hand
            // while it is dragged, and a travel read against the bar itself
            // would chase it.
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(TimelineDock.tracksSpace))
                .onChanged { value in
                    if !isPressed {
                        isPressed = true
                        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                        editorState.beginTrackSelectForwardDrag(layerID: group.layerID,
                                                                onItsTrackOnly: flags.contains(.shift))
                    }
                    editorState.updateClipBarDrag(
                        byMS: ClipPiecesBar.ms(value.translation.width, laneWidth: laneWidth,
                                               ruler: editorState.motionStripRuler))
                }
                .onEnded { _ in
                    isPressed = false
                    editorState.commitClipBarDrag()
                })
            .contextMenu { TimelineClipMenu(layerID: group.layerID, onTheSound: isLinkedSound) }
            .playtestControl("Track Select \(name)", detail: "Timeline")
            .offset(x: x0)
    }
}

/// `.lane .gl`: a hairline under every second on the ruler, so a clip's edge
/// can be read against the numbers above it.
struct TimelineGridlines: View {
    let ruler: MotionStripRuler
    let laneWidth: CGFloat
    let height: CGFloat

    var body: some View {
        // One shape for every line rather than a view each: a far jump of the
        // playhead on a zoomed timeline moves every second to a new one, and a
        // view per second was thrown away and built again in every row
        // (`first-long-jump-when-zoomed-in-walk`).
        Hairlines(xs: ruler.secondTicks.map { laneWidth * ruler.fraction(ofMS: $0.ms) })
            .fill(VideoKit.Palette.edgeLo)
            .frame(width: laneWidth, height: height, alignment: .topLeading)
            .allowsHitTesting(false)
    }

    /// A one point line down the whole height at each of `xs`.
    private struct Hairlines: Shape {
        let xs: [CGFloat]

        func path(in rect: CGRect) -> Path {
            var path = Path()
            for x in xs { path.addRect(CGRect(x: x, y: 0, width: 1, height: rect.height)) }
            return path
        }
    }
}

/// A press or a drag on a bare lane puts the playhead there.
enum TimelineLaneScrub {
    @MainActor
    static func gesture(_ editorState: EditorState, ruler: MotionStripRuler,
                        laneWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !editorState.isAuditioningScrub { editorState.beginPlayheadDrag() }
                let fraction = min(max(0, value.location.x / laneWidth), 1)
                editorState.dragPlayhead(toMS: Int(ruler.ms(atFraction: Double(fraction)).rounded()),
                                         snappingWithinMS: editorState.keySnapReachMS(laneWidth: laneWidth))
            }
            .onEnded { _ in editorState.endPlayheadDrag() }
    }
}

/// A press or a drag on empty track space (`EditorState+TrackRange`): a click
/// moves the playhead, a drag draws a box over the tracks, and a drag with ⌥
/// held or the Range tool in hand picks a stretch of time on the tracks it
/// crosses. The press is read along the lane for time and down the tracks'
/// own space for which tracks it crosses. `space` is the lane's, for a view
/// that covers only part of it (a gap).
enum TimelineLaneMarquee {
    @MainActor
    static func gesture(_ editorState: EditorState, ruler: MotionStripRuler, laneWidth: CGFloat,
                        trackID: UUID, in space: CoordinateSpace = .local) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: space)
            .onChanged { value in
                let top = editorState.trackDropRows[trackID]?.minY ?? 0
                let startMS = ms(value.startLocation.x, laneWidth, ruler)
                // A new press, or one left behind by a gesture the system
                // cancelled without an end.
                if editorState.lanePress?.atMS != startMS {
                    editorState.beginLanePress(
                        atMS: startMS, y: top + value.startLocation.y,
                        drawsRange: NSEvent.modifierFlags.contains(.option) || editorState.timelineTool == .range)
                }
                let moved = hypot(value.translation.width, value.translation.height) >= EditorState.laneClickSlop
                let snap = editorState.lanePress?.drawsRange == true
                    ? editorState.keySnapReachMS(laneWidth: laneWidth) : 0
                editorState.dragLanePress(toMS: ms(value.location.x, laneWidth, ruler), y: top + value.location.y,
                                          moved: moved, snapMS: snap)
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) >= EditorState.laneClickSlop
                editorState.endLanePress(atMS: ms(value.location.x, laneWidth, ruler), moved: moved)
            }
    }

    /// The moment under a point along the lane, which may be past either end
    /// of it while a box is being drawn.
    static func ms(_ x: CGFloat, _ laneWidth: CGFloat, _ ruler: MotionStripRuler) -> Int {
        let fraction = min(max(0, x / max(1, laneWidth)), 1)
        return Int(ruler.ms(atFraction: Double(fraction)).rounded())
    }
}

// MARK: - A part inside a clip

/// Something inside a clip with time or motion of its own (a part of a placed
/// component, a layer inside a group): its own row under its clip's track,
/// named after it, the way the strip has always drawn it.
struct TimelineInnerRow: View {
    @Environment(EditorState.self) private var editorState
    let group: MotionStripGroup
    let laneWidth: CGFloat
    let isBlade: Bool
    let isLocked: Bool
    var rows: TimelineRowZoom = .compact

    var body: some View {
        let height = rows.height(group.isSound ? TimelineDock.soundLaneHeight : TimelineDock.laneHeight)
        let ruler = editorState.motionStripRuler
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: TimelineDock.gap) {
                Button { editorState.selectLayer(group.layerID) } label: {
                    VideoKit.TrackHeader(title: group.layerName, symbol: TimelineTrackRow.symbol(group.trackKind),
                                         width: TimelineDock.gutter - 10, uppercase: false,
                                         isSelected: editorState.selectedLayerID == group.layerID)
                        .padding(.leading, 10)
                        .frame(height: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(group.layerName)
                .accessibilityLabel("Track \(group.layerName)")
                ZStack(alignment: .topLeading) {
                    TimelineGridlines(ruler: ruler, laneWidth: laneWidth, height: height)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(TimelineLaneScrub.gesture(editorState, ruler: ruler, laneWidth: laneWidth))
                    TimelineClipView(group: group, laneWidth: laneWidth, height: height)
                        .allowsHitTesting(!isLocked)
                    if isBlade, !isLocked { TimelineBlade(group: group, laneWidth: laneWidth) }
                }
                .frame(width: laneWidth, height: height, alignment: .topLeading)
                .clipShape(TimelineEdgeClip())
            }
            .frame(height: height)
            .playtestField("Timing \(group.layerName)")
            ForEach(group.lanes) { lane in
                MotionStripLaneView(lane: lane, layerName: group.layerName, laneWidth: laneWidth,
                                    labelWidth: TimelineDock.lanesLeading)
            }
        }
    }
}

// MARK: - A group of tracks

/// A group's heading: a chevron that folds its tracks away and its name. Folded,
/// its lane shows every clip in the group as a thin bar, so you can still see
/// where things happen without the rows.
struct TimelineGroupRow: View {
    @Environment(EditorState.self) private var editorState
    let group: DocumentTrackGroup
    let isCollapsed: Bool
    let tracks: [TimelineTrackRowModel]
    let laneWidth: CGFloat

    static let openHeight: CGFloat = 18
    static let foldedHeight: CGFloat = 22

    @State private var draftName = ""
    @State private var pendingFold: Task<Void, Never>?
    @FocusState private var isNaming: Bool

    var body: some View {
        HStack(spacing: TimelineDock.gap) {
            header
            lane
        }
        .frame(height: isCollapsed ? Self.foldedHeight : Self.openHeight)
        .playtestField("Track group \(group.name)")
    }

    private var header: some View {
        Group {
            if editorState.renamingTrackID == group.id {
                TextField("", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 4)
                    .frame(width: TimelineDock.gutter - 4, height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(VideoKit.Palette.glassThin))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(VideoKit.Palette.accent))
                    .focused($isNaming)
                    .onSubmit { editorState.renameTrackGroup(group.id, to: draftName) }
                    .onExitCommand { editorState.renamingTrackID = nil }
                    .onChange(of: isNaming) { _, focused in
                        if !focused, editorState.renamingTrackID == group.id {
                            editorState.renameTrackGroup(group.id, to: draftName)
                        }
                    }
                    .onAppear {
                        draftName = group.name
                        // A beat later, once the field is in the window, as a
                        // track's name field does: asked for in the same pass
                        // that builds it, the canvas keeps the keyboard.
                        DispatchQueue.main.async { isNaming = true }
                    }
                    .playtestControl("Track group name", detail: "Timeline")
                    .panelReadout("naming \(group.name): \(isNaming ? "typing" : "not holding the keyboard")")
            } else {
                HStack(spacing: 0) {
                    // The chevron folds at once: two clicks on it are two folds.
                    Button { foldNow() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                            .animation(.snappy(duration: 0.18), value: isCollapsed)
                            .frame(width: Self.chevronWidth, height: Self.openHeight, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCollapsed ? "Open \(group.name)" : "Fold \(group.name)")
                    .help(isCollapsed ? "Show the tracks in \(group.name)" : "Fold \(group.name) away")
                    .playtestControl("Track group \(group.name)", detail: "Timeline")
                    .panelReadout("group \(group.name): \(tracks.count) track\(tracks.count == 1 ? "" : "s")"
                                  + (isCollapsed ? ", folded" : ""))
                    // The name folds too, but a double click on it renames, so
                    // a single click waits out the double click before it
                    // folds: folding on the first click of two would fold the
                    // group under the name being typed. A button reading
                    // AppKit's own click count, as a track's name does; a
                    // double tap gesture beside a button never fires.
                    Button { nameClicked() } label: {
                        Text(group.name)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(group.name)
                    .help(isCollapsed ? "Show the tracks in \(group.name)" : "Fold \(group.name) away")
                    .playtestControl("Group name \(group.name)", detail: "Timeline")
                }
                .foregroundStyle(VideoKit.Palette.dim)
                .frame(width: TimelineDock.gutter, alignment: .leading)
                .contextMenu {
                    Button("Rename…") { beginRenaming() }
                    Button("Ungroup") { editorState.ungroupTracks(group.id) }
                }
            }
        }
        .frame(width: TimelineDock.gutter, alignment: .leading)
        .onDisappear { pendingFold?.cancel() }
    }

    /// The chevron's column: its glyph and the gap before the name.
    private static let chevronWidth: CGFloat = 12

    private func foldNow() {
        pendingFold?.cancel()
        pendingFold = nil
        editorState.toggleTrackGroupCollapsed(group.id)
    }

    private func nameClicked() {
        pendingFold?.cancel()
        pendingFold = nil
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            beginRenaming()
            return
        }
        let id = group.id
        pendingFold = Task { @MainActor in
            try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            guard !Task.isCancelled, editorState.renamingTrackID != id else { return }
            editorState.toggleTrackGroupCollapsed(id)
        }
    }

    private func beginRenaming() {
        pendingFold?.cancel()
        pendingFold = nil
        draftName = group.name
        editorState.renamingTrackID = group.id
    }

    @ViewBuilder private var lane: some View {
        let ruler = editorState.motionStripRuler
        ZStack(alignment: .leading) {
            if isCollapsed {
                RoundedRectangle(cornerRadius: 5).fill(VideoKit.Palette.glassThin)
                ForEach(tracks.flatMap { $0.clips + $0.linked }) { clip in
                    let start = Double(clip.bar?.inMS ?? 0)
                    let end = Double(clip.bar?.outMS ?? editorState.documentLengthMS)
                    let x0 = laneWidth * ruler.fraction(ofMS: start)
                    let x1 = laneWidth * ruler.fraction(ofMS: end)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(TimelineTrackRow.clipKind(clip.trackKind).fill)
                        .frame(width: max(2, x1 - x0), height: 8)
                        .offset(x: x0)
                }
            } else {
                Rectangle().fill(VideoKit.Palette.edgeLo).frame(height: 1)
            }
        }
        .frame(width: laneWidth, height: isCollapsed ? Self.foldedHeight : Self.openHeight,
               alignment: .leading)
        .clipShape(TimelineEdgeClip())
        .allowsHitTesting(false)
    }
}

// MARK: - Captions on their way

/// While Add Captions listens: a Captions row under the picture tracks, where
/// the captions will land, with how far along it is and an x to cancel.
///
/// The captions arrive as one undo step when the listening is done, so until
/// then there is no track in the document to hang this on; this row stands in
/// for it. Nothing else on the timeline waits for it.
struct TimelineCaptionsListeningRow: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat

    var body: some View {
        let share = CGFloat(min(1, max(0, editorState.captionsBeingWritten?.share ?? 0)))
        HStack(spacing: TimelineDock.gap) {
            VideoKit.TrackHeader(title: DocumentTrack.Kind.captions.title, width: TimelineDock.gutter,
                                 uppercase: false, isAutomatic: true)
                .frame(width: TimelineDock.gutter, height: TimelineDock.laneHeight, alignment: .leading)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(VideoKit.Palette.comp.opacity(0.08))
                RoundedRectangle(cornerRadius: 4)
                    .fill(VideoKit.Palette.comp.opacity(0.28))
                    .frame(width: max(6, laneWidth * share))
                    .animation(.linear(duration: 0.2), value: share)
                HStack(spacing: 6) {
                    Text("Listening \(Int((share * 100).rounded()))%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(VideoKit.Palette.comp)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 0)
                    Button { editorState.stopWritingCaptions() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VideoKit.Palette.dim)
                    .accessibilityLabel("Cancel Captions")
                    .help("Cancel, keeping the words heard so far")
                    .playtestControl("Cancel Captions", detail: "Timeline")
                }
                .padding(.horizontal, 6)
            }
            .frame(width: laneWidth, height: TimelineDock.laneHeight)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(VideoKit.Palette.comp.opacity(0.35), lineWidth: 1))
        }
        .frame(height: TimelineDock.laneHeight)
        .playtestField("Captions listening")
        .panelReadout("captions listening \(Int((share * 100).rounded()))%")
        .transition(.opacity)
    }
}

// MARK: - Adding a track

/// The foot of the gutter: a + that adds a video, audio or captions track, and
/// a bare lane beside it whose right-click menu does the same.
struct TimelineAddTrackRow: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat

    static let height: CGFloat = 20

    var body: some View {
        HStack(spacing: TimelineDock.gap) {
            Menu {
                items
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VideoKit.Palette.dim)
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Add Track")
            .help("Add a track")
            .playtestControl("Add Track", detail: "Timeline")
            .frame(width: TimelineDock.gutter, alignment: .leading)
            Color.clear
                .frame(width: laneWidth, height: Self.height)
                .contentShape(Rectangle())
                .contextMenu { items }
        }
        .frame(height: Self.height)
    }

    @ViewBuilder private var items: some View {
        Button("Video Track") { editorState.addTrack(.video) }
        Button("Audio Track") { editorState.addTrack(.audio) }
        // Captions from the speech, the way Premiere's Transcribe makes its
        // captions track; an empty one where there is nothing to hear.
        Button("Captions") {
            if editorState.canWriteCaptions && !editorState.hasCaptions {
                editorState.writeCaptions()
            } else {
                editorState.addTrack(.captions)
            }
        }
    }
}

/// A clip's "Timing" name for a walk, left off a caption cue for the reason
/// `ClipPiecesBar.carriesWalkNames` gives.
private struct TimingName: ViewModifier {
    let on: Bool
    let name: String

    func body(content: Content) -> some View {
        if on { content.playtestField(name) } else { content }
    }
}

// MARK: - Only the row that changed

/// A row is rebuilt only when what it was HANDED changed. The grid re-reads
/// every track while a bar is under a hand, because the bar being dragged is
/// drawn from the document as the drag would leave it, and without this every
/// other row, header and lane and all, was rebuilt at every move of the
/// pointer (`bar-end-follows-the-pointer-walk`). What a row reads off the
/// editor for itself still rebuilds it the moment that changes.
extension TimelineTrackRow: Equatable {
    nonisolated static func == (a: TimelineTrackRow, b: TimelineTrackRow) -> Bool {
        a.row == b.row && a.inGroup == b.inGroup && a.index == b.index
            && a.trackCount == b.trackCount && a.laneWidth == b.laneWidth && a.isBlade == b.isBlade
            && a.rows == b.rows && a.isLifted == b.isLifted
    }
}
