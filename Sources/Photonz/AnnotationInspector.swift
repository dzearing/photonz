// The settings for an annotation: arrows and their captions, shapes, and the corner radius row they share.

import PhotonzCore
import SwiftUI

// MARK: - Annotation inspector

/// The picked shapes' own settings: thickness, an arrow's caption and its
/// head — over the WHOLE selection.
///
/// Colors are not here: they live in the Color section, which is where they
/// live whatever is picked, so shift-clicking a second layer widens what a row
/// speaks for instead of moving it. These rows now work the same way. Pick two
/// arrows and Thickness is still there, speaking for both; pick an arrow and a
/// box and only the setting they share is offered, because a Head Size slider
/// over a rectangle is a control that does nothing.
///
/// Corners are not here either, for the same reason colors are not: rounding
/// is one row under Effects that speaks for everything picked, shapes and
/// screenshots alike.
///
/// Sliders preview live and commit one undo step on release, however many
/// shapes they reached.
struct AnnotationInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let selection = editorState.shapeSelection
        let ids = selection.layerIDs
        let rows = Self.visibleRows(selection)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    self.row(row, selection: selection, ids: ids)
                }
                // The label pills a hand has dragged, put back where the app
                // places them. Offered only while there is one to put back.
                if !selection.pinnedCaptionIDs.isEmpty,
                   Experiments.shared.arrowCaptionsEnabled {
                    let pinned = selection.pinnedCaptionIDs
                    Button(pinned.count > 1 ? "Reset label positions" : "Reset label position") {
                        editorState.resetCaptionPlacement(ids: pinned)
                    }
                    .font(.caption)
                    .controlSize(.small)
                    .panelHelp(CrowdWords.all(pinned.count)
                                .map { "Put \($0) labels back where the app places them" }
                          ?? "Put the label back where the app places it")
                }
                SelectionStyleNotes(notes: [selection.note])
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 8)
        }
    }

    /// The rows this section actually shows, which is also what decides whether
    /// the section is there at all: a rectangle whose only setting was its
    /// Thickness brings no section once that width has moved into the Outline
    /// part, rather than an empty heading with its name on it.
    static func visibleRows(_ selection: ShapeSelection) -> [ShapeSettingRow] {
        // There is no arrow section any more where Appearance is on. Every one
        // of these rows moved into Appearance, under the part it belongs to,
        // so one section says how the thing looks (`ShapePartSettings.swift`,
        // asked for by the user on 2026-09-09). The release without the split
        // keeps the section exactly as it was.
        guard !Experiments.shared.shapePartsEnabled else { return [] }
        return selection.rows.filter { row in
            // What a line ENDS in is a Next row and lives under the Outline
            // part with the rest of the line's settings, never in this
            // section (`ShapePartSettings.swift`).
            guard row != .lineEnds else { return false }
            // Captions are a Next feature; without it an arrow is a plain
            // arrow and neither the field nor its size row belongs here.
            guard Experiments.shared.arrowCaptionsEnabled
                    || (row != .caption && row != .labelSize) else { return false }
            // Where the outline is a part that switches off — a box, an
            // ellipse — its width is that part's own setting and is called
            // Width there (`next-shape-parts`). Where the line IS the shape
            // the part has no switch and so no drawer, and the thickness
            // stays right here, in reach the moment the arrow is picked.
            return !(Experiments.shared.shapePartsEnabled && row == .thickness
                     && selection.widthIsAnOutlineSetting)
        }
    }

    @ViewBuilder
    private func row(_ row: ShapeSettingRow, selection: ShapeSelection, ids: [UUID]) -> some View {
        switch row {
        case .lineEnds:
            // Never reached: `visibleRows` keeps it out of this section. It
            // belongs under the Outline part, where the thickness is.
            EmptyView()
        case .thickness:
            // The ONE width of the line round a shape. It reads whichever ring
            // is actually on screen, so a box drawn before the Effects Border
            // slider stopped reaching shapes still shows its width here, and a
            // pull moves that ring onto the stroke where it belongs.
            ShapeSlider(layerIDs: ids, label: "Thickness",
                        reading: selection.outlineWidth,
                        range: AnnotationStyles.strokeWidthRange,
                        format: { DocumentUnit.text($0) },
                        typing: .points,
                        preview: { editorState.previewOutlineWidth(ids: $0, $1) },
                        commit: { editorState.commitOutlineWidth(ids: $0, $1) })
                .panelHelp(Experiments.shared.shapePartsEnabled
                      ? "How thick the line is. Its color is the Color row, in Appearance above"
                      : "How thick the line round the shape is. Its color is Outline, in the Color section above")
        case .caption:
            // ONE arrow only. A single field over three arrows could only give
            // all three the same words, and a caption is what the arrow says,
            // not how it looks.
            if let only = selection.members.first, selection.count == 1 {
                ArrowCaptionField(layerID: only.id)
            }
        case .labelSize:
            ShapeSlider(layerIDs: ids, label: "Label size",
                        reading: selection.number { $0.captionFontSize },
                        range: MeasureContent.labelSizeRangePx,
                        format: { DocumentUnit.text($0) },
                        typing: .points,
                        preview: { editorState.previewCaptionFontSize(ids: $0, $1) },
                        commit: { editorState.commitCaptionFontSize(ids: $0, $1) })
        case .labelCorners:
            ShapeSlider(layerIDs: ids, label: "Label corners",
                        reading: selection.number { $0.captionRoundness },
                        range: AnnotationContent.captionRoundnessRange,
                        format: { roundnessWord($0) },
                        round: { $0 },
                        preview: { editorState.previewCaptionRoundness(ids: $0, $1) },
                        commit: { editorState.commitCaptionRoundness(ids: $0, $1) })
                .panelHelp("How round the label's corners are, from a square box through a badge to a full pill")
        case .headStyle:
            // The one row in this section that is a picture rather than a
            // number, so it carries its own caption instead of a slider's.
            let ending = selection.reading { $0.arrowheadStyle }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Ending").font(.caption).foregroundStyle(.secondary)
                    // A glyph says what the ending IS while you are looking at
                    // the row; the word is what you remember it by afterwards.
                    if ending.isMixed {
                        MixedWord()
                    } else if let word = ArrowheadStylePicker.word(ending.value, isMixed: false) {
                        Text(word).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                ArrowheadStylePicker(selection: ending.value, isMixed: ending.isMixed) {
                    editorState.setArrowheadStyle(ids: ids, $0)
                }
            }
            .playtestField("Ending")
        case .headSize:
            ShapeSlider(layerIDs: ids, label: "Head Size",
                        reading: selection.number { $0.arrowheadScale },
                        range: AnnotationStyles.arrowheadScaleRange,
                        format: { "×\(String(format: "%.1f", $0))" },
                        typing: .times,
                        round: { $0 },
                        preview: { editorState.previewAnnotationRestyle(ids: $0, arrowheadScale: $1) },
                        commit: { editorState.commitAnnotationRestyle(ids: $0, arrowheadScale: $1) })
        }
    }

    /// What the corner row says it is on. The two ends are shapes with names,
    /// because "Square" and "Pill" are what the user is actually after; the
    /// middle is how far it has travelled between them.
    private func roundnessWord(_ value: CGFloat) -> String {
        switch value {
        case ..<0.02: "Square"
        case 0.98...: "Pill"
        default: "\(Int((value * 100).rounded()))%"
        }
    }
}

