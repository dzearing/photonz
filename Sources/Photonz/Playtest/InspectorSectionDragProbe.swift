// Carrying a dock section, for a scripted walk.
//
// A walk cannot press the header and pull: SwiftUI's gestures do not answer
// mouse events posted into the app's queue, the same wall `dragComponent` hits
// with a system drag and `scrollPanel` hits with a synthesized wheel. A press
// on a Button lands; a press on a `.gesture` does not.
//
// So the dock lends the walk the very handlers its own gesture calls. What a
// walk drives here is the whole of the reorder — where the pointer is, which
// section moves aside, what the panel promises, what order it is left in — and
// the one thing it does not cover is the six lines of gesture that turn a
// press into those calls.
//
// Probe builds only; the shipping app compiles the no-op at the bottom.
import SwiftUI

#if PHOTONZ_PLAYTEST

/// The dock's reorder, reachable by name from a walk.
@MainActor final class InspectorSectionDragProbe {
    static let shared = InspectorSectionDragProbe()

    /// Move the pointer while carrying `section`: where it is, measured down
    /// from the top of the dock's visible area, and how far it has carried the
    /// section from where it started.
    var carry: ((InspectorSectionID, CGFloat, CGFloat) -> Void)?
    /// Let go.
    var end: (() -> Void)?
    /// Escape: put it back.
    var cancel: (() -> Void)?
    /// The sections on screen, in draw order, as the dock sees them.
    var sections: [InspectorSectionID] = []
}

extension View {
    func inspectorSectionDragProbe(
        carry: @escaping (InspectorSectionID, CGFloat, CGFloat) -> Void,
        end: @escaping () -> Void,
        cancel: @escaping () -> Void,
        sections: [InspectorSectionID]
    ) -> some View {
        onChange(of: sections, initial: true) { _, ids in
            let probe = InspectorSectionDragProbe.shared
            probe.carry = carry
            probe.end = end
            probe.cancel = cancel
            probe.sections = ids
        }
    }
}

#else

extension View {
    func inspectorSectionDragProbe(
        carry: @escaping (InspectorSectionID, CGFloat, CGFloat) -> Void,
        end: @escaping () -> Void,
        cancel: @escaping () -> Void,
        sections: [InspectorSectionID]
    ) -> some View { self }
}

#endif
