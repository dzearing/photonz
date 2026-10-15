import PhotonzCore
import SwiftUI

/// An animated line as something to click and right click (`AnimatedLine`):
/// a value graph, a key lane's line and a sound's volume line all lay their
/// line out through this one piece.
///
/// Only a strip along the line takes a press, so the lane around it still
/// does its own work. A click is read against the whole line (a dot, a
/// segment, the line either side), a press that travels is the surface's own
/// drag, and a right click opens the menu of the PART it landed on.
///
/// Each segment is its own strip carrying its own menu, and the line either
/// side of the dots is one more. SwiftUI hands a right click the menu it
/// built when the view last updated, BEFORE the click
/// (`CanvasContextMenuHook`), so one menu for the whole line, aimed at where
/// the click landed, was always the previous click's: Linear chosen on a
/// second segment of a value graph bent the first
/// (value-graph-second-segment-menu-walk, 2026-10-14), and a sound's segment
/// right clicked after a level point opened the point's menu
/// (a-sound-s-volume-line-menus-alternate-walk, 2026-10-15). A segment's own
/// menu is about that segment whenever it was built. Every menu is built
/// again after a right click anywhere, so each is told whether the latest
/// right click `landed` on it, and only that one may pick what it is about.
/// The dots draw on top with menus of their own, asking
/// `AnimatedLine.landed(_:on:)` too.
struct AnimatedLineSurface<Drag: Gesture, BeyondMenu: View, SegmentMenu: View>: View {
    @Environment(EditorState.self) private var editorState
    let line: AnimatedLine
    let width: CGFloat
    let height: CGFloat
    /// Where the latest right click landed, in the line's own points, or nil
    /// when it was not on this line's row.
    let rightPress: @MainActor () -> CGPoint?
    let click: (CGPoint) -> Void
    let drag: Drag
    /// The menu of the line before the first dot and after the last.
    @ViewBuilder let beyondMenu: () -> BeyondMenu
    /// Segment `index`'s menu, and whether the latest right click landed on it.
    @ViewBuilder let segmentMenu: (_ index: Int, _ landed: Bool) -> SegmentMenu

    var body: some View {
        ZStack(alignment: .topLeading) {
            strip([line.before, line.after])
                .contextMenu {
                    let _ = editorState.timelineRightPresses
                    BuiltAsItOpens { beyondMenu() }
                }
            ForEach(Array(line.segments.enumerated()), id: \.offset) { index, segment in
                strip([segment])
                    .contextMenu {
                        // Read so a right click builds the menu again, and the
                        // build after it picks the segment it landed on.
                        let _ = editorState.timelineRightPresses
                        BuiltAsItOpens { segmentMenu(index, line.landed(rightPress(), on: .segment(index))) }
                    }
            }
        }
    }

    private func strip(_ lines: [[CGPoint]]) -> some View {
        Color.clear
            .frame(width: width, height: height)
            .contentShape(LineStrip(lines: lines, width: AnimatedLine.lineReach * 2))
            .onTapGesture(coordinateSpace: .local) { click($0) }
            .gesture(drag)
    }
}

/// A menu whose contents are worked out as it opens, not when the view around
/// it is drawn: SwiftUI runs a menu's own body inside `menu(for:)`, so what is
/// in it reads the right click that opened it (`EditorState+TimelinePointing`).
struct BuiltAsItOpens<Content: View>: View {
    @ViewBuilder let content: @MainActor () -> Content

    var body: some View { content() }
}

extension BuiltAsItOpens where Content == MenuRowsView {
    init(rows: @escaping @MainActor () -> [MenuRow]) {
        self.init { MenuRowsView(rows: rows()) }
    }
}

/// A strip of the given width along some lines: what takes a press on an
/// animated line, and nothing either side of it.
struct LineStrip: Shape {
    let lines: [[CGPoint]]
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for line in lines where line.count > 1 {
            var stroke = Path()
            stroke.move(to: line[0])
            for point in line.dropFirst() { stroke.addLine(to: point) }
            path.addPath(stroke)
        }
        return path.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}