/// The ONE Corner Radius row, under Effects, speaking for everything picked.
///
/// Rounding means two different things underneath: a rectangle curves the
/// outline it draws, so the curve follows its border, while a screenshot, a
/// frame or a group has its corners masked off. The panel used to carry a
/// slider for each, one in the shape's own section and one here, both labelled
/// Corner Radius, with nothing to say which was which. They also disagreed in
/// the worst way: the mask chopped the corners clean off a rectangle's
/// outline. So there is one row, it reads whichever number is rounding each
/// picked layer, and a pull writes back to whichever one rounds it properly.
///
/// Dragging previews without recording undo; release commits ONE step,
/// however many layers it reached.
struct CornerRadiusRow: View {
    @Environment(EditorState.self) private var editorState
    let selection: CornerRadiusSelection

    /// Where the knob is while the hand is on it, so it moves smoothly even
    /// though what it sends is whole points.
    @State private var draft: Double?

    /// What the row is answering, when it has been asked. A control that can
    /// only act over part of its range says who owns the rest and the one
    /// thing to do about it, in the line under the row, the moment it is
    /// clicked — never in a hover tip alone (UX-PATTERNS §4).
    @State private var answer: String?

    /// How long the answer holds. Long enough to read twice, short enough that
    /// the row goes back to being a row.
    private static let answerSeconds: Double = 6

