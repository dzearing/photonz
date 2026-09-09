// Where the inspector's sections actually sit, for the scripted playtest.
//
// "Corner Radius is reachable without scrolling" is a claim about pixels, and
// a snapshot only proves it to a person who looks at it. This records each
// section's live frame inside the dock's scroll viewport so a walk can read
// back, as words, which sections a person can see and which ones are below the
// fold. Probe builds only: the shipping app compiles the no-ops at the bottom.
import PhotonzCore
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
    /// Where the scrolling area sits in the WINDOW, so a step that has to put
    /// a pointer on a section can turn a section's frame into a point the
    /// window understands.
    var dockFrame: CGRect = .zero
    /// The section currently being carried, by its title, so a walk can say
    /// the dock really did pick one up rather than only that it looks lifted.
    var carrying: String?
    /// What the panel last did about an effect you opened, in words: which
    /// effect, where it was sitting, and whether the panel had to move to put
    /// it on screen. A reveal that decided to do nothing says so too, since
    /// "it was already all there" is the answer half the time and a walk
    /// reading an empty line could not tell that from a reveal that never ran.
    var effectReveal: String?
    /// What the height budget did to each list section this pass, so a walk can
    /// say "nothing in Effects is cut across the middle" in words rather than
    /// by someone squinting at a capture.
    var listRoom: [InspectorSectionID: ListRoom] = [:]

    /// One list section's side of the height budget.
    ///
    /// This deliberately records the RAW measurements rather than the floor the
    /// panel worked out from them, so a walk checking the promise is not asking
    /// the same code that made it: a floor that stopped being applied would
    /// otherwise lower the bar and the check with it.
    struct ListRoom: Equatable {
        /// How tall the body would be if nothing were taken from it.
        let natural: CGFloat
        /// What it was actually drawn at.
        let drawn: CGFloat
        /// The entries this list is made of, when it is a stack of panes.
        /// Empty for a list of plain rows, which may be cut anywhere.
        let panes: [DockHeightBudget.Block]
        /// The gap between two panes, the padding above and below the stack,
        /// and how much of the next entry a cut is meant to leave showing.
        let spacing: CGFloat
        let topInset: CGFloat
        let bottomInset: CGFloat
        let peek: CGFloat
        /// How much dock there is to share out, so a check knows when a single
        /// pane is simply too tall to promise whole.
        let room: CGFloat?

        /// The height that draws every entry down to and including the first
        /// open one, whole. Nil for a list of rows, which promises nothing.
        var needsForFirstOpen: CGFloat? {
            guard let open = panes.firstIndex(where: \.isOpen) else { return nil }
            let through = panes.prefix(through: open)
            var wanted = topInset + through.reduce(0) { $0 + $1.height }
                + spacing * CGFloat(through.count - 1)
            wanted += open == panes.count - 1 ? bottomInset : spacing + peek
            guard let room else { return wanted }
            return min(wanted, room * DockHeightBudget.floorShareOfDock)
        }

        /// Whether the cut, if there is one, falls past everything the dock
        /// promised to keep whole.
        var keepsItsFloor: Bool {
            guard let needs = needsForFirstOpen else { return true }
            return drawn >= min(natural, needs) - 0.5
        }
    }

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

@MainActor func recordInspectorDockFrame(_ frame: CGRect) {
    InspectorLayoutProbe.shared.dockFrame = frame
}

@MainActor func recordInspectorCarrying(_ title: String?) {
    InspectorLayoutProbe.shared.carrying = title
}

@MainActor func recordEffectReveal(_ id: String, frame: CGRect,
                                   room: CGFloat, action: DockReveal.Action) {
    func points(_ value: CGFloat) -> String { "\(Int(value.rounded()))" }
    let where_ = "\(id) \(points(frame.height))pt at \(points(frame.minY))-\(points(frame.maxY)), "
        + "room \(points(room))pt"
    InspectorLayoutProbe.shared.effectReveal = switch action {
    case .none: "\(where_): already all on screen, nothing moved"
    case .top: "\(where_): scrolled to its top"
    case .bottom: "\(where_): scrolled up to its bottom"
    }
}

@MainActor func recordInspectorListRoom(_ id: InspectorSectionID,
                                        natural: CGFloat, drawn: CGFloat,
                                        panes: [DockHeightBudget.Block],
                                        spacing: CGFloat, topInset: CGFloat,
                                        bottomInset: CGFloat, peek: CGFloat, room: CGFloat?) {
    InspectorLayoutProbe.shared.listRoom[id] =
        InspectorLayoutProbe.ListRoom(natural: natural, drawn: drawn, panes: panes,
                                      spacing: spacing, topInset: topInset,
                                      bottomInset: bottomInset, peek: peek, room: room)
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
@MainActor func recordInspectorDockFrame(_ frame: CGRect) {}
@MainActor func recordInspectorCarrying(_ title: String?) {}
@MainActor func recordEffectReveal(_ id: String, frame: CGRect,
                                   room: CGFloat, action: DockReveal.Action) {}
@MainActor func recordInspectorListRoom(_ id: InspectorSectionID,
                                        natural: CGFloat, drawn: CGFloat,
                                        panes: [DockHeightBudget.Block],
                                        spacing: CGFloat, topInset: CGFloat,
                                        bottomInset: CGFloat, peek: CGFloat, room: CGFloat?) {}

extension View {
    func inspectorLayoutProbe(sections: [InspectorSectionID]) -> some View { self }
}

#endif
