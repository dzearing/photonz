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
/// not bring them up: the gutter is the mock's 84 points, and three switches
/// in it left a picked track's name as "O…".
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

    @State private var isHovered = false
    @State private var draftName = ""
    @FocusState private var isNaming: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var track: DocumentTrack { row.track }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: TimelineDock.gap) {
                header
                lane
            }
            .frame(height: laneHeight)
            .playtestField("Track \(track.name)")
            ForEach(row.clips) { clip in
                // A keyed value is a lane of keys, opened and closed by the
                // arrow on the header (`KeyLanesView`); anything else that
                // moves keeps its timing bar.
                let keyed = Set(editorState.keyLanes(layerID: clip.layerID).map(\.motionID))
                if !keyed.isEmpty, editorState.isKeyTrackOpen(track.id) {
                    KeyLanesView(layerID: clip.layerID, layerName: clip.layerName, laneWidth: laneWidth,
                                 indent: indent, isLocked: track.isLocked)
                }
                ForEach(clip.lanes.filter { !keyed.contains($0.motionID) }) { lane in
                    MotionStripLaneView(lane: lane, layerName: clip.layerName, laneWidth: laneWidth)
                }
            }
            ForEach(row.inner) { group in
                TimelineInnerRow(group: group, laneWidth: laneWidth, isBlade: isBlade,
                                 isLocked: track.isLocked)
            }
        }
        .playtestHover("Track \(track.name)") { isHovered = $0 }
    }

    private var laneHeight: CGFloat {
        row.carriesSound ? TimelineDock.soundLaneHeight : TimelineDock.laneHeight
    }

    private var isPicked: Bool {
        editorState.selectedTrackIDs.contains(track.id)
            || row.clips.contains { $0.layerID == editorState.selectedLayerID }
            || row.linked.contains { $0.layerID == editorState.selectedLayerID }
    }

    // MARK: The header

    private var header: some View {
        HStack(spacing: 0) {
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
                    VideoKit.TrackHeader(title: track.name, symbol: showsAllSwitches ? nil : symbol,
                                         width: TimelineDock.gutter - indent - switchesWidth - twistWidth,
                                         uppercase: false, isSelected: isPicked)
                        .padding(.leading, indent + twistWidth)
                        .frame(height: laneHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .playtestControl("Track \(track.name)", detail: "Timeline")
                switches
            }
        }
        .frame(width: TimelineDock.gutter, height: laneHeight, alignment: .leading)
        .overlay(alignment: .leading) { twist.padding(.leading, indent) }
        .background {
            if editorState.selectedTrackIDs.contains(track.id) {
                RoundedRectangle(cornerRadius: 5).fill(VideoKit.Palette.accent.opacity(0.14))
            }
        }
        .contentShape(Rectangle())
        .contextMenu { TimelineTrackMenu(track: track, index: index) }
        .help(track.name)
        .accessibilityLabel("Track \(track.name)")
        .panelReadout(readout)
    }

    private var indent: CGFloat { inGroup ? 10 : 0 }

    // MARK: The arrow that opens the lanes

    /// Whether anything on this track has a value keyed, which is what earns
    /// the header its arrow.
    private var hasKeyLanes: Bool {
        editorState.trackHasKeyLanes(row.clips.map(\.layerID))
    }

    private var twistWidth: CGFloat { hasKeyLanes ? 12 : 0 }

    /// The arrow before the name, the way Premiere and After Effects open a
    /// track into its keyed values: pointing right while closed, down while
    /// open.
    @ViewBuilder private var twist: some View {
        if hasKeyLanes {
            let open = editorState.isKeyTrackOpen(track.id)
            Button {
                withAnimation(.snappy(duration: 0.18)) { editorState.toggleKeyTrack(track.id) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(VideoKit.Palette.faint)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: 12, height: laneHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? "Hide the keyed values" : "Show the keyed values")
            .accessibilityLabel(open ? "Hide the keyed values of \(track.name)"
                                     : "Show the keyed values of \(track.name)")
            .playtestControl("Key Lanes \(track.name)", detail: "Timeline")
            .panelReadout("\(track.name) keyed values \(open ? "open" : "closed")")
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
    private var switchesWidth: CGFloat { shownSwitches == 0 ? 0 : CGFloat(shownSwitches) * 16 + 3 }

    /// Hide (or mute), solo and lock: up while the pointer is over the track,
    /// and always up while on.
    private var switches: some View {
        let showAll = showsAllSwitches
        return HStack(spacing: 1) {
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
        .padding(.leading, shownSwitches == 0 ? 0 : 3)
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

    private var lane: some View {
        let ruler = editorState.motionStripRuler
        return ZStack(alignment: .topLeading) {
            TimelineGridlines(ruler: ruler, laneWidth: laneWidth, height: laneHeight)
            // A press on the bare lane puts the playhead there, the way the
            // strip always has; a clip on top takes its own presses first.
            Color.clear
                .contentShape(Rectangle())
                .gesture(TimelineLaneScrub.gesture(editorState, ruler: ruler, laneWidth: laneWidth))
                .contextMenu { TimelineTrackMenu(track: track, index: index) }
            let alternates = alternateClips
            ForEach(row.clips) { clip in
                TimelineClipView(group: clip, laneWidth: laneWidth, height: laneHeight,
                                 alternate: alternates.contains(clip.id))
                    .allowsHitTesting(!track.isLocked)
                    .playtestField("Timing \(clip.layerName)")
                if isBlade, !track.isLocked {
                    TimelineBlade(group: clip, laneWidth: laneWidth)
                }
            }
            // A clip's own sound: the clip's bar a second time, as sound, so
            // every drag on it is a drag on the clip and the two never part
            // until Detach Audio.
            ForEach(row.linked) { clip in
                TimelineClipView(group: clip, laneWidth: laneWidth, height: laneHeight,
                                 isLinkedSound: true)
                    .allowsHitTesting(!track.isLocked)
                    .playtestField("Timing \(clip.layerName) sound")
                if isBlade, !track.isLocked {
                    TimelineBlade(group: clip, laneWidth: laneWidth, isLinkedSound: true)
                }
            }
            if !isBlade {
                ForEach(editorState.document?.editPoints(onTrack: track.id) ?? []) { point in
                    TimelineEditPointView(point: point, laneWidth: laneWidth, height: laneHeight)
                        .allowsHitTesting(!track.isLocked)
                }
            }
            if track.isLocked { lockedHatch }
            dropMark
            if let hover = editorState.timelineFileHover, hover.landing.target == .onto(track.id) {
                TimelineFileGhost(hover: hover, laneWidth: laneWidth, height: laneHeight)
            }
        }
        .frame(width: laneWidth, height: laneHeight, alignment: .topLeading)
        .opacity(row.isOff ? 0.4 : 1)
        .clipShape(TimelineEdgeClip())
        .overlay(alignment: .top) { insertionLine(atTop: true) }
        .overlay(alignment: .bottom) { insertionLine(atTop: false) }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(TimelineDock.tracksSpace))
        } action: { frame in
            editorState.trackDropRows[track.id] = TrackDropRow(trackID: track.id, minY: frame.minY,
                                                               maxY: frame.maxY)
        }
        .onDisappear { editorState.trackDropRows[track.id] = nil }
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
    /// cannot.
    @ViewBuilder private var dropMark: some View {
        if let drop = editorState.clipTrackDrop, drop.target == .onto(track.id) {
            let tint = drop.allowed ? VideoKit.Palette.accent : VideoKit.Palette.crit.color(colorScheme)
            RoundedRectangle(cornerRadius: VideoKit.Metrics.clipCornerRadius)
                .fill(tint.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: VideoKit.Metrics.clipCornerRadius)
                    .strokeBorder(tint, lineWidth: 1.5))
                .allowsHitTesting(false)
        }
    }

    /// The line a drop BETWEEN tracks draws, where the new track would go.
    @ViewBuilder private func insertionLine(atTop: Bool) -> some View {
        if let at = newTrackPlace,
           atTop ? at == index : (at == trackCount && index == trackCount - 1) {
            Capsule()
                .fill(VideoKit.Palette.accent)
                .frame(height: 2)
                .offset(y: atTop ? -TimelineDock.rowSpacing / 2 - 1 : TimelineDock.rowSpacing / 2 + 1)
                .allowsHitTesting(false)
                .panelReadout("new track here")
        }
    }

    /// Where a new track would be made by what is in the air: a clip carried
    /// between two tracks, or a file let go there.
    private var newTrackPlace: Int? {
        if let drop = editorState.clipTrackDrop, drop.allowed, case .newTrack(let at) = drop.target {
            return at
        }
        if let hover = editorState.timelineFileHover, case .newTrack(let at) = hover.landing.target {
            return at
        }
        return nil
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
            .frame(width: 15, height: 15)
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

    var body: some View {
        let acted = editorState.tracksActedOn(from: track.id)
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
        Button("Delete Track", role: .destructive) { editorState.deleteTrack(track.id) }
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
    /// This bar is a clip's own sound on the audio track under it.
    var isLinkedSound = false

    var body: some View {
        let ruler = editorState.motionStripRuler
        let own = TimelineTrackRow.clipKind(group.trackKind)
        let kind = alternate && own == .video ? VideoKit.ClipKind.videoAlternate : own
        if let bar = group.bar {
            // The trim session is drawn once, on the picture; the linked
            // sound under it follows the trim as it is shown.
            if editorState.trimmingLayerID == group.layerID, !isLinkedSound {
                ClipTrimBar(bar: bar, layerName: group.layerName, laneWidth: laneWidth, height: height)
            } else {
                ClipPiecesBar(layerID: group.layerID, layerName: group.layerName,
                              bar: bar, laneWidth: laneWidth, isSound: group.isSound,
                              kind: kind, height: height, isLinkedSound: isLinkedSound)
            }
        } else {
            // A layer that is there the whole way through: one clip the
            // length of the document. It has no ends to drag because it has
            // no times of its own; picking it is all a press does.
            let x0 = laneWidth * ruler.fraction(ofMS: 0)
            let x1 = laneWidth * ruler.fraction(ofMS: Double(editorState.documentLengthMS))
            VideoKit.ClipBar(title: group.layerName, kind: kind,
                             isSelected: editorState.selectedLayerID == group.layerID, height: height)
                .frame(width: max(2, x1 - x0))
                .offset(x: x0)
                .onTapGesture { editorState.selectLayer(group.layerID) }
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

/// `.lane .gl`: a hairline under every second on the ruler, so a clip's edge
/// can be read against the numbers above it.
struct TimelineGridlines: View {
    let ruler: MotionStripRuler
    let laneWidth: CGFloat
    let height: CGFloat

    var body: some View {
        ForEach(ruler.secondTicks, id: \.ms) { tick in
            Rectangle()
                .fill(VideoKit.Palette.edgeLo)
                .frame(width: 1, height: height)
                .offset(x: laneWidth * ruler.fraction(ofMS: tick.ms))
        }
        .allowsHitTesting(false)
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

    var body: some View {
        let height = group.isSound ? TimelineDock.soundLaneHeight : TimelineDock.laneHeight
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
                MotionStripLaneView(lane: lane, layerName: group.layerName, laneWidth: laneWidth)
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
                    .onAppear {
                        draftName = group.name
                        isNaming = true
                    }
            } else {
                Button { editorState.toggleTrackGroupCollapsed(group.id) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                            .animation(.snappy(duration: 0.18), value: isCollapsed)
                        Text(group.name)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(VideoKit.Palette.dim)
                    .frame(width: TimelineDock.gutter, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    draftName = group.name
                    editorState.renamingTrackID = group.id
                })
                .accessibilityLabel(isCollapsed ? "Open \(group.name)" : "Fold \(group.name)")
                .help(isCollapsed ? "Show the tracks in \(group.name)" : "Fold \(group.name) away")
                .playtestControl("Track group \(group.name)", detail: "Timeline")
                .panelReadout("group \(group.name): \(tracks.count) track\(tracks.count == 1 ? "" : "s")"
                              + (isCollapsed ? ", folded" : ""))
                .contextMenu {
                    Button("Rename…") {
                        draftName = group.name
                        editorState.renamingTrackID = group.id
                    }
                    Button("Ungroup") { editorState.ungroupTracks(group.id) }
                }
            }
        }
        .frame(width: TimelineDock.gutter, alignment: .leading)
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
        Button("Captions Track") { editorState.addTrack(.captions) }
    }
}
