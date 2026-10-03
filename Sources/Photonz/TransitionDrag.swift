import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

// Carrying a transition tile out of the panel's Transitions group and letting
// go of it on a cut (`video-transitions.html`, `#gEffects`): Premiere's Effects
// panel, where Cross Dissolve is dragged out of Video Transitions onto an edit
// point. Which cut it lands on is `PhotonzDocument.transitionDropPlan`; this is
// the part that knows about pointers and pasteboards.

/// The bytes a transition tile hands over, and how to read them back: the
/// kind's raw value and nothing else.
enum TransitionDrag {
    /// DECLARED in the app's Info.plist (`Scripts/build-app.sh`,
    /// `UTExportedTypeDeclarations`), for the reason `TextStyleDrag` gives: an
    /// identifier the system has never heard of carries zero bytes.
    static let typeIdentifier = "com.photonz.transition"
    static let type = UTType(typeIdentifier) ?? .data

    /// The drag a transition tile starts. Only the app's own type: a
    /// transition means nothing outside a timeline.
    static func itemProvider(_ kind: ClipTransitionKind) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = Data(kind.rawValue.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier,
                                            visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    static func kind(from data: Data?) -> ClipTransitionKind? {
        data.flatMap { String(data: $0, encoding: .utf8) }.flatMap(ClipTransitionKind.init(rawValue:))
    }

    /// The kind a drop is carrying, read off its first provider of this type.
    @MainActor static func load(_ info: DropInfo, then use: @escaping @MainActor (ClipTransitionKind) -> Void) {
        guard let provider = info.itemProviders(for: [type]).first else { return }
        _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let kind = kind(from: data) else { return }
            Task { @MainActor in use(kind) }
        }
    }
}

/// A transition tile in the air over the timeline: the place it would land,
/// if it is near one, and what landing there would do.
struct TimelineTransitionHover: Equatable {
    var kind: ClipTransitionKind
    /// The cut or clip end under the pointer, nil where it is near none.
    var spot: TransitionSpot?
    var plan: TransitionTargetPlan

    /// The track the place is on, so the ghost is drawn on that lane only.
    var trackID: UUID? { spot?.trackID }
    /// Where the place is on the document's clock.
    var atMS: Int { spot?.atMS ?? 0 }

    var lands: Bool { plan.lands }

    /// The label in the bar over the tracks: what goes on and where, the way
    /// a file in the air says Overwrite and the track. A label, not a
    /// sentence, and never nothing: a tile held where it cannot land says
    /// where it can.
    var note: String {
        switch plan {
        case .put: "\(kind.title) · \(CaptionProgress.clock(atMS))"
        case .fade(_, let end, _): "\(kind.title) · \(end.title)"
        case .refused(.noSpare): "Needs spare frames"
        case .refused(.needsTwoClips): "Needs a clip on both sides"
        case .refused(.noCutNearby): Self.nowhereNote
        }
    }

    /// What the bar says while the tile is over no place it could land.
    static let nowhereNote = "Drop on a lit cut or end"
}

extension EditorState {

    /// How far from a cut, in points on the lane, a tile let go still means
    /// that cut: the same reach at every zoom.
    static let transitionDropReachPoints: CGFloat = 16

    /// A tile has arrived over the timeline, or moved across it. `point` is in
    /// the tracks' own space.
    func moveTransitionHover(_ kind: ClipTransitionKind, to point: CGPoint) {
        timelineTransitionInAir = kind
        let next = transitionDropHover(kind, at: point)
        if timelineTransitionHover != next { timelineTransitionHover = next }
    }

    /// The tile has left the timeline without landing.
    func endTransitionHover() {
        timelineTransitionInAir = nil
        transitionTileLifted = nil
        if timelineTransitionHover != nil { timelineTransitionHover = nil }
    }

    /// Where `kind` let go at `point` would land, and what it would do there.
    /// Nil only where transitions cannot be put on at all.
    func transitionDropHover(_ kind: ClipTransitionKind, at point: CGPoint) -> TimelineTransitionHover? {
        guard Experiments.shared.transitionsAtACutEnabled, let document, document.hasTime,
              timelineLaneWidth > 0 else { return nil }
        let ruler = motionStripRuler
        let fraction = min(max(0, (point.x - TimelineDock.lanesLeading) / timelineLaneWidth), 1)
        let ms = Int(ruler.ms(atFraction: Double(fraction)).rounded())
        let reach = max(80, Int(ruler.msSpanning(fraction: Double(Self.transitionDropReachPoints / timelineLaneWidth))
            .rounded()))
        let track: UUID? = if case .onto(let id) = trackDrop(atY: point.y) { id } else { nil }
        guard let spot = document.transitionDropSpot(atMS: ms, onTrack: track, reachMS: reach) else {
            return TimelineTransitionHover(kind: kind, spot: nil, plan: .refused(.noCutNearby))
        }
        return TimelineTransitionHover(kind: kind, spot: spot, plan: document.transitionPlan(kind, on: spot.target))
    }

