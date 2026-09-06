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
///
/// It speaks for ONE picked group or for several, through `ContentsSelection`:
/// a row that agrees shows its answer, one that does not says Mixed in the
/// answer's own place, and whatever you set from it reaches every picked group
/// in one undo step. One group reads exactly the way three do, so there is one
/// path through here rather than two that can drift.
struct ArrangementInspector: View {
    @Environment(EditorState.self) private var editorState
    /// The picked groups these rows speak for, and what each row reads across
    /// them. Handed in already read, so no row here reaches back into the
    /// document and no two rows can disagree about who they are about.
    let contents: ContentsSelection

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

    private var ids: [UUID] { contents.ids }

    /// The one picked group, or nobody as soon as a second is picked. Only the
    /// sentences that tell ONE group's story hang off this: everything that is
    /// a control reads the whole selection instead.
    private var one: ContentsSelection.Group? {
        contents.count == 1 ? contents.groups.first : nil
    }

    private var many: Bool { contents.count > 1 }

    /// What every picked group is arranged as, or nil where they are not all
    /// arranged the same way. `.some(nil)` is every one of them Free.
    private var agreed: GroupLayoutKind?? {
        contents.arrangement.isMixed ? nil : contents.arrangement.value
    }

    /// Whether every picked group is on this one arrangement.
    private func allAre(_ kind: GroupLayoutKind?) -> Bool { agreed == .some(kind) }

