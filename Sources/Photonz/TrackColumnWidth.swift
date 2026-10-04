import AppKit
import Observation
import PhotonzCore
import SwiftUI

/// How wide the column of track names is, for every timeline in the app
/// (`TrackColumn`). The person's, not the document's: dragged in one window it
/// is that wide in all of them, and it is still that wide next launch.
///
/// Live while the edge is in hand and written to the settings only when it is
/// let go, the way the dock's own height is.
@MainActor
@Observable
final class TrackColumnWidth {
    static let shared = TrackColumnWidth()
    static let defaultsKey = "timeline.trackColumnWidth"

    private(set) var width: CGFloat

    private init() {
        width = TrackColumn.width(stored: UserDefaults.standard.double(forKey: Self.defaultsKey))
    }

    /// While the edge is in hand.
    func drag(to width: CGFloat) {
        let held = TrackColumn.clamped(width)
        if held != self.width { self.width = held }
    }

    /// The edge let go: what it was left at is kept.
    func commit() {
        UserDefaults.standard.set(Double(width), forKey: Self.defaultsKey)
    }

    /// A double-click on the edge: back to the default, and nothing on file.
    func reset() {
        width = TrackColumn.defaultWidth
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    /// Reads the setting back off disk, for a walk that wiped it after the app
    /// had already read it.
    func reload() {
        width = TrackColumn.width(stored: UserDefaults.standard.double(forKey: Self.defaultsKey))
    }
}

/// The column's right edge, as a drag handle: the gap between the track names
/// and the lanes, with the left-right resize pointer over it, the way
/// Premiere's track header column widens. A line shows while the pointer is on
/// it or it is in hand; double-click puts the default back.
struct TrackColumnEdge: View {
    @State private var isHovering = false
    @State private var startWidth: CGFloat?

    var body: some View {
        let column = TrackColumnWidth.shared
        Color.clear
            .frame(width: TimelineDock.gap)
            .frame(maxHeight: .infinity)
            .overlay {
                Rectangle()
                    .fill(VideoKit.Palette.accent)
                    .frame(width: 1)
                    .opacity(isHovering || startWidth != nil ? 0.8 : 0)
                    .animation(.easeOut(duration: 0.12), value: isHovering || startWidth != nil)
            }
            .contentShape(Rectangle())
            .playtestHover("Track Column Edge") { inside in
                guard inside != isHovering else { return }
                isHovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                // Global, because the edge moves with the drag: in its own
                // space the pointer would never seem to leave it.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = startWidth ?? column.width
                        if startWidth == nil { startWidth = base }
                        column.drag(to: TrackColumn.dragged(from: base, pointerMovedRight: value.translation.width))
                    }
                    .onEnded { _ in
                        startWidth = nil
                        column.commit()
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { column.reset() })
            .help("Drag to resize the track names")
            .accessibilityLabel("Track names edge")
            .panelReadout("track names \(Int(column.width.rounded())) pt wide")
            .onDisappear {
                if isHovering { NSCursor.pop() }
                isHovering = false
            }
    }
}
