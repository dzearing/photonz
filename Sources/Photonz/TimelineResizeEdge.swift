import AppKit
import SwiftUI

/// The timeline dock's top edge, as a drag handle: the same 1pt line and the
/// same wide, invisible grab strip as the right panel's leading edge
/// (`InspectorResizeHandle`), turned on its side. Drag it up for more tracks
/// and down for more picture; double-click it for the height the dock always
/// had (user 2026-09-28).
///
/// It only reports the pointer. What that does to the dock, and where it
/// stops, is `TimelineDockHeight`'s, in the dock.
struct TimelineResizeEdge: View {
    /// How far the pointer has moved DOWN since the press, live.
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void
    /// A double-click: back to the default height.
    let onReset: () -> Void

    /// The strip a hand has to hit, centred on the 1pt line. Same as the
    /// panel's edge, which is the point: one feel for both.
    static let grabHeight: CGFloat = 14

    /// Whether the pointer is on the strip, so the cursor is pushed and popped
    /// exactly once each.
    @State private var isHovering = false

    var body: some View {
        Divider()
            .frame(height: 1)
            .overlay {
                Color.clear
                    .frame(height: Self.grabHeight)
                    .contentShape(Rectangle())
                    .playtestHover("Timeline Edge") { inside in
                        guard inside != isHovering else { return }
                        isHovering = inside
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        // Global, because the edge moves with the drag: in its
                        // own space the pointer would never seem to leave it.
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { onDrag($0.translation.height) }
                            .onEnded { _ in onEnd() }
                    )
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onReset() })
                    .help("Drag to resize the timeline")
            }
            .onDisappear {
                if isHovering { NSCursor.pop() }
                isHovering = false
            }
    }
}
