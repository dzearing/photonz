import Testing
@testable import PhotonzCore

@Suite struct PanelSectionOrderTests {
    let canonical = ["layers", "arrange", "geometry", "color", "effects", "text", "shadow", "library"]

    // MARK: Splicing in sections a saved order has never seen

    @Test func mergedKeepsASavedOrderAsItIs() {
        let saved = ["arrange", "layers", "geometry", "color", "effects", "text", "shadow", "library"]
        #expect(PanelSectionOrder.merged(saved: saved, canonical: canonical) == saved)
    }

    @Test func mergedSplicesANewSectionIntoItsCanonicalSpot() {
        let saved = ["layers", "arrange", "geometry", "color", "text", "shadow", "library"]
        let merged = PanelSectionOrder.merged(saved: saved, canonical: canonical)
        #expect(merged == ["layers", "arrange", "geometry", "color", "effects", "text", "shadow", "library"])
    }

    @Test func mergedFallsBackToCanonicalWhenNothingIsSaved() {
        #expect(PanelSectionOrder.merged(saved: [], canonical: canonical) == canonical)
    }

    @Test func mergedDropsSectionsThatNoLongerExist() {
        let saved = ["layers", "gone", "arrange", "geometry", "color", "effects", "text", "shadow", "library"]
        let merged = PanelSectionOrder.merged(saved: saved, canonical: canonical)
        #expect(!merged.contains("gone"))
        #expect(merged == canonical)
    }

    @Test func mergedNeverDuplicates() {
        let saved = ["layers", "layers", "arrange"]
        let merged = PanelSectionOrder.merged(saved: saved, canonical: canonical)
        #expect(merged.count == Set(merged).count)
        #expect(Set(merged) == Set(canonical))
    }

    // MARK: Moving one section without disturbing the rest

    @Test func movingPutsTheSectionRightAfterItsAnchor() {
        let saved = ["layers", "arrange", "geometry", "color", "text", "effects", "shadow", "library"]
        let moved = PanelSectionOrder.moving("effects", after: "color", in: saved)
        #expect(moved == ["layers", "arrange", "geometry", "color", "effects", "text", "shadow", "library"])
    }

    @Test func movingLeavesEveryOtherRelativePositionAlone() {
        // Someone dragged Layers to the bottom and Color to the top. Only
        // Effects moves; their two choices survive.
        let saved = ["color", "arrange", "geometry", "text", "shadow", "effects", "library", "layers"]
        let moved = PanelSectionOrder.moving("effects", after: "color", in: saved)
        #expect(moved == ["color", "effects", "arrange", "geometry", "text", "shadow", "library", "layers"])
    }

    @Test func movingIsANoOpWhenItIsAlreadyThere() {
        let saved = ["layers", "color", "effects", "shadow"]
        #expect(PanelSectionOrder.moving("effects", after: "color", in: saved) == saved)
    }

    @Test func movingDoesNothingWhenEitherSideIsMissing() {
        let saved = ["layers", "color", "shadow"]
        #expect(PanelSectionOrder.moving("effects", after: "color", in: saved) == saved)
        #expect(PanelSectionOrder.moving("color", after: "effects", in: saved) == saved)
    }

    @Test func movingPutsTheSectionRightBeforeItsAnchor() {
        let saved = ["layers", "arrange", "geometry", "color", "text", "effects", "shadow", "library"]
        let moved = PanelSectionOrder.moving("effects", before: "color", in: saved)
        #expect(moved == ["layers", "arrange", "geometry", "effects", "color", "text", "shadow", "library"])
    }

    @Test func movingBeforeLeavesEveryOtherRelativePositionAlone() {
        // Someone dragged Layers to the bottom and Color to the top. Only
        // Effects moves; their two choices survive.
        let saved = ["color", "arrange", "geometry", "text", "shadow", "effects", "library", "layers"]
        let moved = PanelSectionOrder.moving("effects", before: "geometry", in: saved)
        #expect(moved == ["color", "arrange", "effects", "geometry", "text", "shadow", "library", "layers"])
    }

    @Test func movingBeforeReachesTheVeryTopOfTheList() {
        let saved = ["layers", "color", "effects", "shadow"]
        #expect(PanelSectionOrder.moving("effects", before: "layers", in: saved)
                == ["effects", "layers", "color", "shadow"])
    }

    @Test func movingBeforeIsANoOpWhenItIsAlreadyThere() {
        let saved = ["layers", "effects", "color", "shadow"]
        #expect(PanelSectionOrder.moving("effects", before: "color", in: saved) == saved)
    }

    @Test func movingBeforeDoesNothingWhenEitherSideIsMissing() {
        let saved = ["layers", "color", "shadow"]
        #expect(PanelSectionOrder.moving("effects", before: "color", in: saved) == saved)
        #expect(PanelSectionOrder.moving("color", before: "effects", in: saved) == saved)
        #expect(PanelSectionOrder.moving("color", before: "color", in: saved) == saved)
    }
}
