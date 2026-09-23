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
        info.hasItemsConforming(to: [.fileURL]) || FileDrop.carriesUsableFile(info, into: editorState)
    }

    func dropEntered(info: DropInfo) {
        editorState.moveTimelineFileHover(to: info.location, insert: Self.insertHeld)
        guard let provider = info.itemProviders(for: [.fileURL]).first else { return }
        let editorState = editorState
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in editorState.beginTimelineFileHover(url) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        editorState.moveTimelineFileHover(to: info.location, insert: Self.insertHeld)
        if let hover = editorState.timelineFileHover, !hover.landing.allowed {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        editorState.endTimelineFileHover()
    }

    func performDrop(info: DropInfo) -> Bool {
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
struct TimelineEditPointView: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.colorScheme) private var colorScheme
    let point: TimelineEditPoint
    let laneWidth: CGFloat
    let height: CGFloat

    @State private var isHovered = false

    /// `.editpt{width:9px}`: room to hit, centred on the seam.
    static let width: CGFloat = 9

    var body: some View {
        let x = laneWidth * editorState.motionStripRuler.fraction(ofMS: Double(point.atMS))
        let picked = editorState.isEditPointPicked(point)
        let warn = VideoKit.Palette.warn
        let lit = picked || isHovered
        ZStack {
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
        .onTapGesture { editorState.pickEditPoint(point) }
        .playtestHover("Edit point \(name)") { isHovered = $0 }
        .playtestControl("Edit point \(name)", detail: "Timeline")
        .accessibilityLabel("Edit point \(name)")
        .accessibilityAddTraits(picked ? .isSelected : [])
        .panelHelp("The cut from \(names.out) to \(names.in)")
        .panelReadout(picked ? "edit point \(name) picked at \(CaptionProgress.clock(point.atMS))"
                             : "edit point \(name) at \(CaptionProgress.clock(point.atMS))")
        .offset(x: x - Self.width / 2)
    }

    private var names: (out: String, in: String) {
        (editorState.document?.layer(id: point.outgoing)?.name ?? "clip",
         editorState.document?.layer(id: point.incoming)?.name ?? "clip")
    }

    private var name: String { "\(names.out) to \(names.in)" }
}