    /// The word these rows talk about their groups in.
    private var noun: String { contents.noun }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A copy is SHOWN how it arranges its contents and refused the
            // typing of it: every one of these numbers is refilled from the
            // original after each edit, so a field here would take a number
            // and lose it by the next redraw (found 2026-09-04). The same
            // answer the W and H fields already give a copy.
            if contents.isFollowed {
                followedRows()
            } else {
                ownRows()
            }
        }
        .onChange(of: ids) {
            sidesOpen = nil
            widthLimitsOpen = nil
            heightLimitsOpen = nil
        }
    }

    /// The whole section as the group that owns it sees it.
    @ViewBuilder
    private func ownRows() -> some View {
        row("Arrangement", mixed: contents.arrangement.isMixed) {
            Picker("", selection: Binding<GroupLayoutKind??>(get: { agreed }, set: { picked in
                // The outer nil is Mixed, which is a report about the picked
                // groups rather than something anybody can choose.
                guard let picked else { return }
                editorState.setArrangement(ids: ids, kind: picked)
            })) {
                Text("Free").tag(GroupLayoutKind??.some(.none))
                ForEach(GroupLayoutKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(GroupLayoutKind??.some(.some(kind)))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 152)
            // A row of words with no segment lit reads as a control nobody has
            // set, so while the picked groups disagree it wears the same one
            // step quieter every other Mixed control does, and the word sits
            // beside the caption where there is room for it.
            .opacity(contents.arrangement.isMixed ? MixedLook.controlOpacity : 1)
            .help(Self.arrangementHelp)
        }
        numbers()
        if let sentence = sentence() {
            Text(sentence)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The one line under the rows, and usually no line at all.
    ///
    /// This used to be a paragraph, and every clause of it said again what a
    /// control two rows up already says: "Everything in this group stays where
    /// you put it" is the lit Free segment, "It is as wide as what is inside
    /// it" is the lit Hug segment, and the limits sentence is the Smallest and
    /// Largest fields, which open themselves the moment one is set. Five lines
    /// of restatement pushed the sections under this one off the bottom of the
    /// panel, so it is gone and the teaching half of it moved into the
    /// Arrangement control's own tooltip, where somebody meeting Stack for the
    /// first time is already looking.
    ///
    /// What is left is the two things that are NOT on screen anywhere: why the
    /// spread switch is missing, and that a stack given a size across is only
    /// filled once the row below says Stretch. One short line each.
    private func sentence() -> String? {
        guard let one else { return nil }
        let parts = [spreadSentence(one.layout), fillSentence(one)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - A copy, which follows its original

    /// What a copy arranges to, readable and not typeable.
    ///
    /// The answers are words on rows, not fields: a field you cannot type in
    /// still looks like a field, and eight of them is a section that reads as
    /// broken rather than as owned by somebody else. They used to be a
    /// paragraph instead, which took three lines to say what three rows say in
    /// one word each and put every number a long way from the row an original
    /// keeps it on. Same rows, same order, same words, answers greyed.
    ///
    /// Only what has no other home on the panel: the size is left out, because
    /// W and H in Position & Size are two rows above this and hold the very
    /// same numbers (`GroupLayout.followedReadout`).
    ///
    /// Who owns all of it is said once, at the FOOT of the whole section,
    /// under the Horizontal and Vertical rows this hands over as well.
    @ViewBuilder
    private func followedRows() -> some View {
        row("Arrangement", mixed: contents.arrangement.isMixed) {
            Text(contents.arrangement.isMixed
                 ? MixedValue.text
                 : ((contents.arrangement.value ?? nil)?.title ?? "Free"))
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .help(PhotonzDocument.instanceArrangementReason)
        if let one {
            ForEach(one.layout.followedReadout(clipsContents: one.clipsContents), id: \.title) {
                readout in
                row(readout.title) {
                    Text(readout.value)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .help(help(for: readout, of: one))
            }
        } else {
            // Three copies of three different originals have no four numbers
            // in common, so there is nothing to put on a row.
            Text("These \(contents.count) copies arrange their contents the way their "
                 + "originals do.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What one read-only row says on hover. Room written clockwise needs its
    /// sides named, the way the typeable field's tooltip names them; the rest
    /// read as themselves.
    private func help(for readout: LayoutReadout, of group: ContentsSelection.Group) -> String {
        guard readout.title == "Padding" else { return "" }
        let room = group.layout.usedPadding
        return room.isUniform
            ? "The room kept clear inside its edges, on all four sides."
            : room.inWords + ", clear inside its edges."
    }

    @ViewBuilder
    private func numbers() -> some View {
        // The rows that belong to ONE arrangement are only there while every
        // picked group is on it: a Direction over a stack and a grid would be
        // a control that reaches half of what is picked, and the sentence
        // under the section says so instead.
        if allAre(.stack) {
            row("Direction", mixed: contents.direction.isMixed) {
                Picker("", selection: Binding<StackDirection?>(
                    get: { contents.direction.value },
                    set: { direction in
                        guard let direction else { return }
                        editorState.updateArrangement(ids: ids) { $0.direction = direction }
                    })) {
                    ForEach(StackDirection.allCases, id: \.self) {
                        Text($0.title).tag(StackDirection?.some($0))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 152)
                .opacity(contents.direction.isMixed ? MixedLook.controlOpacity : 1)
            }
        } else if allAre(.grid) {
            number("Columns", reading: contents.columns.asNumber, minimum: 1,
                   help: "How many cells a row holds before the next one wraps.") { value in
                editorState.updateArrangement(ids: ids) { $0.columns = Int(value.rounded()) }
            }
        }
        // A screen is a box you were given; a group either takes the size its
        // contents make or holds a size of its own, which is what lets a menu
        // be 320 wide before there is a screen to build it on. One screen in
        // the pick takes these away rather than showing a size it cannot set.
        if contents.offersASizeOfItsOwn {
            sizeRows(.width)
            sizeRows(.height)
            // Right under the number that caused the overflow, and in the same
            // two words a screen uses. A screen's own switch is in the Frame
            // section, so it is never offered twice.
            clipRow()
        }
        // A gap is the space the flow leaves BETWEEN things, so it belongs to
        // the two arrangements that put things one after another.
        if allAre(.grid) {
            number("Column gap", reading: contents.gap,
                   help: "The space between one thing and the next.") { value in
                editorState.updateArrangement(ids: ids) { $0.gap = value }
            }
            number("Row gap", reading: contents.rowGap,
                   help: "The space between one row and the next.") { value in
                editorState.updateArrangement(ids: ids) { $0.rowGap = value }
            }
        } else if allAre(.stack) {
            gapRow()
        }
        // A group that arranges itself has edges of its own, whether it was
        // given a size or takes the one its contents make, so it can keep room
        // clear inside them the same way a screen does.
        padding()
    }

    /// Whether these groups cut off what does not fit inside them.
    ///
    /// Only where it could DO something: a group that closes around its
    /// contents has nothing hanging out of it, so the switch is not there at
    /// all rather than sitting on the panel changing nothing. It appears the
    /// moment a width, a height or a largest size gives every picked group a
    /// box of its own, and it starts off, so no picture anybody has already
    /// drawn changes until they ask for it.
    @ViewBuilder
    private func clipRow() -> some View {
        if contents.offersClipping {
            let reading = contents.clips
            // A switch has on and off and nothing else, so while the picked
            // groups disagree it wears the Mixed weight, the word sits beside
            // its caption, and the first press resolves to on for all of them.
            let clips = reading.value == true
            HStack(spacing: 8) {
                Toggle(isOn: Binding(get: { clips },
                                     set: { editorState.setClipsContents(ids: ids, $0) })) {
                    Text("Clip contents")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
                .opacity(reading.isMixed ? MixedLook.controlOpacity : 1)
                .help(clips
                    ? "What sticks out past this \(noun)'s edge is not drawn, not clicked and not exported."
                    : "Cut off whatever sticks out past this \(noun)'s edge, the way a screen does.")
                .playtestControl("Clip contents", detail: clips ? "Group, on" : "Group, off")
                if reading.isMixed { MixedWord().fixedSize() }
            }
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
    private func gapRow() -> some View {
        let offered = contents.canSpread
        // Mixed spreading resolves to on with the first press, the way a mixed
        // switch always has: it is a report about the pick, not a state.
        let spreading = offered && contents.spreads.value == true
        let across = contents.direction.value?.isHorizontal ?? true
        let gap = contents.gap
        HStack(spacing: 6) {
            Text("Gap")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            if offered {
                Button {
                    editorState.updateArrangement(ids: ids) { $0.spreadsGap = !spreading }
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
                .opacity(contents.spreads.isMixed ? MixedLook.controlOpacity : 1)
                .help(spreading
                    ? "Hold one gap between them again, the \(Int(gap.value ?? 0)) that was here before."
                    : "Share the room left over between them, so the first and the last sit at the two ends.")
                .playtestControl("Spread", detail: "Layout")
            }
            Spacer(minLength: 8)
            LayoutNumberField(
                title: "Gap", value: spreading ? nil : gap.value,
                placeholder: spreading ? "Spread" : (gap.isMixed ? MixedValue.text : ""),
                help: spreading
                    ? "The room left over is shared between them. Type a number to hold one gap instead."
                    : "The space between one thing and the next."
            ) { value in
                editorState.updateArrangement(ids: ids) {
                    $0.gap = value
                    $0.spreadsGap = false
                }
            }
        }
        .playtestField("Gap")
    }

    /// The room kept clear inside the edges.
    ///
    /// One field, because one number all round is what most things want, and a
    /// chevron beside it that opens the four sides for the things that do not:
    /// a card 16 in from the left, 12 down from the top and 24 up from the
    /// bottom is ordinary, and it used to be buildable only by nudging pieces
    /// the stack then put back. The sides open themselves whenever they
    /// disagree — one group's own four sides, or two groups against each other
    /// — so room typed on one side is never hidden behind a chevron and never
    /// shows as a single number that is not true.
    @ViewBuilder
    private func padding() -> some View {
        let reading = contents.padding
        let room = reading.value ?? .none
        let open = showsSides()
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
                sidesOpen = !open
            } label: {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(open
                ? "Hide the four sides and keep the room they were given."
                : "Give this \(noun) different room on each of its four sides.")
            .playtestControl("Each side", detail: "Layout")
            Spacer(minLength: 8)
            LayoutNumberField(
                title: "Padding", value: reading.isMixed ? nil : room.uniform,
                placeholder: standIn(reading), help: paddingHelp(reading)
            ) { value in
                editorState.updateArrangement(ids: ids) { $0.padding = GroupPadding(value) }
            }
        }
        .playtestField("Padding")
        if open {
            ForEach(GroupPadding.Side.allCases, id: \.self) { side in
                number(side.title, reading: contents.padding(side), indent: 20,
                       help: "The room kept clear inside the \(noun)'s \(side.title.lowercased()) edge.") { value in
                    editorState.updateArrangement(ids: ids) { $0.padding[side] = value }
                }
            }
        }
    }

    private func paddingHelp(_ reading: PlacementReading<GroupPadding>) -> String {
        guard let room = reading.value else {
            return "These \(contents.plural) keep different room inside their edges. "
                + "Type one number to give every side of every one of them the same."
        }
        return room.isUniform
            ? "The room kept clear inside the \(noun)'s edges, on all four sides."
            : "\(room.inWords). Type one number to give every side the same."
    }

    /// Whether the four sides are showing. Closed until somebody opens them.
    ///
    /// They used to open themselves whenever the sides differed, because the
    /// single field said only "Mixed" and the 24 somebody typed at the bottom
    /// was then nowhere on screen. That stopped being true on 2026-09-04: the
    /// closed field reads the four numbers themselves, `10/16/10/16`, and
    /// typing one number over it still gives every side the same. So the four
    /// rows were spending 108 points of a 489 point section saying what the
    /// row above them already says, which is what pushed everything below
    /// Layout off the bottom of the panel.
    private func showsSides() -> Bool {
        sidesOpen ?? false
    }

    /// What stands in the single field while it has no one number to show.
    ///
    /// With the sides OPEN it is the house word for a value that is not one
    /// value, because the four numbers are already on the rows underneath and
    /// writing them twice is noise. With them CLOSED and ONE group picked, the
    /// field is the only place left on screen where the 24 somebody typed at
    /// the bottom can be read, so it holds the four numbers themselves. Two
    /// groups that keep different room have no four numbers in common either,
    /// so that case is the word. Typing over any of them still gives every side
    /// the same number.
    private func standIn(_ reading: PlacementReading<GroupPadding>) -> String {
        guard let room = reading.value, !showsSides(), !room.isUniform else {
            return MixedValue.text
        }
        return room.shorthand
    }

    /// One axis' Hug-or-Fixed row, and behind a chevron beside it, the
    /// smallest and the largest that axis may get.
    ///
    /// Choosing Fixed starts from the size each group is at that moment, so
    /// nothing moves when you press it, and the number itself is typed in W or
    /// H above rather than in a second field here that would have to agree
    /// with it.
    ///
    /// The two limits hide behind the same twist-open Padding already uses,
    /// because four more always-on rows would be the section telling you it has
    /// run out of room. They open themselves the moment one is set, so a group
    /// that stopped growing never hides the reason.
    @ViewBuilder
    private func sizeRows(_ axis: SizeAxis) -> some View {
        let reading = axis == .width ? contents.hugsWidth : contents.hugsHeight
        let hugs = reading.value ?? true
        let open = showsLimits(axis)
        row(axis.title, chevron: { setLimitsOpen(axis, !open) }, open: open,
            chevronHelp: open
                ? "Hide the smallest and largest \(axis.noun), and keep the numbers they were given."
                : "Give this \(noun) a smallest and a largest \(axis.noun).",
            mixed: reading.isMixed) {
            Picker("", selection: Binding<Bool?>(get: { reading.value }, set: { hugging in
                guard let hugging else { return }
                // Each group holds the size IT is at, never the first one's
                // borrowed by the rest, which is why the change is handed the
                // layer as well as the layout.
                editorState.updateArrangement(ids: ids) { layout, layer in
                    let size = hugging ? nil : (axis == .width ? layer.localBounds.width
                                                               : layer.localBounds.height).rounded()
                    if axis == .width { layout.width = size } else { layout.height = size }
                }
            })) {
                Text("Hug").tag(Bool?.some(true))
                Text("Fixed").tag(Bool?.some(false))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 152)
            .opacity(reading.isMixed ? MixedLook.controlOpacity : 1)
            .help(hugs
                ? "This \(noun) is as \(axis.adjective) as what is inside it. Fixed holds the size it is now, and W and H above set it."
                : "This \(noun) holds the \(axis.noun) it was given. Type it in \(axis.field) above, or drag a handle.")
        }
        if open {
            limit("Smallest", axis: axis,
                  reading: axis == .width ? contents.minWidth : contents.minHeight,
                  help: "The \(axis.least) this \(noun) may ever get, whatever is inside it. Leave it empty for no limit.") { size in
                editorState.updateArrangement(ids: ids) {
                    if axis == .width { $0.minWidth = size } else { $0.minHeight = size }
                }
            }
            limit("Largest", axis: axis,
                  reading: axis == .width ? contents.maxWidth : contents.maxHeight,
                  help: "The \(axis.most) this \(noun) may ever get, whatever is inside it. Leave it empty for no limit.") { size in
                editorState.updateArrangement(ids: ids) {
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
    private func showsLimits(_ axis: SizeAxis) -> Bool {
        let open = axis == .width ? widthLimitsOpen : heightLimitsOpen
        return open ?? (axis == .width ? contents.limitsWidth : contents.limitsHeight)
    }

    private func setLimitsOpen(_ axis: SizeAxis, _ open: Bool) {
        if axis == .width { widthLimitsOpen = open } else { heightLimitsOpen = open }
    }

    /// One limit: empty until somebody types a number, and empty again the
    /// moment they clear it, because "no limit" is the answer every group
    /// starts with and it has to be one keystroke away.
    private func limit(_ title: String, axis: SizeAxis, reading: PlacementReading<CGFloat?>,
                       help: String, commit: @escaping (CGFloat?) -> Void) -> some View {
        // The box answers to the axis' own name — "Smallest width", not
        // "Smallest" — because the word Smallest sits under Width AND under
        // Height, and a field two rows answer to is a field neither of them
        // owns, for a screen reader as much as for a scripted walk.
        row(title, indent: 20, field: "\(title) \(axis.noun)") {
            LayoutNumberField(title: "\(title) \(axis.noun)",
                              value: reading.value ?? nil, prompt: "None",
                              placeholder: reading.isMixed ? MixedValue.text : "",
                              help: help, clear: { commit(nil) }, commit: { commit($0) })
        }
    }

    /// What the three words mean, for somebody meeting them for the first
    /// time. This is the paragraph that used to sit under the rows: it is a
    /// thing you read ONCE and never again, so it belongs on the control it
    /// explains rather than taking five lines of a panel forever.
    static let arrangementHelp =
        "Free leaves everything where you put it. Stack lines them up along one direction "
        + "with a gap you type. Grid fills rows of equal cells. Horizontal and Vertical below "
        + "say where each one sits, and a piece set to Stretch both ways is the surface behind "
        + "the rest rather than one of the line."

    /// Why a stack is not being offered the choice to spread, in one line.
    ///
    /// A stack the size of its contents has no room left over, so the switch
    /// on the Gap row is not there at all. Saying nothing would leave somebody
    /// looking for a control they have seen on another stack, so the section
    /// says which row makes the room instead. One line, and it is one of only
    /// two the section ever says.
    private func spreadSentence(_ layout: GroupLayout) -> String? {
        guard layout.kind == .stack, !contents.canSpread else { return nil }
        return "Nothing to spread until "
            + "\(layout.direction.isHorizontal ? "Width" : "Height") is Fixed."
    }

    /// Where the switch is that makes a stack's rows fill the size it was
    /// given. A stack told how wide it is does NOT widen its rows on its own —
    /// the Horizontal row below still owns that axis — and nothing on screen
    /// says so, which left people staring at a 320-wide stack of 40-wide rows
    /// wondering what they got wrong.
    ///
    /// Only while they are NOT filling. Once they are, the row below reads
    /// Stretch and says it better than a sentence can.
    private func fillSentence(_ group: ContentsSelection.Group) -> String? {
        let layout = group.layout
        guard !group.isFrame, layout.kind == .stack else { return nil }
        let flowsAcross = layout.direction.isHorizontal
        let across = flowsAcross ? layout.usedHeight : layout.usedWidth
        guard across != nil else { return nil }
        let placement = group.contents
        let fills = flowsAcross ? placement.vertical == .stretch : placement.horizontal == .stretch
        guard !fills else { return nil }
        return "Set \(flowsAcross ? "Vertical" : "Horizontal") below to Stretch to fill it."
    }

    /// One labelled row. The label never wraps: "Arrangement" broken over two
    /// lines is the panel telling you it has run out of room, and the control
    /// beside it can give up the points instead.
    ///
    /// `mixed` puts the word Mixed at the end of the label, which is where a
    /// control made of pictures rather than words has to say it: out at the
    /// trailing edge it would land against the next column and stop saying
    /// which of the two rows differs.
    private func row(_ title: String, indent: CGFloat = 0, field: String? = nil,
                     chevron: (() -> Void)? = nil, open: Bool = false,
                     chevronHelp: String = "", mixed: Bool = false,
                     @ViewBuilder control: () -> some View) -> some View {
        // A row saying Mixed carries an extra word, and on this section's rows
        // there is nowhere on the line to put it: the controls here are
        // segmented, and a segmented control cannot shrink below its own words,
        // so the word pushed the whole section past the dock's edge and the
        // Grid segment and the Padding box were cut off (found 2026-09-06).
        // So the label takes a line of its own and the control drops under it,
        // which is what the dock's other wide controls already do
        // (`LayersPanel.labelled`). Same control, same place, one line lower.
        VStack(alignment: .leading, spacing: mixed ? 3 : 0) {
            HStack(spacing: 8) {
                // The sides of a padding sit under the word they belong to, so
                // a Top on its own could never read as a rule about the whole
                // group.
                if indent > 0 { Spacer().frame(width: indent) }
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                if let chevron {
                    Button(action: chevron) {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 12)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(chevronHelp)
                    .playtestControl("Limits", detail: title)
                }
                if mixed {
                    MixedWord().fixedSize()
                    Spacer(minLength: 4)
                } else {
                    Spacer(minLength: 8)
                    control()
                }
            }
            if mixed {
                HStack(spacing: 8) {
                    if indent > 0 { Spacer().frame(width: indent) }
                    Spacer(minLength: 8)
                    control()
                }
            }
        }
        // Lends the row's word to whatever it holds, so a scripted walk can
        // say Width's Fixed rather than whichever Fixed came first. Two rows
        // can share a WORD without sharing a name: Smallest sits under both
        // Width and Height, so each says which one it belongs to.
        .playtestField(field ?? title)
    }

    private func number(_ title: String, reading: PlacementReading<CGFloat>,
                        minimum: CGFloat = 0, indent: CGFloat = 0, help: String,
                        commit: @escaping (CGFloat) -> Void) -> some View {
        row(title, indent: indent) {
            LayoutNumberField(title: title, value: reading.value, minimum: minimum,
                              placeholder: reading.isMixed ? MixedValue.text : "",
                              help: help, commit: commit)
        }
    }
}

extension PlacementReading where Value == Int {
    /// A count read as a number, so one field type serves every typed number in
    /// the section.
    var asNumber: PlacementReading<CGFloat> {
        PlacementReading<CGFloat>(value: value.map { CGFloat($0) },
                                  isMixed: isMixed, follows: follows)
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
/// Shared, not private: a number knob on a copy of a component is this same
/// field (`ComponentPanel.swift`), so the arrow keys, the rounding and the word
/// Mixed are decided once rather than twice.
struct LayoutNumberField: View {
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
