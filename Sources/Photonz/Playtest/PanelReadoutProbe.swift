// The NUMBER a control in the right hand panel is showing, in the words a
// person reads off the screen.
//
// A slider's readout is a SwiftUI `Text`, and a SwiftUI `Text` inside a slider
// row publishes nothing to accessibility: a walk that reads the whole panel
// through the accessibility tree gets the X/Y/W/H boxes (those are real
// `NSTextField`s), the tool bar and the colour wells, and no sign at all that
// Corner Radius is reading 18 of anything. So the panel says its numbers out
// loud, to the probe only, exactly the way `panelHelp` makes `.help()` legible.
//
// This exists so `expectOneUnit` can hold the panel to ONE unit word without a
// walk having to list the rows it knows about. A row added next month wears the
// same modifier as its neighbours and is checked the day it arrives.
//
// Probe builds only; the shipping app carries none of this.
import SwiftUI

#if PHOTONZ_PLAYTEST
import AppKit

/// The invisible marker behind a readout. Like `HelpAnchorView` it is a
/// position and a word: it never draws, never takes a click, and shows nothing.
final class ReadoutAnchorView: NSView {
    var text: String

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct ReadoutAnchor: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> ReadoutAnchorView { ReadoutAnchorView(text: text) }

    func updateNSView(_ view: ReadoutAnchorView, context: Context) { view.text = text }
}

enum PlaytestPanelReadout {
    /// Every number the panel is showing right now, in the order it is drawn.
    /// Hidden ones are left out, so a collapsed section reads as absent rather
    /// than as a row still claiming a value.
    @MainActor static func values(in content: NSView) -> [String] {
        anchors(in: content).map(\.text)
    }

    /// The markers themselves, so a caller that needs to know WHERE a readout
    /// sits — which row it is in — can measure them.
    @MainActor static func anchors(in content: NSView) -> [ReadoutAnchorView] {
        var found: [ReadoutAnchorView] = []
        func walk(_ view: NSView) {
            if !view.isHiddenOrHasHiddenAncestor, let anchor = view as? ReadoutAnchorView {
                found.append(anchor)
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(content)
        return found
    }
}

extension View {
    /// Says out loud, to a scripted walk, the number this control is showing.
    /// Put it on the `Text` that draws the readout and pass the very same
    /// expression, so what the walk reads and what the person reads cannot
    /// drift apart.
    func panelReadout(_ text: String) -> some View {
        background(ReadoutAnchor(text: text))
    }
}

#else

extension View {
    func panelReadout(_ text: String) -> some View { self }
}

#endif
