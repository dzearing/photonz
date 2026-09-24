import Foundation
import Testing
@testable import PhotonzCore

/// Every line the right hand panel shows fits on one line
/// (`panel-copy-and-flag-descriptions-have-a-length-b`, 2026-09-24).
///
/// UX-PATTERNS §4 "How much a section may say": a section says at most one
/// short line. This reads every panel file's own source with
/// `CopyBudget.phrases(inSwift:)` and fails any shown string over
/// `CopyBudget.panelLine` characters. Hover tips are where a cut sentence goes,
/// so they are not held to it.
///
/// `allowed` is the list of offenders that were already there on the day the
/// budget arrived, known by their opening forty characters. It only shrinks:
/// fix one and the test asks you to strike it off, add a new one and the test
/// fails. The video sections were fixed first and may never appear on it.
@Suite("Panel copy fits the line budget")
struct PanelCopyBudgetTests {

    static var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Photonz")
    }

    /// The files that draw the panel, by name, so a new section is covered
    /// the day it is written: every inspector, every part's settings, every
    /// `…Panel`, and the Sections footer.
    static func isPanelFile(_ name: String) -> Bool {
        guard name.hasSuffix(".swift"), !name.hasPrefix("EditorState") else { return false }
        return name.contains("Inspector") || name.hasSuffix("PartSettings.swift")
            || name.hasSuffix("Panel.swift") || name == "PanelSectionsFooter.swift"
    }

    static var panelFiles: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: sources.path)) ?? []
        return names.filter(isPanelFile).sorted()
    }

    /// The sections a video document shows. None of them may carry an
    /// allowance.
    static let videoFiles = [
        "SpeedInspector.swift", "SoundInspector.swift", "CaptionsInspector.swift",
        "TransitionInspector.swift", "MotionListInspector.swift", "PropertyKeysInspector.swift",
        "CompositingInspector.swift",
    ]

    /// Over budget on 2026-09-24, and filed to be cut
    /// (`the-panel-s-long-lines-are-cut-to-one-short-line`).
    static let allowed: [String: [String]] = [
        "ArrangementInspector.swift": [
            "These ···· copies arrange their contents",
            "Free leaves everything where you put it.",
        ],
        "BlendModeInspector.swift": [
            "Blending applies to ···· of the ···· sel",
        ],
        "ColorStylePanel.swift": [
            "Nothing uses this yet. Pick it from a co",
            "···· colors use this. Changing it repain",
        ],
        "ComponentPanel.swift": [
            "Its shared original has gone. This drawi",
            "On the Library shelf of every document. ",
            "Comes with the app. Adding it puts it in",
            "···· is part of a copy. What it shows co",
            "The original has given this component no",
        ],
        "EffectsListInspector.swift": [
            "An open path is a line, so the border ru",
            "Center straddles the edge. The ···· offs",
        ],
        "FrameColumnsInspector.swift": [
            "Draw this screen's columns over it, and ",
            "Each column comes out ···· wide. Draggin",
            "These numbers leave no room for a column",
            "This screen keeps no room at its edges, ",
            "The columns start where this screen's pa",
        ],
        "LayerEffectsInspector.swift": [
            "Border applies to ···· of the ···· selec",
            "···· of the ···· selected layers ···· a ",
        ],
        "PanelSectionsFooter.swift": [
            "Everything else follows the document: a ",
        ],
        "PlacementInspector.swift": [
            "Placed by hand, in front of the rest, wi",
            "Painted to the group's own edges instead",
            "···· is the way this group runs, so Stre",
            "This takes the room ···· has left once e",
            "···· is still set where ···· decides. It",
            "Stretch fills the box with the words pla",
            "Following the screen. Pick something her",
            "Following the group. Pick something here",
            "These all take the room ···· has left, s",
            "Everything inside these ···· follows thi",
            "Everything on this screen follows this w",
            "Everything inside follows this when the ",
        ],
    ]

    static func overBudget(in file: String) throws -> [CopyBudget.Phrase] {
        let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
        return CopyBudget.phrases(inSwift: text)
            .filter { !$0.isTooltip && CopyBudget.overPanelBudget($0.text) }
    }

    @Test func thePanelFilesAreFound() {
        let files = Self.panelFiles
        #expect(files.count >= 30, "found only \(files)")
        for known in Self.videoFiles + ["InspectorPanel.swift", "ShapePartSettings.swift",
                                        "ColorStylePanel.swift", "PanelSectionsFooter.swift"] {
            #expect(files.contains(known), "\(known) is not read")
        }
    }

    @Test(arguments: panelFiles)
    func everyShownLineFits(file: String) throws {
        let allowed = Set(Self.allowed[file] ?? [])
        let new = try Self.overBudget(in: file).filter { !allowed.contains(CopyBudget.key($0.text)) }
        #expect(new.isEmpty, """
            \(file) shows lines longer than \(CopyBudget.panelLine) characters. Cut each to one \
            short line and move the reason into the control's hover tip (.panelHelp): \
            \(new.map { "line \($0.line): \($0.text)" })
            """)
    }

    @Test(arguments: panelFiles)
    func theAllowanceOnlyShrinks(file: String) throws {
        let still = Set(try Self.overBudget(in: file).map { CopyBudget.key($0.text) })
        let fixed = (Self.allowed[file] ?? []).filter { !still.contains($0) }
        #expect(fixed.isEmpty, "\(file) no longer says these, so strike them off `allowed`: \(fixed)")
    }

    @Test func everyAllowanceNamesAPanelFile() {
        let files = Set(Self.panelFiles)
        #expect(Set(Self.allowed.keys).subtracting(files).isEmpty)
    }

    @Test func theVideoSectionsHaveNoAllowance() {
        for file in Self.videoFiles {
            #expect(Self.allowed[file] == nil, "\(file) is a video section and may not be over budget")
        }
    }
}
