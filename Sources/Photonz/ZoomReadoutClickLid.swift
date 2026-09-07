// Telling a double click from a single one on the zoom percentage.
//
// The number in the tool bar has always been a menu button: press it and the
// zoom stops drop down. Double clicking it now means "back to a hundred
// percent", which is what a person reaches for when a picture has wandered off
// its real size.
//
// Those two cannot simply be stacked on the same control. A menu opens on the
// PRESS and then owns every event until it closes, so the second click of a
// double click lands inside the menu rather than on the number, and a double
// click could never arrive. The only way to tell them apart is to let the first
// click sit for a moment: this lid takes the press, waits the double click
// window (`EditorChromeLayout.zoomReadoutDoubleClickWindow`, a quarter of a
// second at most), and then either opens the menu or, if a second click landed
// first, goes to a hundred percent instead.
//
// It is a lid rather than a rewrite of the readout on purpose: the menu
// underneath is still the app's own SwiftUI `Menu`, with its stops, its Fit and
// Actual Size rows and their keys. SwiftUI draws a `Menu` as an AppKit pop up
// button, so opening it is a matter of finding that button and pressing it,
// which is the same fact `PlaytestPanelMenu` is built on.
import AppKit
import PhotonzCore
import SwiftUI

/// A transparent lid over the zoom percentage. Put it in an `.overlay` on the
/// readout, sized to the readout.
struct ZoomReadoutClickLid: NSViewRepresentable {
    /// False while there is no document, when the whole zoom capsule is dimmed
    /// and nothing under the lid would answer a click anyway.
    var isLive: Bool
    /// Take the picture back to a hundred percent.
    var onActualSize: () -> Void

    func makeNSView(context: Context) -> ZoomReadoutLidView {
        let view = ZoomReadoutLidView()
        update(view)
        return view
    }

    func updateNSView(_ view: ZoomReadoutLidView, context: Context) {
        update(view)
    }

    private func update(_ view: ZoomReadoutLidView) {
        view.isLive = isLive
        view.onActualSize = onActualSize
    }
}

final class ZoomReadoutLidView: NSView {
    var onActualSize: () -> Void = {}
    var isLive = true

    /// The menu this click is going to open, unless a second click gets here
    /// first.
    private var pendingOpen: DispatchWorkItem?

    /// The lid takes CLICKS and nothing else. Everything a pointer does short
    /// of pressing — resting on the number so it lights up, waiting for its
    /// tooltip — falls through to the menu button underneath, which is what
    /// draws that highlight and owns that help. A lid that swallowed all of it
    /// would leave a live control looking dead under the pointer.
    ///
    /// With no document the capsule is dimmed and the lid is out of the way
    /// entirely.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isLive else { return nil }
        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return super.hitTest(point)
        default:
            return nil
        }
    }

    /// A click answers straight away even when the window was not the focused
    /// one, which is how a tool bar behaves: you reach for the zoom of the
    /// picture you are looking at, not for the window's focus first. Without
    /// this the first click on an unfocused window is spent activating it, and
    /// the number does nothing at all.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        recordZoomReadoutClick(count: event.clickCount)
        pendingOpen?.cancel()
        pendingOpen = nil
        guard event.clickCount < 2 else {
            recordZoomReadoutDoubleClick()
            onActualSize()
            return
        }
        let open = DispatchWorkItem { [weak self] in self?.openTheStops() }
        pendingOpen = open
        DispatchQueue.main.asyncAfter(
            deadline: .now() + EditorChromeLayout.zoomReadoutDoubleClickWindow(
                systemInterval: NSEvent.doubleClickInterval),
            execute: open)
    }

    /// A click that turned out to be a single one: open the readout's own menu.
    private func openTheStops() {
        recordZoomReadoutWaitEnded()
        pendingOpen = nil
        guard let button = stopsButton() else {
            recordZoomReadoutMenu(found: false, rows: [])
            return
        }
        recordZoomReadoutMenu(found: true, rows: button.menu?.items.map(\.title) ?? [])
        button.performClick(nil)
    }

    /// The pop up button SwiftUI drew for the readout's `Menu`: the one under
    /// this lid. Matched by overlap rather than by identity, since SwiftUI hands
    /// out no handle on the view it made, and the tool bar holds other menus
    /// (the overflow, the grid's cell sizes) that must never be the answer.
    private func stopsButton() -> NSPopUpButton? {
        guard let content = window?.contentView else { return nil }
        let mine = convert(bounds, to: nil)
        var best: (button: NSPopUpButton, overlap: CGFloat)?
        func walk(_ view: NSView) {
            if let button = view as? NSPopUpButton, !button.isHiddenOrHasHiddenAncestor {
                let box = button.convert(button.bounds, to: nil).intersection(mine)
                let overlap = box.isNull ? 0 : box.width * box.height
                if overlap > 0, overlap > (best?.overlap ?? 0) {
                    best = (button, overlap)
                }
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(content)
        return best?.button
    }
}

// MARK: What a walk can read back

#if PHOTONZ_PLAYTEST

/// What the zoom readout has been asked to do, for the scripted playtest.
@MainActor final class ZoomReadoutProbe {
    static let shared = ZoomReadoutProbe()

    /// How many double clicks have gone to a hundred percent.
    var doubleClicks = 0
    /// How many single clicks have opened the stops.
    var menuOpens = 0
    /// Every click the lid has taken, by how many clicks it was.
    var clicks: [Int] = []
    /// How many waits ran out and went looking for the menu.
    var waitsEnded = 0
    /// Whether the last single click found the menu to open at all.
    var foundMenu: Bool?
    /// The rows that menu was carrying, so a walk can prove a single click
    /// still reaches the same stops it always did.
    var menuRows: [String] = []
}

@MainActor func recordZoomReadoutDoubleClick() {
    ZoomReadoutProbe.shared.doubleClicks += 1
}

@MainActor func recordZoomReadoutClick(count: Int) {
    ZoomReadoutProbe.shared.clicks.append(count)
}

@MainActor func recordZoomReadoutWaitEnded() {
    ZoomReadoutProbe.shared.waitsEnded += 1
}

@MainActor func recordZoomReadoutMenu(found: Bool, rows: [String]) {
    ZoomReadoutProbe.shared.foundMenu = found
    ZoomReadoutProbe.shared.menuRows = rows
    if found { ZoomReadoutProbe.shared.menuOpens += 1 }
}

#else

@MainActor func recordZoomReadoutDoubleClick() {}
@MainActor func recordZoomReadoutClick(count: Int) {}
@MainActor func recordZoomReadoutWaitEnded() {}
@MainActor func recordZoomReadoutMenu(found: Bool, rows: [String]) {}

#endif
