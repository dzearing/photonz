import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Letting a file go on the timeline

/// The timeline's drop target: a sound or a recording let go over the tracks
/// lands at the moment and on the track under the pointer (`ClipLanding`).
/// Overwrite, as in Premiere, unless ⌘ is held, which inserts.
///
/// Anything else a file can be (a picture, a Photonz document) is answered
/// exactly as the rest of the window answers it, because SwiftUI hands a drag
/// to the innermost target and never lets it fall through (`FileDrop`).
struct TimelineFileDropDelegate: DropDelegate {
    let editorState: EditorState

    #if PHOTONZ_PLAYTEST
    /// The keys a walk says are held, since it cannot hold ⌘ down itself.
    @MainActor static var walkHoldsInsert: Bool?
    #endif

    /// Whether ⌘ is down. A drop carries no keys, so they are read live.
    @MainActor static var insertHeld: Bool {
        #if PHOTONZ_PLAYTEST
        if let held = walkHoldsInsert { return held }
        #endif
        return NSEvent.modifierFlags.contains(.command)
    }

    /// A file is judged by what it IS, read off its name once it arrives,
    /// the way the canvas judges one: a drag from the Finder says it carries
    /// a file and not always what kind.
    func validateDrop(info: DropInfo) -> Bool {
        carriesTransition(info) || carriesTitle(info) || carriesComponent(info) || carriesPicture(info)
            || carriesBackground(info)
            || info.hasItemsConforming(to: [.fileURL])
            || FileDrop.carriesUsableFile(info, into: editorState)
    }

    /// The types the timeline listens for: every file the window takes, a
    /// transition tile out of the panel's Transitions group, a title page or
    /// name card off the Library shelf, and a component off it.
    static let types: [UTType] = FileDrop.types
        + [TransitionDrag.type, TitlePresetDrag.type, UTType(ComponentDrag.typeIdentifier) ?? .data,
           BackgroundDrag.type]