    private func fadeAnswer() async {
        guard answer != nil else { return }
        try? await Task.sleep(for: .seconds(Self.answerSeconds))
        guard !Task.isCancelled else { return }
        answer = nil
    }

    /// Where the LIVE part of the track runs: from the wall to fully round.
    ///
    /// The whole track still means nought to fully round. What the knob may
    /// reach is only the part above the wall, and the refused stretch under it
    /// is drawn spent rather than cut off the end (`spentTrack`), which is the
    /// difference between a knob resting on 18 and a knob at nothing.
    private var range: ClosedRange<Double> {
        let top = max(1, selection.limit)
        let bottom = min(max(0, selection.floor), top)
        // A frame holding a pill is already as round as its box goes, so its
        // floor and its ceiling meet. A range of no length is not a range, so
        // the row keeps a point of slack; the track it draws is spent end to
        // end and the knob against the wall takes no pointer (`isSpent`).
        return bottom >= top ? (top - 1)...top : bottom...top
    }

    /// How wide the row is, so the wall can be put where the number says it
    /// is. Read off the row itself rather than guessed, because the dock
    /// resizes.
    @State private var rowWidth: CGFloat = 0

    /// A small slider's own metrics, measured off `NSSliderCell`: an 18 by 14
    /// knob whose LEFT EDGE sits at the value's fraction of the leftover
    /// width, on a 4 point bar centred in a 14 point row. Everything drawn here
    /// comes off those two numbers so the wall lands exactly where the knob
    /// stops.
    private static let knobWidth: CGFloat = 18
    private static let barHeight: CGFloat = 4

    /// How much of the row belongs to something else. Nought when nothing is
    /// clamped, which is every shape that rounds its own outline.
    private var spentWidth: CGFloat {
        guard selection.hasWall, rowWidth > Self.knobWidth else { return 0 }
        return CGFloat(selection.wall) * (rowWidth - Self.knobWidth)
    }

    /// The refused stretch of track, drawn spent: the groove one shade down,
    /// no fill in it, and a keyline standing where it stops.
    ///
    /// It is on screen with nothing hovered, which is the whole point of it
    /// (UX-PATTERNS §4, "A control that can only act over part of its range").
    /// The knob's left edge comes to rest exactly on its end, so a row at its
    /// floor reads as a knob against a wall instead of a knob at nothing.
    @ViewBuilder
    private var spentTrack: some View {
        if spentWidth > 0 {
            UnevenRoundedRectangle(topLeadingRadius: Self.barHeight / 2,
                                   bottomLeadingRadius: Self.barHeight / 2)
                // Neutral ink, never the accent: this stretch is range that
                // exists and is not yours, not something you did. Denser than
                // the empty groove beside it in either theme, because
                // `.primary` is the ink of whichever one is on.
                .fill(Color.primary.opacity(0.28))
                .padding(.trailing, 1)
                .frame(width: spentWidth, height: Self.barHeight)
                // The wall itself, standing a little proud of the groove.
                //
                // The mock draws this as a one point keyline and leans on the
                // accent either side of it to carry the difference. This panel
                // cannot: with a grey accent chosen in System Settings the
                // filled stretch is grey too, so spent track and filled track
                // land within a few values of each other and the only thing
                // left saying where the wall is, is the wall. So it is drawn,
                // and drawn taller than the bar, which is also what puts an end
                // stop beside a knob resting against it.
                .overlay(alignment: .trailing) {
                    Capsule().fill(Color.primary.opacity(0.5))
                        .frame(width: 1, height: Self.barHeight + 5)
                }
                .allowsHitTesting(false)
        }
    }

    private var knob: Double {
        min(max(draft ?? selection.reading.value ?? 0, range.lowerBound), range.upperBound)
    }

    /// Mixed only until the drag starts: once it has, they all wear the number
    /// under the knob.
    private var showsMixed: Bool { draft == nil && selection.reading.isMixed }

