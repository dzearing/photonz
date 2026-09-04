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
        .onChange(of: layer.id) { sidesOpen = nil }
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
        Text(caption(layout) + (sizeSentence(layout).map { " " + $0 } ?? ""))
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
                         + "\(Int(layout.usedGap)) apart.")
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
            sizeRow("Width", hugs: layout.hugsWidth, measured: current.localBounds.width) { size in
                editorState.updateArrangement(id: layer.id) { $0.width = size }
            }
            sizeRow("Height", hugs: layout.hugsHeight, measured: current.localBounds.height) { size in
                editorState.updateArrangement(id: layer.id) { $0.height = size }
            }
        }
        // A gap is the space the flow leaves BETWEEN things, so it belongs to
        // the two arrangements that put things one after another.
        if layout.arranges {
            number(layout.kind == .grid ? "Column gap" : "Gap", value: layout.usedGap,
                   help: "The space between one thing and the next.") { value in
                editorState.updateArrangement(id: layer.id) { $0.gap = value }
            }
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

    /// One axis' Hug-or-Fixed row. Choosing Fixed starts from the size the
    /// group is at that moment, so nothing moves when you press it, and the
    /// number itself is typed in W or H above rather than in a second field
    /// here that would have to agree with it.
    private func sizeRow(_ title: String, hugs: Bool, measured: CGFloat,
                         commit: @escaping (CGFloat?) -> Void) -> some View {
        row(title) {
            Picker("", selection: Binding(get: { hugs },
                                          set: { commit($0 ? nil : measured.rounded()) })) {
                Text("Hug").tag(true)
                Text("Fixed").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 152)
            .help(hugs
                ? "This group is as \(title == "Width" ? "wide" : "tall") as what is inside it. Fixed holds the size it is now, and W and H above set it."
                : "This group holds the \(title.lowercased()) it was given. Type it in \(title == "Width" ? "W" : "H") above, or drag a handle.")
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
            return "Everything in this \(noun) lines up \(axis), \(Int(layout.usedGap)) apart. "
                + "\(owned) is the stack's now; \(other) below still says where each one sits, "
                + "and any one layer can answer it differently for itself."
        case .grid:
            return "Everything in this \(noun) fills \(layout.usedColumns) "
                + "\(layout.usedColumns == 1 ? "column" : "columns"), a row at a time. "
                + "Horizontal and Vertical below say where each one sits inside its cell."
        }
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
    private func row(_ title: String, indent: CGFloat = 0,
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
        // say Width's Fixed rather than whichever Fixed came first.
        .playtestField(title)
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
    /// What stands in the field when there is no one number to show: the word
    /// Mixed. It is the field's TEXT, not its placeholder, so it is drawn at
    /// the one strength every other Mixed in the dock is drawn at; a
    /// placeholder is a paler grey again, which made this the fifth answer to
    /// the same question (`MixedLook.swift`).
    var placeholder: String = ""
    let help: String
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
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .foregroundStyle(MixedLook.style(showsMixed, otherwise: .primary))
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
        guard let typed = Double(text.trimmingCharacters(in: .whitespaces)) else {
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
