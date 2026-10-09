import CoreGraphics
import PhotonzCore
import Testing

/// The tool bar's one purpose, held: it carries tools (something you pick,
/// then use on the canvas or the timeline), the colour pair a painting tool
/// uses, and More for the tools that do not fit. Nothing else.
///
/// The placement contract at the top of `docs/design/mocks/shared/UX-PATTERNS.md`
/// is the rule. The user, 2026-09-29: "zoom isn't a tool", and a control in an
/// area whose purpose it does not share confuses people however useful it is.
/// A zoom, a grid, a readout or a setting belongs to the View menu, the keys and
/// the pinch, never to this bar.
@Suite("The tool bar holds tools")
struct ToolBarPurposeTests {

    /// Every section the one glass bar can draw. A new section is a new kind
    /// of thing on the bar, so it fails here until the contract says it
    /// belongs there.
    @Test func theBarsSectionsAreTheToolsAndTheColourPair() {
        #expect(EditorChromeLayout.ToolBarSection.allCases == [.tools, .color])
        #expect(EditorChromeLayout.toolBarSections(showsColor: true) == [.tools, .color])
        #expect(EditorChromeLayout.toolBarSections(showsColor: false) == [.tools])
    }

    /// Every slot of every bar the flags can build, and the video's own front
    /// slots, is a tool, a family of tools or the Blade.
    @Test func everySlotOnEveryBarIsATool() {
        var entries: [ToolBarLayout.Entry] = ToolBarFold.videoLeading.flatMap { $0 }
        for frame in [false, true] {
            for lens in [false, true] {
                for pen in [false, true] {
                    entries += ToolBarLayout.bar(withFrame: frame, withLens: lens,
                                                 withPen: pen).entries
                }
            }
        }
        for entry in entries {
            let tools: [Tool] = switch entry {
            case .tool(let tool): [tool]
            case .group(let group): group.tools
            case .blade: []
            }
            for tool in tools {
                #expect(!Self.notTools.contains(tool.rawValue),
                        "\(tool.rawValue) is on the tool bar but is not a tool")
            }
        }
    }

    /// No tool is a way of LOOKING at the document. Those are the View menu's,
    /// the keys' and the pinch's. (The Zoom Callout is a tool: it draws a
    /// magnified box onto the picture.)
    @Test func noToolIsAViewOption() {
        for tool in Tool.allCases {
            #expect(!Self.notTools.contains(tool.rawValue),
                    "\(tool.rawValue) is a view option, not a tool")
        }
    }

    /// Ways of looking, and things that are not picked up at all.
    ///
    /// The Hand is not on the list: it is picked, then used on the canvas,
    /// which is the contract's own test for a tool, and every app strip in the
    /// user's mocks ends with it (`Hand (H)`, UX-PATTERNS D4), as Photoshop's
    /// bar does. Panning by a command or a readout would still be a view
    /// option, so "pan" stays.
    static let notTools: Set<String> = [
        "zoom", "zoomIn", "zoomOut", "pan", "grid", "rulers", "guides",
        "view", "fit", "actualSize", "snap", "snapping", "readout", "settings",
    ]
}
