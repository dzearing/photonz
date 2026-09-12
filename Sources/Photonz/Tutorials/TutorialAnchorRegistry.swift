import AppKit
import PhotonzCore
import SwiftUI

// Where a tutorial step's target actually IS, right now.
//
// A guide names a control (`TutorialAnchor.tool(.measure)`) and the overlay has
// to turn that name into a rectangle on screen, again and again, as the window
// moves, the panel scrolls, and the layout changes under it. That is all this
// file does.
//
// It is deliberately NOT the playtest harness's `playtestControl` registry,
// which is the same idea and looks like exactly the right thing to reuse. That
// one is compiled out of the shipping build (`PHOTONZ_PLAYTEST` is defined for
// the dev and probe variants only), and tutorials ship to people. So this is
// its own thing, compiled in always, and it borrows the one idea that matters:
// a STEADY NAME, taken off the model rather than off the words on the control,
// so rewording a label cannot break a guide.
//
// The marker itself is the same shape as `HintAnchorView`: an invisible view
// that is a position and nothing else. It never draws and never takes a click.

/// The invisible marker behind a control that says which anchor it is.
final class TutorialAnchorView: NSView {
    var anchor: TutorialAnchor {
        didSet {
            guard anchor != oldValue else { return }
            TutorialAnchorRegistry.shared.forget(self, named: oldValue)
            TutorialAnchorRegistry.shared.remember(self)
        }
    }

    init(anchor: TutorialAnchor) {
        self.anchor = anchor
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Where the control is on screen right now, read fresh every time: a panel
    /// that scrolled a frame ago is still pointed at from where it really is.
    ///
    /// It is the VISIBLE part, not the whole control. A section scrolled half
    /// way off the top of the panel gets a ring round the half you can see, and
    /// a section scrolled away entirely stops resolving at all, so the callout
    /// falls back rather than pointing confidently at a rectangle above the
    /// window. Pointing at something nobody can see is worse than admitting the
    /// control is not there.
    var screenFrame: NSRect? {
        guard let window, let content = window.contentView, !bounds.isEmpty else { return nil }
        // Clipped to the window, not to `visibleRect`. A SwiftUI hosted view's
        // `visibleRect` answers for the hosting view around it, not for this
        // marker, and reading it put a ring round the whole panel instead of
        // round the section: it was measured wrong, so it is not used.
        let shown = convert(bounds, to: nil).intersection(content.bounds)
        guard shown.width > 2, shown.height > 2 else { return nil }
        return window.convertToScreen(shown)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            TutorialAnchorRegistry.shared.forget(self, named: anchor)
        } else {
            TutorialAnchorRegistry.shared.remember(self)
        }
    }

    deinit {
        let anchor = anchor
        MainActor.assumeIsolated {
            TutorialAnchorRegistry.shared.forget(self, named: anchor)
        }
    }
}

/// Every named place in the app that is on screen at the moment.
@MainActor
final class TutorialAnchorRegistry {
    static let shared = TutorialAnchorRegistry()

    private struct Marker {
        weak var view: TutorialAnchorView?
    }

    private var markers: [String: [Marker]] = [:]

    // MARK: - Keeping the list

    func remember(_ view: TutorialAnchorView) {
        var list = markers[view.anchor.name] ?? []
        list.removeAll { $0.view == nil || $0.view === view }
        list.append(Marker(view: view))
        markers[view.anchor.name] = list
    }

    func forget(_ view: TutorialAnchorView, named anchor: TutorialAnchor) {
        guard var list = markers[anchor.name] else { return }
        list.removeAll { $0.view == nil || $0.view === view }
        if list.isEmpty { markers[anchor.name] = nil } else { markers[anchor.name] = list }
    }

    // MARK: - Answering

    /// Where `anchor` is on screen inside `window`, or nil when nothing in that
    /// window carries the name. Scoped to one window on purpose: three editor
    /// windows all have a tool bar, and a guide is running in exactly one.
    func screenFrame(of anchor: TutorialAnchor, in window: NSWindow?) -> CGRect? {
        candidates(for: anchor, in: window)
            .compactMap(\.screenFrame)
            .first { !$0.isEmpty }
    }

    /// Whether this anchor is on screen in that window at all. What a guide's
    /// prepare step is checked against, and what a live check walks.
    func resolves(_ anchor: TutorialAnchor, in window: NSWindow?) -> Bool {
        screenFrame(of: anchor, in: window) != nil
    }

    /// Scrolls whatever is holding this anchor until the anchor is on screen.
    ///
    /// AppKit does the work: `scrollToVisible` walks up to the nearest clip
    /// view and moves it the smallest amount that shows the rect. Doing it here
    /// rather than through the panel's own SwiftUI scroller is deliberate, and
    /// it is the second attempt: a request the panel watched for was only acted
    /// on when the panel happened to redraw for some other reason, so a guide
    /// pointed at a section still below the fold. This one takes effect the
    /// moment it is called, and it works for anything in a scroller rather than
    /// only for panel sections.
    ///
    /// Reveal only. It moves a scroller, never the person's work.
    @discardableResult
    func reveal(_ anchor: TutorialAnchor, in window: NSWindow?) -> Bool {
        guard let view = candidates(for: anchor, in: window)
            .first(where: { !$0.bounds.isEmpty }),
            view.enclosingScrollView != nil else { return false }
        view.scrollToVisible(view.bounds)
        return true
    }

    /// Every anchor name currently hanging on something, sorted. For a failure
    /// message that hands the author something to paste.
    var liveNames: [String] {
        markers.filter { $0.value.contains { $0.view?.window != nil } }
            .keys.sorted()
    }

    private func candidates(for anchor: TutorialAnchor, in window: NSWindow?) -> [TutorialAnchorView] {
        let list = (markers[anchor.name] ?? []).compactMap(\.view)
        guard let window else { return list.filter { $0.window != nil } }
        // A control in the window the guide is running in wins; a panel torn
        // off into its own window still counts if nothing in the main one does.
        let inWindow = list.filter { $0.window === window }
        return inWindow.isEmpty ? list.filter { $0.window != nil } : inWindow
    }
}

private struct TutorialAnchorMarker: NSViewRepresentable {
    let anchor: TutorialAnchor

    func makeNSView(context: Context) -> TutorialAnchorView {
        TutorialAnchorView(anchor: anchor)
    }

    func updateNSView(_ view: TutorialAnchorView, context: Context) {
        view.anchor = anchor
    }
}

extension View {
    /// Names this control so a tutorial step can point at it.
    ///
    /// The name is structural: `.tool(tool)` is built from the tool itself,
    /// `.panelSection(id.rawValue)` from the section's id. Never pass a string
    /// taken off the words on the control, or an edit to the copy can break a
    /// guide and nothing will say so.
    ///
    /// Inert: the marker draws nothing, takes no clicks, and changes no layout,
    /// so hanging one on a shared control costs the Current release nothing.
    func tutorialAnchor(_ anchor: TutorialAnchor) -> some View {
        background(TutorialAnchorMarker(anchor: anchor))
    }
}
