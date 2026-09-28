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

/// Where a transition tile in the air over the timeline would land.
struct TimelineTransitionHover: Equatable {
    var kind: ClipTransitionKind
    var plan: DefaultTransitionPlan
    /// The track the cut is on, so the ghost is drawn on that lane only.
    var trackID: UUID?
    /// Where the cut is on the document's clock.
    var atMS: Int

    var lands: Bool {
        if case .put = plan { return true }
        return false
    }

    /// The label in the bar over the tracks: what goes on and where, the way
    /// a file in the air says Overwrite and the track. A label, not a sentence.
    var note: String {
        switch plan {
        case .put: "\(kind.title) · \(CaptionProgress.clock(atMS))"
        case .refused(.noSpare): "Needs spare frames"
        case .refused(.noCutNearby): ""
        }
    }
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
        if timelineTransitionHover != nil { timelineTransitionHover = nil }
    }

    /// Where `kind` let go at `point` would land, nil where the pointer is not
    /// near any cut at all.
    func transitionDropHover(_ kind: ClipTransitionKind, at point: CGPoint) -> TimelineTransitionHover? {
        guard Experiments.shared.transitionsAtACutEnabled, let document, document.hasTime,
              timelineLaneWidth > 0 else { return nil }
        let ruler = motionStripRuler
        let fraction = min(max(0, (point.x - TimelineDock.lanesLeading) / timelineLaneWidth), 1)
        let ms = Int(ruler.ms(atFraction: Double(fraction)).rounded())
        let reach = max(80, Int(ruler.msSpanning(fraction: Double(Self.transitionDropReachPoints / timelineLaneWidth))
            .rounded()))
        let track: UUID? = if case .onto(let id) = trackDrop(atY: point.y) { id } else { nil }
        let plan = document.transitionDropPlan(kind, atMS: ms, onTrack: track, reachMS: reach)
        switch plan {
        case .put(_, let place):
            let at = document.documentCut(at: place)?.atMS ?? ms
            return TimelineTransitionHover(kind: kind, plan: plan,
                                           trackID: document.trackID(ofClip: place.arrivingClip), atMS: at)
        case .refused(.noSpare):
            // The cut is there and cannot pay: said on the cut, in red.
            let cut = document.transitionCuts(among: nil)
                .filter { track == nil || document.trackID(ofClip: $0.place.arrivingClip) == track }
                .min { abs($0.atMS - ms) < abs($1.atMS - ms) }
            return TimelineTransitionHover(kind: kind, plan: plan,
                                           trackID: cut.flatMap { document.trackID(ofClip: $0.place.arrivingClip) },
                                           atMS: cut?.atMS ?? ms)
        case .refused(.noCutNearby):
            return nil
        }
    }

    /// Let go over the timeline: the tile's transition on the cut the ghost
    /// was on, as one step to undo. False where it lands on nothing.
    @discardableResult
    func dropTransition(_ kind: ClipTransitionKind, at point: CGPoint) -> Bool {
        let hover = transitionDropHover(kind, at: point)
        endTransitionHover()
        guard let hover else { return false }
        switch hover.plan {
        case .put(_, let place):
            closeTransitionPicker()
            transitionsGroupPick = kind
            setTransition(kind, at: place)
            return true
        case .refused(let why):
            raiseCanvasNotice(.defaultTransitionRefused(why))
            return false
        }
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
