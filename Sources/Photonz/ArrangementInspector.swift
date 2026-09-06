import PhotonzCore
import SwiftUI

/// A group that arranges its own contents (Next, `next-auto-layout`).
///
/// Three words at the top of the Layout section — Free, Stack, Grid — and then
/// the numbers that shape whichever one is picked. Free is what every group has
/// always been: things stay where you put them. Stack lays them along one axis
/// with an even gap. Grid fills rows of equal cells.
///
/// All three take a size and room at the edges, because being as big as what is
/// inside you is not something only a stack does: a button is a word with room
/// around it, and it has to grow when the word does.
///
/// The mock (`ui-autolayout`) draws eight controls here, including a
/// distribution row and a per-child hug/fill/fixed row. Both are cut on
/// purpose. Three of distribution's four options only mean anything in a
/// container BIGGER than its contents, and a plain group is exactly as big as
/// its contents. Per-child hug/fill/fixed would be a second control saying what
/// the Horizontal and Vertical rows right below already say, so the stack
/// reuses those instead: the flow owns the axis it runs along, and the
/// placement rows own the other one.
///
/// Every number is typed, never dragged for, because "12 points between the
/// rows" is the thing being built to.
struct ArrangementInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    /// Whether the four sides were opened or closed by hand, and nil while
    /// nobody has said: room that already differs shows itself, and even room
    /// stays one field. Forgotten when the selection moves on, so arriving at a
    /// card with 24 at the bottom always shows the 24.
    @State private var sidesOpen: Bool?

    /// Whether each axis' smallest and largest are showing, and nil while
    /// nobody has said: an axis that already carries one shows it. Forgotten
    /// when the selection moves on, so arriving at a group held at 96 always
    /// shows the 96.
    @State private var widthLimitsOpen: Bool?
    @State private var heightLimitsOpen: Bool?

    private var current: Layer { editorState.document?.layer(id: layer.id) ?? layer }
    /// What this group is working to, including what a group nobody has touched
    /// is already working to, so the rows read the same either way.
    private var layout: GroupLayout { current.workingLayout }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A copy is SHOWN how it arranges its contents and refused the
            // typing of it: every one of these numbers is refilled from the
            // original after each edit, so a field here would take a number
            // and lose it by the next redraw (found 2026-09-04). The same
            // answer the W and H fields already give a copy.
            if current.isComponentInstance {
                followedRows(layout)
            } else {
                ownRows(layout)
            }
        }
        .onChange(of: layer.id) {
            sidesOpen = nil
            widthLimitsOpen = nil
            heightLimitsOpen = nil
        }
    }

    /// The whole section as the group that owns it sees it.
    @ViewBuilder
    private func ownRows(_ layout: GroupLayout) -> some View {
        row("Arrangement") {
            Picker("", selection: Binding(get: { layout.kind },
                                          set: { editorState.setArrangement(id: layer.id,
                                                                            kind: $0) })) {
                Text("Free").tag(GroupLayoutKind?.none)
                ForEach(GroupLayoutKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(GroupLayoutKind?.some(kind))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 152)
        }
        numbers(layout)
        Text(([caption(layout), spreadSentence(layout), sizeSentence(layout),
               current.isFrame ? nil : layout.limitsSentence]
            .compactMap { $0 }).joined(separator: " "))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - A copy, which follows its original

    /// What a copy arranges to, readable and not typeable. The numbers move
    /// into the sentence rather than into greyed-out fields: a field you cannot
    /// type in still looks like a field, and eight of them is a section that
    /// reads as broken rather than as owned by somebody else.
    ///
    /// Who owns them is said once, at the FOOT of the whole section, under the
    /// Horizontal and Vertical rows this hands over as well, so one sentence
    /// covers everything above it instead of stopping halfway down.
    @ViewBuilder
    private func followedRows(_ layout: GroupLayout) -> some View {
        row("Arrangement") {
            Text(layout.kind?.title ?? "Free")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .help(PhotonzDocument.instanceArrangementReason)
        Text(followedSentence(layout))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A copy's arrangement in one sentence, numbers and all, because a number
    /// you cannot change is still a number worth reading off a copy.
    private func followedSentence(_ layout: GroupLayout) -> String {
        var parts: [String] = []
        switch layout.kind {
        case nil:
            parts.append("Everything in this copy stays where the original put it.")
        case .stack:
            parts.append("Everything in this copy lines up "
                         + "\(layout.direction.isHorizontal ? "across" : "down"), "
                         + (canSpread(layout) && layout.spreadsGap
                            ? "with the room left over shared between them."
                            : "\(Int(layout.usedGap)) apart."))
        case .grid:
            parts.append("Everything in this copy fills \(layout.usedColumns) "
                         + "\(layout.usedColumns == 1 ? "column" : "columns"), a row at a time.")
        }
        let room = layout.usedPadding
        if room != .none {
            parts.append(room.isUniform
                ? "It keeps \(Int(room.uniform ?? 0)) clear inside its edges."
                : "It keeps \(room.inWords) clear inside its edges.")
        }
        let fixed = [layout.width.map { "\(Int($0.rounded())) wide" },
                     layout.height.map { "\(Int($0.rounded())) tall" }].compactMap { $0 }
        if !current.isFrame, !fixed.isEmpty {
            parts.append("It is \(fixed.joined(separator: " and ")).")
        }
        if !current.isFrame, let limits = layout.limitsSentence { parts.append(limits) }
        // A copy is shown this and never asked it, like everything else about
        // the way its original arranges its contents.
        if !current.isFrame, current.clipsToBounds {
            parts.append("It cuts off whatever does not fit inside it.")
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private func numbers(_ layout: GroupLayout) -> some View {
        if layout.kind == nil {
            EmptyView()
        } else if layout.kind == .stack {
            row("Direction") {
                Picker("", selection: Binding(get: { layout.direction },
                                              set: { direction in
                    editorState.updateArrangement(id: layer.id) { $0.direction = direction }
                })) {
                    ForEach(StackDirection.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 152)
            }
        } else {
            number("Columns", value: CGFloat(layout.usedColumns), minimum: 1,
                   help: "How many cells a row holds before the next one wraps.") { value in
                editorState.updateArrangement(id: layer.id) { $0.columns = Int(value.rounded()) }
            }
        }
        // A screen is a box you were given; a group either takes the size its
        // contents make or holds a size of its own, which is what lets a menu
        // be 320 wide before there is a screen to build it on.
        if !current.isFrame {
            sizeRows(.width, layout)
            sizeRows(.height, layout)
            // Right under the number that caused the overflow, and in the same
            // two words a screen uses. A screen's own switch is in the Frame
            // section, so it is never offered twice.
            clipRow()
        }
        // A gap is the space the flow leaves BETWEEN things, so it belongs to
        // the two arrangements that put things one after another.
        if layout.kind == .grid {
            number("Column gap", value: layout.usedGap,
                   help: "The space between one thing and the next.") { value in
                editorState.updateArrangement(id: layer.id) { $0.gap = value }
            }
        } else if layout.kind == .stack {
            gapRow(layout)
        }
        if layout.kind == .grid {
            number("Row gap", value: layout.usedRowGap,
                   help: "The space between one row and the next.") { value in
                editorState.updateArrangement(id: layer.id) { $0.rowGap = value }
            }
        }
        // A group that arranges itself has edges of its own, whether it was
        // given a size or takes the one its contents make, so it can keep room
        // clear inside them the same way a screen does.
        padding(layout)
    }

    /// Whether this group cuts off what does not fit inside it.
    ///
    /// Only where it could DO something: a group that closes around its
    /// contents has nothing hanging out of it, so the switch is not there at
    /// all rather than sitting on the panel changing nothing. It appears the
    /// moment a width, a height or a largest size gives the group a box of its
    /// own, and it starts off, so no picture anybody has already drawn changes
    /// until they ask for it.
    @ViewBuilder
    private func clipRow() -> some View {
        if current.hasBoxOfItsOwn {
            let clips = current.clipsToBounds
            Toggle(isOn: Binding(get: { clips },
                                 set: { editorState.setClipsContents(id: layer.id, $0) })) {
                Text("Clip contents")
                    .font(.callout)
            }
            .toggleStyle(.checkbox)
            .help(clips
                ? "What sticks out past this group's edge is not drawn, not clicked and not exported."
                : "Cut off whatever sticks out past this group's edge, the way a screen does.")
            .playtestControl("Clip contents", detail: clips ? "Group, on" : "Group, off")
        }
    }

    /// The space between one thing and the next, and on a stack that has room
    /// to spare, the choice to share that room out instead of holding a number.
    ///
    /// A nav bar is a logo at one end and buttons at the other, and one gap
    /// cannot make that shape: the pieces have to be pushed apart, and until
    /// now the only way to do it was to nudge them and watch the stack put
    /// them back. Spreading is a switch beside the word rather than a row of
    /// its own, because it is two states about the number on the same line and
    /// this section has already spent its rows.
    ///
    /// It is only there where it could DO something. A stack that is the size
    /// of its contents has nothing left over, so the switch is gone and the
    /// sentence under the section says why: a control that is present and
    /// changes nothing is worse than no control.
    ///
    /// Two ways back to a number, because either is the one somebody reaches
    /// for: press the switch again and the gap that was there comes back, or
    /// type a number straight over the word.
    @ViewBuilder
    private func gapRow(_ layout: GroupLayout) -> some View {
        let offered = canSpread(layout)
        let spreading = offered && layout.spreadsGap
        let across = layout.direction.isHorizontal
        HStack(spacing: 6) {
            Text("Gap")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            if offered {
                Button {
                    editorState.updateArrangement(id: layer.id) { $0.spreadsGap = !spreading }
                } label: {
                    Image(systemName: across ? "arrow.left.and.line.vertical.and.arrow.right"
                                             : "arrow.up.and.line.horizontal.and.arrow.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(spreading ? AnyShapeStyle(Color.accentColor)
                                                   : AnyShapeStyle(.secondary))
                        .frame(width: 16, height: 12)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(spreading
                    ? "Hold one gap between them again, the \(Int(layout.usedGap)) that was here before."
                    : "Share the room left over between them, so the first and the last sit at the two ends.")
                .playtestControl("Spread", detail: "Layout")
            }
            Spacer(minLength: 8)
            LayoutNumberField(
                title: "Gap", value: spreading ? nil : layout.usedGap,
                placeholder: spreading ? "Spread" : "",
                help: spreading
                    ? "The room left over is shared between them. Type a number to hold one gap instead."
                    : "The space between one thing and the next."
            ) { value in
                editorState.updateArrangement(id: layer.id) {
                    $0.gap = value
                    $0.spreadsGap = false
                }
            }
        }
        .playtestField("Gap")
    }

    /// Whether this stack has any room to spread. A screen is a box somebody
    /// drew, so it always has; a group has one where the axis it flows along
    /// was given a size or is held open by a floor.
    private func canSpread(_ layout: GroupLayout) -> Bool {
        guard layout.kind == .stack else { return false }
        return current.isFrame || layout.couldSpread
    }

    /// The room kept clear inside the edges.
    ///
    /// One field, because one number all round is what most things want, and a
    /// chevron beside it that opens the four sides for the things that do not:
    /// a card 16 in from the left, 12 down from the top and 24 up from the
    /// bottom is ordinary, and it used to be buildable only by nudging pieces
    /// the stack then put back. The sides open themselves whenever they
    /// disagree, so room typed on one side is never hidden behind a chevron
    /// and never shows as a single number that is not true.
    @ViewBuilder
    private func padding(_ layout: GroupLayout) -> some View {
        let room = layout.usedPadding
        let noun = current.isFrame ? "screen" : "group"
        HStack(spacing: 6) {
            Text("Padding")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            // The same twist-open every section in this panel already uses,
            // beside the word it opens rather than in front of it, so Padding
            // still starts where Gap and Width start and the number still ends
            // where theirs end.
            Button {
                sidesOpen = !showsSides(room)
            } label: {
                Image(systemName: showsSides(room) ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(showsSides(room)
                ? "Hide the four sides and keep the room they were given."
                : "Give this \(noun) different room on each of its four sides.")
            .playtestControl("Each side", detail: "Layout")
            Spacer(minLength: 8)
            LayoutNumberField(
                title: "Padding", value: room.uniform, placeholder: standIn(room),
                help: room.isUniform
                    ? "The room kept clear inside the \(noun)'s edges, on all four sides."
                    : "\(room.inWords). Type one number to give every side the same."
            ) { value in
                editorState.updateArrangement(id: layer.id) { $0.padding = GroupPadding(value) }
            }
        }
        .playtestField("Padding")
        if showsSides(room) {
            ForEach(GroupPadding.Side.allCases, id: \.self) { side in
                number(side.title, value: room[side], indent: 20,
                       help: "The room kept clear inside the \(noun)'s \(side.title.lowercased()) edge.") { value in
                    editorState.updateArrangement(id: layer.id) { $0.padding[side] = value }
                }
            }
        }
    }

    /// Whether the four sides are showing. Until somebody says otherwise, room
    /// that already differs side to side shows itself: the single field has no
    /// honest number to put in that case, and a chevron is not where a person
    /// should have to go looking for the 24 they typed.
    private func showsSides(_ room: GroupPadding) -> Bool {
        sidesOpen ?? !room.isUniform
    }

    /// What stands in the single field while the four sides disagree and it
    /// has no one number to show.
    ///
    /// With the sides OPEN it is the house word for a value that is not one
    /// value, because the four numbers are already on the rows underneath and
    /// writing them twice is noise. With them CLOSED the field is the only
    /// place left on screen where the 24 somebody typed at the bottom can be
    /// read, so it holds the four numbers themselves. Typing over them still
    /// gives every side the same number, exactly as typing over the word did.
    private func standIn(_ room: GroupPadding) -> String {
        showsSides(room) || room.isUniform ? MixedValue.text : room.shorthand
    }

    /// One axis' Hug-or-Fixed row, and behind a chevron beside it, the
    /// smallest and the largest that axis may get.
    ///
    /// Choosing Fixed starts from the size the group is at that moment, so
    /// nothing moves when you press it, and the number itself is typed in W or
    /// H above rather than in a second field here that would have to agree
    /// with it.
    ///
    /// The two limits hide behind the same twist-open Padding already uses,
    /// because four more always-on rows would be the section telling you it has
    /// run out of room. They open themselves the moment one is set, so a group
    /// that stopped growing never hides the reason.
    @ViewBuilder
    private func sizeRows(_ axis: SizeAxis, _ layout: GroupLayout) -> some View {
        let hugs = axis == .width ? layout.hugsWidth : layout.hugsHeight
        let measured = axis == .width ? current.localBounds.width : current.localBounds.height
        let open = showsLimits(axis, layout)
        let noun = current.isFrame ? "screen" : "group"
        HStack(spacing: 8) {
            Text(axis.title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            Button {
                setLimitsOpen(axis, !open)
            } label: {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(open
                ? "Hide the smallest and largest \(axis.noun), and keep the numbers they were given."
                : "Give this \(noun) a smallest and a largest \(axis.noun).")
            .playtestControl("Limits", detail: axis.title)
            Spacer(minLength: 8)
            Picker("", selection: Binding(get: { hugs }, set: { hugging in
                let size = hugging ? nil : measured.rounded()
                editorState.updateArrangement(id: layer.id) {
                    if axis == .width { $0.width = size } else { $0.height = size }
                }
            })) {
                Text("Hug").tag(true)
                Text("Fixed").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 152)
            .help(hugs
                ? "This group is as \(axis.adjective) as what is inside it. Fixed holds the size it is now, and W and H above set it."
                : "This group holds the \(axis.noun) it was given. Type it in \(axis.field) above, or drag a handle.")
        }
        .playtestField(axis.title)
        if open {
            limit("Smallest", axis: axis, value: axis == .width ? layout.minWidth
                                                                : layout.minHeight,
                  help: "The \(axis.least) this \(noun) may ever get, whatever is inside it. Leave it empty for no limit.") { size in
                editorState.updateArrangement(id: layer.id) {
                    if axis == .width { $0.minWidth = size } else { $0.minHeight = size }
                }
            }
            limit("Largest", axis: axis, value: axis == .width ? layout.maxWidth
                                                               : layout.maxHeight,
                  help: "The \(axis.most) this \(noun) may ever get, whatever is inside it. Leave it empty for no limit.") { size in
                editorState.updateArrangement(id: layer.id) {
                    if axis == .width { $0.maxWidth = size } else { $0.maxHeight = size }
                }
            }
        }
    }

    /// One of the two axes a size and its limits belong to, and the words each
    /// one is talked about in, so no row has to work them out from its title.
    private enum SizeAxis {
        case width, height

        var title: String { self == .width ? "Width" : "Height" }
        /// The plain noun, for a sentence: "a smallest and a largest width".
        var noun: String { self == .width ? "width" : "height" }
        /// Which field above holds the number itself.
        var field: String { self == .width ? "W" : "H" }
        var adjective: String { self == .width ? "wide" : "tall" }
        var least: String { self == .width ? "narrowest" : "shortest" }
        var most: String { self == .width ? "widest" : "tallest" }
    }

    /// Whether one axis' limits are showing. Until somebody says otherwise, an
    /// axis that already carries a limit shows it: a number that is holding a
    /// group open is not something to go hunting behind a chevron for.
    private func showsLimits(_ axis: SizeAxis, _ layout: GroupLayout) -> Bool {
        let open = axis == .width ? widthLimitsOpen : heightLimitsOpen
        return open ?? (axis == .width ? layout.limitsWidth : layout.limitsHeight)
    }

    private func setLimitsOpen(_ axis: SizeAxis, _ open: Bool) {
        if axis == .width { widthLimitsOpen = open } else { heightLimitsOpen = open }
    }

    /// One limit: empty until somebody types a number, and empty again the
    /// moment they clear it, because "no limit" is the answer every group
    /// starts with and it has to be one keystroke away.
    private func limit(_ title: String, axis: SizeAxis, value: CGFloat?, help: String,
                       commit: @escaping (CGFloat?) -> Void) -> some View {
        // The box answers to the axis' own name — "Smallest width", not
        // "Smallest" — because the word Smallest sits under Width AND under
        // Height, and a field two rows answer to is a field neither of them
        // owns, for a screen reader as much as for a scripted walk.
        row(title, indent: 20, field: "\(title) \(axis.noun)") {
            LayoutNumberField(title: "\(title) \(axis.noun)", value: value, prompt: "None",
                              help: help, clear: { commit(nil) }, commit: { commit($0) })
        }
    }

    /// What the arrangement is doing, in words, including which axis has
    /// stopped being yours to set. A live menu that changes nothing is worse
    /// than a sentence saying who owns it.
    private func caption(_ layout: GroupLayout) -> String {
        let noun = current.isFrame ? "screen" : "group"
        switch layout.kind {
        case nil:
            return "Everything in this \(noun) stays where you put it. "
                + "Horizontal and Vertical below say what each one does when the \(noun) "
                + "changes size, and a piece set to Stretch both ways is the surface behind "
                + "the rest."
        case .stack:
            let axis = layout.direction.isHorizontal ? "across" : "down"
            let owned = layout.direction.isHorizontal ? "Horizontal" : "Vertical"
            let other = layout.direction.isHorizontal ? "Vertical" : "Horizontal"
            let spacing = canSpread(layout) && layout.spreadsGap
                ? "with the room left over shared between them"
                : "\(Int(layout.usedGap)) apart"
            return "Everything in this \(noun) lines up \(axis), \(spacing). "
                + "\(owned) is the stack's now; \(other) below still says where each one sits, "
                + "and any one layer can answer it differently for itself."
        case .grid:
            return "Everything in this \(noun) fills \(layout.usedColumns) "
                + "\(layout.usedColumns == 1 ? "column" : "columns"), a row at a time. "
                + "Horizontal and Vertical below say where each one sits inside its cell."
        }
    }

    /// Why a stack is not being offered the choice to spread, in one line.
    ///
    /// A stack the size of its contents has no room left over, so the switch
    /// on the Gap row is not there at all. Saying nothing would leave somebody
    /// looking for a control they have seen on another stack, so the section
    /// says which row makes the room instead.
    private func spreadSentence(_ layout: GroupLayout) -> String? {
        guard layout.kind == .stack, !canSpread(layout) else { return nil }
        // One clause, not two sentences: it sits at the end of a paragraph
        // that is already four lines long, and it has one thing to say.
        return "There is nothing left over to spread until "
            + "\(layout.direction.isHorizontal ? "Width" : "Height") is Fixed."
    }

    /// What a size of its own means for what is inside it, in words. A stack
    /// told how wide it is does NOT widen its rows on its own — the Horizontal
    /// row below still owns that axis — so the caption says where that switch
    /// is rather than leaving somebody staring at a 320-wide stack of 40-wide
    /// rows wondering what they got wrong.
    private func sizeSentence(_ layout: GroupLayout) -> String? {
        guard !current.isFrame else { return nil }
        // A group that arranges nothing says the plainer half of the same
        // thing: which of its two sides is the size of what is inside it.
        guard layout.arranges else {
            let hugs = [layout.hugsWidth ? "wide" : nil, layout.hugsHeight ? "tall" : nil]
                .compactMap { $0 }
            guard !hugs.isEmpty else { return nil }
            return "It is as \(hugs.joined(separator: " and as ")) as what is inside it, "
                + "plus the room at its edges."
        }
        guard layout.kind == .stack else { return nil }
        let flowsAcross = layout.direction.isHorizontal
        guard let across = flowsAcross ? layout.usedHeight : layout.usedWidth else { return nil }
        let word = flowsAcross ? "tall" : "wide"
        let axis = flowsAcross ? "Vertical" : "Horizontal"
        let placement = current.contentPlacementDefault
        let fills = flowsAcross ? placement.vertical == .stretch : placement.horizontal == .stretch
        let size = Int(across.rounded())
        return fills
            ? "It is \(size) \(word), and everything in it fills that."
            : "It is \(size) \(word). Set \(axis) below to Stretch and everything in it fills that."
    }

    /// One labelled row. The label never wraps: "Arrangement" broken over two
    /// lines is the panel telling you it has run out of room, and the control
    /// beside it can give up the points instead.
    private func row(_ title: String, indent: CGFloat = 0, field: String? = nil,
                     @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 8) {
            // The sides of a padding sit under the word they belong to, so a
            // Top on its own could never read as a rule about the whole group.
            if indent > 0 { Spacer().frame(width: indent) }
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 8)
            control()
        }
        // Lends the row's word to whatever it holds, so a scripted walk can
        // say Width's Fixed rather than whichever Fixed came first. Two rows
        // can share a WORD without sharing a name: Smallest sits under both
        // Width and Height, so each says which one it belongs to.
        .playtestField(field ?? title)
    }

    private func number(_ title: String, value: CGFloat, minimum: CGFloat = 0,
                        indent: CGFloat = 0, help: String,
                        commit: @escaping (CGFloat) -> Void) -> some View {
        row(title, indent: indent) {
            LayoutNumberField(title: title, value: value, minimum: minimum,
                              help: help, commit: commit)
        }
    }
}

/// One typed number on an arrangement.
///
/// The draft lives in the field until it lands, and it lands on Return and on
/// clicking away, because a number typed and then abandoned is the most common
/// way a person loses an edit. Up and down step it by 1, Shift by 10, without
/// leaving the field — the same keys the geometry fields answer to, through the
/// same `NumberFieldEntry` rules, so no two number fields in this app can drift
/// apart.
private struct LayoutNumberField: View {
    /// The row's own word, which is also what the field answers to by name:
    /// it is the placeholder and the accessibility label, so a walk can put
    /// the keyboard in "Gap" the way a person puts the pointer there.
    let title: String
    /// The number this field holds, or nil where there is no one number to
    /// show — four sides that disagree have none, and the field says so rather
    /// than picking one of them and lying.
    let value: CGFloat?
    var minimum: CGFloat = 0
    /// What the box says while it is EMPTY, which is a different thing from
    /// standing in for a value that is not one value: a limit nobody has set
    /// says None, and typing a number is what sets it.
    var prompt: String?
    /// What stands in the field when there is no one number to show: the word
    /// Mixed. It is the field's TEXT, not its placeholder, so it is drawn at
    /// the one strength every other Mixed in the dock is drawn at; a
    /// placeholder is a paler grey again, which made this the fifth answer to
    /// the same question (`MixedLook.swift`).
    var placeholder: String = ""
    let help: String
    /// Emptying the box, where emptying it means something. A limit cleared is
    /// no limit; a gap cleared is not a thing, so those fields leave this out
    /// and go on snapping back to the number they had.
    var clear: (() -> Void)?
    let commit: (CGFloat) -> Void

    @State private var text = ""
    @State private var isFinishing = false
    @FocusState private var isFocused: Bool

    /// True while the field is standing in for four sides that disagree.
    private var showsMixed: Bool { !placeholder.isEmpty && text == placeholder }

    /// True where what stands in is the four numbers rather than the word
    /// Mixed. Read off the stand-in itself rather than passed in beside it,
    /// so there is no second flag that can disagree with the text.
    private var standsInForNumbers: Bool { placeholder.contains(where: \.isNumber) }

    /// How wide the box is.
    ///
    /// Every field in this panel is pinned by its TRAILING edge, so the one
    /// holding four numbers grows leftwards into space that was empty anyway
    /// and the column of right edges stays flush. The width comes off the
    /// stand-in and not off what is being typed, so it is settled before the
    /// keyboard arrives and does not twitch a point per keystroke.
    private var fieldWidth: CGFloat {
        guard standsInForNumbers else { return 62 }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize,
                                                   weight: .regular)
        let ink = (placeholder as NSString).size(withAttributes: [.font: font]).width
        return min(148, max(62, (ink + 22).rounded(.up)))
    }

    var body: some View {
        // The field wears its own word until there is no one number to show:
        // then the word Mixed sits where the number would be, which is what
        // every other control in the dock does with a value the picked things
        // do not agree on.
        TextField(title, text: $text, prompt: prompt.map { Text($0) })
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            // Grey is what a value that is not one value looks like. A stand-in
            // that names a real state — a gap that is being spread rather than
            // held — is a value, so it is drawn like one; greying it would
            // read as a field somebody had switched off.
            .foregroundStyle(MixedLook.style(showsMixed && placeholder == MixedValue.text,
                                             otherwise: .primary))
            .frame(width: fieldWidth)
            .focused($isFocused)
            .help(help)
            .accessibilityLabel(title)
            .onAppear { text = display(value) }
            .onChange(of: value) { if !isFocused { text = display(value) } }
            // The stand-in can change while the number behind it does not: the
            // four sides closing over room that disagrees swaps the word Mixed
            // for the four numbers without the field ever having a value. The
            // box has to be refilled for that too, or it goes on showing the
            // word after the row it belonged to has gone.
            .onChange(of: placeholder) { if !isFocused { text = display(value) } }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    isFinishing = false
                    // Typing over a word has to replace it, not append to it.
                    // Only the word: a number in the box still takes a caret
                    // where it was clicked, the way it always did.
                    if showsMixed {
                        DispatchQueue.main.async {
                            NSApp.keyWindow?.firstResponder?.trySelectAllText()
                        }
                    }
                } else if !isFinishing { land() }
            }
            .numberFieldKeys(commit: { isFinishing = true; land() },
                             revert: { isFinishing = true; text = display(value) },
                             step: { direction, coarse in
                                 step(direction: direction, coarse: coarse)
                             })
    }

    /// The draft, landed. Text that is not a number snaps back to the number
    /// the group really has rather than being guessed at.
    private func land() {
        let typed = text.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty, let clear {
            guard value != nil else { return }
            clear()
            return
        }
        guard let typed = Double(typed) else {
            text = display(value)
            return
        }
        let clamped = max(minimum, CGFloat(typed).rounded())
        text = display(clamped)
        guard clamped != value else { return }
        commit(clamped)
    }

    /// Up and down step the number in the field. An empty field with no one
    /// number behind it has nothing to step from, so the keys do nothing there
    /// rather than inventing a nought and flattening four sides into one.
    private func step(direction: Int, coarse: Bool) {
        let typed = Double(text.trimmingCharacters(in: .whitespaces))
        guard let base = typed.map({ CGFloat($0) }) ?? value else { return }
        let next = max(minimum, (base + CGFloat(direction * (coarse ? 10 : 1))).rounded())
        text = display(next)
        guard next != value else { return }
        commit(next)
    }

    /// What the box shows: the number the sides agree on, or the word that says
    /// they do not, or nothing at all on a row that has no word to fall back on.
    private func display(_ value: CGFloat?) -> String {
        value.map { "\(Int($0.rounded()))" } ?? placeholder
    }
}