    /// Let go over the timeline: the tile's transition on the cut or clip end
    /// the ghost was on, as one step to undo. A place that cannot take it
    /// says why, and offers what it can take. False where it lands on nothing.
    @discardableResult
    func dropTransition(_ kind: ClipTransitionKind, at point: CGPoint) -> Bool {
        let hover = transitionDropHover(kind, at: point)
        endTransitionHover()
        guard let hover, let spot = hover.spot else { return false }
        closeTransitionPicker()
        transitionsGroupPick = kind
        return putTransition(kind, on: [spot.target])
    }
}

/// The cut a transition tile would land on, lit on its lane while the tile is
/// held over it: a dashed accent band the length the transition will be,
/// placed where it will sit, or a red one on a cut that cannot pay for it.
struct TimelineTransitionGhost: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.colorScheme) private var colorScheme
    let hover: TimelineTransitionHover
    let laneWidth: CGFloat
    let height: CGFloat

    var body: some View {
        let ruler = editorState.motionStripRuler
        let (startMS, spanMS): (Int, Int) = switch hover.plan {
        case .put(let transition, _): (hover.atMS - transition.beforeMS, transition.spanMS)
        case .fade(_, .in, let length): (hover.atMS, length)
        case .fade(_, .out, let length): (hover.atMS - length, length)
        case .refused: (hover.atMS - 100, 200)
        }
        let x0 = laneWidth * ruler.fraction(ofMS: Double(startMS))
        let width = max(8, laneWidth * ruler.fraction(spanningMS: Double(spanMS)))
        let tint = hover.lands ? VideoKit.Palette.accent : VideoKit.Palette.crit.color(colorScheme)
        let shape = RoundedRectangle(cornerRadius: 6)
        ZStack {
            // Solid underneath, as a file's ghost is, so over a clip of the
            // same blue it still reads as something about to land.
            shape.fill(VideoKit.Palette.panel)
            shape.fill(tint.opacity(0.3))
            shape.strokeBorder(tint, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            if width > 44 {
                Text(hover.kind.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VideoKit.Palette.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: width, height: height)
        .offset(x: x0)
        .allowsHitTesting(false)
        .panelReadout(hover.lands ? "\(hover.kind.title.lowercased()) would land at \(CaptionProgress.clock(hover.atMS))"
                                  : "\(hover.kind.title.lowercased()) refused at \(CaptionProgress.clock(hover.atMS))")
        .playtestField("Transition ghost")
    }
}

/// Every place a transition tile could go on one lane, lit while a tile is in
/// the air over the timeline or has just been clicked with no cut picked: a
/// bright accent mark on each cut and clip end that would take it, and a
/// faint red one on each that could not, so a person sees where to let go
/// before they let go.
struct TimelineTransitionSpots: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.colorScheme) private var colorScheme
    let kind: ClipTransitionKind
    let trackID: UUID
    let laneWidth: CGFloat
    let height: CGFloat

    var body: some View {
        let ruler = editorState.motionStripRuler
        let spots = (editorState.document?.transitionSpots() ?? []).filter { $0.trackID == trackID }
        let landing = spots.filter { editorState.document?.transitionPlan(kind, on: $0.target).lands == true }
        ZStack(alignment: .topLeading) {
            ForEach(spots, id: \.self) { spot in
                mark(lands: landing.contains(spot))
                    // Kept whole at the lane's ends, where a clip's first
                    // and last frames are.
                    .offset(x: min(max(0, laneWidth * ruler.fraction(ofMS: Double(spot.atMS)) - Self.width / 2),
                                   laneWidth - Self.width), y: 1)
            }
        }
        .frame(width: laneWidth, height: height, alignment: .topLeading)
        .allowsHitTesting(false)
        .transition(.opacity)
        .panelReadout("\(landing.count) of \(spots.count) places lit for \(kind.title.lowercased())")
        .playtestField("Transition spots")
    }

    static let width: CGFloat = 8

    /// White on an accent ring where it lands, so it reads on a clip of any
    /// colour; dark on a red ring where it cannot, so it reads as a place
    /// that says no rather than as nothing.
    private func mark(lands: Bool) -> some View {
        let crit = VideoKit.Palette.crit.color(colorScheme)
        let shape = RoundedRectangle(cornerRadius: Self.width / 2)
        return shape
            .fill(lands ? Color.white : VideoKit.rgb(0x14161D))
            .overlay(shape.strokeBorder(lands ? VideoKit.Palette.accent : crit, lineWidth: 2))
            .frame(width: Self.width, height: max(0, height - 2))
            .shadow(color: lands ? VideoKit.Palette.accent.opacity(0.8) : .clear, radius: 4)
    }
}
