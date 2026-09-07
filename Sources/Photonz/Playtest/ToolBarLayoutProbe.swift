// How tall each glass group along the bottom of the canvas actually is.
//
// "The zoom group sits at a different height from the ones beside it" is a
// claim about pixels, and a screenshot only proves it to a person who looks at
// it closely. This records every group's live frame so a walk can read the
// numbers back as words, and so a regression shows up as a failing height
// rather than as a picture nobody compared.
//
// Probe builds only: the shipping app compiles the no-ops at the bottom.
import SwiftUI

#if PHOTONZ_PLAYTEST

/// The bottom row's last measured layout. Held by reference and deliberately
/// NOT observable: these frames are written on every layout pass, and redrawing
/// the bar to remember a number nothing draws is exactly the jank the tool bar
/// comments warn about.
@MainActor final class ToolBarLayoutProbe {
    static let shared = ToolBarLayoutProbe()

    /// Every group currently on screen, by the name the bar gave it, in the
    /// window's coordinates.
    var groups: [String: CGRect] = [:]
    /// Draw order, so the log reads left to right instead of alphabetically.
    var order: [String] = []

    func record(_ name: String, frame: CGRect) {
        if !order.contains(name) { order.append(name) }
        groups[name] = frame
    }

    func forget(_ name: String) {
        groups.removeValue(forKey: name)
    }

    /// The groups on screen, left to right.
    var measured: [(name: String, frame: CGRect)] {
        order.compactMap { name in groups[name].map { (name, $0) } }
            .sorted { $0.frame.minX < $1.frame.minX }
    }
}

extension View {
    /// Registers this view as one of the bottom row's glass groups, under the
    /// name a walk reads it back by. Put it on the group's outermost view, the
    /// one that draws the capsule, so the measurement is the capsule.
    func toolBarGroupProbe(_ name: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            ToolBarLayoutProbe.shared.record(name, frame: frame)
        }
        .onDisappear { ToolBarLayoutProbe.shared.forget(name) }
    }
}

#else

extension View {
    func toolBarGroupProbe(_ name: String) -> some View { self }
}

#endif
