import Testing
@testable import PhotonzCore

// A step names the control it is TEACHING. The bar does not always show that
// control: three shapes share one slot, and on a narrow window the last tools
// slide into a More menu. These are the rules for what the ring lands on when
// the named control is not on the bar in its own right, and for the line the
// card adds saying where it went.
@Suite struct TutorialStandInTests {

    // MARK: The order things are tried in

    @Test func aLoneToolIsTriedItselfFirst() {
        let chain = TutorialAnchorStandIns.chain(for: .tool(.measure))
        #expect(chain.first?.anchor == .tool(.measure))
        #expect(chain.first?.concealment == nil)
    }

    @Test func aFamilyMemberFallsBackToItsSlotBeforeTheMoreMenu() {
        let chain = TutorialAnchorStandIns.chain(for: .tool(.ellipse))
        #expect(chain.map(\.anchor) == [.tool(.ellipse), .toolGroup(.shapes), .moreTools])
        #expect(chain[1].concealment == .behindFamilySlot(.shapes))
        #expect(chain[2].concealment == .inMoreMenu)
    }

    @Test func aToolWithNoFamilyFallsStraightToTheMoreMenu() {
        let chain = TutorialAnchorStandIns.chain(for: .tool(.frame))
        #expect(chain.map(\.anchor) == [.tool(.frame), .moreTools])
        #expect(chain[1].concealment == .inMoreMenu)
    }

    @Test func aFamilySlotItselfCanHaveSlidIntoTheMoreMenu() {
        let chain = TutorialAnchorStandIns.chain(for: .toolGroup(.selection))
        #expect(chain.map(\.anchor) == [.toolGroup(.selection), .moreTools])
    }

    @Test func everyMemberOfEveryFamilyKnowsItsSlot() {
        for group in ToolGroup.allCases {
            for tool in group.tools {
                let chain = TutorialAnchorStandIns.chain(for: .tool(tool))
                #expect(chain.contains { $0.concealment == .behindFamilySlot(group) })
            }
        }
    }

    @Test func somethingThatIsNotAToolHasNowhereElseToBe() {
        // A panel section, the canvas, a sheet: none of them hide inside a tool
        // bar slot, so offering one a stand-in would be inventing a place.
        for anchor in [TutorialAnchor.canvas, .panel, .panelSection("layers"),
                       .dialog(.export), .timingStrip] {
            #expect(TutorialAnchorStandIns.chain(for: anchor).map(\.anchor) == [anchor])
        }
    }

    @Test func theMoreButtonIsNeverItsOwnStandIn() {
        #expect(TutorialAnchorStandIns.chain(for: .moreTools).map(\.anchor) == [.moreTools])
    }

    // MARK: What the card says

    @Test func aFamilySlotSaysWhichButtonToPressAndHold() {
        #expect(TutorialConcealment.behindFamilySlot(.shapes).sentence(for: "Ellipse")
            == "The Ellipse is inside the Shapes button. Press and hold the button to reach it.")
    }

    @Test func theMoreMenuSaysToOpenIt() {
        #expect(TutorialConcealment.inMoreMenu.sentence(for: "Frame")
            == "The Frame is in the More menu at the end of the tool bar. Open the menu to reach it.")
    }

    @Test func nothingTellsThePersonTheAppWillDoItForThem() {
        // The guide never opens the list or the menu: a step that says "pick
        // the Ellipse" has to be a thing the person does, or the step is a lie
        // dressed as help. So the sentence always asks THEM to open it.
        for sentence in [TutorialConcealment.behindFamilySlot(.selection).sentence(for: "Magic Wand"),
                         TutorialConcealment.inMoreMenu.sentence(for: "Fill")] {
            #expect(!sentence.contains("opened"))
            #expect(!sentence.contains("for you"))
            #expect(sentence.contains("to reach it"))
        }
    }

    @Test func theCopyReadsLikeTheRestOfTheProduct() {
        for group in ToolGroup.allCases {
            let said = TutorialConcealment.behindFamilySlot(group).sentence(for: "Thing")
            #expect(!said.contains("—"))
            #expect(said.hasSuffix("."))
        }
        #expect(!TutorialConcealment.inMoreMenu.sentence(for: "Thing").contains("—"))
    }

    // MARK: The More button is a place the app promises

    @Test func theMoreButtonIsPromisedAndRingsLikeAToolButton() {
        #expect(TutorialAnchor.all.contains(.moreTools))
        #expect(TutorialAnchor.moreTools.cueShape == .pill)
    }

    // MARK: Taking an anchor apart

    @Test func aToolAnchorNamesItsToolAndAFamilyAnchorItsFamily() {
        #expect(TutorialAnchor.tool(.crop).tool == .crop)
        #expect(TutorialAnchor.tool(.crop).toolGroup == nil)
        #expect(TutorialAnchor.toolGroup(.shapes).toolGroup == .shapes)
        #expect(TutorialAnchor.toolGroup(.shapes).tool == nil)
        #expect(TutorialAnchor.canvas.tool == nil)
        #expect(TutorialAnchor.panelSection("layers").toolGroup == nil)
    }
}
