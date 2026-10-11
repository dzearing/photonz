import Testing
@testable import PhotonzCore

/// The top of the screen reads the way a Photoshop or Final Cut user expects:
/// the menus for what the document is made of, then View, Window and Help.
@Suite struct MenuBarOrderTests {
    @Test func swiftUIsOrderPutsViewBeforeTheDocumentMenus() {
        // What the probe's menu bar read on 2026-09-29 once Capture had gone.
        let built = ["Photonz", "File", "Edit", "View", "Image", "Layer", "Clip", "Sequence",
                     "Measure", "Window", "Help"]
        #expect(MenuBarOrder.arranged(built)
                == ["Photonz", "File", "Edit", "Image", "Layer", "Clip", "Sequence",
                    "Measure", "View", "Window", "Help"])
    }

    @Test func viewGoesStraightBeforeWindow() {
        let move = MenuBarOrder.viewMove(in: ["Photonz", "File", "Edit", "View", "Image", "Layer",
                                              "Window", "Help"])
        #expect(move == MenuBarOrder.Move(from: 3, to: 5))
    }

    @Test func aBarAlreadyInOrderIsLeftAlone() {
        let good = ["Photonz", "File", "Edit", "Image", "Layer", "View", "Window", "Help"]
        #expect(MenuBarOrder.viewMove(in: good) == nil)
        #expect(MenuBarOrder.arranged(good) == good)
    }

    @Test func withNoWindowMenuViewGoesBeforeHelp() {
        let built = ["Photonz", "File", "Edit", "View", "Image", "Layer", "Help"]
        #expect(MenuBarOrder.arranged(built) == ["Photonz", "File", "Edit", "Image", "Layer", "View", "Help"])
    }

    @Test func aBarWithNoViewMenuIsLeftAlone() {
        let built = ["Photonz", "File", "Edit", "Image", "Window", "Help"]
        #expect(MenuBarOrder.viewMove(in: built) == nil)
    }

    /// A menu SwiftUI adds after launch (Clip and Sequence when a video comes
    /// forward) lands after View again, and one more move puts it right.
    @Test func aMenuAddedLaterIsCaughtByTheNextPass() {
        let afterAVideoOpened = ["Photonz", "File", "Edit", "Image", "Layer", "View", "Clip",
                                 "Sequence", "Window", "Help"]
        #expect(MenuBarOrder.arranged(afterAVideoOpened)
                == ["Photonz", "File", "Edit", "Image", "Layer", "Clip", "Sequence", "View",
                    "Window", "Help"])
    }

    /// The app declares its own View after the document menus, so SwiftUI's
    /// order already reads right and nothing has to be moved: SwiftUI's own,
    /// empty View is the one to put away. Moving View fought SwiftUI, which
    /// put it back on every pass, and the bar flickered while a video played
    /// (2026-10-11).
    @Test func withTheAppsOwnViewSwiftUIsIsTheOneToHide() {
        let built = ["Photonz", "File", "Edit", "View", "Image", "Layer", "Clip", "Sequence",
                     "Measure", "View", "Window", "Help"]
        #expect(MenuBarOrder.builtInViewToHide(in: built) == 3)
        #expect(MenuBarOrder.viewMove(in: built) == nil)
        #expect(MenuBarOrder.arranged(built) == built)
    }

    @Test func aSingleViewIsNeverHidden() {
        #expect(MenuBarOrder.builtInViewToHide(in: ["Photonz", "File", "Edit", "View", "Image",
                                                    "Window", "Help"]) == nil)
        #expect(MenuBarOrder.builtInViewToHide(in: ["Photonz", "File", "Edit", "Image",
                                                    "Window", "Help"]) == nil)
    }

    @Test func theContractsOrderIsTheOneWritten() {
        #expect(MenuBarOrder.documentMenus == ["Image", "Layer", "Clip", "Sequence", "Measure"])
        #expect(MenuBarOrder.clip == "Clip")
        #expect(MenuBarOrder.sequence == "Sequence")
    }
}

@Suite struct ProMenuBarFlagTests {
    @Test func nextHasItOnAndCurrentNeverSeesIt() {
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(FeatureCatalog.proMenuBarFlag))
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == FeatureCatalog.proMenuBarFlag })
    }
}

/// Every shortcut printed in a menu does what it says, so no two rows the
/// menu bar shows may print the same one.
@Suite struct MenuKeyClashTests {
    @Test func twoRowsOnOneChordAreNamedTogether() {
        let rows = [
            MenuKeyClash.Row(path: "Clip ▸ Punch In", chord: "⇧Z"),
            MenuKeyClash.Row(path: "View ▸ Zoom Timeline to Fit", chord: "⇧Z"),
            MenuKeyClash.Row(path: "Edit ▸ Undo", chord: "⌘Z"),
        ]
        #expect(MenuKeyClash.clashes(in: rows)
                == [MenuKeyClash(chord: "⇧Z", paths: ["Clip ▸ Punch In", "View ▸ Zoom Timeline to Fit"])])
    }

    @Test func distinctChordsHaveNoClash() {
        let rows = [
            MenuKeyClash.Row(path: "Layer ▸ Ungroup", chord: "⇧⌘G"),
            MenuKeyClash.Row(path: "Layer ▸ Group", chord: "⌘G"),
        ]
        #expect(MenuKeyClash.clashes(in: rows).isEmpty)
    }

    @Test func clashesReadInTheOrderTheBarDoes() {
        let rows = [
            MenuKeyClash.Row(path: "A ▸ One", chord: "⌘1"),
            MenuKeyClash.Row(path: "B ▸ Two", chord: "⌘2"),
            MenuKeyClash.Row(path: "C ▸ Two", chord: "⌘2"),
            MenuKeyClash.Row(path: "D ▸ One", chord: "⌘1"),
        ]
        #expect(MenuKeyClash.clashes(in: rows).map(\.chord) == ["⌘1", "⌘2"])
        #expect(MenuKeyClash.clashes(in: rows).first?.sentence == "⌘1 is on A ▸ One and D ▸ One")
    }
}
