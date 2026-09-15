import Testing
@testable import PhotonzCore

/// The whole chain of one-time section moves the right hand dock has had, run
/// as one thing rather than as six `if`s nobody can check.
///
/// The order a section sits in decides what is above the fold on a laptop
/// window, and the dock is over-subscribed by a factor rather than by a few
/// points, so "what is above the fold" is the entire user-visible behaviour.
/// Before this, the chain lived in a SwiftUI view and the only way to find out
/// what order it produced was to run the app and photograph it.
@Suite struct PanelSectionOrderUpgradeTests {
    /// The dock's sections in the order they are declared, cut down to the ones
    /// these tests argue about.
    let canonical = ["layers", "measurements", "arrange", "component", "text",
                     "geometry", "color", "effects", "motion", "shadow", "library"]

    /// The moves the app makes, in the same order and with the same versions.
    private func migrations(next: Bool) -> [PanelSectionOrder.Migration] {
        [
            .init(version: 1, sections: ["effects"], .after, "color"),
            .init(version: 2, sections: ["component"], .before, "geometry"),
            .init(version: 3, sections: ["text"], .before, "geometry"),
            .init(version: 4, sections: ["color", "effects"], .after, "layers", isEnabled: next),
            .init(version: 5, sections: ["text"], .after, "layers", isEnabled: next),
            .init(version: 6, sections: ["arrange", "component", "geometry"], .before, "color",
                  isEnabled: next),
        ]
    }

    // MARK: What the chain produces

    @Test func nextPutsWhereItSitsRightUnderWhatYouPicked() {
        let upgraded = PanelSectionOrder.upgrade(canonical, from: 0,
                                                 through: migrations(next: true))
        #expect(upgraded.order == ["layers", "text", "arrange", "component", "geometry",
                                   "color", "effects", "measurements", "motion", "shadow",
                                   "library"])
        #expect(upgraded.version == 6)
    }

    @Test func positionAndSizeSitsAboveAppearanceAndEffects() {
        let order = PanelSectionOrder.upgrade(canonical, from: 0,
                                              through: migrations(next: true)).order
        let geometry = order.firstIndex(of: "geometry")!
        #expect(geometry < order.firstIndex(of: "color")!)
        #expect(geometry < order.firstIndex(of: "effects")!)
        #expect(geometry < order.firstIndex(of: "motion")!)
        // ...and still under the thing you actually clicked.
        #expect(order.firstIndex(of: "text")! < geometry)
    }

    @Test func arrangeStaysDirectlyAbovePositionAndSize() {
        let order = PanelSectionOrder.upgrade(canonical, from: 0,
                                              through: migrations(next: true)).order
        #expect(order.firstIndex(of: "arrange")! < order.firstIndex(of: "geometry")!)
        #expect(order.firstIndex(of: "component")! < order.firstIndex(of: "geometry")!)
    }

    // MARK: The release that has not had the moves

    @Test func theOtherReleaseIsLeftWhereItWas() {
        let upgraded = PanelSectionOrder.upgrade(canonical, from: 0,
                                                 through: migrations(next: false))
        #expect(upgraded.order == ["layers", "measurements", "arrange", "component", "text",
                                   "geometry", "color", "effects", "motion", "shadow",
                                   "library"])
        // A move that was skipped must not be counted as done, or turning the
        // release on later would step over it.
        #expect(upgraded.version == 3)
    }

    @Test func switchingReleasesLaterStillGetsEveryMoveItMissed() {
        let stopped = PanelSectionOrder.upgrade(canonical, from: 0,
                                                through: migrations(next: false))
        let resumed = PanelSectionOrder.upgrade(stopped.order, from: stopped.version,
                                                through: migrations(next: true))
        let fresh = PanelSectionOrder.upgrade(canonical, from: 0,
                                              through: migrations(next: true))
        #expect(resumed.order == fresh.order)
        #expect(resumed.version == 6)
    }

    // MARK: Running it twice

    @Test func aSecondRunChangesNothing() {
        let once = PanelSectionOrder.upgrade(canonical, from: 0, through: migrations(next: true))
        let twice = PanelSectionOrder.upgrade(once.order, from: once.version,
                                              through: migrations(next: true))
        #expect(twice.order == once.order)
        #expect(twice.version == once.version)
    }

    @Test func anOrderSomebodyArrangedByHandIsLeftAlone() {
        // They dragged Layers to the bottom. Only the sections a move names
        // relocate; their choice about Layers survives.
        let saved = PanelSectionOrder.upgrade(canonical, from: 0,
                                              through: migrations(next: true)).order
        var byHand = saved
        byHand.removeAll { $0 == "layers" }
        byHand.append("layers")
        let again = PanelSectionOrder.upgrade(byHand, from: 6, through: migrations(next: true))
        #expect(again.order == byHand)
    }

    // MARK: Edges

    @Test func aMoveNamingASectionThisDocumentHasNoneOfIsSkipped() {
        let order = ["layers", "color", "effects"]
        let upgraded = PanelSectionOrder.upgrade(order, from: 0, through: migrations(next: true))
        #expect(upgraded.order.first == "layers")
        #expect(Set(upgraded.order) == Set(order))
    }

    @Test func aMoveAlreadyDoneByHandOnlyBumpsTheVersion() {
        let upgraded = PanelSectionOrder.upgrade(["layers", "effects", "color"], from: 0,
                                                 through: [.init(version: 1, sections: ["effects"],
                                                                 .after, "color")])
        #expect(upgraded.order == ["layers", "color", "effects"])
        #expect(upgraded.version == 1)
    }
}
