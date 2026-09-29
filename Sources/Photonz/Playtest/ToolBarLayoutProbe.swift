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

    /// One view's last word: which group it is and where it was drawn, and
    /// when, so the newest word for a name wins.
    private struct Entry { var name: String; var frame: CGRect; var stamp: Int }

    /// Every live view's last measurement. Kept PER VIEW rather than per name
    /// because two windows can each draw a bar: a recording opened from an
    /// empty window has the empty one draw, animate and close beside it. With
    /// one frame per name, the closing window's last writes replaced the
    /// recording window's and its goodbye then removed them, so the bar still
    /// on screen was missing from the register until something moved it.
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var stamp = 0

    /// Every group currently on screen, by the name the bar gave it, in the
    /// window's coordinates: the most recent word from a live view.
    var groups: [String: CGRect] {
        var newest: [String: Entry] = [:]
        for entry in entries.values where (newest[entry.name]?.stamp ?? -1) < entry.stamp {
            newest[entry.name] = entry
        }
        return newest.mapValues(\.frame)
    }
    /// Draw order, so the log reads left to right instead of alphabetically.
    var order: [String] = []

    func record(_ name: String, frame: CGRect, by writer: ObjectIdentifier) {
        if !order.contains(name) { order.append(name) }
        stamp += 1
        entries[writer] = Entry(name: name, frame: frame, stamp: stamp)
    }

    /// Forgets what the disappearing view wrote, and nothing else: the same
    /// group in a window still open reads on.
    func forget(by writer: ObjectIdentifier) {
        entries.removeValue(forKey: writer)
    }

    /// What the tool bar last drew: its slots in front by name, the rows under
    /// its More button, and the one slot lit ("More" for a folded tool in
    /// hand). Nil until a bar has drawn.
    var slots: ToolBarSlotsReading?
    /// What each row under More does, by its title: the same action the open
    /// menu's row runs, so a walk can pick one without an open menu.
    var moreRows: [String] = []
    var pickMoreRow: (@MainActor (String) -> Void)?

    /// The one glass bar the groups sit in when the bar is drawn whole
    /// (`next-one-glass-tool-bar`); nil while each group is its own capsule.
    var bar: CGRect?

    /// How many glass capsules the row draws: the one bar, or one per group.
    var capsules: Int { bar == nil ? groups.count : 1 }

    private var bars: [ObjectIdentifier: Entry] = [:]

    func recordBar(_ frame: CGRect, by writer: ObjectIdentifier) {
        stamp += 1
        bars[writer] = Entry(name: "Bar", frame: frame, stamp: stamp)
        bar = newestBar
    }

    func forgetBar(by writer: ObjectIdentifier) {
        bars.removeValue(forKey: writer)
        bar = newestBar
    }

    private var newestBar: CGRect? { bars.values.max { $0.stamp < $1.stamp }?.frame }

    /// Every tool button and hairline on the bar, by view: what the gaps and
    /// hairline heights are read off. A tool is named for its slot, a hairline
    /// is `nil`.
    private struct Mark { var tool: String?; var frame: CGRect; var stamp: Int }
    private var markEntries: [ObjectIdentifier: Mark] = [:]

    func recordMark(tool: String?, frame: CGRect, by writer: ObjectIdentifier) {
        stamp += 1
        markEntries[writer] = Mark(tool: tool, frame: frame, stamp: stamp)
    }

    func forgetMark(by writer: ObjectIdentifier) {
        markEntries.removeValue(forKey: writer)
    }

    /// The tools and hairlines inside the bar on screen now, left to right:
    /// the one glass bar when there is one, else the tools' own capsule. A
    /// second window's bar is somewhere else, so it never reads in.
    var marks: [(tool: String?, frame: CGRect)] {
        guard let around = bar ?? groups["Tools"] else { return [] }
        return markEntries.values
            .filter { around.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            .sorted { $0.frame.minX < $1.frame.minX }
            .map { ($0.tool, $0.frame) }
    }

    /// The room between each pair of neighbouring tools with no hairline
    /// between them, left to right.
    var toolGaps: [CGFloat] {
        zip(marks, marks.dropFirst()).compactMap { left, right in
            left.tool != nil && right.tool != nil ? right.frame.minX - left.frame.maxX : nil
        }
    }

    /// Every hairline's height, left to right.
    var hairlineHeights: [CGFloat] { marks.filter { $0.tool == nil }.map(\.frame.height) }

    /// The room between each hairline and the tool or section edge either
    /// side of it, as [left, right] pairs, only where a tool is that neighbour.
    var hairlineRoom: [[CGFloat]] {
        let list = marks
        return list.indices.compactMap { index in
            guard list[index].tool == nil else { return nil }
            let line = list[index].frame
            let left = index > 0 && list[index - 1].tool != nil ? line.minX - list[index - 1].frame.maxX : nil
            let right = index + 1 < list.count && list[index + 1].tool != nil
                ? list[index + 1].frame.minX - line.maxX : nil
            return [left, right].compactMap { $0 }
        }
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
        modifier(ToolBarGroupProbe(name: name))
    }
}

