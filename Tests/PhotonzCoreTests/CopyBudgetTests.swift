import Testing
@testable import PhotonzCore

/// The scanner the panel copy budget reads the app's own source with
/// (`panel-copy-and-flag-descriptions-have-a-length-b`, 2026-09-24).
@Suite("Copy budget: reading a panel's words out of its source")
struct CopyBudgetTests {

    private func texts(_ source: String) -> [String] {
        CopyBudget.phrases(inSwift: source).filter { !$0.isTooltip }.map(\.text)
    }

    private func tips(_ source: String) -> [String] {
        CopyBudget.phrases(inSwift: source).filter(\.isTooltip).map(\.text)
    }

    @Test func aPlainLabelIsOnePhrase() {
        #expect(texts(#"Text("Speed")"#) == ["Speed"])
    }

    @Test func commentsSayWhatTheyLike() {
        let source = """
        // "A comment can run on for as long as it likes, however long it is."
        /* "Nor does a block comment count" */
        Text("Short")
        """
        #expect(texts(source) == ["Short"])
    }

    @Test func gluedPiecesAreMeasuredAsOneSentence() {
        let source = """
        private static let oneAtATime = "Motion is set on one layer at a time, "
            + "because the numbers it animates are that layer's own."
        """
        #expect(texts(source) == [
            "Motion is set on one layer at a time, because the numbers it animates are that layer's own.",
        ])
    }

    @Test func anInterpolationCountsAsAShortValue() {
        let phrases = texts(#"Text("Its \(editorState.keyCount(property)) keys go")"#)
        #expect(phrases.count == 1)
        #expect(phrases.first?.count == "Its ···· keys go".count)
    }

    @Test func aStringInsideAnInterpolationIsNotItsOwnPhrase() {
        #expect(texts(#"Text("Named \(name ?? "none") here")"#).count == 1)
    }

    @Test func escapedQuotesStayInsideTheLiteral() {
        #expect(texts(#"Text("Say \"Done\" instead")"#) == [#"Say \"Done\" instead"#])
    }

    @Test func hoverTipsAreSetAside() {
        let source = """
        Slider(value: $x)
            .panelHelp("How far the shadow reaches, in points. Up and down arrow steps it by 1")
        Button("Go") {}.help(isOn
            ? "Stop the preview and put the picture back"
            : "Play it")
        Row(label: "Blur", sliderHelp: "A long tip that explains the slider in detail",
            caption: "Visible")
        """
        #expect(texts(source) == ["Go", "Blur", "Visible"])
        #expect(tips(source) == [
            "How far the shadow reaches, in points. Up and down arrow steps it by 1",
            "Stop the preview and put the picture back",
            "Play it",
            "A long tip that explains the slider in detail",
        ])
    }

    @Test func aHelperNamedForATipBuildsATip() {
        let source = """
        private func placeHelp(_ id: UUID) -> String {
            guard let v else { return "Puts a copy in the middle of the canvas, or drag the tile" }
            return "Drag it"
        }
        private var helpText: String { "Explained at length on hover" }
        static let showTip = "A tip kept in a constant"
        private func sentence() -> String { "Shown in the panel" }
        """
        #expect(texts(source) == ["Shown in the panel"])
        #expect(tips(source).count == 4)
    }

    @Test func identifiersAndSymbolsAreNotCopy() {
        let source = """
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right.circle.fill")
            .accessibilityIdentifier("inspector.effects.shadow.blur.slider.row.value")
        """
        #expect(texts(source).isEmpty)
    }

    @Test func aPhraseKnowsItsLine() {
        let phrases = CopyBudget.phrases(inSwift: "let a = 1\n\nText(\"Third\")")
        #expect(phrases.first?.line == 3)
    }

    @Test func overBudgetIsLongerThanTheLine() {
        let fits = String(repeating: "a", count: CopyBudget.panelLine)
        #expect(!CopyBudget.overPanelBudget(fits))
        #expect(CopyBudget.overPanelBudget(fits + "a"))
    }

    @Test func wordsAreCountedBySpaces() {
        #expect(CopyBudget.words(in: "Off means the built-in timing.") == 5)
        #expect(CopyBudget.words(in: "  two   words ") == 2)
    }

    @Test func anOffenderIsKnownByItsOpeningWords() {
        let long = "Motion is set on one layer at a time, because the numbers it animates are that layer's own."
        #expect(CopyBudget.key(long) == "Motion is set on one layer at a time, be")
        #expect(CopyBudget.key("Short") == "Short")
    }
}