    /// A moving background off the Library's catalog (`BackgroundDrag`).
    private func carriesBackground(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [BackgroundDrag.type])
    }

    /// A transition tile rather than a file (`TransitionDrag.swift`).
    private func carriesTransition(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [TransitionDrag.type])
    }

    /// A title tile off the Library shelf (`LibraryTitleTile.swift`).
    private func carriesTitle(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [TitlePresetDrag.type])
    }

    /// A component tile off the Library shelf (`LibraryComponentTile`), in a
    /// document whose timeline takes one.
    private func carriesComponent(_ info: DropInfo) -> Bool {
        editorState.timelineTakesComponents
            && info.hasItemsConforming(to: [UTType(ComponentDrag.typeIdentifier) ?? .data])
    }

    /// A picture tile off the Library's Media shelf (`DocumentImageDrag`), in
    /// a document with a timeline. It carries no file, only the picture's id
    /// on the drag. Asked of the drag itself rather than of a type, because
    /// the tile's type is the app's own and not declared to the system, which
    /// would read it as any data at all and take every file for a tile.
    @MainActor private func carriesPicture(_ info: DropInfo) -> Bool {
        editorState.timelineTakesPictures && !info.hasItemsConforming(to: [.fileURL])
            && DocumentImageDrag.idInFlight() != nil
    }

    /// The picture on the drag, read the moment it is asked for.
    @MainActor private func pictureID() -> UUID? {
        editorState.timelinePictureInAir ?? DocumentImageDrag.idInFlight()
    }

    func dropEntered(info: DropInfo) {
        if carriesBackground(info) {
            let point = info.location
            if let lifted = editorState.backgroundTileLifted { editorState.moveBackgroundHover(lifted, to: point) }
            BackgroundDrag.load(info) { [editorState] look in editorState.moveBackgroundHover(look, to: point) }
            return
        }
        if carriesPicture(info) {
            if let id = pictureID() { editorState.movePictureHover(id, to: info.location) }
            return
        }
        if carriesComponent(info) {
            let point = info.location
            // The drag pasteboard answers at once; the drag's own bytes, read
            // in the background, have the last word.
            if let lifted = ComponentDrag.payloadInFlight() { editorState.moveComponentHover(lifted, to: point) }
            ComponentDrag.load(info) { [editorState] payload in editorState.moveComponentHover(payload, to: point) }
            return
        }
        if carriesTitle(info) {
            let point = info.location
            // The tile the shelf just handed over answers at once; the drag's
            // own bytes, read in the background, have the last word.
            if let lifted = editorState.titleTileLifted { editorState.moveTitleHover(lifted, to: point) }
            TitlePresetDrag.load(info) { [editorState] preset in editorState.moveTitleHover(preset, to: point) }
            return
        }
        if carriesTransition(info) {
            let point = info.location
            // The tile the panel just handed over answers at once; the drag's
            // own bytes, read in the background, have the last word.
            if let lifted = editorState.transitionTileLifted { editorState.moveTransitionHover(lifted, to: point) }
            TransitionDrag.load(info) { [editorState] kind in editorState.moveTransitionHover(kind, to: point) }
            return
        }
        editorState.moveTimelineFileHover(to: info.location, insert: Self.insertHeld)
        guard let provider = info.itemProviders(for: [.fileURL]).first else { return }
        Task { @MainActor [editorState] in
            guard let url = await FileDrop.fileURL(from: provider) else { return }
            editorState.beginTimelineFileHover(url)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if carriesBackground(info) {
            if let look = editorState.timelineBackgroundInAir ?? editorState.backgroundTileLifted {
                editorState.moveBackgroundHover(look, to: info.location)
            }
            return DropProposal(operation: .copy)
        }
        if carriesPicture(info) {
            if let id = pictureID() { editorState.movePictureHover(id, to: info.location) }
            return DropProposal(operation: .copy)
        }
        if carriesComponent(info) {
            if let payload = editorState.timelineComponentInAir ?? ComponentDrag.payloadInFlight() {
                editorState.moveComponentHover(payload, to: info.location)
            }
            return DropProposal(operation: .copy)
        }
        if carriesTitle(info) {
            if let preset = editorState.timelineTitleInAir ?? editorState.titleTileLifted {
                editorState.moveTitleHover(preset, to: info.location)
            }
            return DropProposal(operation: .copy)
        }
        if carriesTransition(info) {
            guard let kind = editorState.timelineTransitionInAir ?? editorState.transitionTileLifted else {
                return DropProposal(operation: .copy)
            }
            editorState.moveTransitionHover(kind, to: info.location)
            // Over a cut or a clip end it lands, or says why not and offers
            // what does; anywhere else there is nothing to let go on.
            return DropProposal(operation: editorState.timelineTransitionHover?.spot == nil ? .forbidden : .copy)
        }
        editorState.moveTimelineFileHover(to: info.location, insert: Self.insertHeld)
        if let hover = editorState.timelineFileHover, !hover.landing.allowed {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        editorState.endPictureHover()
        editorState.endBackgroundHover()
        editorState.endTitleHover()
        editorState.endTransitionHover()
        editorState.endComponentHover()
    }

    func performDrop(info: DropInfo) -> Bool {
        if carriesBackground(info) {
            let point = info.location
            if let look = editorState.timelineBackgroundInAir ?? editorState.backgroundTileLifted {
                return editorState.dropBackgroundOnTimeline(look, at: point)
            }
            BackgroundDrag.load(info) { [editorState] look in editorState.dropBackgroundOnTimeline(look, at: point) }
            return true
        }
        if carriesPicture(info) {
            guard let id = pictureID() else {
                editorState.endPictureHover()
                return false
            }
            return editorState.dropPictureOnTimeline(id, at: info.location)
        }
        if carriesComponent(info) {
            let point = info.location
            if let payload = editorState.timelineComponentInAir ?? ComponentDrag.payloadInFlight() {
                return editorState.dropComponentOnTimeline(payload, at: point)
            }
            ComponentDrag.load(info) { [editorState] payload in
                editorState.dropComponentOnTimeline(payload, at: point)
            }
            return true
        }
        if carriesTitle(info) {
            let point = info.location
            if let preset = editorState.timelineTitleInAir ?? editorState.titleTileLifted {
                return editorState.dropTitle(preset, at: point)
            }
            TitlePresetDrag.load(info) { [editorState] preset in editorState.dropTitle(preset, at: point) }
            return true
        }
        if carriesTransition(info) {
            let point = info.location
            // Read already, while it was in the air: land it now, so the
            // drop answers on the frame it is let go.
            if let kind = editorState.timelineTransitionInAir ?? editorState.transitionTileLifted {
                return editorState.dropTransition(kind, at: point)
            }
            TransitionDrag.load(info) { [editorState] kind in editorState.dropTransition(kind, at: point) }
            return true
        }
        if let hover = editorState.timelineFileHover, !hover.landing.allowed {
            editorState.endTimelineFileHover()
            return false
        }
        guard let provider = info.itemProviders(for: [.fileURL]).first else {
            editorState.endTimelineFileHover()
            return FileDrop.accept(info, into: editorState)
        }
        let point = info.location
        let insert = Self.insertHeld
        let editorState = editorState
        Task { @MainActor in
            guard let url = await FileDrop.fileURL(from: provider) else { return }
            // A sound, a recording or a picture lands on the timeline.
            // Anything else is answered the way the rest of the window
            // answers it.
            if MediaFiles.kind(of: url) != nil, editorState.document?.hasTime == true {
                await editorState.dropTimelineFile(url, at: point, insert: insert)
            } else if editorState.dropPictureFileOnTimeline(url, at: point) {
                // A logo or a photo from the Finder: on the shelf and on a track.
            } else {
                editorState.endTimelineFileHover()
                if editorState.mediaDropAnswer(for: url) != nil {
                    editorState.dropMedia(at: url)
                } else {
                    editorState.addImageLayerOrOpen(at: url)
                }
            }
        }
        return true
    }
}

// MARK: - The empty slot

/// A lane with nothing on it, drawn as the place a clip goes: the mock's
/// `.lane.empty` (`video.html`, New video step 1), a dashed edge over
/// diagonal stripes. Its dashes are the drop ghost's, so the slot and the
/// clip about to fill it read as one idea; the ghost is solid and covers it
/// where the clip will land.
struct TimelineEmptySlot: View {
    @Environment(\.colorScheme) private var colorScheme

    /// `repeating-linear-gradient(45deg, transparent 6px, line 60% 6px)`:
    /// a stripe 6 points wide every 12, measured across the stripes.
    static let stripe: CGFloat = 6
    /// `border-radius: var(--r2)`, a lane's corner rather than a clip's.
    static let laneCornerRadius: CGFloat = 8

    /// The same stripes and dashes draw a retimed clip's Source ghost
    /// (`ClipSourceLane`), on a clip's smaller corner.
    var cornerRadius: CGFloat = Self.laneCornerRadius
    var readout = "empty slot"
    /// A gap between two clips (`TimelineGapSlot`) draws its own stripes.
    var stripeWidth: CGFloat = Self.stripe
    var stripeTone: VideoKit.Tone = VideoKit.Palette.line
    var stripeOpacity: Double = 0.6

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        TimelineStripes(width: stripeWidth, color: stripeTone.color(colorScheme).opacity(stripeOpacity))
        .clipShape(shape)
        .overlay(shape.strokeBorder(VideoKit.Palette.lineStrong,
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .allowsHitTesting(false)
        .panelReadout(readout)
    }
}

/// `repeating-linear-gradient(45deg, …)`: one stripe of `color`, `width`
/// across, then as much again of whatever is underneath. The empty slot, a gap
/// and a held frame all draw theirs with it, in their own tones.
struct TimelineStripes: View {
    let width: CGFloat
    let color: Color

    var body: some View {
        let stripeWidth = width
        let color = color
        Canvas { context, size in
            // Across the stripes is 45 degrees, so along the lane a stripe
            // and its gap each take the stripe's width times root 2.
            let step = stripeWidth * 2.squareRoot()
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + step, y: 0))
                path.addLine(to: CGPoint(x: x + step + size.height, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                path.closeSubpath()
                x += step * 2
            }
            context.fill(path, with: .color(color))
        }
    }
}

// MARK: - A gap

/// A gap between two clips, drawn as the cut walkthrough draws `#theGap`
/// (`video-cut-wt.html`, `.gap`): a slot the height of a clip, on a clip's
/// corner, with a dashed edge and `repeating-linear-gradient(45deg,
/// transparent 5px, panel-2 5px 10px)` inside, so a hole left by a lift or a
/// trim reads as one.
struct TimelineGapSlot: View {
    var body: some View {
        TimelineEmptySlot(cornerRadius: VideoKit.Metrics.clipCornerRadius, readout: "gap slot",
                          stripeWidth: 5, stripeTone: VideoKit.Palette.panel2, stripeOpacity: 1)
    }
}

// MARK: - The ghost

/// Where the file in the air will land, drawn on its lane the length it will
/// be: the mock's `.lane.drop`, a dashed accent edge over a wash of accent,
/// red where it cannot land. An insert draws its line at the moment it goes
/// in, since that is where everything after it will be pushed from.
struct TimelineFileGhost: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.colorScheme) private var colorScheme
    let hover: TimelineFileHover
    let laneWidth: CGFloat
    let height: CGFloat

    var body: some View {
        let ruler = editorState.motionStripRuler
        let x0 = laneWidth * ruler.fraction(ofMS: Double(hover.landing.startMS))
        let x1 = laneWidth * ruler.fraction(ofMS: Double(hover.landing.endMS))
        let tint = hover.landing.allowed ? VideoKit.Palette.accent : VideoKit.Palette.crit.color(colorScheme)
        let shape = RoundedRectangle(cornerRadius: VideoKit.Metrics.clipCornerRadius)
        ZStack(alignment: .leading) {
            // Solid underneath, so over a clip it reads as what will cover it
            // rather than a tint on top of it.
            shape.fill(VideoKit.Palette.panel)
            shape.fill(tint.opacity(0.22))
            shape.strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            HStack(spacing: 5) {
                Text(hover.landing.allowed ? hover.name : hover.note)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VideoKit.Palette.ink)
                if hover.landing.allowed {
                    Text(CaptionProgress.clock(hover.landing.startMS))
                        .font(.system(size: 10, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(VideoKit.Palette.dim)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 6)
            if hover.landing.edit == .insert, hover.landing.allowed {
                Rectangle().fill(tint).frame(width: 2).offset(x: -1)
            }
        }
        .frame(width: max(4, x1 - x0), height: height)
        .offset(x: x0)
        .allowsHitTesting(false)
        .panelReadout("landing: \(hover.note)")
    }
}

/// The ghost of a clip that will land on a track of its own: a lane's worth
/// of clip, drawn where the new track will be, rather than only the line a
/// track carried between two others draws (user 2026-10-28: "I want it to
/// look like a ghost of the other rectangle video representation").
struct TimelineNewTrackGhost: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat
    let leading: CGFloat

    var body: some View {
        if let hover = editorState.timelineFileHover, case .newTrack(let at) = hover.landing.target,
           let y = top(at: at) {
            TimelineFileGhost(hover: hover, laneWidth: laneWidth, height: TimelineDock.laneHeight)
                .frame(width: laneWidth, alignment: .leading)
                .offset(x: leading, y: y)
                .allowsHitTesting(false)
        }
    }

    /// Where the new track's lane would start: just under the track it goes
    /// after, or, at the very top, just over the first.
    private func top(at index: Int) -> CGFloat? {
        let tracks = editorState.document?.timelineTracks ?? []
        let order = tracks.map(\.id)
        // A track and the sound row under it are one place to drop, so the
        // ghost goes under the sound row, not over it.
        let joined = TrackDropRow.joiningSoundRows(editorState.trackDropRows.values.sorted { $0.minY < $1.minY },
                                                   of: tracks)
        let rows = Dictionary(joined.map { ($0.trackID, $0) }, uniquingKeysWith: { first, _ in first })
        if index > 0, index - 1 < order.count, let above = rows[order[index - 1]] {
            return above.maxY + TimelineDock.rowSpacing
        }
        if index < order.count, let below = rows[order[index]] {
            return below.minY - TimelineDock.rowSpacing - TimelineDock.laneHeight
        }
        return rows.values.map(\.maxY).max().map { $0 + TimelineDock.rowSpacing }
    }
}

