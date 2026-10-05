import AppKit
import PhotonzCore
import SwiftUI

/// **The one number box**, everywhere a number is typed into a panel.
///
/// Position & Size, Layout, a knob on a copy, the four sides in their popout,
/// a motion row and the timing strip are all this control. Before it there
/// were three of them, written months apart, and each had learned a different
/// lesson the hard way: one knew that a layer can refuse part of what you
/// typed, one knew what the word Mixed has to look like, and the newest knew
/// neither. The fourth panel that needs a number inherits all of it from here.
///
/// What is decided once, and is now the same wherever you type a number:
///
/// - **The draft lives in the box until it lands**, and it lands on Return, on
///   Tab and on clicking away, because a number typed and then abandoned is
///   the most common way a person loses an edit. Escape puts it back. Return
///   and Escape both hand the keyboard to the picture, so the very next key
///   picks a tool instead of landing in the box (`NumberFieldEntry`).
/// - **The box shows what was TAKEN**, not what was asked for. Panels hand
///   back the number the thing really became, so the next arrow key steps from
///   a number something actually has.
/// - **Mixed is the box's TEXT**, drawn at the one strength every other Mixed
///   in the dock uses (`MixedLook`). A stand-in naming a real state instead —
///   "Spread", or four sides written out — is a value and is drawn like one.
/// - **Taking the keyboard selects the whole number**, the way it does in
///   every design tool: you click W to type a new width, not to append digits
///   to the old one.
/// - **Up and down step by one, Shift by ten**, from the whole number on
///   screen.
/// - **Emptying it** is a property the panel sets once (`clear`), not
///   something each box re-decides.
///
/// The decidable half of all that lives in `NumberBox`, in PhotonzCore, where
/// it is tested. This is the part that has to be a view.
struct PanelNumberField: View {
    /// What the box holds when nobody is typing in it: one number, a word
    /// standing in for several that disagree, or room to type.
    let showing: NumberBox.Showing
    /// The box's own name. It is the placeholder and the accessibility label,
    /// so a walk can put the keyboard in "Gap" the way a person puts the
    /// pointer there.
    let label: String
    /// Which thing the number speaks for. A different thing is a different
    /// number, so the draft starts fresh when this changes rather than
    /// carrying the last one's half-typed text. The FIELD itself stays: taking
    /// a new identity per selection tears down and rebuilds the text fields on
    /// every click, which was once the single biggest cost of selecting a
    /// layer (measured 2026-09-03).
    var identity: AnyHashable?
    /// The letter in front of the box, for a row of numbers that are told
    /// apart by one character.
    var leading: String?
    /// The unit mark after the box, for a number that means nothing without
    /// it.
    var suffix: String?
    /// What the box says while it is EMPTY, which is a different thing from
    /// standing in for values that disagree: a limit nobody has set says None,
    /// and typing a number is what sets it.
    var prompt: String?
    var width = Width.fixed(52)
    /// The smallest number this box may hold, or nil where it may go as low as
    /// it likes: a position may hang off the canvas.
    var floor: CGFloat?
    /// The largest, for the numbers that have a top: a strength that means
    /// nothing past 100.
    var ceiling: CGFloat?
    /// Whether this box counts in whole numbers. Room and gaps do; an angle
    /// and a scale do not.
    var wholeNumbers = false
    var help: String?
    /// Whether the number in this box is one the thing is still TAKING from
    /// somewhere else rather than one it holds itself.
    ///
    /// Only a copy of a component has the second kind, and only on its room: a
    /// side it never typed in goes on following the original, so it is drawn
    /// the quieter strength the word Mixed is drawn at. Every other box in the
    /// dock shows a number its own thing holds, and leaves this alone.
    var isFollowing = false
    /// What a walk calls this box, and where it says it lives. Left out on the
    /// panels that name the whole ROW instead (`playtestField`).
    var playtest: (name: String, detail: String)?
    /// Emptying the box, where emptying it means something. A limit cleared is
    /// no limit; a gap cleared is not a thing, so those boxes leave this out
    /// and go on snapping back to the number they had.
    var clear: (() -> Void)?
    /// An arrow key with no number in the box: every thing the box speaks for
    /// steps from its own value, which is the only thing a step can mean when
    /// they differ. Left out where there is nothing sensible to step, and the
    /// key then does nothing rather than inventing a nought.
    var stepEach: ((Int, Bool) -> Void)?
    /// How this panel spells a number. Whole points unless it says otherwise.
    var spell: (CGFloat) -> String = { String(Int($0.rounded())) }
    /// How the box is drawn: the system's own field, or the mock's stepper.
    var look = Look.field
    /// A short list hanging off the end of the box, for a number that has a
    /// handful of everyday values as well as any other you care to type: the
    /// preset sizes on the Size box, the way Photoshop's size field is a box
    /// and a list in one. Only drawn in the `well` look.
    var presets: Presets?
    /// Lands the number, and hands back what the thing really became.
    ///
    /// A layer can refuse part of what was typed — a text box will not go
    /// below its words, a group has a smallest width of its own — and the box
    /// has to show what was taken or the next arrow key steps from a number
    /// nothing has. It is not always a number either: one width typed across
    /// five layers that each hold it differently comes back as Mixed. Hand
    /// back nil where the thing took exactly what it was given.
    let land: (CGFloat) -> NumberBox.Showing?

