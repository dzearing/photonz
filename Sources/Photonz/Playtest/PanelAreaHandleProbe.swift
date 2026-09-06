// The grab bar under a bounded panel area, reachable by name from a walk.
//
// A walk cannot press the bar and pull: SwiftUI's gestures do not answer mouse
// events posted into the app's queue, the same wall `dragSection` hits with the
// dock's reorder. So the bar lends the walk the very handlers its own gesture
// calls, along with the numbers it is deciding from — how tall the area is now,
// how tall its content wants to be, and whether there is a bar there at all.
//
// That last one is the point. The bar was drawn under a two row list, changed
// the pointer to a resize cursor, and moved nothing; nothing in a picture says
// so, and only a step that drags it and reads back the height can.
//
// Probe builds only; the shipping app compiles the no-op at the bottom.
import SwiftUI
import PhotonzCore

/// What a walk reads off a resizable panel area, and what makes the probe
/// notice it has changed.
struct PanelAreaHandleReading: Equatable {
    /// The name a walk calls this area by: "Layers", "Library".
    let area: String
    /// Whether a grab bar is drawn under it at all.
    let isShown: Bool
    /// How tall the area is right now.
    let height: CGFloat
    /// How tall it would be with no ceiling on it.
    let contentHeight: CGFloat
    /// The floor a drag stops at.
    let minHeight: CGFloat
    /// The highest ceiling the panel allows.
    let maxAllowedHeight: CGFloat
}

#if PHOTONZ_PLAYTEST

/// Every resizable area in the dock, by name.
///
/// Held by reference and deliberately NOT observable: these numbers are
/// written on every frame of a drag, and redrawing the dock to remember a
/// number nothing draws is the jank the panel's own comments are about.
@MainActor final class PanelAreaHandleProbe {
    static let shared = PanelAreaHandleProbe()

    struct Handle {
        let reading: PanelAreaHandleReading
        /// Move the pointer, that far down from where the drag started.
        let carry: (CGFloat) -> Void
        /// Let go.
        let end: () -> Void
    }

    var handles: [String: Handle] = [:]

    /// The areas a walk could name, for the refusal when it names another.
    var names: [String] { handles.keys.sorted() }

    func handle(named name: String) -> Handle? {
        handles.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

extension View {
    func panelAreaHandleProbe(_ reading: PanelAreaHandleReading,
                              carry: @escaping (CGFloat) -> Void,
                              end: @escaping () -> Void) -> some View {
        onChange(of: reading, initial: true) { _, reading in
            PanelAreaHandleProbe.shared.handles[reading.area] =
                PanelAreaHandleProbe.Handle(reading: reading, carry: carry, end: end)
        }
    }
}

#else

extension View {
    func panelAreaHandleProbe(_ reading: PanelAreaHandleReading,
                              carry: @escaping (CGFloat) -> Void,
                              end: @escaping () -> Void) -> some View { self }
}

#endif
