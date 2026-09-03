// Where the inspector's sections actually sit, for the scripted playtest.
//
// "Corner Radius is reachable without scrolling" is a claim about pixels, and
// a snapshot only proves it to a person who looks at it. This records each
// section's live frame inside the dock's scroll viewport so a walk can read
// back, as words, which sections a person can see and which ones are below the
// fold. Probe builds only: the shipping app compiles the no-ops at the bottom.
import SwiftUI

#if PHOTONZ_PLAYTEST

/// The dock's last measured layout. Held by reference and deliberately NOT
/// observable: these numbers are written on every scroll tick, and redrawing
/// the dock to remember a number nothing draws is the jank InspectorPanel's
/// own comments are about.
@MainActor final class InspectorLayoutProbe {
    static let shared = InspectorLayoutProbe()

    struct Section {
        let id: InspectorSectionID
        let title: String
        let frame: CGRect
    }

    /// The sections currently in the dock, in the order they are drawn.
    var visible: [InspectorSectionID] = []
    /// Every section's frame in the scroll viewport's coordinates, so a
    /// negative `minY` means scrolled off the top and a `maxY` past the
    /// viewport height means below the fold.
    var frames: [InspectorSectionID: Section] = [:]
    /// How tall the scrolling area is.
    var viewportHeight: CGFloat = 0

    /// The visible sections with a measurement, in draw order.
    var measured: [Section] {
        visible.compactMap { frames[$0] }
    }

    /// A section counts as reachable when all of it is inside the viewport.
    func isFullyVisible(_ section: Section) -> Bool {
        guard viewportHeight > 0 else { return false }
        return section.frame.minY >= -0.5 && section.frame.maxY <= viewportHeight + 0.5
    }

    /// ...and as started when its header is inside it, which is the weaker
    /// claim a collapsed section can make.
    func isHeaderVisible(_ section: Section) -> Bool {
        guard viewportHeight > 0 else { return false }
        return section.frame.minY >= -0.5 && section.frame.minY <= viewportHeight - 24
    }
}

@MainActor func recordInspectorSection(_ id: InspectorSectionID, title: String, frame: CGRect) {
    InspectorLayoutProbe.shared.frames[id] =
        InspectorLayoutProbe.Section(id: id, title: title, frame: frame)
}

@MainActor func recordInspectorViewportHeight(_ height: CGFloat) {
    InspectorLayoutProbe.shared.viewportHeight = height
}

extension View {
    /// Tells the probe which sections the dock is drawing, in order.
    func inspectorLayoutProbe(sections: [InspectorSectionID]) -> some View {
        onChange(of: sections, initial: true) { _, ids in
            InspectorLayoutProbe.shared.visible = ids
        }
    }
}

#else

@MainActor func recordInspectorSection(_ id: InspectorSectionID, title: String, frame: CGRect) {}
@MainActor func recordInspectorViewportHeight(_ height: CGFloat) {}

extension View {
    func inspectorLayoutProbe(sections: [InspectorSectionID]) -> some View { self }
}

#endif