    /// The two ways a number box is drawn.
    enum Look: Equatable {
        /// The system's rounded field, with any letter in front of it. Every
        /// number box in the panel until 2026-10-05.
        case field
        /// The mock's stepper (`input.css` `.stepper.sm`): one sunken well
        /// with the box's name inside it, small and faint in front of the
        /// number, and the number flush right. A click anywhere on the well,
        /// the name included, puts the keyboard in the number.
        case well
    }

    /// The list at the end of a `well`: what it is called, what it says it
    /// shows (a walk reads that back), and its rows.
    struct Presets {
        let label: String
        let value: String
        let choices: [VideoKit.Choice]
    }

    /// How wide the box is.
    enum Width: Equatable {
        /// One width, always.
        case fixed(CGFloat)
        /// At least this, and the rest of the row if there is any going.
        case flexible(least: CGFloat)
        /// Grown to hold a stand-in made of NUMBERS — four sides written out —
        /// and left alone for one made of words. Every box in such a panel is
        /// pinned by its trailing edge, so the one holding four numbers grows
        /// leftwards into space that was empty anyway and the column of right
        /// edges stays flush. The width comes off the stand-in and not off
        /// what is being typed, so it is settled before the keyboard arrives
        /// and does not twitch a point per keystroke.
        case fitting(least: CGFloat, most: CGFloat)
    }

