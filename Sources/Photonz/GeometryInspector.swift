import AppKit
import PhotonzCore
import SwiftUI

/// Where the selected layers sit, how big they are and what angle they were
/// turned to, as numbers you can type (Next, `next-geometry-fields`).
///
/// The point of this section is building to a spec: two buttons the same width,
/// a row exactly 296 by 118, a badge at exactly 45. Dragging can get close and
/// never exact, so every number here is typeable, steps by an arrow key the
/// same 1 and 10 the canvas nudges by, and lands as one undo step.
///
/// A is the odd one out in one way only: it is not a number about the box, so
/// it is written to the layer's transform rather than its frame
/// (`LayerGeometrySelection.turning(to:)`). It is the same FIELD as the other
/// four, which is the whole reason it is one of them: Mixed, the read-only
/// look, the click that explains itself and the arrow keys all come with it
/// rather than being invented again for one control. It carries a degree sign
/// because it is the one number in the section that is not a length.
///
/// It speaks for the WHOLE selection. Pick four buttons and type one width and
/// all four take it; type one X and all four line up on that left edge. Where
/// the picked layers already agree the field shows their number, and where they
/// do not it says Mixed rather than showing the last one you clicked, because a
/// number that stands for one layer out of four is how you set three layers to
/// something you never meant to type.
///
/// The fields follow a drag in flight (they read `previewedFrame`), so the
/// numbers move with the layer instead of jumping on mouse-up. Which of the
/// four accept typing is `LayerGeometryEditing`'s call: a field is typeable
/// exactly where the canvas already lets you drag the same thing.
///
/// The other numbers are READOUTS and are drawn as such. A height a paragraph
/// worked out for itself, a position a stack decided, everything about a
/// locked layer: those are `GeometryReadout`, not a field you can type into
/// wearing a slightly greyer number, because a box that looks like an input
/// and refuses the keyboard is the panel telling a lie. Clicking one says why
/// straight away in the line under the fields, rather than leaving the click
/// unanswered until a hover tip catches up.
///
/// The line under the fields has ONE voice and two registers. At rest it is
/// `LayerGeometrySelection.caption`, so what the panel says is decided and
/// tested next to what it does: a locked layer says it is locked there, and a
/// section whose X and Y a stack decided promises the arrow key on W and H
/// only, rather than describing keys that step nothing. When you do something
/// the section has to explain it carries an ANSWER for six seconds — a click on
/// a number you cannot type, or a number the picked layers would not take — and
/// then the caption comes back. One answer at a time, the newest wins, and no
/// toast. The whole rule is in `docs/design/mocks/shared/UX-PATTERNS.md` §4,
/// "The line under a section".
///
/// The section has a second subject: the MARQUEE. While a selection tool has
/// the arrow keys they walk the selection outline rather than the picked
/// layer, and a panel that went on reporting the layer's numbers would be
/// describing something the keyboard is not touching, so it reads the
/// selection box instead and its four numbers place the marquee exactly.
/// `EditorState.regionGeometry` decides which subject, using `Nudge.target` —
/// the same rule the keys use, so the two can never disagree. The header says
/// "Selection" and the caption says the selection box, not the layer under it,
/// because a section that swaps subject silently is a section telling a lie.
struct GeometryInspector: View {
    @Environment(EditorState.self) private var editorState

    /// What the line under the fields is answering, when it is answering
    /// something rather than saying what the section says at rest.
    ///
    /// One answer at a time and the newest wins, because there is one line and
    /// a queue of sentences under a panel is not a thing anybody reads. The
    /// whole rule for this line is written down in
    /// `docs/design/mocks/shared/UX-PATTERNS.md` §4, "The line under a section".
    ///
    /// What is kept is WHAT YOU DID, never the sentence, so the words are
    /// worked out afresh every time the panel draws. Setting a piece's Stretch
    /// back hands it its width again, and a sentence held in a box would go on
    /// explaining a rule that had just been taken off, for the rest of its six
    /// seconds.
    private enum Answer: Hashable {
        /// A click on a number that takes no typing. A click on one of these
        /// used to do nothing at all: the reason was in a hover tip, which
        /// arrives a second later and only if you keep still, so the first
        /// thing a person learned was that the panel ignored them.
        case explaining(LayerGeometryField)
        /// A number that was typed and the picked layers would not take: the
        /// field, what was asked for, and what they came back reading. A value
        /// springing back with nothing said reads as a control that is broken
        /// rather than a selection that refused.
        case refused(LayerGeometryField, CGFloat, LayerGeometryReading)
    }

    @State private var answer: Answer?

