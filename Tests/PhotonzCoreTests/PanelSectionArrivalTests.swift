import PhotonzCore
import Testing

/// When a click changes what the dock has to show, the sections it already has
/// answer at once and brand new ones wait a beat. These tests pin the two
/// halves of that rule and, just as importantly, pin the case where nothing
/// waits: a click that only moves the selection between two things with the
/// same sections must not be slowed down by any of this.
@Suite("PanelSectionArrival")
struct PanelSectionArrivalTests {

    // MARK: Nothing changes

    @Test func showsEverythingWhenTheSectionsAreTheOnesAlreadyMounted() {
        let mounted = ["layers", "geometry", "effects"]
        #expect(PanelSectionArrival.showing(target: mounted, mounted: mounted) == mounted)
        #expect(PanelSectionArrival.isWaiting(target: mounted, mounted: mounted) == false)
    }

    @Test func aSelectionThatKeepsTheSameSectionsNeverWaits() {
        // Clicking from one group to another asks for the same section list.
        // Nothing is new, so nothing is held back and no extra pass is needed.
        let sections = ["layers", "geometry", "placement", "effects", "shadow", "library"]
        #expect(PanelSectionArrival.showing(target: sections, mounted: sections) == sections)
        #expect(PanelSectionArrival.isWaiting(target: sections, mounted: sections) == false)
    }

    // MARK: Arrivals wait

    @Test func holdsBackSectionsThatAreNotMountedYet() {
        // The click that brings the panel back after a deselect.
        let mounted = ["layers", "library"]
        let target = ["layers", "geometry", "placement", "component", "effects", "shadow", "library"]
        #expect(PanelSectionArrival.showing(target: target, mounted: mounted) == ["layers", "library"])
        #expect(PanelSectionArrival.isWaiting(target: target, mounted: mounted))
    }

    @Test func oneNewSectionIsTheOnlyThingHeldBack() {
        let mounted = ["layers", "geometry", "library"]
        let target = ["layers", "geometry", "color", "library"]
        #expect(PanelSectionArrival.showing(target: target, mounted: mounted)
                == ["layers", "geometry", "library"])
    }

    // MARK: Departures do not

    @Test func dropsSectionsTheSelectionNoLongerWantsInTheSamePass() {
        // Deselecting must clear the sections immediately: a Shadow section
        // still standing over nothing is worse than a shorter panel.
        let mounted = ["layers", "geometry", "effects", "shadow", "library"]
        let target = ["layers", "library"]
        #expect(PanelSectionArrival.showing(target: target, mounted: mounted) == target)
        #expect(PanelSectionArrival.isWaiting(target: target, mounted: mounted) == false)
    }

    @Test func sectionsLeavingAndArrivingAtOnceStillLeaveAtOnce() {
        let mounted = ["layers", "annotation", "library"]
        let target = ["layers", "component", "library"]
        #expect(PanelSectionArrival.showing(target: target, mounted: mounted) == ["layers", "library"])
        #expect(PanelSectionArrival.isWaiting(target: target, mounted: mounted))
    }

    // MARK: Order comes from the target

    @Test func keepsTheOrderTheSelectionAsksFor() {
        // Dragging a section to a new place must not be a pass late, so the
        // order is always the live one and only membership trails.
        let mounted = ["layers", "effects", "shadow"]
        let target = ["shadow", "effects", "layers"]
        #expect(PanelSectionArrival.showing(target: target, mounted: mounted) == target)
        #expect(PanelSectionArrival.isWaiting(target: target, mounted: mounted) == false)
    }

    // MARK: First render

    @Test func showsEverythingWhenNothingIsMountedYet() {
        // A window opening has no previous frame to protect, and an empty dock
        // for one pass would be a visible flash of nothing.
        let target = ["layers", "geometry", "library"]
        #expect(PanelSectionArrival.showing(target: target, mounted: []) == target)
        #expect(PanelSectionArrival.isWaiting(target: target, mounted: []) == false)
    }

    @Test func anEmptyTargetShowsNothing() {
        #expect(PanelSectionArrival.showing(target: [], mounted: ["layers"]).isEmpty)
        #expect(PanelSectionArrival.isWaiting(target: [], mounted: ["layers"]) == false)
    }

    // MARK: The waiting always ends

    @Test func theHeldBackSectionsArriveOnTheNextPass() {
        // The catch-up pass mounts exactly what the selection asked for, and
        // then nothing is waiting: the panel can never settle part-built.
        let mounted = ["layers", "library"]
        let target = ["layers", "geometry", "effects", "library"]
        let first = PanelSectionArrival.showing(target: target, mounted: mounted)
        #expect(PanelSectionArrival.isWaiting(target: target, mounted: mounted))
        // Next pass: the dock is allowed everything the selection asked for.
        let second = PanelSectionArrival.showing(target: target, mounted: target)
        #expect(second == target)
        #expect(PanelSectionArrival.isWaiting(target: target, mounted: target) == false)
        #expect(first != second)
    }
}