    @State private var draft = ""
    /// The text the box itself last put in the draft. A draft still reading
    /// exactly that was never typed in, and letting go of it lands nothing
    /// (`NumberBox.landing`): a drag that takes the keyboard from X part way
    /// in used to land X's old number over the moving shape, and the drag
    /// then cost two undos instead of one.
    @State private var offered: String?
    /// Set while Return or Escape is handing the keyboard over, so the focus
    /// loss that follows does not land the draft a second time. Escape needs
    /// it: without it, letting go would commit the rounded number on screen
    /// over the fraction a drag left behind, and abandoning an edit would cost
    /// an undo step that changes nothing you can see.
    @State private var isFinishing = false
    @FocusState private var isFocused: Bool
    /// Which box this is to `NumberFieldDraft`, so letting go of the keyboard
    /// only ever takes down this box's own draft.
    @State private var token = UUID()

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch look {
        case .field: fieldBody
        case .well: wellBody
        }
    }

    /// The mock's stepper: the name, the number and the preset list in one
    /// well, the same height and corner as the dropdown it sits beside.
    private var wellBody: some View {
        HStack(spacing: 6) {
            Text(leading ?? label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(VideoKit.Palette.faint)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
            box
            if let presets {
                VideoKit.Dropdown(label: presets.label, value: presets.value,
                                  help: presets.label, isBare: true,
                                  choices: presets.choices)
                    .frame(width: 16)
                    .playtestControl("\(presets.label) presets", detail: presets.label)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, presets == nil ? 8 : 2)
        .frame(height: VideoKit.Metrics.controlSmall)
        // Sunk into the panel, as `--well-sh` draws it: a soft shadow along
        // the inside of the top edge.
        .background(RoundedRectangle(cornerRadius: 6).fill(VideoKit.Palette.well.shadow(
            .inner(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.10), radius: 1, y: 1))))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(wellEdge))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        // The name and the room around the number are the box's too: a click
        // on the word Size is a click on the size.
        .onTapGesture { isFocused = true }
        .kitHover(label) { isHovering = $0 }
        .modifier(OptionalPanelHelp(text: help))
        .modifier(OptionalPlaytestControl(playtest: playtest))
    }

    /// The well's edge: the accent while you type in it, a hint of it under
    /// the pointer, the panel's own hairline at rest (`.stepper:focus-within`,
    /// `.stepper:hover`).
    private var wellEdge: AnyShapeStyle {
        if isFocused { return AnyShapeStyle(VideoKit.Palette.accent) }
        if isHovering { return AnyShapeStyle(VideoKit.Palette.accent.opacity(0.45)) }
        return AnyShapeStyle(VideoKit.Palette.line)
    }

    private var fieldBody: some View {
        HStack(spacing: 4) {
            if let leading {
                Text(leading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 11, alignment: .leading)
            }
            box
            if let suffix {
                // A unit is one word and never wraps: in the narrowest dock
                // "px" broke onto two lines beside its box (2026-09-24).
                Text(suffix).font(.caption2).foregroundStyle(.tertiary).fixedSize()
            }
        }
        .modifier(OptionalPanelHelp(text: help))
        .modifier(OptionalPlaytestControl(playtest: playtest))
    }

    private var box: some View {
        TextField(label, text: $draft, prompt: prompt.map { Text($0) })
            .modifier(BoxLook(look: look))
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            // Mixed is a word among numbers, so it reads as the quieter thing
            // it is rather than as a value someone typed.
            .foregroundStyle(MixedLook.style(showing.isMixed || isFollowing,
                                             otherwise: .primary))
            .modifier(BoxWidth(width: width, showing: showing))
            .focused($isFocused)
            .accessibilityLabel(label)
            // Tab, and anything else that moves the keyboard on by itself,
            // still lands the draft; Return goes through the key rule below so
            // it can hand the keyboard back as well.
            .onSubmit { landDraft() }
            .numberFieldKeys(commit: { finish { landDraft() } },
                             revert: { finish { offer(showing.text) } },
                             step: { direction, coarse in step(direction, coarse) })
            .onAppear { offer(showing.text) }
            // Only while nobody is typing. A number that changes underneath a
            // half-typed draft must not wipe it.
            .onChange(of: showing) { if !isFocused { offer(showing.text) } }
            // A different thing being spoken for IS a different number, so the
            // draft starts fresh whether or not the box has the keyboard.
            .onChange(of: identity) { offer(showing.text) }
            // Handed over afresh on every keystroke, so the box that lands it
            // is the one on screen, reading what it reads now.
            .onChange(of: draft) { if isFocused { holdDraft() } }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    isFinishing = false
                    selectEverything()
                    holdDraft()
                    return
                }
                NumberFieldDraft.let(go: token)
                if isFinishing {
                    isFinishing = false
                } else {
                    landDraft()
                }
            }
    }

    /// Finishing with the box: do the thing the key means, then remember that
    /// the focus loss on its way over is this, not a click somewhere else.
    private func finish(_ body: () -> Void) {
        body()
        isFinishing = true
    }

    /// The draft becoming the number the thing really holds. True when
    /// something actually changed.
    @discardableResult
    private func landDraft() -> Bool {
        switch NumberBox.landing(draft: draft, showing: showing, canClear: clear != nil,
                                 floor: floor, ceiling: ceiling, wholeNumbers: wholeNumbers,
                                 offered: offered) {
        case .putBack:
            offer(showing.text)
            return false
        case .clear:
            clear?()
            // Landed: the focus loss still on its way must not clear it twice.
            offered = draft
            return true
        case .land(let value):
            return reach(value)
        }
    }

    /// One press of an arrow key.
    private func step(_ direction: Int, _ coarse: Bool) {
        switch NumberBox.stepping(draft: draft, direction: direction, coarse: coarse,
                                  floor: floor, ceiling: ceiling, wholeNumbers: wholeNumbers,
                                  stepsEach: stepEach != nil) {
        case .nothing:
            break
        case .each(let direction, let coarse):
            stepEach?(direction, coarse)
        case .to(let value):
            reach(value)
        }
    }

    /// A number, reaching the thing the box speaks for — unless it is already
    /// there, in which case the box only puts itself straight and no undo step
    /// is spent on a change nobody can see.
    @discardableResult
    private func reach(_ value: CGFloat) -> Bool {
        guard !NumberBox.alreadyShowing(value, showing: showing) else {
            offer(showing.text)
            return false
        }
        offer(land(value)?.text ?? spell(value))
        return true
    }

    /// Leaves this box's draft where a press on the canvas can land it first
    /// (`NumberFieldDraft`).
    private func holdDraft() {
        NumberFieldDraft.hold(token) { landDraft() }
    }

    /// The box writing its own draft, as opposed to somebody typing it.
    private func offer(_ text: String) {
        draft = text
        offered = text
    }

    /// Taking the keyboard selects the whole number, the way it does in every
    /// design tool. SwiftUI has no way to say this, so it goes through the
    /// field editor that just became first responder. Every window, not just
    /// the key one: an app that is not frontmost has no key window at all,
    /// which is exactly the state a probe run is in.
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
}

