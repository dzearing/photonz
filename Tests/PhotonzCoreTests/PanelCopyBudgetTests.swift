import Foundation
import Testing
@testable import PhotonzCore

/// Every line the right hand panel shows is a label, not a sentence
/// (`panel-copy-and-flag-descriptions-have-a-length-b`, 2026-09-24;
/// `the-panel-s-long-lines-are-cut-to-one-short-line`, 2026-09-27).
///
/// The user, answering the card on 2026-09-25: "no sentences in the panel,
/// just labels and tools", with forty characters the most a line may run to.
/// This reads every panel file's own source with `CopyBudget.phrases(inSwift:)`
/// and fails any shown string over `CopyBudget.panelLine` characters or written
/// as a sentence. Hover tips are where an explanation goes, so they are not
/// held to it. There is no allowance: the last offenders went on 2026-09-27.
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

    /// The sections a video document shows, named so the scan is known to
    /// reach every one of them.
    static let videoFiles = [
        "SpeedInspector.swift", "SoundInspector.swift", "CaptionsInspector.swift",
        "TransitionInspector.swift", "MotionListInspector.swift", "PropertyKeysInspector.swift",
        "CompositingInspector.swift",
    ]

    static func overBudget(in file: String) throws -> [CopyBudget.Phrase] {
        let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
        return CopyBudget.phrases(inSwift: text)
            .filter { !$0.isTooltip && (CopyBudget.overPanelBudget($0.text) || CopyBudget.isSentence($0.text)) }
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
    func everyShownLineIsALabel(file: String) throws {
        let over = try Self.overBudget(in: file)
        #expect(over.isEmpty, """
            \(file) shows lines longer than \(CopyBudget.panelLine) characters, or sentences. Cut \
            each to a short label and move the reason into the control's hover tip (.panelHelp), \
            or into the section header's question mark: \(over.map { "line \($0.line): \($0.text)" })
            """)
    }
}
