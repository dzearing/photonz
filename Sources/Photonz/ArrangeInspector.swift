import PhotonzCore
import SwiftUI

/// Lining several layers up with each other (Next, `next-align-layers`).
///
/// The section appears once there is something to line up: two or more movable
/// layers picked, or one layer that sits inside something with a box to line it
/// up in, which is a screen or the rest of the group holding it. It sits above
/// Position & Size because the two answer the same question at different
/// scales: where do these sit against each other, and where does this one sit
/// on the picture.
///
/// Whatever the reference is, the caption says it and every button's hover tip
/// repeats it, so a single layer with six live buttons is never a guess about
/// what is about to move where.
///
/// Eight buttons in two rows, in the order every design tool puts them: the
/// three horizontal alignments, the three vertical ones, then spacing. Spacing
/// needs three layers to mean anything, so with two picked those two buttons
/// are dimmed and say why on hover rather than disappearing and moving the
/// others around under the pointer.
struct ArrangeInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                ForEach(LayerAlignment.allCases, id: \.self) { alignment in
                    alignButton(alignment)
                    // A gap between the sideways three and the up-and-down
                    // three, so the row reads as two ideas and not six.
                    if alignment == .right { Spacer().frame(width: 10) }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 2) {
                ForEach(LayerDistribution.allCases, id: \.self) { axis in
                    spaceButton(axis)
                }
                Spacer(minLength: 0)
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var caption: String {
        if let reference = editorState.arrangeReferenceName {
            // Why half the row is dim beats a note about spacing evenly, which
            // the two dim buttons under it already explain on hover.
            let rest = editorState.arrangeDeadAxisNote ?? "Spacing evenly needs three layers."
            return "This layer lines up inside \(reference). \(rest)"
        }
        let count = editorState.arrangeableLayerCount
        if editorState.canDistributeSelection {
            return "\(count) layers line up with each other, not with the picture."
        }
        return "\(count) layers line up with each other. Spacing evenly needs three."
    }

    /// The button's hover tip: the command, and what it lines up against when
    /// that is not just the selection itself. A button with nowhere to move the
    /// layer says why instead, the way the spacing buttons do.
    private func tip(_ alignment: LayerAlignment) -> String {
        if let reason = editorState.arrangeDeadAxisReason(alignment) {
            return "\(alignment.title). \(reason)"
        }
        guard let reference = editorState.arrangeReferenceName else { return alignment.title }
        return "\(alignment.title) in \(reference)"
    }

    private func alignButton(_ alignment: LayerAlignment) -> some View {
        Button {
            editorState.alignSelection(alignment)
        } label: {
            Image(systemName: symbol(alignment))
        }
        .buttonStyle(IconActionButtonStyle(diameter: 26, squareHitTarget: true))
        .disabled(!editorState.canAlignSelection(alignment))
        .help(tip(alignment))
        .accessibilityLabel(alignment.title)
    }

    private func spaceButton(_ axis: LayerDistribution) -> some View {
        Button {
            editorState.distributeSelection(axis)
        } label: {
            Image(systemName: axis == .horizontal ? "distribute.horizontal" : "distribute.vertical")
        }
        .buttonStyle(IconActionButtonStyle(diameter: 26, squareHitTarget: true))
        .disabled(!editorState.canDistributeSelection)
        .help(editorState.canDistributeSelection
            ? axis.title
            : "\(axis.title). Needs three or more layers, so there is a gap to even out.")
        .accessibilityLabel(axis.title)
    }

    private func symbol(_ alignment: LayerAlignment) -> String {
        switch alignment {
        case .left: "align.horizontal.left"
        case .horizontalCenter: "align.horizontal.center"
        case .right: "align.horizontal.right"
        case .top: "align.vertical.top"
        case .verticalCenter: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        }
    }
}
