import PhotonzCore
import SwiftUI

extension Tool {
    /// The glyph the tool bar draws for this tool.
    var barSymbol: String {
        switch self {
        case .select: "cursorarrow"
        case .crop: "crop"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .highlight: "highlighter"
        case .text: "character.cursor.ibeam"
        case .zoomCallout: "plus.magnifyingglass"
        case .measure: "ruler"
        case .fill: "drop"
        case .rectSelect: "rectangle.dashed"
        case .ellipseSelect: "circle.dashed"
        case .wand: "wand.and.rays"
        }
    }

    /// The tool's name as the bar prints it in a menu row or a tooltip.
    var barTitle: String {
        switch self {
        case .select: "Select"
        case .crop: "Crop"
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .highlight: "Highlight"
        case .text: "Text"
        case .zoomCallout: "Zoom Callout"
        case .measure: "Measure"
        case .fill: "Fill"
        case .rectSelect: "Rectangle Select"
        case .ellipseSelect: "Ellipse Select"
        case .wand: "Magic Wand"
        }
    }
}

/// The tiny wedge in a tool button's corner that says "there is more inside
/// me": a mode list or a family of tools. ONE marker for both, so the bar has
/// one way of flagging a group, the way a pro editor always has, and it costs
/// no width because it sits inside the button's own footprint.
struct ToolBarMoreMarker: View {
    let isActive: Bool

    var body: some View {
        Image(systemName: "arrowtriangle.down.fill")
            .font(.system(size: 5, weight: .black))
            .foregroundStyle(isActive ? Color.white.opacity(0.9) : Color.secondary)
            .padding(1)
            .allowsHitTesting(false)
    }
}

/// One tool bar slot for a family of tools (`ToolGroup`): the button wears the
/// member you used last, a click picks that member up, press-and-hold lists
/// the family with each member's letter, and the family's key vocabulary
/// lives on invisible stand-ins because a `Menu` cannot fire a shortcut for a
/// row while it is closed.
///
/// Built on the same `Menu(primaryAction:)` and corner marker as
/// `ToolModeButton`, so a group of tools and a tool with modes read as one
/// idiom in the bar.
struct ToolGroupButton: View {
    let group: ToolGroup
    /// The member the button stands for right now.
    let remembered: Tool
    /// Whether the tool in hand belongs to this family.
    let isActive: Bool
    /// The namespace the tool bar's sliding accent circle lives in.
    let namespace: Namespace.ID
    /// A line the tooltip adds after the key vocabulary (the selection
    /// family's modifier chords, say). Nil for nothing more to say.
    var hint: String? = nil
    /// Picks a member up.
    let activate: (Tool) -> Void
    /// Picks the remembered member up. A closure rather than `remembered`
    /// read back, because a shortcut's action is registered once and can
    /// outlive the snapshot it was built from; the caller reads live state.
    let pickRemembered: () -> Void
    /// Moves to the next member, from live state for the same reason.
    let cycle: () -> Void

    private var keyLabel: String? {
        group.groupKey.map { String($0).uppercased() }
    }

    /// "⇧M cycles" for a family with a key of its own; otherwise the letters
    /// the members answer to.
    private var cycleLine: String {
        let letters = group.cycleKeys.map { String($0).uppercased() }
        guard let first = letters.first else { return "" }
        return letters.count == 1 ? "⇧\(first) cycles" : "⇧ plus a letter cycles"
    }

    private var tooltip: String {
        let members = group.tools.map { tool -> String in
            let key = tool.shortcutHint ?? keyLabel
            return key.map { "\(tool.barTitle) (\($0))" } ?? tool.barTitle
        }
        var text = "\(group.title): \(members.joined(separator: ", ")). \(cycleLine)."
        if let hint { text += "\n\(hint)" }
        return text
    }

    var body: some View {
        Menu {
            ForEach(group.tools, id: \.self) { tool in
                Button {
                    activate(tool)
                } label: {
                    Label(tool.barTitle, systemImage: tool.barSymbol)
                }
                // Printed, not fired: the stand-ins below do the firing. A
                // member without a letter of its own borrows the family's.
                .keyboardShortcut((tool.keyEquivalent ?? group.groupKey.map { KeyEquivalent($0) })
                    .map { KeyboardShortcut($0, modifiers: []) })
            }
            Divider()
            Text(cycleLine)
        } label: {
            glyph
        } primaryAction: {
            pickRemembered()
        }
        .menuIndicator(.hidden)
        .menuStyle(.button)
        // The shared tool style, not borderless: a `Menu` with a primary
        // action under the borderless style draws its label at about two
        // thirds strength, so this button sat in the bar looking disabled
        // beside the plain tool buttons (measured 155 vs 244 on a real
        // capture). The shared style sets the glyph's own foreground, adds
        // the hover and pressed fills and the accent circle, and keeps the
        // click and the press-and-hold.
        .buttonStyle(.tool(isActive: isActive, in: namespace))
        .fixedSize()
        // The hint names the member the button stands for; the family and
        // its letters are one press-and-hold away, in the list.
        .toolTip(remembered.barTitle, key: remembered.shortcutHint ?? keyLabel, fallback: tooltip)
        .accessibilityLabel("\(group.title): \(remembered.barTitle)")
        .background {
            ToolGroupShortcuts(group: group, activate: activate,
                               pickRemembered: pickRemembered, cycle: cycle)
        }
    }

    /// The glyph with the family's corner marker. The accent circle and the
    /// pointer response come from the shared button style.
    private var glyph: some View {
        Image(systemName: remembered.barSymbol)
            .font(.system(size: 15, weight: .medium))
            .overlay(alignment: .bottomTrailing) { ToolBarMoreMarker(isActive: isActive) }
    }
}

/// A family's key vocabulary on invisible stand-ins: the family key picks the
/// remembered member up, each member's own letter picks that member, and
/// shift plus any of those letters walks the family. Used behind the group's
/// button, and again for a group that has slid into the overflow menu, so the
/// keys work at every window width.
///
/// Each letter is registered exactly ONCE, with shift read at action time
/// (`KeyModifierTracker`): SwiftUI matches a letter shortcut with its
/// modifiers ignored, so a second registration for the shifted letter would
/// not add a chord, it would add a coin toss.
struct ToolGroupShortcuts: View {
    let group: ToolGroup
    let activate: (Tool) -> Void
    let pickRemembered: () -> Void
    let cycle: () -> Void

    /// One row per distinct letter: what a plain press does. Shift always
    /// cycles.
    private var letters: [(key: Character, plain: () -> Void)] {
        var rows: [(key: Character, plain: () -> Void)] = []
        if let key = group.groupKey {
            rows.append((key, pickRemembered))
        }
        for tool in group.tools {
            guard let key = tool.shortcutKey, !rows.contains(where: { $0.key == key }) else { continue }
            rows.append((key, { activate(tool) }))
        }
        return rows
    }

    var body: some View {
        ZStack {
            ForEach(letters, id: \.key) { row in
                Button("") {
                    if KeyModifierTracker.isShiftDown { cycle() } else { row.plain() }
                }
                .keyboardShortcut(KeyEquivalent(row.key), modifiers: [])
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