    /// How long an answer holds before the caption comes back. Long enough to
    /// read a sentence twice, short enough that the panel goes back to saying
    /// what it says at rest.
    private static let answerSeconds: Double = 6

    private var selection: LayerGeometrySelection { editorState.geometrySelection }

    var body: some View {
        // While a selection tool has the arrow keys the marquee owns this
        // section, because a panel reporting a layer's numbers while the keys
        // walk the marquee is describing something the keyboard is not
        // touching. `EditorState.regionGeometry` decides, by the same rule the
        // keys use.
        if let region = editorState.regionGeometry {
            regionBody(region)
        } else {
            layerBody()
        }
    }

    /// The marquee's own four numbers. No Mixed and nothing read-only: there
    /// is exactly one selection and all four of its numbers take typing.
    private func regionBody(_ region: RegionGeometry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                regionField(.x, region)
                regionField(.y, region)
            }
            HStack(spacing: 8) {
                regionField(.width, region)
                regionField(.height, region)
            }
            Text(region.caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }

    private func regionField(_ field: LayerGeometryField,
                             _ region: RegionGeometry) -> some View {
        GeometryNumberField(
            field: field,
            // One selection, so there is no set of ids for the draft to start
            // fresh on: a new box changes `reading`, and that resets it.
            selectionKey: [],
            reading: region.reading(field),
            help: RegionGeometry.help(field),
            // The outline first, then the outline READ AGAIN, the same way the
            // layer fields do it: what the box shows is what the selection
            // became, not what was asked for.
            set: { value in
                editorState.setRegionGeometry(field: field, to: value)
                return editorState.regionGeometry?.reading(field) ?? region.reading(field)
            },
            stepAll: { direction, coarse in
                editorState.stepRegionGeometry(field: field, direction: direction, coarse: coarse)
            })
    }

