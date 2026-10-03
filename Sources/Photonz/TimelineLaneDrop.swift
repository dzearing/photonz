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
        carriesTransition(info) || info.hasItemsConforming(to: [.fileURL])
            || FileDrop.carriesUsableFile(info, into: editorState)
    }

    /// The types the timeline listens for: every file the window takes, and a
    /// transition tile out of the panel's Transitions group.
    static let types: [UTType] = FileDrop.types + [TransitionDrag.type]

    /// A transition tile rather than a file (`TransitionDrag.swift`).
    private func carriesTransition(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [TransitionDrag.type])
    }

    func dropEntered(info: DropInfo) {
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
        let editorState = editorState
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in editorState.beginTimelineFileHover(url) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
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
        editorState.endTimelineFileHover()
        editorState.endTransitionHover()
    }

    func performDrop(info: DropInfo) -> Bool {
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
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                // A sound or a recording lands on the timeline. Anything else
                // is answered the way the rest of the window answers it.
                if MediaFiles.kind(of: url) != nil, editorState.document?.hasTime == true {
                    await editorState.dropTimelineFile(url, at: point, insert: insert)
                } else {
                    editorState.endTimelineFileHover()
                    if editorState.mediaDropAnswer(for: url) != nil {
                        editorState.dropMedia(at: url)
                    } else {
                        editorState.addImageLayerOrOpen(at: url)
                    }
                }
            }
        }
        return true
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
        .frame(width: Self.width, height: height)
        .contentShape(Rectangle())
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

    /// The band (`.xband`): drawn ON both clips, before, across or after the
    /// cut as it was placed, never between them, so putting it on moved
    /// nothing. A dip that holds spans its fade down, the hold and its fade up.
    private func band(_ drawn: ClipTransition) -> some View {
        let ruler = editorState.motionStripRuler
        let x0 = laneWidth * ruler.fraction(ofMS: Double(point.atMS - drawn.beforeMS))
        let width = max(6, laneWidth * ruler.fraction(spanningMS: Double(drawn.spanMS)))
        let picked = editorState.isEditPointPicked(point)
        return VideoKit.TransitionBand(isDip: !drawn.kind.needsOverlap, isSelected: picked,
                                       height: height)
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
            ZStack(alignment: .topLeading) {
                if let after = cut.spareAfterOutMS, after > 0 {
                    strip(fromMS: point.atMS, lengthMS: after, alongTop: true)
                }
                if let before = cut.spareBeforeInMS, before > 0 {
                    strip(fromMS: point.atMS - before, lengthMS: before, alongTop: false)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// `.xspare{height:5px}`, 3pt dashes: purple for the outgoing side, orange
    /// for the incoming one, with its length riding inside the clip body.
    private func strip(fromMS start: Int, lengthMS: Int, alongTop: Bool) -> some View {
        let ruler = editorState.motionStripRuler
        let x0 = max(0, laneWidth * ruler.fraction(ofMS: Double(start)))
        let x1 = min(laneWidth, laneWidth * ruler.fraction(ofMS: Double(start + lengthMS)))
        let width = max(2, x1 - x0)
        let ink = alongTop ? VideoKit.rgb(0x9A7DFF) : VideoKit.rgb(0xFFB98A)
        let label = "\(ClipTransitionCopy.seconds(lengthMS)) spare"
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
                .padding(alongTop ? .leading : .trailing, 2)
        }
        .frame(width: width, height: height, alignment: alongTop ? .topLeading : .bottomTrailing)
        .offset(x: x0)
        .panelReadout(label)
        .playtestField(alongTop ? "Spare after strip" : "Spare before strip")
    }
}
