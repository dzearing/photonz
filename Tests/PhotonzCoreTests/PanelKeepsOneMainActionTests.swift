import Foundation
import Testing

/// The right hand panel is where you read and tune what the picked thing is.
/// Each section keeps at most ONE main action; every other one-shot verb lives
/// on the right-click menu of the thing it acts on and in the menu bar
/// (UX-PATTERNS, the placement contract's Inspector row; the card "How many
/// buttons may the right hand panel keep?", taken as recommended on
/// 2026-10-20).
///
/// This reads the source, the way `EveryCommandIsInTheMenuBarTests` does: a
/// verb that came back into a panel section fails here, and so does a verb
/// that left the panel without a right-click row and a menu bar row to go to.
@Suite("Each panel section keeps one main action, and the rest are on right-click and in the menu bar")
struct PanelKeepsOneMainActionTests {

    static func source(_ path: String) throws -> String {
        try String(contentsOf: EveryCommandIsInTheMenuBarTests.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// A verb that left the panel: the words it wore in the section it left,
    /// the right-click row that now carries it (in the file that builds that
    /// menu), and its row in the menu bar.
    struct Moved: Sendable, CustomTestStringConvertible {
        let verb: String
        let left: String
        let panelWords: [String]
        let rightClickFile: String
        let rightClickRow: String
        let barRow: String
        var testDescription: String { verb }
    }

    static let moved: [Moved] = [
        Moved(verb: "Flatten Level",
              left: "Sources/Photonz/SoundInspector.swift",
              panelWords: ["Button(\"Flatten\")", "clearSoundLevelPoints()"],
              rightClickFile: "Sources/Photonz/EditorState+SoundLine.swift",
              rightClickRow: ".command(\"Flatten Level\"",
              barRow: "Flatten Level"),
        Moved(verb: "Captions Earlier",
              left: "Sources/Photonz/CaptionsInspector.swift",
              panelWords: ["nudgeButton(", "nudgeCaptions("],
              rightClickFile: "Sources/Photonz/EditorState+TimelineMenus.swift",
              rightClickRow: ".command(\"Earlier\"",
              barRow: "Captions Earlier"),
        Moved(verb: "Captions Later",
              left: "Sources/Photonz/CaptionsInspector.swift",
              panelWords: ["nudgeButton(", "nudgeCaptions("],
              rightClickFile: "Sources/Photonz/EditorState+TimelineMenus.swift",
              rightClickRow: ".command(\"Later\"",
              barRow: "Captions Later"),
        Moved(verb: "Export Subtitles",
              left: "Sources/Photonz/CaptionsInspector.swift",
              panelWords: ["Menu(\"Export\")", "exportCaptions("],
              rightClickFile: "Sources/Photonz/EditorState+TimelineMenus.swift",
              rightClickRow: ".submenu(\"Export Subtitles\"",
              barRow: "Export Captions as SRT\u{2026}"),
        Moved(verb: "Clear Captions (the section)",
              left: "Sources/Photonz/CaptionsInspector.swift",
              panelWords: ["Button(\"Clear\")", "clearCaptions()"],
              rightClickFile: "Sources/Photonz/EditorState+TimelineMenus.swift",
              rightClickRow: ".command(\"Clear Captions\"",
              barRow: "Clear Captions"),
        Moved(verb: "Clear Captions (the caption track's bar)",
              left: "Sources/Photonz/CaptionTrackBar.swift",
              panelWords: ["clearCaptions()"],
              rightClickFile: "Sources/Photonz/EditorState+TimelineMenus.swift",
              rightClickRow: ".command(\"Clear Captions\"",
              barRow: "Clear Captions"),
        Moved(verb: "Reset Captions (the caption track's bar)",
              left: "Sources/Photonz/CaptionTrackBar.swift",
              panelWords: ["resetCaptions()"],
              rightClickFile: "Sources/Photonz/EditorState+TimelineMenus.swift",
              rightClickRow: ".command(\"Reset Captions\"",
              barRow: "Reset Captions"),
    ]

    /// The one main action a section keeps, as its button is written.
    static let kept: [(section: String, file: String, button: String)] = [
        ("Gain", "Sources/Photonz/SoundInspector.swift", "Button(\"Normalize\")"),
        ("Captions", "Sources/Photonz/CaptionsInspector.swift", "Label(\"Add Captions\""),
        ("Measurement", "Sources/Photonz/MeasureInspector.swift", "Button(\"Copy Measurement\")"),
        ("Key", "Sources/Photonz/CompositingInspector.swift", "Button(\"Key It\")"),
        ("Canvas", "Sources/Photonz/CanvasInspector.swift", "Button(\"Canvas Size\u{2026}\")"),
        ("Transition", "Sources/Photonz/TransitionInspector.swift", "Label(\"Add transition\""),
    ]

    @Test("A verb that left the panel is not back in its section", arguments: moved)
    func leftThePanel(_ verb: Moved) throws {
        let text = try Self.source(verb.left)
        for words in verb.panelWords {
            #expect(!text.contains(words),
                    "\(verb.left) still carries \(words): \(verb.verb) is a one-shot verb, so it is on right-click and in the menu bar, not a panel button")
        }
    }

    @Test("A verb that left the panel is on the right-click menu of the thing it acts on", arguments: moved)
    func onTheRightClick(_ verb: Moved) throws {
        let text = try Self.source(verb.rightClickFile)
        #expect(text.contains(verb.rightClickRow),
                "\(verb.verb) has no right-click row \(verb.rightClickRow) in \(verb.rightClickFile)")
    }

    @Test("A verb that left the panel has a row in the menu bar", arguments: moved)
    func inTheMenuBar(_ verb: Moved) throws {
        let bar = try EveryCommandIsInTheMenuBarTests.menuBarTitles()
        #expect(bar.contains(verb.barRow), "no menu bar row called \"\(verb.barRow)\" for \(verb.verb)")
    }

    @Test("Each section still has its one main action")
    func mainActionsStay() throws {
        for (section, file, button) in Self.kept {
            #expect(try Self.source(file).contains(button), "the \(section) section lost its main action \(button)")
        }
    }

    @Test("The caption track's bar over the timeline says what the track is and holds no buttons or readouts")
    func captionTrackBarHoldsNoVerbs() throws {
        let text = try Self.source("Sources/Photonz/CaptionTrackBar.swift")
        guard let start = text.range(of: "struct CaptionTrackBarView: View {") else {
            Issue.record("CaptionTrackBarView is gone; point this test at what draws the caption track's bar")
            return
        }
        let view = EveryCommandIsInTheMenuBarTests.block(in: text, from: text.index(before: start.upperBound))
        #expect(!view.contains("Button"), "the caption track's bar has a button again")
        #expect(!view.contains("Readouts"), "the caption track's bar reads out the word and the time again")
    }

    @Test("The placement contract's Inspector row states the rule")
    func ruleIsWritten() throws {
        let patterns = try Self.source("docs/design/mocks/shared/UX-PATTERNS.md")
        guard let row = patterns.split(separator: "\n").first(where: { $0.hasPrefix("| **Inspector**") }) else {
            Issue.record("UX-PATTERNS.md has no Inspector row in its placement contract")
            return
        }
        #expect(row.contains("one main action"), "the Inspector row does not say a section keeps one main action")
        #expect(!row.contains("is the open card"), "the Inspector row still calls the answered card open")
    }
}