    private func layerBody() -> some View {
        let selection = selection
        // Nil as soon as the rule it was about is gone, so the panel never
        // holds a sentence about something that is no longer there.
        let said = answer.flatMap { sentence(for: $0, in: selection) }
        return VStack(alignment: .leading, spacing: 6) {
            // Two pairs, position over size, each field taking half the panel:
            // the numbers are the point of the section, so they get the room
            // rather than sitting in 58 points with the panel empty beside them.
            HStack(spacing: 8) {
                field(.x, selection)
                field(.y, selection)
            }
            .panelStartProbe(.row, owner: "Position")
            HStack(spacing: 8) {
                field(.width, selection)
                field(.height, selection)
            }
            .panelStartProbe(.row, owner: "Size")
            // The angle, on its own row under the size. It keeps the left
            // column rather than spreading across, so X, W and A line up in
            // one column of numbers and the row does not read as a fifth field
            // twice the width of the four above it. The empty half is the
            // honest shape of a section with an odd number of numbers in it.
            HStack(spacing: 8) {
                field(.rotation, selection)
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
            .panelStartProbe(.row, owner: "Angle")
            Text(said ?? selection.caption)
                .font(.caption2)
                .foregroundStyle(said == nil ? AnyShapeStyle(.tertiary)
                                             : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeOut(duration: 0.12), value: said)
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
        // A new set of layers is a new set of numbers, so the sentence about
        // the old one goes rather than sitting over the new caption.
        .onChange(of: selection.members.map(\.id)) { answer = nil }
        .task(id: answer) { await fadeAnswer() }
    }

    /// The words for what you just did, read off the selection as it stands
    /// right now. Nil means the line goes back to the caption at once.
    private func sentence(for answer: Answer,
                          in selection: LayerGeometrySelection) -> String? {
        switch answer {
        case .explaining(let field):
            return selection.explanation(for: field)
        case .refused(let field, let value, let landed):
            return selection.refusal(asking: value, for: field, landedOn: landed)
        }
    }

    private func fadeAnswer() async {
        guard answer != nil else { return }
        try? await Task.sleep(for: .seconds(Self.answerSeconds))
        guard !Task.isCancelled else { return }
        answer = nil
    }

    /// One of the four. A number you can type is a field; a number worked out
    /// for you is a readout, and the two are different things on screen rather
    /// than the same box in two shades of grey.
    @ViewBuilder
    private func field(_ field: LayerGeometryField,
                       _ selection: LayerGeometrySelection) -> some View {
        if selection.isReadOnly(field) {
            GeometryReadout(
                field: field,
                reading: selection.reading(field),
                help: help(field, selection),
                explain: { answer = .explaining(field) })
        } else {
            GeometryNumberField(
                field: field,
                selectionKey: selection.members.map(\.id),
                reading: selection.reading(field),
                help: help(field, selection),
                // The layers first, then the layers READ AGAIN. Never the
                // other way round: what the field shows is whatever they are
                // in once the change has been made.
                set: { value in
                    editorState.setLayerGeometry(field: field, to: value)
                    let after = editorState.geometrySelection
                    let landed = after.reading(field)
                    // A number they would not take says why, where the eye
                    // already is. Nothing at all when they took it: silence IS
                    // the answer to a number that landed, and the line goes
                    // back to the caption rather than congratulating anybody.
                    answer = after.refusal(asking: value, for: field, landedOn: landed) == nil
                        ? nil : .refused(field, value, landed)
                    return landed
                },
                stepAll: { direction, coarse in
                    editorState.stepLayerGeometry(field: field, direction: direction, coarse: coarse)
                })
        }
    }

    /// The hover tip: why a field takes nothing, or what it is plus how much of
    /// the selection it reaches. A width that quietly skips the arrow in the
    /// selection says so here rather than looking broken.
    private func help(_ field: LayerGeometryField,
                      _ selection: LayerGeometrySelection) -> String {
        if let reason = selection.fixedReason(for: field) { return reason }
        guard let note = selection.note(for: field) else { return field.title }
        return "\(field.title). \(note)"
    }
}

/// One typed geometry number, standing for every selected layer.
///
/// The draft lives in the field until it lands, and it lands on Return, on Tab,
/// and on clicking away, because a number typed and then abandoned is the most
/// common way a person loses an edit. Up and down arrow step it without leaving
/// the field. Text that is not a number snaps back to what the layers really
/// are rather than being guessed at.
///
/// Typing a number is a moment, not a mode: Return and Escape both finish it
/// and hand the keyboard back to the picture, so the very next key picks a tool
/// or nudges the layer instead of landing in the box. `NumberFieldEntry` owns
/// that rule.
private struct GeometryNumberField: View {
    let field: LayerGeometryField
    /// Which layers the number stands for. A different set of layers is a
    /// different set of numbers, so the draft starts fresh when this changes
    /// rather than carrying the last selection's half-typed text. The FIELD
    /// itself stays: the section used to take a new identity per selection,
    /// which tore down and rebuilt four text fields on every click, the single
    /// biggest cost of selecting a layer (measured 2026-09-03). Only the draft
    /// ever had to be reset.
    let selectionKey: [UUID]
    let reading: LayerGeometryReading
    let help: String
    /// Lands the number on every selected layer and hands back what they are
    /// in AFTERWARDS.
    ///
    /// A layer can refuse part of what was typed — a text box will not go
    /// below its words, a flow will not leave its smallest width — and the box
    /// has to show what they took, not what was asked for, or the next arrow
    /// key steps from a number nothing has. Worked out after the change rather
    /// than before it, because the panel does not know every rule a layer will
    /// apply to itself: a group's smallest width is one it had never heard of,
    /// and typing 50 into a stack held at 160 left a 50 in the box with a 160
    /// on the canvas.
    let set: (CGFloat) -> LayerGeometryReading
    /// An arrow key with no number in the box: every layer steps from its own
    /// value, which is the only thing a step can mean when they differ.
    let stepAll: (Int, Bool) -> Void

    @State private var text = ""
    /// Set while Return or Escape is handing the keyboard over, so the focus
    /// loss that follows does not land the draft a second time. Escape needs
    /// it: without it, letting go would commit the rounded number on screen
    /// over the fraction a drag left behind, and abandoning an edit would cost
    /// an undo step that changes nothing you can see.
    @State private var isFinishing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(field.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 11, alignment: .leading)
            TextField(field.label, text: $text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 52, maxWidth: .infinity)
                .focused($isFocused)
                .monospacedDigit()
                // Mixed is a word among numbers, so it reads as the quieter
                // thing it is rather than as a value someone typed. The one
                // strength every control in the dock says it at
                // (`MixedLook.swift`).
                .foregroundStyle(MixedLook.style(reading.isMixed, otherwise: .primary))
                // Tab, and anything else that moves the keyboard on by itself,
                // still lands the draft; Return goes through the key rule
                // below so it can hand the keyboard back as well.
                .onSubmit { land() }
                // Up and down step the number. The canvas nudges the layer on
                // the same keys, but it only sees them when the canvas itself
                // has focus, so a focused field and a focused canvas never both
                // answer one press.
                .numberFieldKeys(
                    commit: { finish { land() } },
                    revert: { finish { text = display() } },
                    step: { direction, coarse in step(direction: direction, coarse: coarse) })
        }
        .panelHelp(help)
        // Named the same way the readout beside it is, so a `panel` step lists
        // all four numbers whether or not this selection lets you type them,
        // and pressing one puts the keyboard in it.
        .playtestControl(field.label, detail: "Position & Size")
        .onAppear { text = display() }
        .onChange(of: reading) { text = display() }
        .onChange(of: selectionKey) { text = display() }
        .onChange(of: isFocused) { _, focused in
            if focused {
                selectEverything()
            } else if isFinishing {
                isFinishing = false
            } else {
                land()
            }
        }
    }

