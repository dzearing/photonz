// Right clicking the picture: working out what the click was over and handing
// back the menu about it, in that order and in one event.
//
// The menu is built HERE, as an ordinary `NSMenu`, rather than hung off the
// canvas as a SwiftUI `.contextMenu`. That was the first attempt and it does
// not work: SwiftUI resolves a context menu's contents when the view around it
// updates, not when the menu pops up, so a menu that has to be aimed at a POINT
// is always about the previous right click. Wired that way, right clicking a
// fresh group and choosing Delete removed one of its children and left the
// group standing (2026-09-16). An `NSMenu` built in `menu(for:)` is about the
// click that asked for it, always.
//
// What it carries is not decided here: the rows come from `LayerCommandList`,
// the same list the layers panel draws, so the two menus cannot drift apart.

import AppKit
import PhotonzCore

extension CanvasNSView {

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let aimed = contextMenuAim(at: event) else { return super.menu(for: event) }
        let rows = canvasMenu(aimed.id, aimed.context, aimed.point)
        guard !rows.isEmpty else { return super.menu(for: event) }
        return NSMenu.rows(rows)
    }

    /// What this right click is over, or nil when the canvas should not answer
    /// at all.
    ///
    /// Nothing is aimed while another gesture owns the canvas: adjusting the
    /// grid, typing into a text layer or naming a screen are each one act
    /// spread over several clicks, and a menu in the middle of one is a menu
    /// nobody asked for. Same for every tool but Select: a tool that draws owns
    /// its own clicks in this app, and pulling a layer out from under a
    /// half-drawn stroke is not what the hand meant.
    private func contextMenuAim(at event: NSEvent) -> (id: UUID?, context: UUID?, point: CGPoint)? {
        guard Experiments.shared.canvasMenuEnabled,
              tool == .select,
              gridAdjust == nil, textSession == nil, canvasNameField == nil,
              let viewport else { return nil }
        let point = viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil))
        var pick = groupAwarePick(at: point, zoom: viewport.zoom)
        // A right click on a title you are not already working inside is
        // about the title as a whole (Animate In, Replay Title, Save as
        // Preset), the way a clip's is; once a part of it is picked, a right
        // click on a part is about that part.
        if let title = pick?.context, title != groupContext,
           document?.layer(id: title)?.group?.titleRecipe != nil {
            pick = (title, document?.parentID(of: title))
        }
        return (pick?.id, pick?.context, point)
    }
}
