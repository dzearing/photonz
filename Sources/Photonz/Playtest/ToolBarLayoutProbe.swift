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

    /// Forgets `name` only if what is recorded is still `frame`, the last
    /// thing the disappearing view wrote: when one window closes as another
    /// opens, the new window's bar must not be forgotten along with the old.
    func forget(_ name: String, ifStill frame: CGRect?) {
        guard let frame, groups[name] == frame else { return }
        groups.removeValue(forKey: name)
    }

    /// What the tool bar last drew: its slots in front by name, the rows under
    /// its More button, and the one slot lit ("More" for a folded tool in
    /// hand). Nil until a bar has drawn.
    var slots: ToolBarSlotsReading?
    /// What each row under More does, by its title: the same action the open
    /// menu's row runs, so a walk can pick one without an open menu.
    var moreRows: [String] = []
    var pickMoreRow: (@MainActor (String) -> Void)?

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
        modifier(ToolBarGroupProbe(name: name))
    }
}

/// One reading of the tool bar's slots (`ToolBarLayoutProbe.slots`).
struct ToolBarSlotsReading: Equatable {
    var shown: [String]
    var more: [String]
    var lit: String?
}

extension View {
    /// Records what the tool bar is showing, so a walk can read the slots back
    /// by name rather than photographing them.
    func toolBarSlotsProbe(shown: [String], more: [String], lit: String?) -> some View {
        onChange(of: ToolBarSlotsReading(shown: shown, more: more, lit: lit), initial: true) { _, now in
            ToolBarLayoutProbe.shared.slots = now
        }
    }

    /// Registers what each row under More does (`ToolBarLayoutProbe.moreRows`).
    func toolBarMoreProbe(_ rows: [String], pick: @escaping @MainActor (String) -> Void) -> some View {
        onChange(of: rows, initial: true) { _, now in
            ToolBarLayoutProbe.shared.moreRows = now
            ToolBarLayoutProbe.shared.pickMoreRow = pick
        }
    }
}

private struct ToolBarGroupProbe: ViewModifier {
    let name: String
    /// What this view last recorded. Not drawn, so it never redraws the bar.
    @State private var recorded = Recorded()

    final class Recorded { var frame: CGRect? }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                recorded.frame = frame
                ToolBarLayoutProbe.shared.record(name, frame: frame)
            }
            .onDisappear { ToolBarLayoutProbe.shared.forget(name, ifStill: recorded.frame) }
    }
}

#else

extension View {
    func toolBarGroupProbe(_ name: String) -> some View { self }
    func toolBarSlotsProbe(shown: [String], more: [String], lit: String?) -> some View { self }
    func toolBarMoreProbe(_ rows: [String], pick: @escaping @MainActor (String) -> Void) -> some View { self }
}

#endif
