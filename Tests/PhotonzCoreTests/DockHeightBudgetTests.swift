import CoreGraphics
import Testing

@testable import PhotonzCore

/// How the dock decides which of its groups gives up room when the panel holds
/// more than the window is tall.
@Suite("Dock height budget")
struct DockHeightBudgetTests {
    /// A group whose body is a form: a fixed set of controls, so nothing in it
    /// may be squeezed.
    private func form(_ key: String, _ height: CGFloat) -> DockHeightBudget.Group {
        DockHeightBudget.Group(key: key, fixed: 32 + height, flexible: 0, floor: 0)
    }

    /// A group whose body is a list, which may be shortened and scroll inside
    /// itself.
    private func list(_ key: String, natural: CGFloat, floor: CGFloat = 100)
        -> DockHeightBudget.Group
    {
        DockHeightBudget.Group(key: key, fixed: 32, flexible: natural, floor: floor)
    }

    @Test("A dock that already fits leaves every list at its natural height")
    func fitsUntouched() {
        let groups = [list("layers", natural: 200), form("effects", 160)]
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: 800)
        #expect(heights["layers"] == 200)
        #expect(DockHeightBudget.overflow(groups, viewport: 800) == 0)
    }

    @Test("A list never grows past its content just because there is room")
    func neverStretches() {
        let heights = DockHeightBudget.flexibleHeights([list("layers", natural: 90)],
                                                       viewport: 2000)
        #expect(heights["layers"] == 90)
    }

    @Test("The list gives up exactly the room the dock is short by")
    func shrinksByTheOverflow() {
        // 32 + 400 body of form, plus a 32pt header and a 300pt list = 764.
        // A 700pt viewport is 64 short, so the list draws 236.
        let groups = [list("layers", natural: 300), form("text", 400)]
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: 700)
        #expect(heights["layers"] == 236)
        #expect(DockHeightBudget.overflow(groups, viewport: 700) == 0)
    }

    @Test("A form is never shortened, however tight the dock is")
    func formsAreNeverSqueezed() {
        let groups = [form("text", 400), form("effects", 400)]
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: 300)
        #expect(heights.isEmpty)
        // 864 of forms against 300: the dock still scrolls, and says so.
        #expect(DockHeightBudget.overflow(groups, viewport: 300) == 564)
    }

    @Test("The taller list gives first, so a short list is left alone")
    func tallestGivesFirst() {
        // 64 of headers + 120 + 400 = 584, against 500: 84 to find. All of it
        // comes out of the tall one, which is still taller than the short one
        // afterwards.
        let groups = [list("layers", natural: 120), list("parts", natural: 400)]
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: 500)
        #expect(heights["layers"] == 120)
        #expect(heights["parts"] == 316)
    }

    @Test("Once the lists are level they give evenly")
    func levelListsGiveEvenly() {
        // 64 of headers + 300 + 300 = 664 against 464: 200 to find, and the two
        // are the same height, so each gives 100.
        let groups = [list("layers", natural: 300), list("parts", natural: 300)]
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: 464)
        #expect(heights["layers"] == 200)
        #expect(heights["parts"] == 200)
    }

    @Test("A list stops at its floor and the dock reports what is still over")
    func floorHolds() {
        // 32 + 500 list against a 200 viewport. The list stops at 100, leaving
        // 32 + 100 = 132 drawn, which fits — but a second form pushes it over.
        let groups = [list("layers", natural: 500, floor: 100), form("text", 200)]
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: 300)
        #expect(heights["layers"] == 100)
        // 32 + 100 + 232 = 364 against 300.
        #expect(DockHeightBudget.overflow(groups, viewport: 300) == 64)
    }

    @Test("Each list keeps its own floor")
    func floorsAreForEachList() {
        // 64 of headers against a 250 viewport leaves 186 for two lists whose
        // floors already come to 230, so both stop dead on their own floor
        // rather than on a shared one.
        let groups = [list("layers", natural: 400, floor: 150),
                      list("parts", natural: 400, floor: 80)]
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: 250)
        #expect(heights["layers"] == 150)
        #expect(heights["parts"] == 80)
        #expect(DockHeightBudget.overflow(groups, viewport: 250) == 44)
    }

    @Test("A list shorter than its own floor is drawn at its content, not padded out")
    func shortListIsNotPaddedToItsFloor() {
        let groups = [list("layers", natural: 40, floor: 100), form("text", 900)]
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: 300)
        #expect(heights["layers"] == 40)
    }

    @Test("A collapsed group costs its header and nothing else")
    func collapsedCostsAHeaderOnly() {
        let collapsed = DockHeightBudget.Group(key: "parts", fixed: 32, flexible: 0, floor: 0)
        let groups = [list("layers", natural: 300), collapsed]
        // 32 + 300 + 32 = 364, which fits in 400 with room to spare.
        #expect(DockHeightBudget.flexibleHeights(groups, viewport: 400)["layers"] == 300)
        #expect(DockHeightBudget.overflow(groups, viewport: 400) == 0)
    }

    @Test("A dock with no room at all still returns each list's floor")
    func noRoomAtAll() {
        let groups = [list("layers", natural: 300, floor: 100)]
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: 0)
        #expect(heights["layers"] == 100)
    }

    @Test("An empty dock asks for nothing")
    func emptyDock() {
        #expect(DockHeightBudget.flexibleHeights([], viewport: 800).isEmpty)
        #expect(DockHeightBudget.overflow([], viewport: 800) == 0)
    }

    @Test("Heights come back as whole points, so a section never lands on a half pixel")
    func wholePoints() {
        let groups = [list("layers", natural: 300), list("parts", natural: 300)]
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: 465)
        for height in heights.values {
            #expect(height == height.rounded())
        }
        // ...and the rounding never spends more room than there is.
        #expect(DockHeightBudget.overflow(groups, viewport: 465) == 0)
    }

    @Test("A viewport that has not been measured yet changes nothing")
    func unmeasuredViewportIsANoOp() {
        // Height zero is the one frame before layout has run. Shrinking every
        // list to its floor for that frame and back again is a flicker, so an
        // unmeasured dock is left exactly as it is.
        let groups = [list("layers", natural: 300)]
        #expect(DockHeightBudget.flexibleHeights(groups, viewport: nil)["layers"] == 300)
        #expect(DockHeightBudget.overflow(groups, viewport: nil) == 0)
    }
}
