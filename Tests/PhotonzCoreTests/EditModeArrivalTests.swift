import PhotonzCore
import Testing

/// Edit mode arriving on a recording opened in View builds the editor over a
/// few passes instead of one. These pin the order, and that a window which is
/// not arriving (a recording opened straight into Edit, a picture) shows
/// everything at once.
@Suite("EditModeArrival")
struct EditModeArrivalTests {

    @Test func aWindowThatIsNotArrivingShowsEverything() {
        let settled = EditModeArrival.settled
        #expect(settled.showsTimeline)
        #expect(settled.showsToolBar)
        #expect(settled.showsTrackRows)
        #expect(settled.panelMayFill)
        #expect(settled.next == nil)
    }

    @Test func theKeyPassBuildsOnlyTheFrames() {
        let start = EditModeArrival.start
        #expect(start.showsTimeline == false)
        #expect(start.showsToolBar == false)
        #expect(start.showsTrackRows == false)
        #expect(start.panelMayFill == false)
    }

    @Test func oneHeavyPieceAPassAndThePanelLast() {
        var passes: [EditModeArrival] = [.start]
        while let next = passes.last?.next { passes.append(next) }
        #expect(passes == [.keyPass, .timeline, .trackRows, .panelSections])
        #expect(passes.map(\.showsTimeline) == [false, true, true, true])
        #expect(passes.map(\.showsToolBar) == [false, true, true, true])
        #expect(passes.map(\.showsTrackRows) == [false, false, true, true])
        #expect(passes.map(\.panelMayFill) == [false, false, false, true])
        #expect(passes.last == .settled)
    }
}