// MARK: - The edit point

/// Where two clips on one track meet (`comp-video.html` §02, `.editpt`): a
/// faint hairline at rest, lit on hover, and picked with a click, which is the
/// cut a transition goes on. It has no width of its own, because a cut has no
/// duration until a transition is put on it.
///
/// The click also opens the tiles right there (`video-transition-wt.html`,
/// "At this cut"). Once a transition is on it, the cut is drawn as the band
/// over both clips (§03), as long as the transition is, and either end of the
/// band drags its length.
struct TimelineEditPointView: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.colorScheme) private var colorScheme
    let point: TimelineEditPoint
    let laneWidth: CGFloat
    let height: CGFloat

    @State private var isHovered = false
    /// Which half of the edit point the pointer is on: the outgoing clip's end
    /// (true) or the incoming clip's start (false). A drag there trims that
    /// side, as Premiere's Selection tool does on an edit point, and ⌘ makes it
    /// a ripple trim (`RippleEdgeDrag.swift`).
    @State private var hoveredOutgoingSide: Bool?

    /// `.editpt{width:9px}`: room to hit, centred on the seam.
    static let width: CGFloat = 9

    private var place: TimelineCutPlace { .edit(outgoing: point.outgoing, incoming: point.incoming) }

    var body: some View {
        if let drawn = transitionDrawn {
            ZStack(alignment: .topLeading) {
                if drawn.holdMS > 0 { held(drawn) }
                band(drawn)
                if let session = editorState.clipTransitionDrag, session.place == place {
                    TransitionLengthBubble(
                        pointerX: laneWidth * editorState.motionStripRuler.fraction(
                            ofMS: Double(point.atMS + session.pointerFromCutMS)),
                        laneWidth: laneWidth, height: height)
                }
            }
        } else {
            seam
        }
    }

    /// The black a dip holds on (`video-transition-wt.html`, `#clipBlack`):
    /// real time between the two clips, drawn like a clip of its own under
    /// the band, because it is time the timeline now has.
    private func held(_ drawn: ClipTransition) -> some View {
        let ruler = editorState.motionStripRuler
        let x = laneWidth * ruler.fraction(ofMS: Double(point.atMS))
        let width = max(2, laneWidth * ruler.fraction(spanningMS: Double(drawn.holdMS)))
        let isWhite = drawn.kind == .dipToWhite
        return RoundedRectangle(cornerRadius: 6)
            .fill(isWhite ? Color.white : VideoKit.rgb(0x05060A))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(VideoKit.rgb(0x2A2F45)))
            .overlay {
                Text(isWhite ? "White" : "Black")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isWhite ? VideoKit.rgb(0x3A3F55) : VideoKit.rgb(0x8B93B5))
                    .lineLimit(1)
            }
            .frame(width: width, height: height)
            .offset(x: x)
            .allowsHitTesting(false)
            .panelReadout("\(isWhite ? "white" : "black") held \(ClipTransitionCopy.seconds(drawn.holdMS))")
            .playtestField("Hold \(name)")
    }

    /// The transition on this cut as it is being drawn: the hand's length
    /// while its band is dragged, else what is written down.
    private var transitionDrawn: ClipTransition? {
        guard Experiments.shared.transitionsAtACutEnabled,
              let cut = editorState.document?.documentCut(at: place)?.cut else { return nil }
        return editorState.drawnClipTransition(cut, at: place)
    }

    private var seam: some View {
        let x = laneWidth * editorState.motionStripRuler.fraction(ofMS: Double(point.atMS))
        let picked = editorState.isEditPointPicked(point)
        let warn = VideoKit.Palette.warn
        let lit = picked || isHovered
        return ZStack {
            if picked {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(warn, lineWidth: 2)
                    .padding(-3)
            }
            Capsule()
                .fill(lit ? AnyShapeStyle(warn) : AnyShapeStyle(VideoKit.Palette.edgeLo))
                .frame(width: 2)
                .padding(.vertical, 2)
                .background {
                    if lit {
                        Capsule().fill(warn).opacity(picked ? 0.34 : 0.22).frame(width: 8).padding(.vertical, 1)
                    }
                }
        }
        // Drawn where the cut was until the hand lets go, so while one of its
        // clips is in a drag the cut is not drawn at all: a ripple carries the
        // next clip under where it was. Still there to hold the drag.
        .opacity(isInADrag ? 0 : 1)
        .frame(width: Self.width, height: height)
        .overlay { rippleBracket }
        .contentShape(Rectangle())
        // Each half takes hold of its own side of the cut. A press that does
        // not move falls through to the pick below.
        .overlay {
            HStack(spacing: 0) {
                side(outgoing: true)
                side(outgoing: false)
            }
        }
        .onTapGesture {
            editorState.pickEditPoint(point)
            editorState.openTransitionPicker(at: place)
        }
        .contextMenu { MenuRowsView(rows: editorState.timelineEditPointMenuRows(point)) }
        .transitionPicker(at: place, editorState: editorState)
        .playtestHover("Edit point \(name)") { isHovered = $0 }
        .playtestControl("Edit point \(name)", detail: "Timeline")
        .accessibilityLabel("Edit point \(name)")
        .accessibilityAddTraits(picked ? .isSelected : [])
        .panelHelp("The cut from \(names.out) to \(names.in)")
        .panelReadout(picked ? "edit point \(name) picked at \(CaptionProgress.clock(point.atMS))"
                             : "edit point \(name) at \(CaptionProgress.clock(point.atMS))")
        .offset(x: x - Self.width / 2)
    }

    /// One half of the edit point: hovered with ⌘ it wears the ripple
    /// bracket, and dragged it trims its own side of the cut.
    private func side(outgoing: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .playtestHover("Edit point \(name) \(outgoing ? "end" : "start")") { inside in
                if inside {
                    hoveredOutgoingSide = outgoing
                } else if hoveredOutgoingSide == outgoing {
                    hoveredOutgoingSide = nil
                }
                editorState.clipBarGripHover("\(point.id)-\(outgoing)", inside: inside)
            }
            .gesture(sideDrag(outgoing: outgoing))
    }

    /// The drag on one side: the outgoing clip's end, or the incoming clip's
    /// start, exactly as its own grip would take it, ⌘ making it a ripple.
    /// Read in the hand's space, which stays put while the edge moves.
    private func sideDrag(outgoing: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: ClipPiecesBar.handSpace)
            .onChanged { value in
                if editorState.clipBarDrag == nil {
                    let id = outgoing ? point.outgoing : point.incoming
                    guard let count = editorState.document?.layer(id: id)?.clipPieces?.count else { return }
                    editorState.beginClipBarDrag(layerID: id,
                                                 grab: outgoing ? .seam(after: count - 1) : .clipStart,
                                                 ripple: ClipPiecesBar.commandHeld)
                }
                let travel = ClipPiecesBar.ms(value.translation.width, laneWidth: laneWidth,
                                              ruler: editorState.motionStripRuler)
                let free = ClipPiecesBar.commandHeld && editorState.clipBarDrag?.ripple != true
                editorState.updateClipBarDrag(byMS: travel + editorState.timelineEdgePannedMS, free: free)
                editorState.clipBarDragHand(laneX: ClipPiecesBar.laneX(globalX: value.location.x, editorState),
                                            contentY: nil, handMS: travel, travelledY: 0, free: free)
            }
            .onEnded { _ in editorState.commitClipBarDrag() }
    }

    /// Premiere's ripple cursor drawn on the cut: a yellow bracket opening
    /// towards the clip whose edge ⌘ would ripple, while ⌘ is down with the
    /// pointer on that half.
    @ViewBuilder private var rippleBracket: some View {
        if let outgoing = rippleSide {
            RippleBracket(opensLeft: outgoing)
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .padding(.vertical, 3)
                .allowsHitTesting(false)
        }
    }

    /// Whether either clip at this cut is in a hand.
    private var isInADrag: Bool {
        guard let id = editorState.clipBarDrag?.layerID else { return false }
        return id == point.outgoing || id == point.incoming
    }

    /// Which side wears the ripple bracket, if either. Not during a drag:
    /// the cut is drawn where it was until the hand lets go, so a bracket
    /// left there would float over the clip that followed the edge, and the
    /// edge's own grip is yellow for the whole drag instead.
    private var rippleSide: Bool? {
        guard editorState.clipBarDrag == nil, editorState.clipBarCommandHeld else { return nil }
        return hoveredOutgoingSide
    }

    /// The band (`.xband`): drawn ON both clips, before, across or after the
    /// cut as it was placed, never between them, so putting it on moved
    /// nothing. A dip that holds spans its fade down, the hold and its fade up.
    private func band(_ drawn: ClipTransition) -> some View {
        let ruler = editorState.motionStripRuler
        let x0 = laneWidth * ruler.fraction(ofMS: Double(point.atMS - drawn.beforeMS))
        let width = max(6, laneWidth * ruler.fraction(spanningMS: Double(drawn.spanMS)))
        let picked = editorState.isEditPointPicked(point)
        return VideoKit.TransitionBand(isDip: !drawn.kind.needsOverlap, isSelected: picked,
                                       height: height,
                                       leadingGrip: ClipTransitionEdgeDrag.canGrab(leadingEdge: true, of: drawn),
                                       trailingGrip: ClipTransitionEdgeDrag.canGrab(leadingEdge: false, of: drawn))
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { editorState.openTransitionPicker(at: place) }
            .onTapGesture { editorState.pickEditPoint(point) }
            .contextMenu { MenuRowsView(rows: editorState.timelineEditPointMenuRows(point)) }
            .overlay(alignment: .leading) {
                if ClipTransitionEdgeDrag.canGrab(leadingEdge: true, of: drawn) { bandGrip(leading: true) }
            }
            .overlay(alignment: .trailing) {
                if ClipTransitionEdgeDrag.canGrab(leadingEdge: false, of: drawn) { bandGrip(leading: false) }
            }
            .transitionPicker(at: place, editorState: editorState)
            .playtestControl("Transition \(name)", detail: "Timeline")
            .accessibilityLabel("\(drawn.kind.title), \(name)")
            .accessibilityAddTraits(picked ? .isSelected : [])
            .panelHelp("\(drawn.kind.title), \(ClipTransitionCopy.seconds(drawn.lengthMS)). "
                       + "Drag an end to change its length.")
            .panelReadout("\(drawn.kind.title.lowercased()) \(ClipTransitionCopy.seconds(drawn.lengthMS)) "
                          + "on the cut from \(name)\(picked ? ", picked" : "")")
            .offset(x: x0)
    }

    /// One end of the band, which follows the hand (`ClipTransitionEdgeDrag`).
    private func bandGrip(leading: Bool) -> some View {
        Color.clear
            .frame(width: 8, height: height)
            .contentShape(Rectangle())
            .offset(x: leading ? -3 : 3)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: ClipPiecesBar.handSpace)
                .onChanged { value in
                    if editorState.clipTransitionDrag == nil {
                        editorState.beginClipTransitionDrag(place: place, leadingEdge: leading)
                    }
                    editorState.updateClipTransitionDrag(
                        byMS: ClipPiecesBar.ms(value.translation.width, laneWidth: laneWidth,
                                               ruler: editorState.motionStripRuler))
                }
                .onEnded { _ in editorState.commitClipTransitionDrag() })
            .playtestControl("Transition \(name) \(leading ? "start" : "end")", detail: "Timeline")
    }

    private var names: (out: String, in: String) {
        (editorState.document?.layer(id: point.outgoing)?.name ?? "clip",
         editorState.document?.layer(id: point.incoming)?.name ?? "clip")
    }

    private var name: String { "\(names.out) to \(names.in)" }
}

