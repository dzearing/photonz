import AppKit
import PhotonzCore
import SwiftUI

/// One part of a title on its row under the title: a bar from where the part
/// starts coming in to where it has gone, its in and its out shaded at either
/// end, a grip at each end (task
/// `a-title-page-s-parts-each-have-their-own-labelle`).
///
/// Dragging an end changes when that part comes in or goes, and nothing else;
/// dragging the middle slides the part inside the title. It catches on the
/// playhead, the title's ends, the other parts' ends and the markers, and the
/// whole drag is one undo step.
struct TimelineTitlePartBar: View {
    @Environment(EditorState.self) private var editorState
    let timing: TitlePartTiming
    let kind: TimelineTrackKind
    let laneWidth: CGFloat
    let height: CGFloat

    /// Where the bar's left end is in the space the hand is read in.
    @State private var barMinX: CGFloat = 0
    @State private var carrying = false

    /// How wide the grab zone at each end is (`MotionStripBar.gripWidth`).
    private static let gripWidth: CGFloat = 7
    private static let minimumWidth: CGFloat = 16
    /// How near, in points, an end comes to a moment before it catches on it.
    private static let catchPoints: CGFloat = 6

    var body: some View {
        let x0 = x(timing.startMS)
        let width = max(Self.minimumWidth, x(timing.endMS) - x0)
        let inWidth = min(width, max(0, x(timing.inEndMS) - x0))
        let outWidth = min(width, max(0, x(timing.endMS) - x(timing.outStartMS)))
        let isPicked = editorState.selectedLayerID == timing.pieceID
        let clip = TimelineTrackRow.clipKind(kind)
        RoundedRectangle(cornerRadius: 5)
            .fill(clip.fill)
            .overlay(alignment: .leading) { ramp(arriving: true).frame(width: inWidth) }
            .overlay(alignment: .trailing) { ramp(arriving: false).frame(width: outWidth) }
            .overlay(alignment: .leading) {
                Text(timing.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.leading, 9)
                    .padding(.trailing, 9)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isPicked ? AnyShapeStyle(VideoKit.Palette.accent)
                                           : AnyShapeStyle(clip.border ?? .clear),
                                  lineWidth: isPicked ? 2 : 1)
            }
            .overlay(alignment: .leading) { grip }
            .overlay(alignment: .trailing) { grip }
            .frame(width: width, height: max(10, height - 4))
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: ClipPiecesBar.handSpace).minX
            } action: { barMinX = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let at):
                    (grab(at: at.x, width: width) == .body ? NSCursor.arrow : NSCursor.resizeLeftRight).set()
                case .ended:
                    if !carrying { NSCursor.arrow.set() }
                }
            }
            .gesture(drag(width: width))
            .onTapGesture { pick() }
            .help("\(timing.name): \(reading(timing.startMS)) to \(reading(timing.endMS))")
            .accessibilityLabel("\(timing.name), \(reading(timing.startMS)) to \(reading(timing.endMS))")
            .playtestControl("Part bar \(timing.name)", detail: "Timeline")
            .panelReadout("part \(timing.name): in \(timing.startMS)-\(timing.inEndMS) ms, "
                          + "out \(timing.outStartMS)-\(timing.endMS) ms" + (isPicked ? ", picked" : ""))
            .offset(x: x0)
            .frame(maxHeight: .infinity, alignment: .center)
    }

    /// Where a moment of the title is across the lane.
    private func x(_ ms: Int) -> CGFloat {
        laneWidth * editorState.motionStripRuler.fraction(ofMS: Double(timing.titleInMS + ms))
    }

    /// The in or the out drawn as a wedge darkening the bar where the part is
    /// still on its way, the way the title's own bar draws its out.
    private func ramp(arriving: Bool) -> some View {
        Canvas { context, size in
            var wedge = Path()
            if arriving {
                wedge.move(to: .zero)
                wedge.addLine(to: CGPoint(x: size.width, y: 0))
                wedge.addLine(to: CGPoint(x: 0, y: size.height))
            } else {
                wedge.move(to: CGPoint(x: 0, y: 0))
                wedge.addLine(to: CGPoint(x: size.width, y: 0))
                wedge.addLine(to: CGPoint(x: size.width, y: size.height))
            }
            wedge.closeSubpath()
            context.fill(wedge, with: .color(.black.opacity(0.38)))
        }
        .allowsHitTesting(false)
    }

    private var grip: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(.white.opacity(0.85))
            .frame(width: 3)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .allowsHitTesting(false)
    }

    private func reading(_ ms: Int) -> String {
        MotionStripRuler.timecode(Double(timing.titleInMS + ms))
    }

    private func pick() {
        guard let titleID = editorState.document?.titleLayerID(containing: timing.pieceID) else { return }
        editorState.selectLayer(timing.pieceID, inGroup: titleID)
    }

    private func drag(width: CGFloat) -> some Gesture {
        // Read in a space that does not move with the bar (`MotionStripBar.drag`).
        DragGesture(minimumDistance: 1, coordinateSpace: ClipPiecesBar.handSpace)
            .onChanged { value in
                if !carrying {
                    carrying = true
                    editorState.beginTitlePartDrag(pieceID: timing.pieceID,
                                                   grab: grab(at: value.startLocation.x - barMinX, width: width))
                }
                editorState.updateTitlePartDrag(byMS: ms(value.translation.width), catchMS: catchMS)
            }
            .onEnded { value in
                guard carrying else { return }
                carrying = false
                editorState.updateTitlePartDrag(byMS: ms(value.translation.width), catchMS: catchMS)
                editorState.commitTitlePartDrag()
                NSCursor.arrow.set()
            }
    }

    /// Which part of the bar the hand came down on. A bar too short for three
    /// zones is all body.
    private func grab(at x: CGFloat, width: CGFloat) -> TitlePartGrab {
        guard width >= Self.gripWidth * 3 else { return .body }
        if x <= Self.gripWidth { return .start }
        if x >= width - Self.gripWidth { return .end }
        return .body
    }

    private var catchMS: Int {
        Int(editorState.motionStripRuler.msSpanning(fraction: Double(Self.catchPoints / max(1, laneWidth))).rounded())
    }

    private func ms(_ points: CGFloat) -> Int {
        Int(editorState.motionStripRuler.msSpanning(fraction: Double(points / max(1, laneWidth))).rounded())
    }
}
