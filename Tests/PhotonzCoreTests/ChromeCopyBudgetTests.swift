import Foundation
import Testing
@testable import PhotonzCore

/// The chrome outside the panel shows labels and values, never sentences
/// (`no-sentences-or-debug-readouts-anywhere-in-the-c`, 2026-09-25).
///
/// The user, pointing at the timeline bar's "Playhead no animated property @
/// 0.00s": "I don't like how you're throwing big sentences into the ui like
/// this... completely unprofessional ux." `PanelCopyBudgetTests` only read
/// the panel, so the timeline, transport, tool bar, canvas overlays,
/// popovers and empty states were never checked. This reads them with
/// `CopyBudget.phrases(inSwift:)` and fails any shown string that breaks
/// `CopyBudget.chromeFaults`: over `CopyBudget.chromeLine` characters, a
/// sentence, a debug reading ("@", raw ms), a "no X" or a bracketed
/// explanation. Hover tips, walk probes and screen-reader words are not
/// drawn, so they are not held to it.
///
/// `allowed` is the shrink-only list of what was already there outside the
/// video surfaces, known by its opening forty characters. The video surfaces
/// may never appear on it.
@Suite("Chrome copy is labels and values")
struct ChromeCopyBudgetTests {

    static var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Photonz")
    }

    /// The video editor's chrome: the timeline dock and everything drawn in
    /// it, the transition picker, and the drop label. None may carry an
    /// allowance.
    static let videoFiles = [
        "TimelineDock.swift", "TimelineTrackRows.swift", "ClipPiecesBar.swift", "KeyLanesView.swift",
        "CaptionWordsLane.swift", "CaptionCuesLayer.swift", "CaptionWordField.swift", "SoundLane.swift",
        "CutStrip.swift", "TimelineZoomBar.swift", "TimelineLaneDrop.swift", "TransitionPicker.swift",
        "EditorState+TimelineDrop.swift", "PlaybackScrubber.swift", "TrimTimeline.swift",
        "CanvasMotionPath.swift", "MotionStripView.swift", "VideoEditorView.swift",
        "VideoPreviewView.swift",
        "VideoKit/VideoKit.swift", "VideoKit/VideoKitControls.swift", "VideoKit/VideoKitPicker.swift",
        "VideoKit/VideoKitRulerMark.swift", "VideoKit/VideoKitTimeline.swift",
        "VideoKit/VideoKitTransport.swift",
    ]

    /// Files that draw no chrome of their own: state, dialogs (a macOS
    /// alert speaks in sentences), stores and app plumbing.
    static func isChromeFile(_ name: String) -> Bool {
        guard name.hasSuffix(".swift"), !PanelCopyBudgetTests.isPanelFile(name) else { return false }
        let plumbing = ["EditorState", "Dialog", "Store", "Experiments", "AppCoordinator", "Updater",
                        "UpdateChecker", "OpenSourceNotices", "AppInfo", "AppRelauncher", "WindowController",
                        "PhotonzApp", "WindowCloseConfirmation", "EditorCommands", "VideoEditorState",
                        "MainMenuState"]
        return !plumbing.contains { name.hasPrefix($0) || name.contains($0) }
    }

    static var chromeFiles: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: sources.path)) ?? []
        let kit = ((try? FileManager.default.contentsOfDirectory(
            atPath: sources.appendingPathComponent("VideoKit").path)) ?? []).map { "VideoKit/\($0)" }
        let found = names.filter(isChromeFile) + kit.filter { $0.hasSuffix(".swift") }
        return Array(Set(found + videoFiles)).sorted()
    }

    /// Over the rules on 2026-09-25, outside the video surfaces. All of them
    /// are shared with Current (`the-shared-chrome-says-labels-not-sentences`).
    static let allowed: [String: [String]] = [
        "EditorView.swift": ["Drop a photo or screenshot here"],
        "LayersListView.swift": ["No layer says that"],
        "TitlebarModeChip.swift": [
            "hands every folded section back and leav",
            "puts this mode back the way it shipped",
            "A mode folds the panel down to what one ",
        ],
        "HistoryOverlay.swift": [
            "No captures yet. ⇧⌘4 grabs a rectangle, ",
            "No captures yet.",
            "No screenshots yet.",
            "No videos yet.",
            "Photonz needs Screen Recording access to",
        ],
        "DesignedColorPicker.swift": ["Nothing painted yet.", "Nothing picked yet."],
        "VideoCropOverlay.swift": ["Drag to select the area to keep"],
    ]

    static func offenders(in file: String) throws -> [(phrase: CopyBudget.Phrase, faults: [CopyBudget.ChromeFault])] {
        let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
        return CopyBudget.phrases(inSwift: text)
            .filter { !$0.isTooltip && !CopyBudget.isIdentifier($0.text) && $0.text.contains(where: \.isLetter) }
            .map { ($0, CopyBudget.chromeFaults($0.text)) }
            .filter { !$0.1.isEmpty }
    }

    @Test func theChromeFilesAreFound() {
        let files = Self.chromeFiles
        #expect(files.count >= 60, "found only \(files)")
        for known in Self.videoFiles + ["EditorView.swift", "ToolModeButton.swift", "HistoryOverlay.swift",
                                        "CanvasDragReadout.swift", "ToastController.swift"] {
            #expect(files.contains(known), "\(known) is not read")
        }
        #expect(!files.contains("InspectorPanel.swift"), "the panel has its own budget")
    }

    @Test(arguments: chromeFiles)
    func everyShownStringIsALabel(file: String) throws {
        let allowed = Set(Self.allowed[file] ?? [])
        let new = try Self.offenders(in: file).filter { !allowed.contains(CopyBudget.key($0.phrase.text)) }
        #expect(new.isEmpty, """
            \(file) puts words in the chrome that are not a label or a value. Make each a short label \
            (\(CopyBudget.chromeLine) characters at most), or show nothing, and move any reason into \
            the hover tip (.panelHelp): \
            \(new.map { "line \($0.phrase.line) [\($0.faults.map(\.rawValue).joined(separator: ","))]: \($0.phrase.text)" })
            """)
    }

    @Test(arguments: chromeFiles)
    func theAllowanceOnlyShrinks(file: String) throws {
        let still = Set(try Self.offenders(in: file).map { CopyBudget.key($0.phrase.text) })
        let fixed = (Self.allowed[file] ?? []).filter { !still.contains($0) }
        #expect(fixed.isEmpty, "\(file) no longer says these, so strike them off `allowed`: \(fixed)")
    }

    @Test func everyAllowanceNamesAChromeFile() {
        #expect(Set(Self.allowed.keys).subtracting(Self.chromeFiles).isEmpty)
    }

    @Test func theVideoSurfacesHaveNoAllowance() {
        for file in Self.videoFiles {
            #expect(Self.allowed[file] == nil, "\(file) is a video surface and may not break the rules")
        }
    }
}
