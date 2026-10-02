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

    /// Filmed 2026-09-30 on a five minute captioned recording: building the
    /// rest while the frames moved left the slide 8 or 9 pictures in its first
    /// 330ms, 90 to 120ms apart; waiting for it to land gave 23 to 26, never
    /// more than 20ms apart.
    @Test func everythingAfterTheKeyPassWaitsForTheSlideToLand() {
        #expect(EditModeArrival.keyPass.nextWaitsForTheSlide)
        #expect(EditModeArrival.timeline.nextWaitsForTheSlide == false)
        #expect(EditModeArrival.trackRows.nextWaitsForTheSlide == false)
        #expect(EditModeArrival.panelSections.nextWaitsForTheSlide == false)
    }

    // MARK: Built behind View (2026-10-02)

    /// Edit's pieces built behind View: Cmd-2 builds nothing, so everything
    /// comes in with the slide rather than up to 0.7s after it.
    @Test func editBuiltBehindViewSimplySlidesIn() {
        let kept = EditModeArrival.switchingToEdit(hasTime: true, keptBehindView: true, current: .settled)
        #expect(kept.arrival == .settled)
        #expect(kept.startsArriving == false)
    }

    /// Still being built behind View when Cmd-2 came: it carries on where it
    /// was rather than starting again.
    @Test func aBuildBehindViewCarriesOnFromWhereItWas() {
        let partway = EditModeArrival.switchingToEdit(hasTime: true, keptBehindView: true, current: .trackRows)
        #expect(partway.arrival == .trackRows)
        #expect(partway.startsArriving == false)
    }

    /// Cmd-2 before anything was built behind View: the arrival starts at
    /// the key pass, and since the window already stood there (a recording
    /// opens at the start) the switch has to set it going itself.
    @Test func nothingBuiltYetArrivesAPassAtATime() {
        let fresh = EditModeArrival.switchingToEdit(hasTime: true, keptBehindView: false, current: .keyPass)
        #expect(fresh.arrival == .start)
        #expect(fresh.startsArriving)
    }

    /// A picture has no View mode and nothing to arrive.
    @Test func aPictureIsAlwaysSettled() {
        let picture = EditModeArrival.switchingToEdit(hasTime: false, keptBehindView: false, current: .settled)
        #expect(picture.arrival == .settled)
        #expect(picture.startsArriving == false)
    }
}
