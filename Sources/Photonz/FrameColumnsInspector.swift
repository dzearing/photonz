import PhotonzCore
import SwiftUI

/// The column layout the screen you are working on is designed to (Next,
/// `next-frames`) — the screen you picked, or the screen what you picked is
/// on, which is the same screen Layer ▸ Show Columns acts on.
///
/// A section of its own rather than three more rows inside Frame, because the
/// app now has two things a person could call a grid and the surest way to tell
/// them apart is that each has its own place with its own words:
///
/// - **Columns** is here, on a screen. A count and a gutter, saved with the
///   document, drawn inside the room that screen keeps at its edges, and the
///   only one of the two that pulls at a drag. A screen that keeps no room has
///   a margin of its own here; one that has padding has no second number,
///   because the padding is the inset.
/// - **Grid** is in the Canvas section. A spacing across the whole canvas, kept
///   between launches rather than in the document, and it never pulls.
///
/// The word "grid" appears nowhere in this section on purpose.
struct FrameColumnsInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    private var columns: FrameColumns? { editorState.columnsTargetSettings }
    private var isShowing: Bool { columns?.isVisible ?? false }

    private static let labelWidth: CGFloat = 66

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(FrameColumnsCopy.show, isOn: Binding(
                get: { isShowing },
                set: { editorState.setFrameColumnsVisible($0) }))
                .font(.callout)
                .toggleStyle(.checkbox)
                .panelHelp(FrameColumnsCopy.showCaption)
                .playtestControl(FrameColumnsCopy.show,
                                 detail: "Columns on \(layer.name), "
                                     + (isShowing ? "shown" : "hidden"))

            if let columns, isShowing {
                // Only while they are showing: with nothing drawn on the screen
                // there is nothing for these numbers to describe, and three
                // dead fields under an unticked box is a section that looks
                // broken.
                numberRow(FrameColumnsCopy.count, suffix: "", value: Double(columns.count)) {
                    editorState.setFrameColumnCount(Int($0.rounded()))
                }
                numberRow(FrameColumnsCopy.gutter, suffix: DocumentUnit.word, value: Double(columns.gutter)) {
                    editorState.setFrameColumnGutter(CGFloat($0))
                }
                if editorState.columnsTargetPadding == .none {
                    // Only a screen that keeps no room at its edges has a
                    // margin of its own. The moment it has padding, that is
                    // the one inset it has, and a second number here would be
                    // a number that does nothing.
                    numberRow(FrameColumnsCopy.margin, suffix: DocumentUnit.word,
                              value: Double(columns.margin)) {
                        editorState.setFrameColumnMargin(CGFloat($0))
                    }
                    .panelHelp(FrameColumnsCopy.marginCaption)
                } else {
                    Text(FrameColumnsCopy.followsPadding(editorState.columnsTargetPadding))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // What the three numbers actually come out as. It is the thing
                // a person is really working out in their head while they type
                // a gutter, and it is the number they will type into a width
                // field a moment later.
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
        .id(layer.id)
    }

    private var footnote: String {
        guard let width = editorState.columnsTargetColumnWidth, width >= 1 else {
            return FrameColumnsCopy.noRoom
        }
        return FrameColumnsCopy.columnWidth(Int(width.rounded()))
    }

    /// One typed number. It commits on Return and on losing the keyboard, steps
    /// with the arrow keys like every other number in the panel, and hands the
    /// keyboard back afterwards so the next letter picks a tool.
    @ViewBuilder private func numberRow(_ label: String, suffix: String, value: Double,
                                        set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            TextField(label, value: Binding(get: { value }, set: { set($0) }),
                      format: .number.precision(.fractionLength(0)).grouping(.never))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .numberFieldKeys(
                    commit: {},
                    revert: {},
                    step: { direction, coarse in
                        set(Double(LayerGeometry.stepped(value, direction: direction,
                                                         coarse: coarse)))
                    })
            if !suffix.isEmpty {
                Text(suffix).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .playtestField(label)
        // The number is in a box and its unit is beside it, so a walk reading
        // the row back has to be handed the two together to see the pair a
        // person reads.
        .panelReadout(suffix.isEmpty ? "" : "\(Int(value.rounded())) \(suffix)")
    }
}

/// Every word this feature says out loud, in one place, so the menu row and the
/// panel can never drift apart. No "grid" anywhere: that word belongs to the
/// canvas grid, which is a different thing in a different place.
enum FrameColumnsCopy {
    static let section = "Columns"
    static let show = "Show columns"
    static let showCaption = "Draw this screen's columns over it, and pull a drag to their edges."
    static let count = "Columns"
    static let gutter = "Gutter"
    static let margin = "Margin"
    /// The Layer menu's row, in Title Case as a menu row is. It acts on the
    /// screen you have picked, or on the screen what you picked lives in.
    static let menuItem = MenuToggleNames.showColumns

    static func columnWidth(_ points: Int) -> String {
        "Each column comes out \(DocumentUnit.text(CGFloat(points))) wide. Dragging pulls to the column edges; hold Command to drag free."
    }

    static let noRoom = "These numbers leave no room for a column on this screen, so nothing is drawn."

    /// Why there is a margin here at all, on a screen that keeps no room at
    /// its edges. Give the screen padding and this row goes away, because the
    /// padding is then the only inset it has.
    static let marginCaption = "This screen keeps no room at its edges, so the columns use this margin. "
        + "Give it padding in Layout and they follow the padding instead."

    /// What stands in for the Margin row once the screen has padding: one
    /// inset, named, and where to change it.
    static func followsPadding(_ padding: GroupPadding) -> String {
        let room = padding.uniform.map { "\(DocumentUnit.text($0)) on every side" }
            ?? padding.inWords
        return "The columns start where this screen's padding does, \(room). "
            + "Change Padding in Layout to move them."
    }

    /// Whose columns the section is showing, for its header, when the screen
    /// is not the thing selected: "on Home". With the screen itself picked the
    /// header says nothing extra, because the panel is already about it.
    static func belongsTo(_ screen: String) -> String { "on \(screen)" }
}