extension View {
    /// Registers this view as the ONE glass bar the groups are sections of.
    func toolBarGlassProbe() -> some View {
        modifier(ToolBarGlassProbe())
    }
}

private struct ToolBarGlassProbe: ViewModifier {
    @State private var recorded = ToolBarGroupProbe.Recorded()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                recorded.frame = frame
                ToolBarLayoutProbe.shared.recordBar(frame, by: ObjectIdentifier(recorded))
            }
            // Back from a disappearance with its geometry unchanged, which
            // does not fire the geometry change again (`ToolBarGroupProbe`).
            .onAppear {
                if let frame = recorded.frame {
                    ToolBarLayoutProbe.shared.recordBar(frame, by: ObjectIdentifier(recorded))
                }
            }
            .onDisappear { ToolBarLayoutProbe.shared.forgetBar(by: ObjectIdentifier(recorded)) }
    }
}

extension View {
    /// Registers a tool button (`tool` its slot's name) or a hairline (`nil`)
    /// on the floating bar, so a walk can read the gaps between them as numbers.
    func toolBarMarkProbe(tool: String?) -> some View {
        modifier(ToolBarMarkProbe(tool: tool))
    }
}

private struct ToolBarMarkProbe: ViewModifier {
    let tool: String?
    @State private var recorded = ToolBarGroupProbe.Recorded()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                recorded.frame = frame
                ToolBarLayoutProbe.shared.recordMark(tool: tool, frame: frame, by: ObjectIdentifier(recorded))
            }
            .onAppear {
                if let frame = recorded.frame {
                    ToolBarLayoutProbe.shared.recordMark(tool: tool, frame: frame, by: ObjectIdentifier(recorded))
                }
            }
            .onDisappear { ToolBarLayoutProbe.shared.forgetMark(by: ObjectIdentifier(recorded)) }
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
    /// This view's identity in the register. Not drawn, so it never redraws
    /// the bar.
    @State private var recorded = Recorded()

    final class Recorded { var frame: CGRect? }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                recorded.frame = frame
                ToolBarLayoutProbe.shared.record(name, frame: frame, by: ObjectIdentifier(recorded))
            }
            // A window opened with a recording is hidden and shown again once
            // it has drawn: every view on it says goodbye and comes back in
            // the same place, and a geometry that did not change never fires
            // again, so the bar was gone from the register until something
            // moved. Coming back puts back what it last measured.
            .onAppear {
                if let frame = recorded.frame {
                    ToolBarLayoutProbe.shared.record(name, frame: frame, by: ObjectIdentifier(recorded))
                }
            }
            .onDisappear { ToolBarLayoutProbe.shared.forget(by: ObjectIdentifier(recorded)) }
    }
}

#else

extension View {
    func toolBarGroupProbe(_ name: String) -> some View { self }
    func toolBarGlassProbe() -> some View { self }
    func toolBarMarkProbe(tool: String?) -> some View { self }
    func toolBarSlotsProbe(shown: [String], more: [String], lit: String?) -> some View { self }
    func toolBarMoreProbe(_ rows: [String], pick: @escaping @MainActor (String) -> Void) -> some View { self }
}

#endif
