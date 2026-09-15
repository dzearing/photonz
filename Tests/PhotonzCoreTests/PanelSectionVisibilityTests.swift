import Testing
@testable import PhotonzCore

/// Which of the right hand panel's sections are on screen, and why.
///
/// The rule under test is one sentence: **what you PICK never adds or removes
/// an optional section; only what the document holds, the tool in your hand,
/// and what you asked for may.** Every automatic answer is therefore a fact
/// about the document or the window, never about the selection — which is what
/// stops the panel rearranging itself as you click from layer to layer.
@Suite struct PanelSectionVisibilityTests {

    /// A document with nothing in it yet: no measurements, no motion, no
    /// components, no frames, and the Library never asked for.
    private var emptyHanded: PanelSectionVisibility.Situation {
        PanelSectionVisibility.Situation()
    }

    // MARK: What is optional at all

    @Test func theCoreSectionsAreNeverOptional() {
        for id in ["layers", "color", "effects", "text", "annotation", "canvas", "frame"] {
            #expect(!PanelSectionVisibility.isOptional(id),
                    "\(id) must never be hideable: hiding all of them would leave an empty panel")
        }
    }

    @Test func theQuestionableSectionsAreOptional() {
        for id in ["library", "libraryItem", "measurements", "motion",
                   "placement", "columns", "arrange", "component", "shadow"] {
            #expect(PanelSectionVisibility.isOptional(id))
        }
    }

    /// The panel can never be emptied: the list you may hide and the list the
    /// panel is built from do not overlap on the sections that carry a layer's
    /// own settings.
    @Test func hidingEveryOptionalSectionStillLeavesAPanel() {
        var choices = PanelSectionVisibility.Choices()
        for id in PanelSectionVisibility.optionalSections { choices.set(id, shown: false) }
        let drawn = ["layers", "text", "color", "effects"].filter {
            PanelSectionVisibility.isShown($0, choices: choices, in: emptyHanded)
        }
        #expect(drawn == ["layers", "text", "color", "effects"])
    }

    // MARK: The automatic answers

    @Test func anEmptyDocumentAsksForNoneOfTheJobSections() {
        let choices = PanelSectionVisibility.Choices()
        for id in ["library", "libraryItem", "measurements", "placement",
                   "columns", "component"] {
            #expect(!PanelSectionVisibility.isShown(id, choices: choices, in: emptyHanded),
                    "\(id) has nothing to say about a document that holds none of them")
        }
    }

    @Test func theLibraryArrivesOnlyWhenAskedFor() {
        let choices = PanelSectionVisibility.Choices()
        var asked = emptyHanded
        asked.isLibraryAskedFor = true
        #expect(PanelSectionVisibility.isShown("library", choices: choices, in: asked))
        #expect(PanelSectionVisibility.isShown("libraryItem", choices: choices, in: asked))
    }

    @Test func measurementsArriveWithTheFirstMeasurement() {
        let choices = PanelSectionVisibility.Choices()
        var measuring = emptyHanded
        measuring.documentHasMeasurement = true
        #expect(PanelSectionVisibility.isShown("measurements", choices: choices, in: measuring))
    }

    /// Motion is deliberately NOT gated on the document already moving. The plus
    /// on its own header is how the first motion is made, and the timing strip
    /// only exists once something moves, so a rule that hid the section would
    /// leave nothing in the window that could start an animation at all.
    @Test func motionIsThereForEveryLayerBecauseItIsTheOnlyWayIn() {
        let choices = PanelSectionVisibility.Choices()
        #expect(PanelSectionVisibility.isShown("motion", choices: choices, in: emptyHanded))
    }

    @Test func somebodyWhoNeverAnimatesCanTurnMotionOffForGood() {
        var choices = PanelSectionVisibility.Choices()
        choices.set("motion", shown: false)
        #expect(!PanelSectionVisibility.isShown("motion", choices: choices, in: emptyHanded))
    }

    @Test func layoutArrivesOnceThereIsSomethingToLayOut() {
        let choices = PanelSectionVisibility.Choices()
        var building = emptyHanded
        building.documentHasContainer = true
        #expect(PanelSectionVisibility.isShown("placement", choices: choices, in: building))
    }

    @Test func componentArrivesOnceTheDocumentHoldsOne() {
        let choices = PanelSectionVisibility.Choices()
        var withComponents = emptyHanded
        withComponents.documentHasComponent = true
        #expect(PanelSectionVisibility.isShown("component", choices: choices, in: withComponents))
    }

    /// Arrange and Shadow have no document-level fact to wait for: they answer
    /// for whatever is picked, so automatic simply says yes and the value of
    /// listing them is that they can be turned OFF.
    @Test func theSectionsWithNothingToWaitForAreOnByDefault() {
        let choices = PanelSectionVisibility.Choices()
        #expect(PanelSectionVisibility.isShown("arrange", choices: choices, in: emptyHanded))
        #expect(PanelSectionVisibility.isShown("shadow", choices: choices, in: emptyHanded))
        #expect(PanelSectionVisibility.isShown("motion", choices: choices, in: emptyHanded))
    }

    /// The rule that keeps the panel predictable, stated as a test: nothing in
    /// a Situation is about the selection, so no automatic answer can change
    /// when you click a different layer.
    @Test func noAutomaticAnswerDependsOnWhatIsPicked() {
        let choices = PanelSectionVisibility.Choices()
        var everything = PanelSectionVisibility.Situation()
        everything.documentHasMeasurement = true
        everything.documentHasComponent = true
        everything.documentHasContainer = true
        everything.documentHasColumns = true
        everything.isLibraryAskedFor = true
        let before = PanelSectionVisibility.optionalSections.filter {
            PanelSectionVisibility.isShown($0, choices: choices, in: everything)
        }
        // The same situation asked again is the same answer. A Situation holds
        // no selection at all, so there is nothing a click could change.
        let after = PanelSectionVisibility.optionalSections.filter {
            PanelSectionVisibility.isShown($0, choices: choices, in: everything)
        }
        #expect(before == after)
        #expect(before.count == PanelSectionVisibility.optionalSections.count)
    }

    // MARK: Overriding the automatic answer

    @Test func turningOneOnBeatsTheAutomaticNo() {
        var choices = PanelSectionVisibility.Choices()
        choices.set("measurements", shown: true)
        #expect(PanelSectionVisibility.isShown("measurements", choices: choices, in: emptyHanded))
    }

    @Test func turningOneOffBeatsTheAutomaticYes() {
        var choices = PanelSectionVisibility.Choices()
        choices.set("measurements", shown: false)
        var measuring = emptyHanded
        measuring.documentHasMeasurement = true
        #expect(!PanelSectionVisibility.isShown("measurements", choices: choices, in: measuring))
    }

    /// The picked tile's section is part of the shelf, so turning the shelf off
    /// takes it too rather than leaving a headed section for a shelf that is
    /// not on screen.
    @Test func theLibraryItemSectionFollowsTheShelf() {
        var choices = PanelSectionVisibility.Choices()
        var asked = emptyHanded
        asked.isLibraryAskedFor = true
        choices.set("library", shown: false)
        #expect(!PanelSectionVisibility.isShown("libraryItem", choices: choices, in: asked))
        choices.set("library", shown: true)
        #expect(PanelSectionVisibility.isShown("libraryItem", choices: choices, in: emptyHanded))
    }

    @Test func oneOverrideLeavesTheRestAutomatic() {
        var choices = PanelSectionVisibility.Choices()
        choices.set("library", shown: true)
        #expect(PanelSectionVisibility.isShown("library", choices: choices, in: emptyHanded))
        #expect(!PanelSectionVisibility.isShown("measurements", choices: choices, in: emptyHanded))
    }

    @Test func aSectionThatIsNotOptionalIgnoresAnOverride() {
        var choices = PanelSectionVisibility.Choices()
        choices.set("layers", shown: false)
        #expect(PanelSectionVisibility.isShown("layers", choices: choices, in: emptyHanded),
                "the layers list is not something anybody may lose")
    }

    @Test func handingBackOneSectionLeavesTheOthersAsTheyWere() {
        var choices = PanelSectionVisibility.Choices()
        choices.set("motion", shown: true)
        choices.set("shadow", shown: false)
        choices.useAutomatic(for: "motion")
        #expect(!choices.isCustom("motion"))
        #expect(choices.isCustom("shadow"))
    }

    @Test func handingEverythingBackClearsTheLot() {
        var choices = PanelSectionVisibility.Choices()
        choices.set("measurements", shown: true)
        choices.set("library", shown: false)
        #expect(choices.hasAnyCustom)
        choices.useAutomaticForAll()
        #expect(!choices.hasAnyCustom)
        #expect(!PanelSectionVisibility.isShown("measurements", choices: choices, in: emptyHanded))
    }

    // MARK: Saying what it did, in words

    /// The popover tells you WHY a section is off, or there is no way to tell a
    /// section you hid from one the document has nothing for.
    @Test func eachRowSaysWhyItIsWhereItIs() {
        var choices = PanelSectionVisibility.Choices()
        choices.set("shadow", shown: false)
        let rows = PanelSectionVisibility.rows(for: ["measurements", "columns", "shadow"],
                                               choices: choices, in: emptyHanded)
        #expect(rows.count == 3)
        #expect(rows[0].isShown == false)
        #expect(rows[0].reason == .automaticallyOut)
        #expect(rows[1].reason == .automaticallyOut)
        #expect(rows[2].isShown == false)
        #expect(rows[2].reason == .turnedOff)
    }

    @Test func aRowPinnedOnSaysSo() {
        var choices = PanelSectionVisibility.Choices()
        choices.set("library", shown: true)
        let rows = PanelSectionVisibility.rows(for: ["library"], choices: choices, in: emptyHanded)
        #expect(rows[0].isShown)
        #expect(rows[0].reason == .turnedOn)
    }

    @Test func aRowTheDocumentEarnedSaysThatToo() {
        let choices = PanelSectionVisibility.Choices()
        var measuring = emptyHanded
        measuring.documentHasMeasurement = true
        let rows = PanelSectionVisibility.rows(for: ["measurements"], choices: choices, in: measuring)
        #expect(rows[0].isShown)
        #expect(rows[0].reason == .automaticallyIn)
    }

    // MARK: Remembering it

    @Test func theChoiceSurvivesBeingWrittenDownAndReadBack() {
        var choices = PanelSectionVisibility.Choices()
        choices.set("motion", shown: true)
        choices.set("library", shown: false)
        let restored = PanelSectionVisibility.Choices(stored: choices.stored)
        #expect(restored == choices)
        #expect(PanelSectionVisibility.isShown("motion", choices: restored, in: emptyHanded))
        #expect(!PanelSectionVisibility.isShown("library", choices: restored, in: emptyHanded))
    }

    @Test func nothingSavedMeansEverythingAutomatic() {
        let restored = PanelSectionVisibility.Choices(stored: "")
        #expect(!restored.hasAnyCustom)
    }

    /// A saved choice naming a section this build no longer has is dropped
    /// rather than carried, the way a saved ORDER drops ids it does not know.
    @Test func aSavedChoiceForASectionThatIsGoneIsDropped() {
        let restored = PanelSectionVisibility.Choices(stored: "motion=1;wormhole=0")
        #expect(restored.isCustom("motion"))
        #expect(!restored.isCustom("wormhole"))
    }

    @Test func rubbishOnDiskIsReadAsNoChoiceAtAll() {
        #expect(!PanelSectionVisibility.Choices(stored: ";;=;x").hasAnyCustom)
    }
}