    /// Whether the four corners are open in their popout.
    ///
    /// They used to fold open UNDERNEATH this row, four more rows of a panel
    /// that does not fit its own contents. Now they come out over the row, in
    /// the shape of a box with a number at each corner, and the row stays one
    /// row whether they are open or shut (`FourSidedPopout`).
    ///
    /// A popout is anchored to the row it came out of, so it shuts when the
    /// selection moves on rather than hanging over a row that is now about
    /// something else.
    @State private var cornersOpen = false

    /// Whether the four corners can be opened at all. This row is shared with
    /// the release that came before Appearance and Effects split, and setting a
    /// corner on its own belongs to the new panel, so only it grows the
    /// chevron. Both releases READ four corners honestly, because a document is
    /// a document: a card drawn with a rounded top opened in either one shows
    /// the four numbers rather than a single one that is not true.
    private var canOpenCorners: Bool { Experiments.shared.shapePartsEnabled }

    /// What the box holds when nobody is typing in it.
    ///
    /// With the corners CLOSED, the four numbers themselves — `16/16/0/0` —
    /// because the box is then the only place on screen a corner set on its
    /// own can be read. Two layers rounded differently have no four numbers in
    /// common either, so that case is the house word. This is exactly what
    /// Padding's single field does, on purpose (`ArrangementInspector.swift`).
    private var showing: NumberBox.Showing {
        if showsMixed { return .standIn(LayerStyleSelection.mixedText) }
        guard selection.hasUnevenCorners else { return .number(String(Int(knob.rounded()))) }
        // Next opens the four in a popout, so the row says the house word every
        // other control in the dock says and the numbers themselves are one
        // press away, and in the tooltip in words (`FourSidedNumber`). The
        // release before it cannot open them at all, so there this row is still
        // the only place a corner set on its own can be read and it holds the
        // four.
        guard !canOpenCorners, let shorthand = selection.shorthand else {
            return .standIn(LayerStyleSelection.mixedText)
        }
        return .standIn(shorthand)
    }

    /// What a PERSON reads on this row, which is the number AND the unit beside
    /// it — "18 px", not the "18" in the box. The one-unit check and every walk
    /// that quotes the row read this.
    private var readout: String {
        switch showing {
        case .number(let digits): DocumentUnit.text(digits: digits)
        case .standIn(let text): text
        case .nothing: ""
        }
    }

