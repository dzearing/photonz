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

    /// The row the pointer is over, so a name that can be clicked looks like it.
    @State private var hoveredContentID: UUID?

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
        // What "Follow" would actually give you, which is the CONTAINER's
        // answer. The resolved one is this layer's own rule wherever it has
        // set one, and a Follow row that reads back the override it is
        // offering to drop promises the very thing picking it takes away.
        let inherited = container.contentPlacementDefault
        // The axis the container's own flow runs along is its answer, not this
        // layer's, so that row says who owns it rather than offering a menu
        // that changes nothing. The same rule the group's own rows use below.
        let flow = PlacementEditing(arrangement: arrangement(of: container))
        // What this layer still says on the axis the flow took over, so the row
        // that owns it can offer to take it off.
        let stale = flow.inertRule(in: current.placement)
        VStack(alignment: .leading, spacing: 6) {
            Text(container.isFrame ? "This layer on \(container.name)"
                                   : "This layer in \(container.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if flow.canSetHorizontal {
                row("Horizontal") {
                    Menu {
                        Button(followTitle(inherited.horizontal.title, isFrame: container.isFrame)) {
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
            } else {
                ownedByTheFlow("Horizontal", flow, clearing: stale) {
                    editorState.setPlacement(id: current.id, horizontal: nil)
                }
            }
            if flow.canSetVertical {
                row("Vertical") {
                    Menu {
                        Button(followTitle(inherited.vertical.title, isFrame: container.isFrame)) {
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
            } else {
                ownedByTheFlow("Vertical", flow, clearing: stale) {
                    editorState.setPlacement(id: current.id, vertical: nil)
                }
            }
            Text(childCaption(resolved, flow, stale: stale))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The group's own default still written on the axis its flow decides, so
    /// the Contents rows can offer to clear it the same way a layer's do.
    private func contentsInertRule(_ flow: PlacementEditing) -> String? {
        flow.inertRule(in: current.group?.contentPlacement)
    }

    /// How a group arranges its contents, or nil where it arranges nothing —
    /// which is every group while auto layout is switched off.
    private func arrangement(of layer: Layer) -> GroupLayout? {
        Experiments.shared.autoLayoutEnabled ? layer.group?.layout : nil
    }

    private func followTitle(_ inherited: String, isFrame: Bool) -> String {
        isFrame ? "Follow screen (\(inherited))" : "Follow group (\(inherited))"
    }

    private var isOnAScreen: Bool { container?.isFrame == true }

    private func childCaption(_ resolved: ResolvedPlacement, _ flow: PlacementEditing,
                              stale: String?) -> String {
        // A rule sitting on the axis the flow took over is the one thing on
        // these rows nobody expects, so when there is one it is what the
        // caption talks about: saying "following the group" over a row that is
        // offering to clear a rule reads as a contradiction.
        if let stale, let owner = flow.flowNoun {
            return "\(stale) is still set where \(owner) decides. It changes nothing now, "
                + "and comes back if the direction changes."
        }
        // Stretch means something different for words than it does for a box:
        // the box fills, and where the words sit in it is the Text section's
        // Align. Said here because this is where the choice is made. Only on an
        // axis still being asked about: a Stretch down a column stack fills
        // nothing, so promising it would fill the box is a lie.
        let stretches = (flow.canSetHorizontal && resolved.horizontal == .stretch)
            || (flow.canSetVertical && resolved.vertical == .stretch)
        if current.text != nil, stretches {
            return "Stretch fills the box with the words placed by Align, in Text."
        }
        // Same again for who is following whom: a rule left on the axis the
        // flow decides changes nothing, so it does not make this layer an
        // exception to anything.
        if (!flow.canSetHorizontal || resolved.followsHorizontal),
           (!flow.canSetVertical || resolved.followsVertical) {
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
        let arrangement = arrangement(of: current)
        let flow = PlacementEditing(arrangement: arrangement)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Contents of \(current.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
            // How this group arranges its contents, above where each one sits,
            // because the arrangement decides which of the two rows below is
            // still a question (Next, `next-auto-layout`).
            if Experiments.shared.autoLayoutEnabled {
                ArrangementInspector(layer: current)
            }
            // The axis a stack runs along is the stack's answer, not a menu:
            // a live control that changes nothing is worse than a row that
            // says who owns it.
            if current.isComponentInstance {
                // A copy's contents are its original's, down to where they
                // sit: these are refilled from the original after every edit,
                // so a menu here would take an answer and lose it by the next
                // redraw (found 2026-09-04).
                //
                // An axis the arrangement decides says so in the SAME words
                // the original says it in, rather than reading back the answer
                // underneath that the flow is overriding: the two sections
                // describe one fact, so they had better agree.
                followedRow("Horizontal", flow.canSetHorizontal
                            ? effective.horizontal.title
                            : (flow.setByTheFlow ?? effective.horizontal.title))
                followedRow("Vertical", flow.canSetVertical
                            ? effective.vertical.title
                            : (flow.setByTheFlow ?? effective.vertical.title))
            } else if !flow.canSetHorizontal {
                ownedByTheFlow("Horizontal", flow, clearing: contentsInertRule(flow)) {
                    editorState.setContentPlacement(id: current.id, horizontal: nil)
                }
            } else {
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
            }
            if current.isComponentInstance {
                EmptyView()
            } else if !flow.canSetVertical {
                ownedByTheFlow("Vertical", flow, clearing: contentsInertRule(flow)) {
                    editorState.setContentPlacement(id: current.id, vertical: nil)
                }
            } else {
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
            }
            // A copy says who owns all of this ONCE, here at the foot, so the
            // one sentence covers the arrangement above it and the two rows
            // right above it rather than stopping halfway down the section.
            if current.isComponentInstance {
                Text(PhotonzDocument.instanceArrangementReason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // With an arrangement on, the Arrangement rows say what happens in
            // words already, so this would be the second caption in a row.
            if arrangement == nil, !current.isComponentInstance {
                Text(current.isFrame
                     ? "Everything on this screen follows this when the screen is resized, "
                       + "unless a layer says otherwise for itself."
                     : "Everything inside follows this when the group is resized, "
                       + "unless a layer says otherwise for itself.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            exceptions
        }
    }

    // MARK: - The pieces that are not following

    /// Who inside this group placed itself, named right under the setting they
    /// are ignoring. Without this the only way to find an override is to click
    /// every piece in turn, and a group whose contents will not move is a
    /// mystery until you do. A group where everybody follows says nothing:
    /// an empty list would be a permanent question about an answer of none.
    @ViewBuilder
    private var exceptions: some View {
        let overrides = current.contentsWithTheirOwnPlacement(arrangement: arrangement(of: current))
        if !overrides.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(overrides.count == 1 ? "One layer has a rule of its own"
                                          : "\(overrides.count) layers have rules of their own")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                ForEach(overrides.prefix(exceptionsShown)) { exception in
                    exceptionRow(exception)
                }
                // A group with a dozen exceptions would push the rest of the
                // inspector off the panel, so the list stops and says so; the
                // Layers list is where you go through all of them.
                if overrides.count > exceptionsShown {
                    Text("and \(overrides.count - exceptionsShown) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 6)
                }
            }
            .padding(.top, 4)
        }
    }

    private var exceptionsShown: Int { 6 }

    /// One name, what it does instead, and a click that goes there.
    private func exceptionRow(_ exception: PlacementOverride) -> some View {
        Button {
            editorState.selectLayer(exception.id, inGroup: current.id)
        } label: {
            HStack(spacing: 8) {
                Text(exception.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(exception.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(.rect(cornerRadius: 5))
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(hoveredContentID == exception.id ? AnyShapeStyle(.quaternary)
                                                       : AnyShapeStyle(.clear)))
        }
        .buttonStyle(.plain)
        .onHover { hoveredContentID = $0 ? exception.id : nil }
        .help("Select \(exception.name)")
        .playtestControl(exception.name, detail: "Layout, a layer with a rule of its own")
    }

    /// The row for something a COPY is shown rather than asked: the answer in
    /// the same column a menu would put it, greyed, with the reason on hover.
    /// The Layout section's own line above already says where it is set, so
    /// this row carries no second sentence.
    private func followedRow(_ title: String, _ value: String) -> some View {
        row(title) {
            Text(value)
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .help(PhotonzDocument.instanceArrangementReason)
    }

    /// The row for an axis the stack decides. It stays in place, with the same
    /// label in the same column, so nothing shuffles under the pointer when a
    /// group becomes a stack, and hovering it says where the answer is set.
    ///
    /// `clearing` is the rule still written on that axis from before the stack
    /// took it over. It does nothing today, and it is not counted as a rule of
    /// its own anywhere else, so this row is the one place it can be seen — and
    /// the only place it can be taken off before flipping the direction brings
    /// it back to life.
    @ViewBuilder
    private func ownedByTheFlow(_ title: String, _ flow: PlacementEditing,
                                clearing stale: String? = nil,
                                clear: @escaping () -> Void = {}) -> some View {
        if let answer = flow.setByTheFlow {
            row(title) {
                HStack(spacing: 8) {
                    Text(answer)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    if let stale {
                        Button("Clear \(stale)", action: clear)
                            .buttonStyle(.link)
                            .font(.caption)
                            .help("\(stale) is still set here from before, and does nothing while "
                                  + "\(flow.flowNoun ?? "the flow") decides this direction. Clear "
                                  + "it so changing the direction later does not bring it back.")
                            .playtestControl("Clear \(stale)", detail: "Layout")
                    }
                }
            }
            .help(flow.reason ?? "")
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
        // Lends the row's word to whatever it holds, so a scripted walk can
        // say which of two rows wearing the same answer it means.
        .playtestField(title)
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
