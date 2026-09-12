// What is inside a tool button's own list, and what each row does.
//
// A tool that owns modes keeps them behind its button: press and hold and the
// modes appear. The bar is drawn by SwiftUI from end to end, so unlike the
// panel's menus there is no AppKit button in the window for a walk to click,
// and the list only exists while a person is holding the mouse down on it.
// Every audit of the tool bar has therefore had to describe that list from the
// source rather than from the app.
//
// So the button says what its list holds. Each row hands over its words, its
// glyph, whether it is the live one, and THE SAME closure its own row runs —
// one closure, used by both, so a walk can never choose something the pointer
// would not.
//
// Probe builds only; the shipping app compiles the no-op at the bottom.
import SwiftUI

/// One row of a tool's own list, as a walk reads it. Declared in every build so
/// the button can name the type either side of the probe flag; only a probe
/// build ever asks for one.
@MainActor struct ToolFlyoutRow {
    /// The words on the row: "Gap", "16:9".
    let title: String
    /// The glyph beside them.
    let symbol: String
    /// Whether this is the mode the tool is in, which is the row wearing the
    /// tick.
    let isLive: Bool
    /// Exactly what a click on the row runs.
    let choose: @MainActor () -> Void
}

#if PHOTONZ_PLAYTEST

/// The lists the tool bar is showing right now, by the tool's own words.
///
/// Held by reference and deliberately NOT observable: it is rewritten as the
/// bar redraws, and redrawing the bar to remember something nothing draws is
/// the jank the tool bar comments warn about.
@MainActor final class ToolModeFlyoutProbe {
    static let shared = ToolModeFlyoutProbe()

    private struct Entry {
        /// Which copy of the button wrote this. SwiftUI rebuilds the tool bar
        /// often, and it brings the new copy up BEFORE it takes the old one
        /// down, so the outgoing button's goodbye lands after the incoming
        /// one's hello. Without this the two cancelled out and the probe
        /// reported that no tool in the app had a list at all.
        let owner: UUID
        let rows: [ToolFlyoutRow]
    }

    private var lists: [String: Entry] = [:]
    /// Left to right, so the log reads the way the bar does.
    private(set) var order: [String] = []

    func record(_ tool: String, owner: UUID, rows: [ToolFlyoutRow]) {
        if !order.contains(tool) { order.append(tool) }
        lists[tool] = Entry(owner: owner, rows: rows)
    }

    /// Only the copy that is still the live one can take a list away.
    func forget(_ tool: String, owner: UUID) {
        guard lists[tool]?.owner == owner else { return }
        lists.removeValue(forKey: tool)
        order.removeAll { $0 == tool }
    }

    /// The tools with a list, in bar order.
    var tools: [String] { order.filter { lists[$0] != nil } }

    func rows(of tool: String) -> [ToolFlyoutRow]? { lists[tool]?.rows }
}

extension View {
    /// Publishes this tool button's list for a walk to read and to choose from.
    ///
    /// The modifier goes on the button ITSELF rather than on a zero-size view
    /// hidden in its background: a `Color.clear` sized to nothing never came up
    /// in the tool bar, so the first cut of this probe reported that no tool in
    /// the app had a list at all. `ToolBarLayoutProbe` next door registers the
    /// same way, straight off the view being described.
    ///
    /// `signature` is what the rows are SAYING, so the registration is
    /// refreshed whenever the words or the tick change and never on a pass that
    /// changed nothing.
    func toolFlyoutProbe(tool: String, signature: String,
                         rows: @escaping @MainActor () -> [ToolFlyoutRow]) -> some View {
        modifier(ToolFlyoutProbeModifier(tool: tool, signature: signature, rows: rows))
    }
}

private struct ToolFlyoutProbeModifier: ViewModifier {
    let tool: String
    let signature: String
    let rows: @MainActor () -> [ToolFlyoutRow]
    /// This copy of the button, so its goodbye cannot take down a list a newer
    /// copy has already put up.
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { ToolModeFlyoutProbe.shared.record(tool, owner: owner, rows: rows()) }
            .onChange(of: signature) {
                ToolModeFlyoutProbe.shared.record(tool, owner: owner, rows: rows())
            }
            .onDisappear { ToolModeFlyoutProbe.shared.forget(tool, owner: owner) }
    }
}

#else

extension View {
    func toolFlyoutProbe(tool: String, signature: String,
                         rows: @escaping @MainActor () -> [ToolFlyoutRow]) -> some View { self }
}

#endif