/// The draft in whichever number box has the keyboard, for a press on the
/// canvas to land BEFORE it starts a drag.
///
/// A box lets go of the keyboard a moment after the canvas takes it, and by
/// then a drag is already moving the shape: a number typed into X and never
/// sent with Return landed over the moving shape and the drag then wrote over
/// it, costing two undos and losing the number. So the canvas lands the box
/// first, on the press, and the press that landed it does nothing else.
@MainActor
enum NumberFieldDraft {
    private static var held: (token: UUID, land: () -> Bool)?

    static func hold(_ token: UUID, land: @escaping () -> Bool) {
        held = (token, land)
    }

    static func `let`(go token: UUID) {
        if held?.token == token { held = nil }
    }

    /// Lands whatever is being typed, once, and says whether anything
    /// changed. A draft nobody typed in lands nothing (`NumberBox.landing`),
    /// so a press with a box merely open goes on to do what it always did.
    static func landNow() -> Bool {
        guard let draft = held else { return false }
        held = nil
        return draft.land()
    }
}

/// The field itself in each look: the system's rounded border, or bare text
/// in the mock's 11pt with the well around it doing the drawing.
private struct BoxLook: ViewModifier {
    let look: PanelNumberField.Look

    func body(content: Content) -> some View {
        switch look {
        case .field:
            content.textFieldStyle(.roundedBorder).controlSize(.small)
        case .well:
            content.textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
        }
    }
}

/// The width rule, as a modifier so the three shapes stay one `frame` call.
private struct BoxWidth: ViewModifier {
    let width: PanelNumberField.Width
    let showing: NumberBox.Showing

    func body(content: Content) -> some View {
        switch width {
        case .fixed(let points):
            content.frame(width: points)
        case .flexible(let least):
            content.frame(minWidth: least, maxWidth: .infinity)
        case .fitting(let least, let most):
            content.frame(width: fitted(least: least, most: most))
        }
    }

    private func fitted(least: CGFloat, most: CGFloat) -> CGFloat {
        guard showing.standsInForNumbers else { return least }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize,
                                                    weight: .regular)
        let ink = (showing.text as NSString).size(withAttributes: [.font: font]).width
        return min(most, max(least, (ink + 22).rounded(.up)))
    }
}

/// `panelHelp` on the boxes that have a sentence, and nothing at all on the
/// ones that do not, because an empty tooltip is still a tooltip.
private struct OptionalPanelHelp: ViewModifier {
    let text: String?

    @ViewBuilder func body(content: Content) -> some View {
        if let text, !text.isEmpty { content.panelHelp(text) } else { content }
    }
}

private struct OptionalPlaytestControl: ViewModifier {
    let playtest: (name: String, detail: String)?

    @ViewBuilder func body(content: Content) -> some View {
        if let playtest {
            content.playtestControl(playtest.name, detail: playtest.detail)
        } else {
            content
        }
    }
}