// MARK: - The spare either side of a picked cut

/// The spare media either side of the edit point in hand (`comp-video.html`
/// §03, `.xspare`): a dashed strip along the top from the cut rightwards, as
/// far as the outgoing clip's recording runs on past its out point, and one
/// along the bottom leftwards, as far back as the incoming clip's recording
/// goes before its in point. It is the budget Before, Across and After spend,
/// so it is drawn only while the cut is picked, and only while the clips meet:
/// in a hold the time between them is black, not spare.
struct TimelineSpareStrips: View {
    @Environment(EditorState.self) private var editorState
    let point: TimelineEditPoint
    let laneWidth: CGFloat
    let height: CGFloat

    var body: some View {
        if Experiments.shared.transitionsAtACutEnabled, editorState.isEditPointPicked(point),
           let cut = editorState.document?.documentCut(
               at: .edit(outgoing: point.outgoing, incoming: point.incoming))?.cut,
           (cut.transition?.holdMS ?? 0) == 0 {
            // A transition's band sits over the cut, so each length starts
            // past the band's edge rather than under its handle.
            let band = cut.drawnTransition
            ZStack(alignment: .topLeading) {
                if let after = cut.spareAfterOutMS, after > 0 {
                    strip(fromMS: point.atMS, lengthMS: after, alongTop: true,
                          clearOfMS: band?.afterMS ?? 0)
                }
                if let before = cut.spareBeforeInMS, before > 0 {
                    strip(fromMS: point.atMS - before, lengthMS: before, alongTop: false,
                          clearOfMS: band?.beforeMS ?? 0)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// `.xspare{height:5px}`, 3pt dashes: purple for the outgoing side, orange
    /// for the incoming one, with its length riding inside the clip body,
    /// `clearOfMS` along from the cut so a band over it does not cover it.
    private func strip(fromMS start: Int, lengthMS: Int, alongTop: Bool, clearOfMS: Int) -> some View {
        let ruler = editorState.motionStripRuler
        let x0 = max(0, laneWidth * ruler.fraction(ofMS: Double(start)))
        let x1 = min(laneWidth, laneWidth * ruler.fraction(ofMS: Double(start + lengthMS)))
        let width = max(2, x1 - x0)
        let ink = alongTop ? VideoKit.rgb(0x9A7DFF) : VideoKit.rgb(0xFFB98A)
        let label = "\(ClipTransitionCopy.seconds(lengthMS)) spare"
        let clear = clearOfMS > 0
            ? laneWidth * ruler.fraction(spanningMS: Double(clearOfMS)) + 6
            : 0
        return ZStack(alignment: alongTop ? .topLeading : .bottomTrailing) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 2.5))
                path.addLine(to: CGPoint(x: width, y: 2.5))
            }
            .stroke(ink, style: StrokeStyle(lineWidth: 5, dash: [3, 3]))
            .frame(width: width, height: 5)
            .frame(maxHeight: .infinity, alignment: alongTop ? .top : .bottom)
            Text(label)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(VideoKit.rgb(0xDBE4FF))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(VideoKit.rgb(0x080A12, 0.72)))
                .padding(alongTop ? .top : .bottom, 7)
                .padding(alongTop ? .leading : .trailing, 2 + clear)
        }
        .frame(width: width, height: height, alignment: alongTop ? .topLeading : .bottomTrailing)
        .offset(x: x0)
        .panelReadout(label)
        .playtestField(alongTop ? "Spare after strip" : "Spare before strip")
    }
}

/// Premiere's ripple bracket: a stroke down the cut with short arms at top and
/// bottom pointing into the clip being trimmed, `]` for the outgoing clip's
/// end and `[` for the incoming clip's start.
struct RippleBracket: Shape {
    let opensLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arm = rect.width / 2
        let x = rect.midX
        let tip = opensLeft ? x - arm : x + arm
        path.move(to: CGPoint(x: tip, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        path.addLine(to: CGPoint(x: tip, y: rect.maxY))
        return path
    }
}
