import PhotonzCore
import SwiftUI

/// Where the pieces sit when something is resized (Next, `next-placement`).
///
/// Two ideas, and a layer can be on both sides of them at once. A GROUP says
/// what everything inside it does — centre it, start it at the left, stretch it
/// to fill. A layer that sits INSIDE a group can say something different for
/// itself, one axis at a time, and until it does its row reads "Follow group"
/// with the group's answer in brackets, so you can always see what is going to
/// happen without changing anything to find out.
///
/// The mock (`ui-grid`) draws these as a four-button segmented control. There
/// are five choices here, not four — the proportional Scale that every layer
/// starts on has to be one of them — and a child's row needs a sixth state for
/// following the group, which is one word rather than a glyph. So each axis is
/// a menu, matching the Frame section's Size menu right above it, and the
/// current answer is readable as a word instead of a highlighted icon.
struct PlacementInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    /// The live layer, so a menu pick redraws the row it came from.
    private var current: Layer { editorState.document?.layer(id: layer.id) ?? layer }

    private var container: Layer? { editorState.containerOfSelection }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let container {
                childRows(in: container)
            }
            if current.isGroup {
                if container != nil { Divider() }
                contentRows
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .id(layer.id)
    }

    // MARK: - What this layer does inside the thing holding it

    @ViewBuilder
    private func childRows(in container: Layer) -> some View {
        let resolved = current.resolvedPlacement(in: container)
        VStack(alignment: .leading, spacing: 6) {
            Text(container.isFrame ? "This layer on \(container.name)"
                                   : "This layer in \(container.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
            row("Horizontal") {
                Menu {
                    Button(followTitle(resolved.horizontal.title, isFrame: container.isFrame)) {
                        editorState.setPlacement(id: current.id, horizontal: nil)
                    }
                    Divider()
                    ForEach(container.horizontalPlacementChoices, id: \.self) { choice in
                        Button(choice.title) {
                            editorState.setPlacement(id: current.id, horizontal: choice)
                        }
                    }
                } label: {
                    menuLabel(resolved.horizontal.title, following: resolved.followsHorizontal)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            row("Vertical") {
                Menu {
                    Button(followTitle(resolved.vertical.title, isFrame: container.isFrame)) {
                        editorState.setPlacement(id: current.id, vertical: nil)
                    }
                    Divider()
                    ForEach(container.verticalPlacementChoices, id: \.self) { choice in
                        Button(choice.title) {
                            editorState.setPlacement(id: current.id, vertical: choice)
                        }
                    }
                } label: {
                    menuLabel(resolved.vertical.title, following: resolved.followsVertical)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Text(childCaption(resolved))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func followTitle(_ inherited: String, isFrame: Bool) -> String {
        isFrame ? "Follow screen (\(inherited))" : "Follow group (\(inherited))"
    }

    private var isOnAScreen: Bool { container?.isFrame == true }

    private func childCaption(_ resolved: ResolvedPlacement) -> String {
        if resolved.followsHorizontal, resolved.followsVertical {
            return isOnAScreen
                ? "Following the screen. Pick something here to give this one layer its own rule."
                : "Following the group. Pick something here to give this one layer its own rule."
        }
        return isOnAScreen ? "This layer's own rule, which wins over the screen's."
                           : "This layer's own rule, which wins over the group's."
    }

    // MARK: - What everything inside this group does

    private var contentRows: some View {
        let effective = current.contentPlacementDefault
        return VStack(alignment: .leading, spacing: 6) {
            Text("Contents of \(current.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
            row("Horizontal") {
                Menu {
                    ForEach(current.horizontalPlacementChoices, id: \.self) { choice in
                        Button(choice.title) {
                            editorState.setContentPlacement(id: current.id, horizontal: choice)
                        }
                    }
                } label: {
                    menuLabel(effective.horizontal.title, following: false)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            row("Vertical") {
                Menu {
                    ForEach(current.verticalPlacementChoices, id: \.self) { choice in
                        Button(choice.title) {
                            editorState.setContentPlacement(id: current.id, vertical: choice)
                        }
                    }
                } label: {
                    menuLabel(effective.vertical.title, following: false)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Text(current.isFrame
                 ? "Everything on this screen follows this when the screen is resized, "
                   + "unless a layer says otherwise for itself."
                 : "Everything inside follows this when the group is resized, "
                   + "unless a layer says otherwise for itself.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Furniture

    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            control()
        }
    }

    /// The current answer. A row that has not been set says the same word the
    /// group said, dimmed, so following and choosing never read as the same
    /// thing at a glance.
    private func menuLabel(_ title: String, following: Bool) -> some View {
        Text(title)
            .font(.callout)
            .foregroundStyle(following ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }
}
