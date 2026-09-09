import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The app measures the document in ONE space, so it says ONE word for it.
///
/// This suite is the guard on that. A corner radius of 24, a line thickness of
/// 24, a grid spacing of 24 and a caliper reading 24 all mean the same distance,
/// and a person redlining a screenshot must never have to work out which of two
/// unit words their number is in. Before this landed the right hand panel said
/// "18 pt" for Corner Radius and "px from the top left" for Position and Size,
/// two rows apart.
@Suite("The one unit word")
struct DocumentUnitTests {

    @Test func theWordIsPx() {
        #expect(DocumentUnit.word == "px")
    }

    // The measure readouts are the number a redliner copies into a spec, so
    // they are what everything else has to agree with rather than the other
    // way round.
    @Test func theWordIsTheOneTheCaliperReadsOut() {
        for unit in MeasureUnit.allCases {
            #expect(DocumentUnit.word == unit.suffix)
        }
    }

    @Test func layerGeometryUsesTheSameWord() {
        #expect(LayerGeometry.unitSuffix == DocumentUnit.word)
    }

    @Test func aLengthIsTheNumberThenTheWord() {
        #expect(DocumentUnit.text(18) == "18 px")
        #expect(DocumentUnit.text(0) == "0 px")
    }

    /// A readout shows whole units, so it rounds rather than showing a number
    /// nobody typed.
    @Test func aLengthRoundsToWholeUnits() {
        #expect(DocumentUnit.text(17.4) == "17 px")
        #expect(DocumentUnit.text(17.6) == "18 px")
    }

    /// The grid writes halves ("7.5"), so the unit word has to be joinable to a
    /// number somebody else already wrote out.
    @Test func anAlreadyWrittenNumberKeepsItsOwnSpelling() {
        #expect(DocumentUnit.text(digits: "7.5") == "7.5 px")
        #expect(DocumentUnit.text(digits: "4 \u{2192} 32") == "4 \u{2192} 32 px")
    }
}

/// Every readout that measures the document space, asked what word it says.
///
/// One test per surface, because the drift this fixes was surface by surface:
/// each of these was its own hardcoded string literal.
@Suite("Every surface says the one word")
struct UnitWordAgreementTests {

    private func unitWord(of text: String) -> String? {
        text.split(separator: " ").last.map(String.init)
    }

    @Test func theGridSpacingSaysIt() {
        #expect(unitWord(of: CanvasGridSettings(spacing: 16).spacingText) == DocumentUnit.word)
        #expect(unitWord(of: CanvasGridSettings(spacing: 7.5).spacingText) == DocumentUnit.word)
    }

    @Test func theGridCellButtonSaysIt() {
        let settings = CanvasGridSettings(spacing: 16, minimumCell: 16)
        #expect(unitWord(of: settings.cellButtonText) == DocumentUnit.word)
    }

    /// A type size is a length in the same document space: 16 px of text sits
    /// beside a 16 px gap, and the two numbers have to read as the same thing.
    @Test func aTypeSizeSaysIt() {
        #expect(unitWord(of: TextStyles.sizeWords(24)) == DocumentUnit.word)
        #expect(unitWord(of: TextStyles.unpadded(TextStyles.sizeTitle(24))) == DocumentUnit.word)
    }

    /// Whatever else changes about the Size menu, its titles stay one column
    /// wide, so swapping the word must not have moved the padding.
    @Test func theTypeSizeMenuStaysOneColumnWide() {
        let widths = Set([8, 24, 128].map { TextStyles.sizeTitle(CGFloat($0)).count })
        #expect(widths.count == 1)
    }

    @Test func aLayerSizeRefusalSaysIt() {
        // The sentences that name a floor or a ceiling carry the unit too.
        let unit = LayerGeometry.unitSuffix
        #expect(unit == DocumentUnit.word)
    }
}

/// Finding a row that spells the unit differently, in whatever the panel
/// happens to be showing.
///
/// This is what the walk leans on: reading the panel back is only useful if
/// something can look at a pile of readouts and say "this one disagrees".
@Suite("Spotting a stray unit word")
struct StrayUnitTests {

    @Test func agreeingReadoutsHaveNoStrays() {
        #expect(DocumentUnit.strays(in: ["18 px", "4 px", "24 px", "100%", "Fill, on"]).isEmpty)
    }

    @Test func theOldWordIsCaught() {
        let strays = DocumentUnit.strays(in: ["18 px", "4 pt"])
        #expect(strays.map(\.text) == ["4 pt"])
        #expect(strays.map(\.word) == ["pt"])
    }

    /// Any spelling of a length that is not the one word, not just `pt`: the
    /// point is that the panel never grows a SECOND word, whichever it is.
    @Test func anyOtherLengthWordIsCaught() {
        for stray in ["12 points", "12 pts", "12 pixels", "12 dp", "12 rem", "1.5 em"] {
            #expect(!DocumentUnit.strays(in: [stray]).isEmpty, "\(stray) went unnoticed")
        }
    }

    /// A readout is short and full of ordinary words. None of them is a unit,
    /// and a check that cries wolf over "Border, on" is a check nobody keeps.
    @Test func plainWordsAfterANumberAreNotUnits() {
        let ordinary = ["2 layers", "Mixed", "Border, Inside", "3 of 5 selected",
                        "Row", "24 px \u{2192} 48 px", "\u{00d7}1.5", "0\u{00b0}"]
        #expect(DocumentUnit.strays(in: ordinary).isEmpty)
    }

    /// The word has to be a word of its own. "4 point" is a unit; "4 pointing"
    /// is not, and neither is the Position menu's "Inside".
    @Test func onlyAWholeWordCounts() {
        #expect(DocumentUnit.strays(in: ["4 pointing at it"]).isEmpty)
        #expect(DocumentUnit.strays(in: ["4 point"]).count == 1)
    }

    /// It has to be a unit ON a number. A sentence that happens to contain the
    /// letters is not a readout saying a length.
    @Test func aWordWithNoNumberInFrontIsNotAUnit() {
        #expect(DocumentUnit.strays(in: ["pt", "Points of interest"]).isEmpty)
    }

    @Test func theWordIsFoundWithNoSpaceBeforeIt() {
        #expect(DocumentUnit.strays(in: ["18pt"]).map(\.word) == ["pt"])
        #expect(DocumentUnit.strays(in: ["18px"]).isEmpty)
    }
}
