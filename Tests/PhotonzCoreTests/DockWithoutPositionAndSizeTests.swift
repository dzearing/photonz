import CoreGraphics
import Testing
@testable import PhotonzCore

/// What the right hand dock is once the Position & Size boxes are no longer in
/// it, worked out from heights measured off the running app rather than from
/// heights somebody guessed.
///
/// Every number below was read back by a scripted walk on 2026-09-15 at 1200 by
/// 720 (`/tmp/photonz-playtest/dock-picked-first/log.json`, and the three
/// window sizes in `Scripts/playtest/studies/side-pane-load-walk.json`). A
/// piece of text picked in a three layer document asked the dock for 1052
/// points against a 688 point viewport, and 130 of those points were the X, Y,
/// width and height boxes.
///
/// The first answer to that, on the morning of 2026-09-15, was to move those
/// boxes up the order so they were at least on screen. The user's answer that
/// afternoon was better: they are not worth the room at all, because moving
/// something is what the pointer is for and an exact number is wanted rarely.
/// So the section is gone and the same fields open on a command
/// (`ExactPlacement`), and what these tests pin is what the dock got back.
@Suite struct DockWithoutPositionAndSizeTests {
    /// The dock's own padding above its first section (`DockMetrics`).
    let topPadding: CGFloat = 6
    /// What the Position & Size section cost, measured: 33 of header and
    /// hairline over 97 points of fields and caption.
    let positionAndSizeHeight: CGFloat = 130

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
    /// drop shadow it comes with open, in the order the dock used on the
    /// morning of 2026-09-15: what you picked, then where it sits, then what it
    /// looks like.
    ///
    /// Layers: 33 of chrome, 18 of count line and grab bar, a 160 point list
    /// with a 112 point floor. Text 198, Position & Size 130, Appearance 223,
    /// all forms. Effects: 33 of chrome over a 299 point list whose floor is
    /// the open shadow pane, so it cannot give anything back.
    var withTheBoxes: [DockHeightBudget.Group] {
        [list("layers", chrome: 51, body: 160, floor: 112),
         form("text", height: 198),
         form("geometry", height: positionAndSizeHeight),
         form("color", height: 223),
         list("effects", chrome: 33, body: 299, floor: 299)]
    }

    /// The same selection, in the same window, with the boxes taken out and
    /// nothing else changed. This is the whole change under test.
    var withoutTheBoxes: [DockHeightBudget.Group] {
        withTheBoxes.filter { $0.key != "geometry" }
    }

    /// How tall the dock is DRAWN for this selection: the bottom of its last
    /// section, once the budget has said how tall the lists may be.
    func drawnHeight(_ groups: [DockHeightBudget.Group], viewport: CGFloat) -> CGFloat {
        spans(groups, viewport: viewport).last!.bottom
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

    // MARK: The dock is shorter by exactly what the boxes cost

    /// The headline number, before and after, for the same selection in the
    /// same window: 1052 points down to 922. 1052 is the figure the study
    /// measured off the running app, so this is the arithmetic being pinned to
    /// the measurement rather than to itself.
    @Test func theDockIsOneHundredAndThirtyPointsShorter() {
        for viewport in [608.0, 688.0] as [CGFloat] {
            #expect(drawnHeight(withTheBoxes, viewport: viewport) == 1052)
            #expect(drawnHeight(withoutTheBoxes, viewport: viewport) == 922)
        }
    }

    @Test func thereIsNoPositionAndSizeSectionLeftToMeasure() {
        #expect(withoutTheBoxes.contains { $0.key == "geometry" } == false)
    }

    /// The whole point, and the first time it has ever been true: in the
    /// largest window this display allows, the panel fits. It asked for 1052
    /// against 968 before, at every window size, so Effects ran off the bottom
    /// no matter how big the window was made.
    @Test func theWholePanelFitsTheLargestWindowForTheFirstTime() {
        #expect(drawnHeight(withTheBoxes, viewport: 968) > 968)
        #expect(drawnHeight(withoutTheBoxes, viewport: 968) <= 968)
    }

    // MARK: ...and the room goes somewhere useful

    /// In a window with room to spare the freed points go to the layers list
    /// first, because it was the one section being drawn squeezed. So the
    /// visible effect of taking four boxes out is a longer list of layers, not
    /// 130 points of empty panel.
    @Test func theLayersListTakesTheRoomBackInALargeWindow() {
        let before = span("layers", in: withTheBoxes, viewport: 968)
        let after = span("layers", in: withoutTheBoxes, viewport: 968)
        #expect(after.bottom - before.bottom == 40)
    }

    /// In a tight window nothing has room to spare, so every section under the
    /// boxes simply rises by the whole 130.
    @Test func everythingBelowRisesByTheFullHeightInATightWindow() {
        for key in ["color", "effects"] {
            let before = span(key, in: withTheBoxes, viewport: 688)
            let after = span(key, in: withoutTheBoxes, viewport: 688)
            #expect(before.top - after.top == positionAndSizeHeight)
        }
    }

    /// And nothing was bought at the expense of the layers list or the section
    /// named after what you picked: both were already whole and both stayed
    /// exactly where they were.
    @Test func theSectionYouPickedAndTheLayersListAreUntouchedInATightWindow() {
        for viewport in [608.0, 688.0] as [CGFloat] {
            for key in ["layers", "text"] {
                let before = span(key, in: withTheBoxes, viewport: viewport)
                let after = span(key, in: withoutTheBoxes, viewport: viewport)
                #expect(after.top == before.top)
                #expect(after.bottom == before.bottom)
            }
        }
    }

    // MARK: The dock is still over budget, and saying so is the point

    /// 130 points is a real saving and it is not a cure: the same selection
    /// still asks a laptop window for more than it has. The rest of that is
    /// three other tasks (a simpler padding row, hiding panes that are not
    /// relevant, and the Library), and a test that pretended otherwise would
    /// be the loop congratulating itself.
    @Test func aLaptopWindowStillCannotHoldItAll() {
        #expect(drawnHeight(withoutTheBoxes, viewport: 688) > 688)
    }
}