    var body: some View {
        let ids = selection.layerIDs
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                heading
                if let only = selection.soleStyleRoundedID {
                    InstanceStyleRevert(layerID: only, field: .cornerRadius)
                }
                Spacer(minLength: 8)
                PanelNumberField(
                    showing: showing,
                    label: "Corner Radius",
                    identity: selection.layerIDs,
                    suffix: DocumentUnit.word,
                    // Grown only for the four numbers written out, which is
                    // the one thing here that is longer than a word.
                    width: .fitting(least: 48, most: 110),
                    // The wall is NOT given to the box as its floor. A number
                    // typed under it has to land on it and say why, and a box
                    // that clamps on its own would swallow that silently
                    // (`CornerRadiusSelection.typed`). Nought is the box's own
                    // bottom, because there is no such thing as a corner
                    // rounded less than square.
                    floor: 0,
                    ceiling: CGFloat(selection.limit),
                    wholeNumbers: true,
                    help: sliderHelp
                ) { number in
                    let took = selection.typed(number)
                    if took.refused { answer = selection.wallSentence }
                    // Landing the number it already wears would be an undo
                    // step that changes nothing you can see, which is what a
                    // down arrow held against the wall would otherwise spend.
                    if took.radius != CGFloat(knob.rounded()) {
                        editorState.commitCornerRadius(ids: ids, took.radius.rounded())
                    }
                    return .number(String(Int(took.radius.rounded())))
                }
                .disabled(ids.isEmpty)
                .panelReadout(readout)
                if canOpenCorners {
                    FourSidedButton(
                        isOpen: $cornersOpen,
                        help: "Round each of the four corners on its own.",
                        control: "Twist", detail: cornersOpen ? "open" : "shut"
                    ) {
                        FourSidedPopout(heading: "Corner Radius", shape: .corners,
                                        numbers: cornerNumbers(ids: ids))
                    }
                }
            }
            Slider(value: Binding(
                get: { knob },
                set: { v in
                    draft = v
                    editorState.previewCornerRadius(ids: ids, CGFloat(v.rounded()))
                }), in: range) { editing in
                if !editing {
                    editorState.commitCornerRadius(ids: ids, CGFloat((draft ?? knob).rounded()))
                    draft = nil
                }
            }
            .controlSize(.small)
            // Named on the LIVE slider rather than on the padded row, so a
            // walk pressing a fraction of the way along presses a fraction of
            // the range it can actually reach. A press at 0.3 of a row whose
            // first three tenths are spent lands on the wall and moves nothing.
            .playtestControl("Slider", detail: "Corner Radius")
            // The live slider starts at the wall, so its own fill measures
            // what YOU added rather than what was already there: a knob
            // resting on the floor shows no fill at all.
            .padding(.leading, spentWidth)
            .disabled(ids.isEmpty)
            // Spent end to end: the knob stops taking the pointer, and the row
            // is NOT dimmed. Dimming says broken or waiting, and this one has
            // simply been spent.
            .allowsHitTesting(!selection.isSpent)
            .overlay(alignment: .leading) { spentTrack }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            .help(sliderHelp)
            // A control that can only act over part of its range answers a
            // click on the row, in the line under it, rather than leaving the
            // reason to a hover tip nobody has asked for.
            if let said = answer {
                Text(said)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    // Named, so a walk can claim the sentence a refused number
                    // raises rather than only photograph it. The Room answer
                    // under Padding carries the same handle. It goes BEFORE
                    // the transition: a name put on the far side of one is
                    // never registered, so the sentence was on screen in a
                    // photograph and missing from every walk that looked.
                    .playtestControl("Wall answer", detail: said)
                    .transition(.opacity)
            }
        }
        .contentShape(.rect)
        // Simultaneous, not `onTapGesture`: the row's own click has to answer
        // WITHOUT taking the click away from the number box sitting in it. A
        // gesture on the whole row that swallows the press is a box you cannot
        // put the keyboard in, which is the whole point of putting one here.
        .simultaneousGesture(TapGesture().onEnded { answer = selection.wallSentence })
        .animation(.easeOut(duration: 0.12), value: answer)
        .playtestField("Corner Radius")
        .task(id: answer) { await fadeAnswer() }
        .onChange(of: selection.layerIDs) { cornersOpen = false; answer = nil }
    }

    /// The row's own word. It opens nothing: the four corners come out of the
    /// small control at the trailing end of the row, beside the number they are
    /// about, rather than folding the panel open under it.
    @ViewBuilder
    private var heading: some View {
        Text("Corner Radius").font(.caption).foregroundStyle(.secondary)
    }

    /// What the track says when you rest on it.
    ///
    /// Over a group it says what it is rounding. A group draws nothing of its
    /// own, so there are no corners on it to curve, and the row reaches through
    /// to the things inside it instead (`PhotonzCore/ContainerRounding.swift`).
    /// The number is theirs, and saying so is the difference between a row you
    /// trust and a row you have to experiment with.
    ///
    /// A card told to cut off what sticks out is the one group with an edge you
    /// can SEE, so the row stays on the card and rounds the curve it crops
    /// with: the photo inside it is left alone.
    ///
    /// A group somebody masked by hand still rounds by masking, and there the
    /// track also says WHY it will not go below where it is: a mask can take a
    /// corner away but never put a curve back, so the number cannot go under
    /// the curve the things inside it already have. Without this the knob
    /// simply refuses to move and leaves you guessing.
    private var sliderHelp: String {
        // The same constant the wall on the track is drawn from and the same
        // one a click on the row puts underneath it, so the three can never
        // drift apart (`CornerRadiusSelection.wallSentence`).
        if let wall = selection.wallSentence { return wall }
        if selection.cropsContents {
            return "This card cuts off what sticks out, so this rounds the edge it cuts with."
        }
        if selection.reachesContents {
            return "A group has no corners of its own, so this rounds what is inside it."
        }
        return selection.hasUnevenCorners
            ? "These corners are set apart. Pulling this gives all four the same."
            : "How round every corner of the picked layers is."
    }

    /// The four corners as the popout takes them: clockwise from the top left,
    /// each reading the whole pick on its own, typed rather than dragged. You
    /// come here to say "the top two, sixteen, the bottom two, nothing", and
    /// four more knobs would be four more things to nudge by accident.
    private func cornerNumbers(ids: [UUID]) -> [FourSidedPopout.Number] {
        CornerRadii.Corner.allCases.map { corner in
            let reading = selection.corner(corner)
            return FourSidedPopout.Number(
                title: corner.title,
                help: "How round the \(corner.spoken) corner is.",
                value: reading.value.map { CGFloat($0) },
                commit: { typed in
                    editorState.commitCornerRadius(ids: ids, corner: corner, typed)
                    // Typing a number under the wall lands ON the wall, and
                    // saying so is how a person learns where the wall is.
                    // Settling in silence is the one thing it must not do.
                    if Double(typed) < selection.floor, let wall = selection.wallSentence {
                        answer = wall
                    }
                })
        }
    }
}