    /// Taking the keyboard selects the whole number, the way it does in every
    /// design tool: you click W to type a new width, not to append digits to
    /// the old one. SwiftUI has no way to say this, so it goes through the
    /// field editor that just became first responder.
    private func selectEverything() {
        DispatchQueue.main.async {
            let windows = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 } + NSApp.windows
            for window in windows {
                if let editor = window.firstResponder as? NSTextView {
                    editor.selectAll(nil)
                    return
                }
            }
        }
    }

    /// Finishing with the field: do the thing the key means, then remember
    /// that the focus loss on its way over is this, not a click somewhere else.
    private func finish(_ body: () -> Void) {
        body()
        isFinishing = true
    }

    /// The field's draft becoming every selected layer's real number.
    private func land() {
        guard let parsed = LayerGeometry.parse(text) else {
            text = display()
            return
        }
        // The layers may clamp what was asked for (a width of 0 is not a
        // layer, a text box stops at its own words, a flow stops at its
        // smallest width); showing what they actually became beats showing
        // what was typed.
        text = display(set(parsed))
    }

    /// An arrow key. A number in the box steps that number and lands it on
    /// everything; an empty box or a Mixed one steps each layer from its own
    /// value, so a spread-out row moves together and stays spread out.
    private func step(direction: Int, coarse: Bool) {
        guard let base = LayerGeometry.parse(text) ?? reading.number else {
            stepAll(direction, coarse)
            return
        }
        let next = LayerGeometry.stepped(base, direction: direction, coarse: coarse)
        // Down arrow at a text box's floor holds at the floor rather than
        // counting on down a box that is not moving.
        text = display(set(next))
    }

    /// What the box shows: the number the layers agree on, or the word that
    /// says they do not.
    private func display() -> String { display(reading) }

    /// Whole points, the same rounding `LayerGeometry.displayValue` does, so
    /// what is on screen is exactly what an arrow key steps from, and the same
    /// spelling the readout beside it uses so the two columns agree.
    private func display(_ reading: LayerGeometryReading) -> String {
        reading.draftText(for: field)
    }
}

/// One geometry number the app worked out for you: read, never typed.
///
/// It sits in the same slot as a field, with the same letter in front of it
/// and its digits landing in the same column, so the four numbers still read
/// as four numbers. What it does not wear is the rounded box, because that box
/// is the panel's promise that the keyboard will land there.
///
/// It is never in the tab order, it never takes focus, and a click on it is
/// answered. The two looks were built side by side and photographed; the user
/// picked the plain one on 2026-09-05, so the box is gone rather than sitting
/// behind a switch.
private struct GeometryReadout: View {
    let field: LayerGeometryField
    let reading: LayerGeometryReading
    let help: String
    let explain: () -> Void

    /// The size a small rounded-border field takes, matched by hand so a row
    /// of readouts is exactly as tall as a row of fields and the panel does
    /// not shuffle when a layer is locked. The trailing inset is the bezel's,
    /// so a readout's last digit sits in the same column as a field's.
    private static let fieldHeight: CGFloat = 21
    private static let bezelInset: CGFloat = 5

    /// The digits, the word for "they differ", or the mark that stands for no
    /// number at all. Never blank: an arrow has no width, and a lone W with a
    /// gap after it reads as a row that failed to draw.
    private var text: String { reading.readoutText(for: field) }

    var body: some View {
        // The slot IS the control: clicking anywhere on it, the letter, the
        // number, or the empty space beside a readout with no number, says why
        // it takes nothing. It is a real button rather than a tap gesture laid
        // over the row because the box underneath swallows the mouse before a
        // gesture ever sees it, which is how the first build of this answered
        // a click on H with the very silence it was meant to fix. Nothing
        // inside takes the mouse, so the button always gets it.
        Button(action: explain) {
            HStack(spacing: 4) {
                Text(field.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 11, alignment: .leading)
                number
                    .frame(minWidth: 52, maxWidth: .infinity)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .panelHelp(help)
        .playtestControl(field.label, detail: "Position & Size")
    }

    private var number: some View {
        Text(text)
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, Self.bezelInset)
            .frame(height: Self.fieldHeight)
    }
}
