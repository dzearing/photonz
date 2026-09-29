import CoreGraphics
import Foundation
import XCTest
@testable import PhotonzCore

// Every control the caption panels show, driven the way the panel drives it
// (`Sources/PhotonzCore/CaptionLookControl.swift`).
//
// The user, 2026-09-28: "the caption properties have a bunch of dropdowns that
// do not function ... I can't change the caption styling properties at all."
// Each row in the Captions and Text sections reads and writes the look through
// one `CaptionLookControl`, so a control that writes nothing, writes the wrong
// thing, or writes something the drawn caption ignores fails here.
final class CaptionLookControlTests: XCTestCase {

    /// Every value each control offers, on every named style: the look takes
    /// it and the control reads it back.
    func testEveryControlWritesWhatItReadsBack() {
        for preset in CaptionLook.Preset.allCases {
            let base = CaptionLook.preset(preset)
            for control in CaptionLookControl.allCases {
                for value in control.samples where value != control.value(in: base) {
                    var look = base
                    control.set(value, in: &look)
                    XCTAssertNotEqual(look, base, "\(control) to \(value) on \(preset) changed nothing")
                    XCTAssertEqual(control.value(in: look), value,
                                   "\(control) on \(preset) reads back what it was set to")
                }
            }
        }
    }

    /// A control never reaches past its own setting.
    func testEachControlTouchesOnlyItsOwnSetting() {
        let base = CaptionLook.preset(.boldPop)
        for control in CaptionLookControl.allCases {
            for value in control.samples where value != control.value(in: base) {
                var look = base
                control.set(value, in: &look)
                for other in CaptionLookControl.allCases where other != control && !control.alsoMoves.contains(other) {
                    XCTAssertEqual(other.value(in: look), other.value(in: base),
                                   "setting \(control) moved \(other)")
                }
            }
        }
    }

    /// A value of the wrong kind is ignored rather than guessed at.
    func testAValueOfTheWrongKindIsIgnored() {
        let base = CaptionLook.preset(.caption)
        for control in CaptionLookControl.allCases {
            var look = base
            let stranger: CaptionLookValue = control.kind == .toggle ? .motion(.pop) : .on(true)
            control.set(stranger, in: &look)
            XCTAssertEqual(look, base, "\(control) took \(stranger)")
        }
    }

    /// The colours: a well each, and all but the words' own ink can be none.
    func testTheColourControlsAndWhichCanBeNone() {
        let colours = CaptionLookControl.allCases.filter { $0.kind == .colour }
        XCTAssertEqual(Set(colours), [.wordColour, .wordPill, .wordGlow, .wordStroke,
                                      .textColour, .background, .glow, .stroke])
        XCTAssertFalse(CaptionLookControl.textColour.allowsNone)
        for control in colours where control != .textColour {
            XCTAssertTrue(control.allowsNone, "\(control)")
            var look = CaptionLook.preset(.neon)
            control.set(.colour("#123456"), in: &look)
            control.set(.colour(nil), in: &look)
            XCTAssertEqual(control.value(in: look), .colour(nil), "\(control) can be switched off")
        }
        var look = CaptionLook.preset(.caption)
        CaptionLookControl.textColour.set(.colour(nil), in: &look)
        XCTAssertEqual(look, .preset(.caption), "the words always have an ink")
    }

    /// The colour a well opens its picker on when it holds none: something
    /// that shows, never the none it came from.
    func testAnEmptyWellOpensOnAColourThatShows() {
        for control in CaptionLookControl.allCases where control.kind == .colour {
            XCTAssertNotNil(RGBA(hex: control.openingHex(in: CaptionLook.preset(.caption))), "\(control)")
        }
    }

    // MARK: - The caption drawn

    /// Enough words, in a box narrow enough, that every setting has something
    /// to show on: two lines, a word being said, words said and to come.
    private let words: [TranscribedWord] = [
        "Photonz", "opens", "a", "screen", "recording", "as", "an", "ordinary", "document",
        "with", "time", "in", "it", "and", "every", "word", "is", "timed",
    ].enumerated().map { index, word in
        TranscribedWord(word, startMS: index * 400, endMS: index * 400 + 380)
    }

    /// The caption layers a frame of the film is drawn from, at a handful of
    /// moments: early in a word (mid motion), late in one, and further on.
    private func drawn(_ look: CaptionLook) -> [Layer] {
        let box = CGSize(width: 420, height: 160)
        let perLine = CaptionLayers.charactersPerLine(boxWidth: box.width, fontSize: 28)
        var sized = look
        sized.fontSize = sized.fontSize ?? 28
        let cues = CaptionCues.cues(from: words, showing: look.show, lines: look.lines,
                                    charactersPerLine: perLine)
        let layers = CaptionLayers.layers(for: cues, in: box, look: sized, box: box)
        return [1_630, 1_700, 1_960, 3_250].flatMap { ms in
            layers.filter { ($0.time?.inMS ?? 0) <= ms && ms < ($0.time?.outMS ?? 0) }
                .map { $0.withSpokenWordLit(atTimeMS: ms, look: sized) }
        }
    }

    /// Every value of every control changes what is drawn, from a look where
    /// that control has something to act on.
    func testEveryControlChangesTheDrawnCaption() {
        for control in CaptionLookControl.allCases {
            let base = control.liveBase
            let before = drawn(base)
            XCTAssertFalse(before.isEmpty, "\(control): nothing drawn to compare")
            for value in control.samples where value != control.value(in: base) {
                var look = base
                control.set(value, in: &look)
                XCTAssertNotEqual(drawn(look), before, "\(control) to \(value) left the caption as it was")
            }
        }
    }

    // MARK: - The panels write through here

    private var panelSources: String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return ["CaptionStyleInspector.swift", "CaptionsInspector.swift"].compactMap {
            try? String(contentsOf: root.appendingPathComponent("Sources/Photonz/\($0)"), encoding: .utf8)
        }.joined(separator: "\n")
    }

    /// Every control is on a panel, set through its control, and no row
    /// reaches into the look on its own where this list cannot see it.
    func testThePanelsSetEveryControlThroughThisList() {
        let source = panelSources
        XCTAssertFalse(source.isEmpty, "the panel sources were not found")
        for control in CaptionLookControl.allCases {
            let named = source.contains("(.\(control.rawValue),") || source.contains("control: .\(control.rawValue),")
                || source.contains("setCaption(.\(control.rawValue),")
            XCTAssertTrue(named, "no panel row sets \(control)")
        }
        XCTAssertFalse(source.contains("changeCaptionLook {"),
                       "a panel row writes the look directly instead of through CaptionLookControl")
    }
}
