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
    /// The one layer picked, or nil while several are. The rows below speak for
    /// the whole selection either way; this is only what the parts that are
    /// about ONE layer hang off — the group's own Contents rows, the rule left
    /// over on an axis the flow took, and the caption that tells one layer's
    /// story.
    let layer: Layer?

    /// The row the pointer is over, so a name that can be clicked looks like it.
    @State private var hoveredContentID: UUID?

    /// The layers this section places and what each row reads across them. One
    /// layer or five, it is the same reading, so the rows have one path.
    private var selection: PlacementSelection { editorState.placementSelection }

    /// The one layer the parts that are about ONE layer speak for, live from
    /// the document so a menu pick redraws the row it came from. Nobody as soon
    /// as a second layer is picked.
    ///
    /// Read off what is PICKED rather than off `selection`, because a group
    /// loose on the canvas is placed by nothing and so is not in the selection
    /// at all — and its Contents rows are the whole reason the section is on
    /// screen for it.
    private var only: Layer? {
        let picked = editorState.actionableLayerIDs
        guard picked.count == 1, let id = picked.first else { return nil }
        return editorState.document?.layer(id: id) ?? layer
    }

    private var container: Layer? {
        selection.containerID.flatMap { editorState.document?.layer(id: $0) }
    }

    /// The picked groups whose OWN contents this section also speaks for, and
    /// what each of those rows reads across them. One group or three: picking a
    /// second card no longer takes the whole Contents block off the panel.
    private var contents: ContentsSelection { editorState.contentsSelection }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selection.hasDifferentContainers {
                // Every picked layer sits in something, so the section applies;
                // they just do not sit in the same something. A panel that
                // silently went blank here would read as a fault, so it says
                // which it is.
                Text(PlacementSelection.differentContainersNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let container {
                childRows(in: container)
            }
            // What the picked groups tell their OWN contents is a separate
            // question from where they themselves sit, and it has an answer
            // even when the first one does not: two cards on two different
            // screens still each place what is inside them.
            if contents.isPresent {
                if container != nil || selection.hasDifferentContainers { Divider() }
                contentRows()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .id(layer?.id)
    }

    // MARK: - What this layer does inside the thing holding it

    @ViewBuilder
    private func childRows(in container: Layer) -> some View {
        // What one picked layer does, or nothing while several are picked: with
        // a selection the rows follow the CONTAINER's flow rather than any one
        // layer's, because a row that was live for the surface and dead for the
        // three buttons beside it would silently mean one layer out of four.
        let resolved = only?.resolvedPlacement(in: container)
        // What "Follow" would actually give you, which is the CONTAINER's
        // answer. The resolved one is this layer's own rule wherever it has
        // set one, and a Follow row that reads back the override it is
        // offering to drop promises the very thing picking it takes away.
        let inherited = container.contentPlacementDefault
        // The axis the container's own flow runs along is its answer, not this
        // layer's, so that row says who owns it rather than offering a menu
        // that changes nothing. The same rule the group's own rows use below.
        // ...unless the flow is not arranging this layer at all. Stretched both
        // ways, it is the surface behind everything the flow lays out, painted
        // to the group's own edges, so neither of its directions belongs to the
        // stack and both rows stay live.
        let arranges = arrangement(of: container)?.arranges == true
        let flow = PlacementEditing(arrangement: arrangement(of: container), placing: resolved,
                                    onAScreen: container.isFrame)
        // What this layer still says on the axis the flow took over, so the row
        // that owns it can offer to take it off. One layer only: the leftover
        // rule is a different word on each of four layers, and a Clear button
        // that named one of them would be lying about the other three.
        let stale = only.flatMap { flow.inertRule(in: $0.placement) }
        let ids = selection.layers
        VStack(alignment: .leading, spacing: 6) {
            Text(heading(container))
                .font(.caption)
                .foregroundStyle(.secondary)
            if flow.canSetHorizontal {
                row("Horizontal") {
                    Menu {
                        Button(followTitle(inherited.horizontal.title, isFrame: container.isFrame)) {
                            editorState.setPlacement(ids: ids, horizontal: nil)
                        }
                        Divider()
                        ForEach(container.horizontalPlacementChoices, id: \.self) { choice in
                            Button(choice.title) {
                                editorState.setPlacement(ids: ids, horizontal: choice)
                            }
                        }
                    } label: {
                        menuLabel(selection.horizontal.value?.title ?? PlacementSelection.mixedText,
                                  following: selection.horizontal.follows,
                                  isMixed: selection.horizontal.isMixed)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            } else {
                ownedByTheFlow("Horizontal", flow, clearing: stale, filling: fillingRow(flow)) {
                    editorState.setPlacement(ids: ids, horizontal: nil)
                }
            }
            if flow.canSetVertical {
                row("Vertical") {
                    Menu {
                        Button(followTitle(inherited.vertical.title, isFrame: container.isFrame)) {
                            editorState.setPlacement(ids: ids, vertical: nil)
                        }
                        Divider()
                        ForEach(container.verticalPlacementChoices, id: \.self) { choice in
                            Button(choice.title) {
                                editorState.setPlacement(ids: ids, vertical: choice)
                            }
                        }
                    } label: {
                        menuLabel(selection.vertical.value?.title ?? PlacementSelection.mixedText,
                                  following: selection.vertical.follows,
                                  isMixed: selection.vertical.isMixed)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            } else {
                ownedByTheFlow("Vertical", flow, clearing: stale, filling: fillingRow(flow)) {
                    editorState.setPlacement(ids: ids, vertical: nil)
                }
            }
            Text(resolved.map {
                childCaption($0, flow, stale: stale, arranges: arranges,
                             arrangement: arrangement(of: container))
            } ?? manyCaption(flow))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Who these rows are about, in the words of what is holding them.
    private func heading(_ container: Layer) -> String {
        guard selection.count > 1 else {
            return container.isFrame ? "This layer on \(container.name)"
                                     : "This layer in \(container.name)"
        }
        return container.isFrame ? "These \(selection.count) layers on \(container.name)"
                                 : "These \(selection.count) layers in \(container.name)"
    }

    /// Whether the picked layers take the room their stack has left over, and
    /// how to say otherwise. Only a layer's own rows carry it: the Contents
    /// rows speak for everything inside a group at once, and "all of you take
    /// what is left" is a grid, not a stack.
    private func fillingRow(_ flow: PlacementEditing) -> FillingRow? {
        guard container != nil, flow.canFill,
              let fill = flow.fillTitle, let answer = flow.setByTheFlow else { return nil }
        let ids = selection.layers
        guard !ids.isEmpty else { return nil }
        let reading = selection.fills
        let fills = reading.value ?? false
        return FillingRow(
            title: reading.isMixed ? PlacementSelection.mixedText : (fills ? fill : answer),
            isMixed: reading.isMixed,
            follows: !fills && !reading.isMixed,
            answer: answer, fill: fill,
            set: { editorState.setFillsTheFlow(ids: ids, $0) })
    }

    /// The group's own default still written on the axis its flow decides, so
    /// the Contents rows can offer to clear it the same way a layer's do.
    ///
    /// One group only: the leftover rule is a different word on each of three
    /// groups, and a Clear button that named one of them would be lying about
    /// the other two. The same rule the child rows' own Clear already follows.
    private func contentsInertRule(_ flow: PlacementEditing) -> String? {
        guard contents.count == 1, let one = contents.groups.first else { return nil }
        return flow.inertRule(in: one.rule)
    }

    /// The word beside a listed piece, which for the surface is a plainer
    /// sentence than a pair of directions and reads better a shade quieter.
    private func exceptionStyle(_ exception: PlacementOverride) -> AnyShapeStyle {
        exception.isSurface ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary)
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
                              stale: String?, arranges: Bool,
                              arrangement: GroupLayout?) -> String {
        // The one layer in an arranged group that is not being arranged. Left
        // unsaid, its rows read like any other layer's while it is doing
        // something else entirely, and the Stretch that puts it there looks
        // like a leftover worth clearing.
        if arranges, resolved.isSurface {
            return "Stretch both ways makes this the surface behind the rest, painted to the "
                + "group's own edges instead of being lined up with the others. Change either "
                + "one and it becomes one of them again."
        }
        // The same thing said about one direction: a hairline across a bar, a
        // rail down a panel. Stretch is the size of the box, which is the one
        // thing a row in this stack cannot be, so it steps out and spans the
        // group instead. Unsaid, it reads like a row that has quietly stopped
        // lining up.
        if arranges, resolved.stepsOutOfTheFlow(of: arrangement) {
            let way = arrangement?.flowsHorizontally == true ? "Across" : "Down"
            return "\(way) is the way this group runs, so Stretch here spans the whole group "
                + "and paints this to the group's own edges instead of giving it a place in "
                + "the line. Change it and it lines up with the others again."
        }
        // Taking the room the stack has left over is the loudest thing a piece
        // can be doing, and it is not on either menu the other branches talk
        // about, so it is said first.
        if only?.fillsTheFlow == true, flow.canFill, let owner = flow.flowNoun {
            return "This takes the room \(owner) has left once everything else, the gaps and "
                + "the room at its edges have taken theirs. Set it back and it goes to the size "
                + "it was before."
        }
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
        if only?.text != nil, stretches {
            return "Stretch fills the box with the words placed by Align, in Text."
        }
        // A stack with nothing to spare is the one place the row above went
        // quiet, so this is where it says why, with the number that would
        // change the answer. It goes in the caption that was already here
        // rather than as a second line: the section is short on room, and
        // "following the group" is the less useful of the two things to say.
        if let missing = flow.noRoomToFill {
            return missing
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

    /// The line under the rows when they speak for SEVERAL layers.
    ///
    /// The single-layer caption tells one layer's story: it is the surface, it
    /// still carries a rule the stack ignores, its words fill the box it was
    /// told to stretch to. None of that survives being said about four layers
    /// at once, so this says the two things that are still true of all of them
    /// — who is deciding, and that one pick here reaches every one.
    private func manyCaption(_ flow: PlacementEditing) -> String {
        // No counting here: the heading right above already says how many, and
        // "All 2 are following the group" is a sentence nobody says out loud.
        if selection.fills.value == true, flow.canFill, let owner = flow.flowNoun {
            return "These all take the room \(owner) has left, shared equally, once everything "
                + "else, the gaps and the room at its edges have taken theirs."
        }
        if let missing = flow.noRoomToFill {
            return missing
        }
        let following = (!flow.canSetHorizontal || selection.horizontal.follows)
            && (!flow.canSetVertical || selection.vertical.follows)
        if following {
            return isOnAScreen
                ? "These are all following the screen. Pick something here to give every one of "
                    + "them the same rule."
                : "These are all following the group. Pick something here to give every one of "
                    + "them the same rule."
        }
        return isOnAScreen
            ? "One pick here reaches every one of them, and wins over the screen's rule."
            : "One pick here reaches every one of them, and wins over the group's rule."
    }

    // MARK: - What everything inside these groups does

    /// What the picked groups tell their own contents, for one group or for
    /// three. Every row here reads the whole pick and reaches the whole pick,
    /// so making two cards stack their contents 12 apart is one visit to this
    /// block rather than one visit per card.
    private func contentRows() -> some View {
        // Which of the two directions the groups' own flows have taken over.
        // Where they do not agree, both rows stay live and one line underneath
        // says so: a row that went dead would be answering for the groups it
        // is not about.
        let flow = contents.flow
        let stale = contentsInertRule(flow)
        let ids = contents.ids
        // Whether the block ends on the line about following. It is the last
        // thing in the block when it is there, so it is also where the promise
        // about reaching every picked group goes.
        let showsFollowCaption = contents.nothingArranged && !contents.isFollowed
        return VStack(alignment: .leading, spacing: 6) {
            Text(contents.heading)
                .font(.caption)
                .foregroundStyle(.secondary)
            // How these groups arrange their contents, above where each one
            // sits, because the arrangement decides which of the two rows below
            // is still a question (Next, `next-auto-layout`).
            if Experiments.shared.autoLayoutEnabled {
                ArrangementInspector(contents: contents)
            }
            // The axis a stack runs along is the stack's answer, not a menu:
            // a live control that changes nothing is worse than a row that
            // says who owns it.
            if contents.isFollowed {
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
                            ? answer(contents.horizontal.value?.title)
                            : (flow.setByTheFlow
                               ?? answer(contents.horizontal.value?.title)))
                followedRow("Vertical", flow.canSetVertical
                            ? answer(contents.vertical.value?.title)
                            : (flow.setByTheFlow
                               ?? answer(contents.vertical.value?.title)))
            } else {
                if flow.canSetHorizontal {
                    row("Horizontal") {
                        Menu {
                            ForEach(contents.horizontalChoices, id: \.self) { choice in
                                Button(choice.title) {
                                    editorState.setContentPlacement(ids: ids, horizontal: choice)
                                }
                            }
                        } label: {
                            menuLabel(answer(contents.horizontal.value?.title),
                                      following: false,
                                      isMixed: contents.horizontal.isMixed)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                } else {
                    ownedByTheFlow("Horizontal", flow, clearing: stale, filling: nil) {
                        editorState.setContentPlacement(ids: ids, horizontal: nil)
                    }
                }
                if flow.canSetVertical {
                    row("Vertical") {
                        Menu {
                            ForEach(contents.verticalChoices, id: \.self) { choice in
                                Button(choice.title) {
                                    editorState.setContentPlacement(ids: ids, vertical: choice)
                                }
                            }
                        } label: {
                            menuLabel(answer(contents.vertical.value?.title),
                                      following: false,
                                      isMixed: contents.vertical.isMixed)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                } else {
                    ownedByTheFlow("Vertical", flow, clearing: stale, filling: nil) {
                        editorState.setContentPlacement(ids: ids, vertical: nil)
                    }
                }
            }
            // A copy says who owns all of this ONCE, here at the foot, so the
            // one line covers the arrangement above it and the two rows right
            // above it rather than stopping halfway down the section. One
            // LINE: every row above is already greyed, so the foot only has to
            // carry the thing somebody can act on.
            if contents.isFollowed {
                Text(PhotonzDocument.instanceArrangementShortReason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // With an arrangement on, the Arrangement rows say what happens in
            // words already, so this would be the second caption in a row.
            if showsFollowCaption {
                Text(contentsCaption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // What one pick here does, said ONCE at the foot of the whole
            // block rather than at the end of every caption in it: the rows
            // above it are three sentences already, and reading the same
            // promise three times is how a panel starts sounding anxious.
            if contents.flowsDiffer {
                // The one case where these rows reach some of the picked groups
                // differently from the rest, said out loud rather than left for
                // somebody to discover by setting one and watching two move. It
                // carries the reach itself, so it replaces the line below.
                Text(ContentsSelection.flowsDifferNote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if contents.count > 1, !showsFollowCaption {
                // The line above already carries this where it is there. This
                // is the same promise for the arranged case, where it is not.
                Text("One pick or one number here reaches every one of them, in one step "
                     + "that one undo puts back.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            exceptions()
        }
    }

    /// What a Contents row shows: the answer the picked groups agree on, or the
    /// one word for an answer they do not. A reading with no value is a reading
    /// they disagreed on, since a group always tells its contents something.
    private func answer(_ title: String?) -> String { title ?? MixedValue.text }

    /// The line under the Contents rows for a group that arranges nothing.
    private var contentsCaption: String {
        guard contents.count == 1, let one = contents.groups.first else {
            // This is the last line of the block, so it carries the reach as
            // well and the section does not need a paragraph of its own for it.
            return "Everything inside these \(contents.plural) follows this when they are "
                + "resized, unless a layer says otherwise for itself. One pick here reaches "
                + "every one of them."
        }
        return one.isFrame
            ? "Everything on this screen follows this when the screen is resized, "
                + "unless a layer says otherwise for itself."
            : "Everything inside follows this when the group is resized, "
                + "unless a layer says otherwise for itself."
    }

    // MARK: - The pieces that are not following

    /// Who inside these groups placed itself, named right under the setting
    /// they are ignoring. Without this the only way to find an override is to
    /// click every piece in turn, and a group whose contents will not move is a
    /// mystery until you do. A group where everybody follows says nothing:
    /// an empty list would be a permanent question about an answer of none.
    @ViewBuilder
    private func exceptions() -> some View {
        let overrides = contents.overrides
        if !overrides.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(contents.overridesHeading)
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

    /// One name, which group it is in while this block speaks for more than
    /// one, what it does instead, and a click that goes there.
    ///
    /// The group's name is only there when it is telling you something: with
    /// one group picked every row would carry the same word, and two cards can
    /// each hold a layer called Title, which is exactly the pair of rows
    /// nobody could tell apart without it.
    private func exceptionRow(_ exception: ContentsOverride) -> some View {
        Button {
            editorState.selectLayer(exception.id, inGroup: exception.groupID)
        } label: {
            HStack(spacing: 8) {
                Text(exception.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if contents.count > 1 {
                    Text("in \(exception.groupName)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(exception.summary)
                    .font(.caption)
                    .foregroundStyle(exceptionStyle(exception.override))
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
    /// The stack decides WHERE each piece sits along here, but not how much
    /// room it takes: one piece may be told to take whatever the stack has
    /// left over, which is how a search field ends up being the part of a nav
    /// bar the logo and the buttons did not want. So the row is a menu with
    /// exactly two answers rather than a dead word, and it reads the answer
    /// back the same way every other row in this section does.
    ///
    /// Where the stack has nothing left over the menu is not there at all: the
    /// answer goes back to being a word and the caption under the rows says
    /// why, because a choice that is present and changes nothing is worse than
    /// no choice.
    ///
    /// `clearing` is the rule still written on that axis from before the stack
    /// took it over. It does nothing today, and it is not counted as a rule of
    /// its own anywhere else, so this row is the one place it can be seen — and
    /// the only place it can be taken off before flipping the direction brings
    /// it back to life.
    @ViewBuilder
    private func ownedByTheFlow(_ title: String, _ flow: PlacementEditing,
                                clearing stale: String? = nil,
                                filling: FillingRow? = nil,
                                clear: @escaping () -> Void = {}) -> some View {
        if let answer = flow.setByTheFlow {
            row(title) {
                HStack(spacing: 8) {
                    if let filling {
                        Menu {
                            Button(filling.answer) { filling.set(false) }
                            Button(filling.fill) { filling.set(true) }
                        } label: {
                            menuLabel(filling.title, following: filling.follows,
                                      isMixed: filling.isMixed)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help(PlacementEditing.fillReason(flow.flowNoun ?? "the stack"))
                    } else {
                        Text(answer)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
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
    /// thing at a glance — and a row whose picked layers do not agree says
    /// Mixed in that same slot, at the one strength the whole dock says it
    /// (`MixedLook`).
    private func menuLabel(_ title: String, following: Bool, isMixed: Bool = false) -> some View {
        Text(title)
            .font(.callout)
            .foregroundStyle(MixedLook.style(isMixed, otherwise:
                following ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)))
    }
}

/// The two-answer menu on the row a stack owns: keep your size, or take the
/// room the stack has left. It carries what the picked layers READ as well as
/// what setting it does, so one layer and five go through the same row.
struct FillingRow {
    /// What the menu shows now: one of the two answers, or Mixed.
    let title: String
    /// Whether the picked layers disagree.
    let isMixed: Bool
    /// Whether they are all doing the ordinary thing, which reads quieter.
    let follows: Bool
    /// The two answers, in the flow's own words.
    let answer: String
    let fill: String
    let set: (Bool) -> Void
}
