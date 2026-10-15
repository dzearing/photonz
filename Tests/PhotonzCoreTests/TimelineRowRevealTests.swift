import CoreGraphics
import Testing
@testable import PhotonzCore

/// A pick or a key never resizes the timeline: the rows it opens scroll inside
/// it. These pin the one scroll the timeline makes for them, so the rows just
/// opened are on screen: the least that brings them in, and none at all when
/// they already are.
@Suite("Timeline row reveal")
struct TimelineRowRevealTests {

    // 200 of tracks on screen, 500 of them in all.
    let viewport: CGFloat = 200
    let content: CGFloat = 500

    @Test("A row already on screen does not scroll anything")
    func onScreenStays() {
        let row = TimelineRowExtent(top: 40, height: 100)
        #expect(TimelineRowReveal.offset(revealing: row, offset: 0, viewportHeight: viewport,
                                         contentHeight: content) == nil)
    }

    @Test("A row running past the foot scrolls up just enough to show its foot")
    func pastTheFootScrollsTheLeast() {
        let row = TimelineRowExtent(top: 120, height: 130)
        #expect(TimelineRowReveal.offset(revealing: row, offset: 0, viewportHeight: viewport,
                                         contentHeight: content) == 50)
    }

    @Test("A row above the top scrolls down to its top")
    func aboveTheTopScrollsToItsTop() {
        let row = TimelineRowExtent(top: 30, height: 40)
        #expect(TimelineRowReveal.offset(revealing: row, offset: 100, viewportHeight: viewport,
                                         contentHeight: content) == 30)
    }

    @Test("A row taller than the timeline shows its top, never its foot at the cost of its top")
    func tallerThanTheViewKeepsItsTop() {
        let row = TimelineRowExtent(top: 60, height: 300)
        #expect(TimelineRowReveal.offset(revealing: row, offset: 0, viewportHeight: viewport,
                                         contentHeight: content) == 60)
    }

    @Test("The scroll never runs past the end of the tracks")
    func neverPastTheEnd() {
        let row = TimelineRowExtent(top: 380, height: 150)
        #expect(TimelineRowReveal.offset(revealing: row, offset: 0, viewportHeight: viewport,
                                         contentHeight: content) == 300)
    }

    @Test("With no room measured yet, nothing scrolls")
    func noViewportNoScroll() {
        let row = TimelineRowExtent(top: 380, height: 50)
        #expect(TimelineRowReveal.offset(revealing: row, offset: 0, viewportHeight: 0,
                                         contentHeight: content) == nil)
    }
}
