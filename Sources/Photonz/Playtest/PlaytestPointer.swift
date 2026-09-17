// What a scripted walk's pointer can make the app notice, and how.
//
// A walk drives the canvas with synthesized mouse events and that works,
// because the canvas is one AppKit view that reads the point out of the event
// it is handed. Hovering is not like that. AppKit works out `mouseEntered` and
// `mouseExited` from where the REAL cursor is, which in a walk is wherever the
// person left it, and SwiftUI's `.onHover` sits at the end of that chain. So a
// walk written to prove a hover worked reported nothing at all: the line at the
// foot of the canvas never knew a pointer had come to rest on its button.
//
// Every way of faking it was tried on 2026-09-17 and none of them worked:
// delivering `mouseEntered` and `mouseMoved` by hand to the SwiftUI hosting
// view's own tracking area, `window.sendEvent`, `NSApp.sendEvent`, a real
// `CGEvent` posted to our own process, and warping the actual cursor onto the
// button with the app activated. `.onHover` stayed silent through all five.
//
// So the walk takes the path the tool flyout already takes for a list that
// AppKit cannot click: it runs the control's OWN closure — the very one a real
// hover runs — and it finds it through a marker the control hangs behind
// itself, so the region and its frame come from the live layout rather than
// from a number typed into a walk. What this proves is everything that happens
// BECAUSE of a hover, at the place a hover really happens. What it cannot prove
// is SwiftUI's own delivery, and the harness doc says so.
import SwiftUI

#if PHOTONZ_PLAYTEST
import AppKit

/// The invisible marker behind one thing that reacts to the pointer resting on
/// it. Like `HintAnchorView` and `PanelTargetView` it is a position and a name
/// and nothing else: it never draws and never takes a click.
@MainActor
final class HoverTargetView: NSView {
    /// The name a walk's log calls this, empty where the control never needed
    /// one. Not how a walk finds it: a walk points, the way a hand does.
    var name: String
    /// Exactly the closure the view's own `.onHover` is given, so a walk can
    /// never set a hover state the pointer would not.
    var perform: (Bool) -> Void
    /// Whether this marker currently thinks the pointer is on it, so the
    /// pointer never enters twice or leaves something it was never on.
    var isInside = false

    init(name: String, perform: @escaping (Bool) -> Void) {
        self.name = name
        self.perform = perform
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Where this sits in its window, for the log and for the pointer's own
    /// containment test. Read fresh every time, so a panel that scrolled a beat
    /// ago is measured where it actually is.
    var frameInWindow: CGRect { convert(bounds, to: nil) }

    var described: String {
        let box = frameInWindow
        let where_ = "\(Int(box.minX)),\(Int(box.minY)) \(Int(box.width))x\(Int(box.height))"
        return name.isEmpty ? where_ : "\"\(name)\" \(where_)"
    }
}

private struct HoverTargetAnchor: NSViewRepresentable {
    let name: String
    let perform: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTargetView {
        HoverTargetView(name: name, perform: perform)
    }

    func updateNSView(_ view: HoverTargetView, context: Context) {
        view.name = name
        view.perform = perform
    }
}
#endif

extension View {
    /// `.onHover`, and in a probe build also a marker a scripted walk can rest
    /// its pointer on.
    ///
    /// Use this and never `.onHover` directly: a bare `.onHover` is invisible
    /// to every walk in the set, so the thing it drives can break and nothing
    /// says so. `PlaytestHoverIsReachableTests` fails the build's tests if one
    /// creeps back in.
    ///
    /// `name` is only for a walk's log line. A walk finds this by pointing at
    /// it, the way a hand does, so the name can be left out where there is
    /// nothing useful to call it.
    func playtestHover(_ name: String = "", perform: @escaping (Bool) -> Void) -> some View {
        #if PHOTONZ_PLAYTEST
        return onHover(perform: perform)
            .background(HoverTargetAnchor(name: name, perform: perform))
        #else
        return onHover(perform: perform)
        #endif
    }
}

#if PHOTONZ_PLAYTEST
/// Where a walk's pointer is, and what it has told the app about being there.
///
/// One pointer per app, so the state is static: a walk that moves from a button
/// in the editor to a tile in the capture history still leaves the button.
@MainActor
enum PlaytestPointer {
    /// The regions that currently think the pointer is on them.
    private static var inside: [HoverTargetView] = []

    /// Forget where the pointer was without telling anything it left. For the
    /// start of a walk, where the views from the last one are already gone.
    static func forget() {
        for region in inside { region.isInside = false }
        inside = []
    }

    /// The pointer comes to rest at `location`, in `window`'s own coordinates.
    ///
    /// Returns one line for the walk's log naming what it arrived on and what
    /// it left, so a walk that expected a hover and did not get one can see
    /// whether there was anything under the pointer to hover at all.
    @discardableResult
    static func rest(at location: CGPoint, in window: NSWindow) -> String {
        guard let content = window.contentView else { return "pointer: the window has no content view" }
        var over: [HoverTargetView] = []
        collect(in: content, at: location, into: &over)
        for accessory in window.styleMask.contains(.titled)
            ? window.titlebarAccessoryViewControllers.map(\.view) : [] {
            collect(in: accessory, at: location, into: &over)
        }

        // Everything the pointer has walked off. A region whose view has left
        // the window since is dropped in silence: there is nothing left to tell
        // the pointer has gone, and its own state went with it.
        let left = inside.filter { old in !over.contains { $0 === old } }
        for region in left {
            region.isInside = false
            if region.window != nil { region.perform(false) }
        }
        // Then everything it has arrived on. Nested regions BOTH count, which
        // is what a real pointer does too: a hand over a button inside a row
        // hovers the button and the row.
        let arrived = over.filter { !$0.isInside }
        for region in arrived {
            region.isInside = true
            region.perform(true)
        }
        inside = over

        return report(arrived: arrived, left: left, over: over)
    }

    private static func report(arrived: [HoverTargetView],
                               left: [HoverTargetView],
                               over: [HoverTargetView]) -> String {
        func names(_ regions: [HoverTargetView]) -> String {
            regions.map(\.described).joined(separator: ", ")
        }
        var parts: [String] = []
        if !arrived.isEmpty { parts.append("pointer on \(names(arrived))") }
        if !left.isEmpty { parts.append("pointer off \(names(left))") }
        if parts.isEmpty {
            return over.isEmpty
                ? "nothing under the pointer watches for one"
                : "pointer still on \(names(over))"
        }
        return parts.joined(separator: ", ")
    }

    private static func collect(in view: NSView, at location: CGPoint, into found: inout [HoverTargetView]) {
        guard !view.isHidden, view.alphaValue > 0.01 else { return }
        if let region = view as? HoverTargetView,
           !region.bounds.isEmpty,
           region.frameInWindow.contains(location) {
            found.append(region)
        }
        for subview in view.subviews { collect(in: subview, at: location, into: &found) }
    }
}
#endif
