import AppKit
import PhotonzCore
import SwiftUI

// MARK: - The Layers header's own buttons (Next, `next-dock-headers`)

/// The far end of the Layers header, as both component mocks draw it
/// (`component-configure-wt.html` `#gLayersH`): the Make Component button, then
/// the panel menu. The one-click way to turn the picked group into a
/// component, where your eye already is when you pick it.
struct LayersHeaderControls: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        HStack(spacing: 6) {
            if editorState.componentsEnabled { MakeComponentHeaderButton() }
            LayersPanelMenu()
        }
    }
}

/// The mock's `#btnMakeComp`: a ghost icon button wearing the component glyph.
/// Exactly what Option Command K does, and dimmed when that would do nothing.
private struct MakeComponentHeaderButton: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        Button {
            editorState.makeComponent()
        } label: {
            // The glyph a component wears everywhere else, drawn in outline
            // and in the header's ink as the mock's line icons are: this is a
            // verb, not the violet mark a component wears.
            ComponentGlyphShape()
                .stroke(style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
                .frame(width: 13, height: 13)
                .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(!editorState.canMakeComponent)
        .accessibilityLabel(LayersPanelHeader.makeComponent)
        .panelHelp(LayersPanelHeader.makeComponentHelp)
        .playtestControl(LayersPanelHeader.makeComponent,
                         detail: "the component button on the Layers header")
    }
}

/// The three dots at the end of the Layers header (`components.html`,
/// `#layerMenu`): Group Selection, Make Component, and Hide This Panel. Each
/// is its menu bar twin, under the same name and on the same key.
private struct LayersPanelMenu: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        Menu {
            // The rows that act on the layers, then a divider, then the one
            // that acts on the window. Built in two runs rather than with a
            // divider behind an `if` inside one loop, which left an empty
            // separator above the first row.
            ForEach(rows.filter { !$0.startsSection }, id: \.self, content: item)
            Divider()
            ForEach(rows.filter(\.startsSection), id: \.self, content: item)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(LayersPanelHeader.menuName)
        .panelHelp("Group, make a component, or hide")
        .playtestControl(LayersPanelHeader.menuName, detail: "the three dots on the Layers header")
    }

    private func item(_ row: LayersPanelHeader.MenuRow) -> some View {
        Button { perform(row) } label: {
            // Each with the mock's icon beside it, as the Properties menu's are.
            Label { Text(row.title) } icon: { Self.icon(row) }
        }
            .keyboardShortcut(row.shortcut.map(Self.keyboardShortcut))
            .disabled(!canPerform(row))
    }

    /// A row whose command is switched off is absent, as it is in the menu
    /// bar, so nobody hunts for why a dead row is there.
    private var rows: [LayersPanelHeader.MenuRow] {
        LayersPanelHeader.MenuRow.allCases.filter { row in
            switch row {
            case .groupSelection: Experiments.shared.layerGroupsEnabled
            case .makeComponent: editorState.componentsEnabled
            case .hidePanel: true
            }
        }
    }

    private func canPerform(_ row: LayersPanelHeader.MenuRow) -> Bool {
        switch row {
        case .groupSelection: editorState.canGroupSelection
        case .makeComponent: editorState.canMakeComponent
        case .hidePanel: true
        }
    }

    private func perform(_ row: LayersPanelHeader.MenuRow) {
        switch row {
        case .groupSelection: editorState.groupSelection()
        case .makeComponent: editorState.makeComponent()
        case .hidePanel: editorState.setInspectorVisible(false)
        }
    }

    /// The mock's `ic-group`, `ic-component` and `ic-sidebar`.
    private static func icon(_ row: LayersPanelHeader.MenuRow) -> Image {
        switch row {
        case .groupSelection: Image(systemName: "rectangle.3.group")
        case .makeComponent: Image(nsImage: componentIcon)
        case .hidePanel: Image(systemName: "sidebar.right")
        }
    }

    /// The component glyph in outline as a template image, since a menu row
    /// takes a picture rather than a shape and no system symbol means this.
    private static let componentIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: true) { rect in
            let path = NSBezierPath(cgPath: ComponentGlyph.path(in: rect.insetBy(dx: 1, dy: 1)))
            path.lineWidth = 1.1
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()

    private static func keyboardShortcut(_ shortcut: LayersPanelHeader.Shortcut) -> KeyboardShortcut {
        var modifiers: EventModifiers = []
        for modifier in shortcut.modifiers {
            switch modifier {
            case .command: modifiers.insert(.command)
            case .option: modifiers.insert(.option)
            case .shift: modifiers.insert(.shift)
            }
        }
        return KeyboardShortcut(KeyEquivalent(shortcut.key), modifiers: modifiers)
    }
}
