import CoreGraphics
import Testing
@testable import PhotonzCore

/// Where the right hand dock actually lands Position & Size, worked out from
/// heights measured off the running app rather than from heights somebody
/// guessed.
///
/// Every number below was read back by a scripted walk on 2026-09-15 at 1200 by
/// 720 (`/tmp/photonz-playtest/dock-picked-first/log.json`, and the three
/// window sizes in `Scripts/playtest/studies/side-pane-load-walk.json`). A
/// piece of text picked in a three layer document asked the dock for 1052
/// points against a 688 point viewport, and the X, Y, width and height boxes
/// were the part that fell off the bottom.
///
/// That is a shortfall of a FACTOR, not of a few points: the three forms alone
/// come to 551 and every list is already drawn at its floor. So the fix is not
/// arithmetic, it is which sections sit above the fold, and what these tests
/// pin is the consequence: in the order the dock now uses, Position & Size is
/// wholly inside the viewport at every window size this machine can give.
@Suite struct DockPositionAndSizeFitsTests {
    /// The dock's own padding above its first section (`DockMetrics`).
    let topPadding: CGFloat = 6
    /// A header and the hairline under it, which every section pays for.
    let chrome: CGFloat = 33

    /// A section whose body is a form: paid in full, never squeezed.
    func form(_ key: String, height: CGFloat) -> DockHeightBudget.Group {
        .init(key: key, fixed: height, flexible: 0, floor: 0)
    }

    /// A section whose body is a list: its chrome up front, the rest squeezable
    /// down to `floor`.
    func list(_ key: String, chrome: CGFloat, body: CGFloat,
              floor: CGFloat) -> DockHeightBudget.Group {
        .init(key: key, fixed: chrome, flexible: body, floor: floor)
    }

    /// One piece of text picked in a document of three layers, with the one
    /// drop shadow it comes with open, in the order the dock now uses:
    /// what you picked, then where it sits, then what it looks like.
    ///
    /// Layers: 33 of chrome, 18 of count line and grab bar, a 160 point list
    /// with a 112 point floor. Text 198, Position & Size 130, Appearance 223,
    /// all forms. Effects: 33 of chrome over a 299 point list whose floor is
    /// the open shadow pane, so it cannot give anything back.
    var textPicked: [DockHeightBudget.Group] {
        [list("layers", chrome: 51, body: 160, floor: 112),
         form("text", height: 198),
         form("geometry", height: 130),
         form("color", height: 223),
         list("effects", chrome: 33, body: 299, floor: 299)]
    }

    /// Where each section starts and ends down the dock, once the budget has
    /// said how tall the lists may be drawn.
    func spans(_ groups: [DockHeightBudget.Group],
               viewport: CGFloat) -> [(key: String, top: CGFloat, bottom: CGFloat)] {
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: viewport - 2 * topPadding)
        var top = topPadding
        return groups.map { group in
            let bottom = top + group.fixed + (heights[group.key] ?? group.flexible)
            defer { top = bottom }
            return (group.key, top, bottom)
        }
    }

    func span(_ key: String, in groups: [DockHeightBudget.Group],
              viewport: CGFloat) -> (key: String, top: CGFloat, bottom: CGFloat) {
        spans(groups, viewport: viewport).first { $0.key == key }!
    }

    // MARK: Position & Size is whole, at every size this machine gives

    @Test func positionAndSizeIsWholeInALaptopWindow() {
        // 1200 by 720 leaves the dock 688 points.
        let geometry = span("geometry", in: textPicked, viewport: 688)
        #expect(geometry.top >= 0)
        #expect(geometry.bottom <= 688)
    }

    @Test func positionAndSizeIsWholeInASmallWindow() {
        // 1000 by 640 leaves it 608, which is the tightest this is asked for.
        let geometry = span("geometry", in: textPicked, viewport: 608)
        #expect(geometry.bottom <= 608)
    }

    @Test func positionAndSizeIsWholeInTheLargestWindowThisDisplayAllows() {
        let geometry = span("geometry", in: textPicked, viewport: 968)
        #expect(geometry.bottom <= 968)
    }

    @Test func theSectionYouPickedIsWholeToo() {
        for viewport in [608.0, 688.0, 968.0] as [CGFloat] {
            #expect(span("text", in: textPicked, viewport: viewport).bottom <= viewport)
            #expect(span("layers", in: textPicked, viewport: viewport).bottom <= viewport)
        }
    }

    // MARK: ...and a second effect cannot push it off

    @Test func openingASecondEffectMovesNothingAboveIt() {
        var richer = textPicked
        // A second shadow opened: the Effects list doubles, and its floor with
        // it, because the pane you just opened is drawn whole.
        richer[4] = list("effects", chrome: 33, body: 598, floor: 598)
        for viewport in [608.0, 688.0, 968.0] as [CGFloat] {
            let before = span("geometry", in: textPicked, viewport: viewport)
            let after = span("geometry", in: richer, viewport: viewport)
            #expect(after.top == before.top)
            #expect(after.bottom == before.bottom)
            #expect(after.bottom <= viewport)
            #expect(span("text", in: richer, viewport: viewport).bottom <= viewport)
            #expect(span("color", in: richer, viewport: viewport).top
                == span("color", in: textPicked, viewport: viewport).top)
        }
    }

    // MARK: What the old order did, so the regression cannot come back quietly

    @Test func theOldOrderPutItBelowTheBottomEdgeAtEverySize() {
        // Appearance and Effects above Position & Size, which is where they sat
        // until 2026-09-15.
        let old = [list("layers", chrome: 51, body: 160, floor: 112),
                   form("text", height: 198),
                   form("color", height: 223),
                   list("effects", chrome: 33, body: 299, floor: 299),
                   form("geometry", height: 130)]
        for viewport in [608.0, 688.0, 968.0] as [CGFloat] {
            #expect(span("geometry", in: old, viewport: viewport).bottom > viewport)
        }
    }
}
