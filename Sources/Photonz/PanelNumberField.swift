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
    /// Lands the number, and hands back what the thing really became.
    ///
    /// A layer can refuse part of what was typed — a text box will not go
    /// below its words, a group has a smallest width of its own — and the box
    /// has to show what was taken or the next arrow key steps from a number
    /// nothing has. It is not always a number either: one width typed across
    /// five layers that each hold it differently comes back as Mixed. Hand
    /// back nil where the thing took exactly what it was given.
    let land: (CGFloat) -> NumberBox.Showing?

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
    /// Set while Return or Escape is handing the keyboard over, so the focus
    /// loss that follows does not land the draft a second time. Escape needs
    /// it: without it, letting go would commit the rounded number on screen
    /// over the fraction a drag left behind, and abandoning an edit would cost
    /// an undo step that changes nothing you can see.
    @State private var isFinishing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let leading {
                Text(leading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 11, alignment: .leading)
            }
            box
            if let suffix {
                Text(suffix).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .modifier(OptionalPanelHelp(text: help))
        .modifier(OptionalPlaytestControl(playtest: playtest))
    }

    private var box: some View {
        TextField(label, text: $draft, prompt: prompt.map { Text($0) })
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            // Mixed is a word among numbers, so it reads as the quieter thing
            // it is rather than as a value someone typed.
            .foregroundStyle(MixedLook.style(showing.isMixed, otherwise: .primary))
            .modifier(BoxWidth(width: width, showing: showing))
            .focused($isFocused)
            .accessibilityLabel(label)
            // Tab, and anything else that moves the keyboard on by itself,
            // still lands the draft; Return goes through the key rule below so
            // it can hand the keyboard back as well.
            .onSubmit { landDraft() }
            .numberFieldKeys(commit: { finish { landDraft() } },
                             revert: { finish { draft = showing.text } },
                             step: { direction, coarse in step(direction, coarse) })
            .onAppear { draft = showing.text }
            // Only while nobody is typing. A number that changes underneath a
            // half-typed draft must not wipe it.
            .onChange(of: showing) { if !isFocused { draft = showing.text } }
            // A different thing being spoken for IS a different number, so the
            // draft starts fresh whether or not the box has the keyboard.
            .onChange(of: identity) { draft = showing.text }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    isFinishing = false
                    selectEverything()
                } else if isFinishing {
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

    /// The draft becoming the number the thing really holds.
    private func landDraft() {
        switch NumberBox.landing(draft: draft, showing: showing, canClear: clear != nil,
                                 floor: floor, ceiling: ceiling, wholeNumbers: wholeNumbers) {
        case .putBack:
            draft = showing.text
        case .clear:
            clear?()
        case .land(let value):
            reach(value)
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
    private func reach(_ value: CGFloat) {
        guard !NumberBox.alreadyShowing(value, showing: showing) else {
            draft = showing.text
            return
        }
        draft = land(value)?.text ?? spell(value)
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
