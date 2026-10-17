import AppKit
import PhotonzCore
import SwiftUI

/// One part of a logo, a group or a component on its row under it: a bar for
/// when that part is on screen, a grip at each end (task
/// `any-timeline-row-that-holds-sub-layers-expands-a`).
///
/// Dragging an end changes when that part comes on or goes, and nothing else;
/// dragging the middle slides it, its keys with it. It stays inside what it is
/// part of, catches on the playhead, the other parts' ends and the markers,
/// and the whole drag is one undo step. A title's parts have their own bar
/// (`TimelineTitlePartBar`), timed through the title's design.
struct TimelinePartBar: View {
    @Environment(EditorState.self) private var editorState
    let stretch: LayerPartStretch
    let name: String
    let kind: TimelineTrackKind
    let laneWidth: CGFloat
    let height: CGFloat

    @State private var barMinX: CGFloat = 0
    @State private var carrying = false

    private static let gripWidth: CGFloat = 7
    private static let minimumWidth: CGFloat = 16
    private static let catchPoints: CGFloat = 6

    /// A part of a copy of a component is drawn, never dragged: its contents
    /// are its original's, and the next sync would undo the drag.
    private var canDrag: Bool { !stretch.isInsideACopy }

    var body: some View {
        let x0 = x(stretch.startMS)
        let width = max(Self.minimumWidth, x(stretch.endMS) - x0)
        let isPicked = editorState.selectedLayerID == stretch.layerID
        let clip = TimelineTrackRow.clipKind(kind)
        RoundedRectangle(cornerRadius: 5)
            .fill(clip.fill)
            .overlay(alignment: .leading) {
                Text(name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isPicked ? AnyShapeStyle(VideoKit.Palette.accent)
                                           : AnyShapeStyle(clip.border ?? .clear),
                                  lineWidth: isPicked ? 2 : 1)
            }
            .overlay(alignment: .leading) { if canDrag { grip } }
            .overlay(alignment: .trailing) { if canDrag { grip } }
            .frame(width: width, height: max(10, height - 4))
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: ClipPiecesBar.handSpace).minX
            } action: { barMinX = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard canDrag else { return }
                switch phase {
                case .active(let at):
                    (grab(at: at.x, width: width) == .body ? NSCursor.arrow : NSCursor.resizeLeftRight).set()
                case .ended:
                    if !carrying { NSCursor.arrow.set() }
                }
            }
            .gesture(drag(width: width), including: canDrag ? .all : .none)
            .onTapGesture { pick() }
            .help("\(name): \(reading(stretch.startMS)) to \(reading(stretch.endMS))")
            .accessibilityLabel("\(name), \(reading(stretch.startMS)) to \(reading(stretch.endMS))")
            .playtestControl("Part bar \(name)", detail: "Timeline")
            .panelReadout("part \(name): \(stretch.startMS)-\(stretch.endMS) ms"
                          + (stretch.hasOwnTime ? ", own time" : "") + (isPicked ? ", picked" : ""))
            .offset(x: x0)
            .frame(maxHeight: .infinity, alignment: .center)
    }

    private func x(_ ms: Int) -> CGFloat {
        laneWidth * editorState.motionStripRuler.fraction(ofMS: Double(ms))
    }

    private var grip: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(.white.opacity(0.85))
            .frame(width: 3)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .allowsHitTesting(false)
    }

    private func reading(_ ms: Int) -> String { MotionStripRuler.timecode(Double(ms)) }

    private func pick() {
        editorState.selectLayer(stretch.layerID, inGroup: editorState.document?.parentID(of: stretch.layerID))
    }

    private func drag(width: CGFloat) -> some Gesture {
        // Read in a space that does not move with the bar (`MotionStripBar.drag`).
        DragGesture(minimumDistance: 1, coordinateSpace: ClipPiecesBar.handSpace)
            .onChanged { value in
                if !carrying {
                    carrying = true
                    editorState.beginPartBarDrag(pieceID: stretch.layerID,
                                                 grab: grab(at: value.startLocation.x - barMinX, width: width))
                }
                editorState.updatePartBarDrag(byMS: ms(value.translation.width), catchMS: catchMS)
            }
            .onEnded { value in
                guard carrying else { return }
                carrying = false
                editorState.updatePartBarDrag(byMS: ms(value.translation.width), catchMS: catchMS)
                editorState.commitPartBarDrag()
                NSCursor.arrow.set()
            }
    }

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

/// A closed row's summary of what is inside it: a thin faint line along the
/// foot of its bar for each part whose timing is its own, so a person can see
/// there is something inside to open up and retime. Nothing on an open row,
/// whose parts have rows of their own, and nothing where every part runs the
/// whole way.
struct TimelineChildMarks: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let laneWidth: CGFloat
    let height: CGFloat

    var body: some View {
        let marks = editorState.timelineChildMarks(of: layerID)
        if !marks.isEmpty {
            let ruler = editorState.motionStripRuler
            Canvas { context, size in
                for (index, mark) in marks.enumerated() {
                    let x0 = size.width * ruler.fraction(ofMS: Double(mark.inMS))
                    let x1 = size.width * ruler.fraction(ofMS: Double(mark.outMS))
                    // Stacked a hair apart at the foot of the bar, so two parts
                    // that overlap read as two.
                    let y = size.height - 5 - CGFloat(index % 3) * 2.5
                    let line = CGRect(x: x0 + 2, y: y, width: max(2, x1 - x0 - 4), height: 1.5)
                    context.fill(Path(roundedRect: line, cornerRadius: 0.75), with: .color(.white.opacity(0.55)))
                }
            }
            .frame(width: laneWidth, height: height)
            .allowsHitTesting(false)
            .panelReadout("\(marks.count) part timing mark\(marks.count == 1 ? "" : "s")")
        }
    }
}
