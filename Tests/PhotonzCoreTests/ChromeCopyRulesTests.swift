import Testing
@testable import PhotonzCore

/// What the chrome outside the panel may say
/// (`no-sentences-or-debug-readouts-anywhere-in-the-c`, 2026-09-25): a label or
/// a value, never a sentence about state, a debug reading or a "no X".
@Suite("Copy budget: the rules for chrome")
struct ChromeCopyRulesTests {

    @Test func aLabelPasses() {
        for label in ["Easing", "Fit", "4x", "Ease In and Out", "⌘ Insert", "Insert · V1 · ····"] {
            #expect(CopyBudget.chromeFaults(label).isEmpty, "\(label)")
        }
    }

    @Test func theRejectedReadoutFailsOnEveryCount() {
        let faults = CopyBudget.chromeFaults("Playhead no animated property @ 0.00s")
        #expect(faults.contains(.long))
        #expect(faults.contains(.debug))
    }

    @Test func aSentenceAboutStateFails() {
        #expect(CopyBudget.chromeFaults("Drop to add it.").contains(.sentence))
        #expect(CopyBudget.chromeFaults("It moves. Then it stops").contains(.sentence))
    }

    @Test func anEllipsisIsNotASentence() {
        #expect(CopyBudget.chromeFaults("Export…").isEmpty)
        #expect(CopyBudget.chromeFaults("Export...").isEmpty)
    }

    @Test func aNoPlaceholderFails() {
        #expect(CopyBudget.chromeFaults("no animated property").contains(.placeholder))
        #expect(CopyBudget.chromeFaults("No room on V1").contains(.placeholder))
        // A menu's own choice of nothing is a value, not a placeholder.
        #expect(CopyBudget.chromeFaults("None").isEmpty)
        #expect(CopyBudget.chromeFaults("Normal").isEmpty)
    }

    @Test func debugReadingsFail() {
        #expect(CopyBudget.chromeFaults("at @ 1s").contains(.debug))
        #expect(CopyBudget.chromeFaults("in at ····ms").contains(.debug))
    }

    @Test func aParentheticalFails() {
        #expect(CopyBudget.chromeFaults("Speed (slowed)").contains(.parenthetical))
    }

    @Test func overThirtyCharactersFails() {
        #expect(CopyBudget.chromeLine == 30)
        #expect(CopyBudget.chromeFaults(String(repeating: "a", count: 30)).isEmpty)
        #expect(CopyBudget.chromeFaults(String(repeating: "a", count: 31)) == [.long])
    }

    @Test func probesAndAccessibilityAreNotShownWords() {
        let source = """
        Text("Speed")
            .panelReadout("playhead at \\(ms)ms, no markers")
            .playtestControl("Timeline Blade", detail: "Timeline")
            .playtestField("Playhead Readout")
            .accessibilityLabel("Put the timeline away for now")
            .tutorialAnchor("anchor name")
        """
        #expect(CopyBudget.phrases(inSwift: source).map(\.text) == ["Speed"])
    }

    @Test func anIdentifierIsNotChromeCopy() {
        #expect(CopyBudget.isIdentifier("timelineTracks"))
        #expect(CopyBudget.isIdentifier("next.video.newKeyEase"))
        #expect(!CopyBudget.isIdentifier("Easing"))
        #expect(!CopyBudget.isIdentifier("no markers"))
    }

    @Test func wordsBuiltForAWalkAreNotShownWords() {
        let source = """
        private var readout: String {
            "track \\(name) (\\(count) clips)"
        }
        static func readout(_ document: Doc?) -> String {
            guard let document else { return "ruler" }
            return "no markers"
        }
        private var trackSummary: String { "no piece picked" }
        var body: some View { Text("Fit") }
        """
        #expect(CopyBudget.phrases(inSwift: source).map(\.text) == ["Fit"])
    }

    @Test func aShortcutInBracketsIsNotAnExplanation() {
        #expect(CopyBudget.chromeFaults(" (····)").isEmpty)
        #expect(CopyBudget.chromeFaults("Blade (B)").isEmpty)
        #expect(CopyBudget.chromeFaults("Speed (slowed)") == [.parenthetical])
    }

    @Test func aPlaytestReportAndAHintAreNotShownWords() {
        let source = """
        var playtestMeasuringReport: String {
            "foot A is down, waiting for a click on foot B"
        }
        slotButton(hint: "⇧ adds to the selection, ⌥ subtracts, ⇧⌥ intersects.")
        """
        #expect(CopyBudget.phrases(inSwift: source).filter { !$0.isTooltip }.isEmpty)
    }
}
