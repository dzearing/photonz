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
/// - **Columns** is here, on a screen. A count, a gutter and a margin, saved
///   with the document, and the only one of the two that pulls at a drag.
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
                .help(FrameColumnsCopy.showCaption)
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
                numberRow(FrameColumnsCopy.gutter, suffix: "pt", value: Double(columns.gutter)) {
                    editorState.setFrameColumnGutter(CGFloat($0))
                }
                numberRow(FrameColumnsCopy.margin, suffix: "pt", value: Double(columns.margin)) {
                    editorState.setFrameColumnMargin(CGFloat($0))
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
        .padding(.horizontal, 14)
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
        "Each column comes out \(points) pt wide. Dragging pulls to the column edges; hold Command to drag free."
    }

    static let noRoom = "These numbers leave no room for a column on this screen, so nothing is drawn."

    /// Whose columns the section is showing, for its header, when the screen
    /// is not the thing selected: "on Home". With the screen itself picked the
    /// header says nothing extra, because the panel is already about it.
    static func belongsTo(_ screen: String) -> String { "on \(screen)" }
}
