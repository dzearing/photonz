import AppKit
import PhotonzCore
import SwiftUI

// The button that shows and hides the right hand panel, in the place a Mac
// keeps it: the trailing end of the window's own title bar, level with the
// traffic lights. Finder, Mail and Xcode all put it there, so a hand goes
// there without being told.
//
// It used to move with the thing it controls — inside the panel's header while
// the panel was open, and a glass capsule floating on the canvas while it was
// closed — so the way back was never in the same place twice, and with the
// panel open the button disappeared along with it (reported 2026-09-06).
//
// The editor window is `hiddenTitleBar`: no title text, no bar drawn across
// the top, but the title bar AREA is still there, holding the traffic lights.
// A titlebar ACCESSORY drops a view into that area without asking for a
// toolbar, so the window keeps exactly the look it had and gains one control.
// A toolbar was the other route and was not taken: on macOS 26 it brings its
// own glass background and a separator under it, which is a bar drawn across
// the top of a window that deliberately has none.

/// Puts the panel toggle in the host window's title bar, at the trailing end.
///
/// Put it in a `.background`: it draws nothing itself and takes no space.
///
/// The title bar's view is built ONCE and left alone. It reads `EditorState`
/// directly, and that is observable, so it redraws itself when the panel comes
/// and goes. Handing it a fresh root view on every pass of the editor's body
/// instead is what hung the window: a new root view re-measures the accessory,
/// re-measuring the accessory lays the window out, and laying the window out
/// runs the editor's body again.
struct TitlebarPanelToggleInstaller: NSViewRepresentable {
    /// The state the button reads and writes. Handed over rather than
    /// inherited: the title bar is outside the editor's own view tree, so
    /// nothing flows down into it.
    let editorState: EditorState

    func makeNSView(context: Context) -> InstallerView {
        InstallerView(editorState: editorState)
    }

    func updateNSView(_ view: InstallerView, context: Context) {
        view.install()
    }

    static func dismantleNSView(_ view: InstallerView, coordinator: ()) {
        view.remove()
    }

    /// The invisible view that finds the window and hangs the accessory on it.
    /// Never draws, never takes a click.
    final class InstallerView: NSView {
        private let accessoryView: NSView
        private var accessory: NSTitlebarAccessoryViewController?

        init(editorState: EditorState) {
            let toggle = NSHostingView(
                rootView: TitlebarPanelToggle().environment(editorState))
            // A fixed box, not a self-sizing one. A trailing accessory takes
            // the size of the view it is given, so a view that re-measures
            // itself would shove the title bar around every time the tooltip's
            // tracking view came and went.
            let box = NSView(frame: CGRect(x: 0, y: 0,
                                           width: TitlebarPanelToggle.boxWidth,
                                           height: TitlebarPanelToggle.barHeight))
            toggle.frame = box.bounds
            toggle.autoresizingMask = [.width, .height]
            box.addSubview(toggle)
            accessoryView = box
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            install()
        }

        /// Hangs the accessory on this view's window, once. SwiftUI hands a
        /// representable its window a beat after the view is made, and a
        /// window that already carries this accessory must not be given a
        /// second one, so both cases are checked every pass.
        func install() {
            guard let window, accessory == nil else { return }
            let controller = NSTitlebarAccessoryViewController()
            controller.layoutAttribute = .trailing
            controller.view = accessoryView
            // Zero on purpose: full screen hides the title bar and its
            // accessories with it, the same as every other Mac window without
            // a toolbar. Pinning it open instead would keep a strip of chrome
            // across the top of a full-screen canvas forever, and the keyboard
            // (⌥⌘L) and the View menu are still the way in.
            controller.fullScreenMinHeight = 0
            window.addTitlebarAccessoryViewController(controller)
            accessory = controller
        }

        /// Takes the accessory off the window when the editor goes away, so a
        /// window reused for another document never wears two of them.
        func remove() {
            guard let controller = accessory else { return }
            if let window = controller.view.window,
               let index = window.titlebarAccessoryViewControllers.firstIndex(of: controller) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            accessory = nil
        }
    }
}

/// The panel toggle as it appears in the title bar: one glyph that never
/// moves, showing whether the panel is up and putting it back when it is not.
struct TitlebarPanelToggle: View {
    @Environment(EditorState.self) private var editorState

    /// The control's own square. Sized to the title bar rather than to the
    /// tool bar's 30pt circles: a title bar control is a quiet one.
    static let diameter: CGFloat = 24
    /// How far it floats off the window's trailing edge, so it sits at the
    /// same remove from its edge as the traffic lights do from theirs.
    static let trailingInset: CGFloat = 10
    /// The title bar's own height. The button is centred in it.
    static let barHeight: CGFloat = 28
    /// The whole accessory: the button and the room to its right.
    static let boxWidth: CGFloat = diameter + trailingInset

    var body: some View {
        let shown = editorState.isInspectorShown
        Button {
            editorState.setInspectorVisible(!shown)
        } label: {
            Image(systemName: "sidebar.trailing")
                .font(.system(size: 14, weight: .medium))
        }
        // The same icon language as every other small action button in the
        // app. Open, the glyph rests at full strength, the way a Mac shows a
        // panel toggle that is switched on; closed it drops back to secondary.
        .buttonStyle(IconActionButtonStyle(diameter: Self.diameter,
                                           restingTint: shown ? .primary : .secondary,
                                           keepsLabelFont: true,
                                           squareHitTarget: true))
        .frame(width: Self.diameter, height: Self.barHeight)
        .padding(.trailing, Self.trailingInset)
        // Below, always: the button is at the very top of the window, and a
        // tooltip drawn above it would land off the top of the screen.
        .toolTip(shown ? "Hide Panel" : "Show Panel", key: "⌥⌘L", below: true)
        // Named for a scripted walk. One name in both states, because it is
        // one button in one place now: a walk asks for "Panel" and presses
        // whatever it currently means.
        .playtestControl("Panel", detail: shown ? "the title bar's panel toggle, panel open"
                                                : "the title bar's panel toggle, panel closed")
    }
}
