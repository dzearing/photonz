import Testing
@testable import PhotonzCore

/// How a menu row, a menu heading and a button label are capitalised: the Mac
/// way, Title Case (the user, 2026-09-30, answering
/// `the-design-rules-say-how-a-menu-row-is-capitalis`).
@Suite("Menu rows and buttons are in Title Case")
struct MenuTitleCaseTests {

    @Test func theAppsOwnRowsPass() {
        for title in ["Apply to Every Cut", "Reset to Defaults", "Copy Look", "Set as Default Transition",
                      "Merge into One Clip", "Export Captions as SRT…", "Split Everything at Playhead",
                      "Clear In and Out", "Punch In", "Rename Layer…", "Show Grid", "Snap in Timeline",
                      "Curve the Path", "Add Captions for Range", "Reveal in Finder", "Delete"] {
            #expect(MenuTitleCase.departures(in: title).isEmpty, "\(title)")
        }
    }

    @Test func theMocksSentenceCaseFails() {
        #expect(MenuTitleCase.departures(in: "Apply to every cut") == ["every", "cut"])
        #expect(MenuTitleCase.departures(in: "Reset to defaults") == ["defaults"])
        #expect(MenuTitleCase.departures(in: "Draw a curve...") == ["curve"])
        #expect(MenuTitleCase.departures(in: "Use this curve") == ["this", "curve"])
    }

    @Test func aSmallWordStaysSmallInTheMiddle() {
        #expect(MenuTitleCase.departures(in: "Apply To Every Cut") == ["To"])
        #expect(MenuTitleCase.departures(in: "Draw A Curve") == ["A"])
        #expect(MenuTitleCase.departures(in: "Cut And Paste") == ["And"])
    }

    @Test func theFirstAndLastWordsAreAlwaysCapitalised() {
        #expect(MenuTitleCase.departures(in: "the Path") == ["the"])
        #expect(MenuTitleCase.departures(in: "What It Is For") == [])
        #expect(MenuTitleCase.departures(in: "What It Is for") == ["for"])
        #expect(MenuTitleCase.departures(in: "Zoom In") == [])
    }

    @Test func aParticleOfAVerbMayBeCapitalised() {
        // "In" here is a phrasal verb's particle or a noun, not a preposition.
        #expect(MenuTitleCase.departures(in: "Clear In and Out").isEmpty)
        #expect(MenuTitleCase.departures(in: "Turn Off Snapping").isEmpty)
        #expect(MenuTitleCase.departures(in: "Zoom In on Selection").isEmpty)
    }

    @Test func namesKeysAndNumbersAreLeftAlone() {
        for title in ["Open in macOS Preview", "Export as SRT", "Scale 2x", "50%", "⌘K", "·", "Go to iCloud",
                      "1920 × 1080", "H.264", "Built-in Presets"] {
            #expect(MenuTitleCase.departures(in: title).isEmpty, "\(title)")
        }
    }

    @Test func punctuationAroundAWordIsNotPartOfIt() {
        #expect(MenuTitleCase.departures(in: "Rename…").isEmpty)
        #expect(MenuTitleCase.departures(in: "Export (Current Frame)").isEmpty)
        #expect(MenuTitleCase.departures(in: "Export (current frame)") == ["current", "frame"])
        #expect(MenuTitleCase.departures(in: "“Title” Style").isEmpty)
        #expect(MenuTitleCase.departures(in: "Transition: a Fade").isEmpty == false)
    }

    @Test func titleCasingFixesTheMocksWording() {
        #expect(MenuTitleCase.titleCased("Apply to every cut") == "Apply to Every Cut")
        #expect(MenuTitleCase.titleCased("Draw a curve...") == "Draw a Curve...")
        #expect(MenuTitleCase.titleCased("Use this curve") == "Use This Curve")
        #expect(MenuTitleCase.titleCased("reset to style") == "Reset to Style")
        #expect(MenuTitleCase.titleCased("Apply To Every Cut") == "Apply to Every Cut")
        #expect(MenuTitleCase.titleCased("Open in macOS Preview") == "Open in macOS Preview")
    }

    @Test func aTitleCasedTitleHasNoDepartures() {
        for title in ["apply to every cut", "use this curve", "the path for the move", "export (current frame)"] {
            #expect(MenuTitleCase.departures(in: MenuTitleCase.titleCased(title)).isEmpty, "\(title)")
        }
    }
}
