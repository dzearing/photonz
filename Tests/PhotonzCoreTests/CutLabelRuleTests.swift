import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A label the chrome cut short is found by the "…" it ends on, wherever the
/// words were read off the window, except over the picture and the clips on
/// the lanes, where a long name cut to fit is how every editor draws it.
struct CutLabelRuleTests {
    @Test func aLabelEndingInAnEllipsisIsCut() {
        #expect(CutLabelRule.isCut("Write Ag…"))
        #expect(CutLabelRule.isCut("Ease In and..."))
        #expect(CutLabelRule.isCut("Tutori…e.mp4"))
        #expect(CutLabelRule.isCut("Ca..."))
        #expect(CutLabelRule.isCut("Lower.."))
    }

    @Test func wholeWordsAreNotCut() {
        #expect(!CutLabelRule.isCut("Rewrite"))
        #expect(!CutLabelRule.isCut("10 captions"))
        #expect(!CutLabelRule.isCut("0:04"))
        #expect(!CutLabelRule.isCut("4.31s / 17.25s"))
        #expect(!CutLabelRule.isCut("Sample Talk · 1280 x 800 · 0:17"))
    }

    @Test func wordsOverThePictureOrTheLanesAreLeftOut() {
        let lanes = CGRect(x: 100, y: 500, width: 800, height: 200)
        let readings = [
            CutLabelRule.Reading(text: "Write Ag…", frame: CGRect(x: 1000, y: 300, width: 60, height: 12)),
            CutLabelRule.Reading(text: "Fodons opens a scr…", frame: CGRect(x: 120, y: 520, width: 150, height: 12)),
            CutLabelRule.Reading(text: "Captions", frame: CGRect(x: 20, y: 520, width: 50, height: 12)),
        ]
        let cut = CutLabelRule.cut(readings, outside: [lanes])
        #expect(cut.map(\.text) == ["Write Ag…"])
    }

    @Test func aNamedWordIsFoundOnlyWhenItIsReadWhole() {
        let readings = [
            CutLabelRule.Reading(text: "Generate", frame: .zero),
            CutLabelRule.Reading(text: "Rewrite 10 captions", frame: .zero),
            CutLabelRule.Reading(text: "Lower…", frame: .zero),
        ]
        #expect(CutLabelRule.missing(["Rewrite", "Darker", "Lower third"], in: readings)
                == ["Darker", "Lower third"])
    }

    @Test func labelsWholeIsAWalkStep() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "labelsWhole", "stage": "1-default" },
                     { "do": "labelsWhole", "stage": "2-narrow", "words": ["Rewrite"], "report": true } ] }
        """.utf8))
        guard case .labelsWhole(let stage, let words, let report) = script.steps[0],
              case .labelsWhole(_, let narrowWords, let narrowReport) = script.steps[1]
        else { Issue.record("labelsWhole"); return }
        #expect(stage == "1-default")
        #expect(words.isEmpty && !report)
        #expect(narrowWords == ["Rewrite"] && narrowReport)
        #expect(PlaytestStep.names.contains("labelsWhole"))
    }
}