/// One arrow's caption. Its own view because it holds a draft and the keyboard:
/// typing edits the draft, and Return, Escape or clicking away all land or drop
/// it exactly once.
struct ArrowCaptionField: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    /// Whether the field says its own name above itself. In Appearance the row
    /// it hangs under is already called Caption, and a label repeating the
    /// heading two lines above it is a word in the way.
    var showsLabel = true
    @State private var captionDraft: String = ""
    @FocusState private var captionFocused: Bool
    /// True from the moment the field takes focus until its draft has been
    /// committed or dropped, so a field that disappears mid-edit (the arrow was
    /// deselected by a canvas click) still lands what was typed.
    @State private var captionEditing = false

    private var annotation: AnnotationContent? {
        editorState.document?.layer(id: layerID)?.annotation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsLabel {
                Text("Caption").font(.caption).foregroundStyle(.secondary)
            }
            // As many lines as the caption has: a single line field showed a
            // two line label as its first line alone and landed that back on
            // the arrow the moment the field lost focus, quietly throwing the
            // second line away.
            TextField("Add a caption", text: $captionDraft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .focused($captionFocused)
                // The canvas field's keys, so the two fields for one label
                // agree: Return drops a line, Command and Return lands the
                // caption, Esc drops the draft and shows the arrow's caption
                // again. Both closing keys hand the keyboard to the picture.
                // Clearing `captionEditing` first is what stops the focus loss
                // that follows from landing the same words a second time.
                .onKeyPress(phases: .down) { press in
                    let key: ArrowCaptionEntry.Key
                    switch press.key {
                    case .return, KeyEquivalent("\u{3}"):
                        key = .return(command: press.modifiers.contains(.command))
                    case .escape: key = .escape
                    default: return .ignored
                    }
                    switch ArrowCaptionEntry.action(for: key) {
                    case .type: return .ignored
                    case .commit:
                        captionEditing = false
                        editorState.setAnnotationCaption(layerID: layerID, captionDraft)
                    case .cancel:
                        captionDraft = annotation?.caption ?? ""
                        captionEditing = false
                    }
                    KeyboardHandback.toCanvas()
                    return .handled
                }
                // Like every Mac text field, clicking away commits what you
                // typed (one undo step; none if unchanged). Not when the canvas
                // has just opened its own editor on this arrow: that editor
                // owns the draft now.
                .onChange(of: captionFocused) { _, focused in
                    if focused {
                        captionEditing = true
                    } else if captionEditing {
                        captionEditing = false
                        commitInspectorCaption()
                    }
                }
                .onDisappear {
                    if captionEditing {
                        captionEditing = false
                        commitInspectorCaption()
                    }
                }
        }
        // Track the model (initially, after undo, on layer switch); typing
        // edits only the draft until Return commits.
        .onChange(of: annotation?.caption ?? "", initial: true) { _, new in
            captionDraft = new
        }
        // The canvas opening its own editor on this arrow closes the
        // inspector's draft (one draft at a time): the field falls back to the
        // caption the canvas editor starts from. In practice the click that
        // opens the canvas editor takes focus first, so a pending draft has
        // already landed by then (verified on the probe app); this is the
        // fallback.
        .onChange(of: editorState.editingCaptionLayerID) { _, editing in
            if editing == layerID {
                captionEditing = false
                captionDraft = annotation?.caption ?? ""
            }
        }
    }

    /// The field landing its draft (Return or focus loss). Skipped while the
    /// canvas editor is open on the same arrow: the two fields share one draft
    /// and the canvas holds it.
    private func commitInspectorCaption() {
        guard editorState.editingCaptionLayerID != layerID else { return }
        editorState.setAnnotationCaption(layerID: layerID, captionDraft)
    }
}
