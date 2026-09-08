// What a control in the right hand panel would say if you rested on it.
//
// The dock explains itself with SwiftUI's `.help()`, and `.help()` is invisible
// from outside: it sets neither `toolTip` nor `accessibilityHelp` on the views
// underneath, and a synthesized mouse move never raises the help tag. So the
// one sentence a menu says when its box is too narrow for the name it is
// showing — the whole reason the Font menu was pinned to a width on 2026-09-07
// — could be neither photographed nor read back, and the only proof it existed
// was a unit test of the string, which would go on passing with the `.help()`
// deleted.
//
// So the panel says its tooltips out loud, to the probe only. `panelHelp` is
// the ONE expression: it hands the same text to `.help()` and to an invisible
// marker behind the control, so a walk that reads back nothing is being told
// the tooltip is really gone rather than that the probe lost sight of it.
//
// Reading is the question the panel already answers for the alignment rows:
// what would resting HERE say. `PlaytestPanelPress.tip(at:among:)` answers it
// for the app's own designed tooltip, and `PlaytestPanelHelp.tip(at:in:)`
// answers it for both kinds at once, smallest marker winning, so a walk never
// has to know which of the two drew the words.
//
// Probe builds only; the shipping app compiles the plain `.help()` at the
// bottom and carries none of this.
import SwiftUI

#if PHOTONZ_PLAYTEST
import AppKit

/// The invisible marker behind a control that explains itself with `.help()`.
/// Like `HintAnchorView` and `PanelTargetView` it is a position and a word: it
/// never takes a click, never draws, and has no tracking area, because nothing
/// here shows anything. The system's own help tag still does that.
final class HelpAnchorView: NSView {
    var text: String

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct HelpAnchor: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> HelpAnchorView { HelpAnchorView(text: text) }

    func updateNSView(_ view: HelpAnchorView, context: Context) { view.text = text }
}

enum PlaytestPanelHelp {
    /// Every tooltip in the window, of either kind, as a word and the box it
    /// covers.
    @MainActor static func anchors(in content: NSView) -> [(text: String, frame: CGRect)] {
        var found: [(String, CGRect)] = []
        func walk(_ view: NSView) {
            if !view.isHiddenOrHasHiddenAncestor {
                if let hint = view as? HintAnchorView {
                    found.append((hint.label, hint.convert(hint.bounds, to: nil)))
                } else if let help = view as? HelpAnchorView {
                    found.append((help.text, help.convert(help.bounds, to: nil)))
                }
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(content)
        return found
    }

    /// What a pointer resting at this point would say, in words. The SMALLEST
    /// marker covering the point wins, so a menu's own sentence beats one laid
    /// across the whole section it sits in — the same rule the alignment rows
    /// already read their per-picture names by.
    @MainActor static func tip(at point: CGPoint, in content: NSView) -> String? {
        anchors(in: content)
            .filter { $0.frame.contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?
            .text
    }
}

extension View {
    /// Says what this control is, both to the person who rests on it and to a
    /// scripted walk. Use it anywhere in the panel instead of `.help()`, and
    /// pass the very expression the tooltip is built from: one text, two
    /// readers, so they can never disagree.
    func panelHelp(_ text: String) -> some View {
        help(text).background(HelpAnchor(text: text))
    }
}

#else

extension View {
    func panelHelp(_ text: String) -> some View { help(text) }
}

#endif
