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

    @Test func aPickThatSharesNoSectionWithTheLastShowsItsFirstAtOnce() {
        // On a video the Layers list is not in the dock (the timeline is the
        // layer list), so picking a cut after a clip swaps EVERY section.
        // Holding them all back left the dock empty, and with nothing mounted
        // nothing counted as waiting, so it stayed empty for good (found
        // 2026-09-24, `transition-picker-at-a-cut-walk`). The top section
        // answers in the click's own pass and the rest follow it.
        let target = ["editPoint", "transition"]
        let mounted = ["speed", "sound", "keys"]
        #expect(PanelSectionArrival.showing(target: target, mounted: mounted) == ["editPoint"])
        #expect(PanelSectionArrival.isWaiting(target: target, mounted: mounted))
    }

    @Test func anEmptyTargetShowsNothing() {
        #expect(PanelSectionArrival.showing(target: [], mounted: ["layers"]).isEmpty)
        #expect(PanelSectionArrival.isWaiting(target: [], mounted: ["layers"]) == false)
    }

    // MARK: The waiting always ends

    @Test func theHeldBackSectionsArriveOnePerPassFromTheTop() {
        // Picking a caption after the canvas asks for six sections the dock
        // has never built. Building all six in one pass held the window for a
        // tenth of a second (2026-09-24, `caption-pick-answers-at-once-walk`);
        // one per pass keeps every pass short, and the top one, the one on
        // screen, comes first.
        let target = ["captions", "text", "properties", "arrange", "time"]
        var mounted = ["canvas", "time", "captions"]
        #expect(PanelSectionArrival.showing(target: target, mounted: mounted) == ["captions", "time"])
        var passes: [[String]] = []
        while PanelSectionArrival.isWaiting(target: target, mounted: mounted) {
            mounted = PanelSectionArrival.next(target: target, mounted: mounted)
            passes.append(PanelSectionArrival.showing(target: target, mounted: mounted))
            #expect(passes.count <= target.count)
            if passes.count > target.count { break }
        }
        #expect(passes == [
            ["captions", "text", "time"],
            ["captions", "text", "properties", "time"],
            ["captions", "text", "properties", "arrange", "time"],
        ])
    }

    @Test func theCatchUpDropsWhatTheSelectionNoLongerWants() {
        let target = ["layers", "geometry", "library"]
        #expect(PanelSectionArrival.next(target: target, mounted: ["layers", "shadow", "library"])
                == ["layers", "geometry", "library"])
    }

    @Test func theCatchUpOfASettledDockIsTheTarget() {
        let target = ["layers", "geometry"]
        #expect(PanelSectionArrival.next(target: target, mounted: target) == target)
        #expect(PanelSectionArrival.next(target: [], mounted: ["layers"]).isEmpty)
    }

    @Test func aSwapOfEverySectionFillsInWithoutEverShowingAnEmptyDock() {
        let target = ["editPoint", "transition", "time"]
        var mounted = ["speed", "sound"]
        var shown = [PanelSectionArrival.showing(target: target, mounted: mounted)]
        while PanelSectionArrival.isWaiting(target: target, mounted: mounted), shown.count <= target.count {
            mounted = PanelSectionArrival.next(target: target, mounted: mounted)
            shown.append(PanelSectionArrival.showing(target: target, mounted: mounted))
        }
        #expect(shown.allSatisfy { !$0.isEmpty })
        #expect(shown.last == target)
        #expect(shown.count == 3)
    }
}
