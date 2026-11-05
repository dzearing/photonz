import Foundation

/// The state of each system-wide capture shortcut, and what to say about it.
///
/// A shortcut Photonz cannot answer fails in the quietest way there is. With
/// macOS's own ⇧⌘3 or ⇧⌘4 still on, which is how every Mac ships, the key takes
/// a picture and saves it to the Desktop, and the clipboard never moves: to the
/// person that reads as Photonz failing to copy. So each key's state is shown
/// (Settings), and a problem is said once in the corner with the way to fix it.
public enum CaptureShortcutReport {

    public enum State: String, Equatable, Sendable {
        case ready
        /// macOS's own screenshot shortcut takes the key before any app.
        case heldByMacOS
        /// macOS refused the registration, usually because another app has it.
        case notRegistered
        /// Another running copy of Photonz answers it (`CaptureShortcutOwner`).
        case anotherPhotonz

        public var label: String {
            switch self {
            case .ready: "Ready"
            case .heldByMacOS: "Held by macOS"
            case .notRegistered: "Not registered"
            case .anotherPhotonz: "Another Photonz answers"
            }
        }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        public let hotkey: CaptureHotkey
        public let state: State

        public var id: String { hotkey.rawValue }
        public var name: String { CaptureShortcutReport.name(of: hotkey) }
        public var keys: String { CaptureShortcutReport.keys(of: hotkey) }
    }

    public struct Notice: Equatable, Sendable {
        public let title: String
        public let detail: String
        /// The button that opens the Mac's Keyboard Shortcuts pane.
        public let action: String
    }

    public static func rows(answersHere: Bool, failed: Set<CaptureHotkey>,
                            macOSHolds: [SystemScreenshotShortcuts.Shortcut]) -> [Row] {
        let held = Set(macOSHolds.map(hotkey(for:)))
        return CaptureHotkey.allCases.map { hotkey in
            let state: State
            if held.contains(hotkey) {
                state = .heldByMacOS
            } else if !answersHere {
                state = .anotherPhotonz
            } else {
                state = failed.contains(hotkey) ? .notRegistered : .ready
            }
            return Row(hotkey: hotkey, state: state)
        }
    }

    /// What is wrong, as words that can be remembered between launches so each
    /// thing is said once. A copy that does not answer the keys has nothing to
    /// say: the copy that does says it.
    public static func problems(in rows: [Row]) -> Set<String> {
        guard !rows.contains(where: { $0.state == .anotherPhotonz }) else { return [] }
        return Set(rows.filter { $0.state == .heldByMacOS || $0.state == .notRegistered }
            .map { "\($0.hotkey.rawValue):\($0.state.rawValue)" })
    }

    /// What to say, or nil when every problem has been said already.
    public static func notice(for rows: [Row], alreadyTold: Set<String>) -> Notice? {
        guard !problems(in: rows).subtracting(alreadyTold).isEmpty else { return nil }
        let held = rows.filter { $0.state == .heldByMacOS }
        let failed = rows.filter { $0.state == .notRegistered }
        // macOS's keys first: they are the ones that lose a picture.
        if !held.isEmpty {
            let shots = held.filter { $0.hotkey == .captureFullScreen || $0.hotkey == .captureRegion }
            let detail: String
            if shots.isEmpty {
                detail = held.count == 1 ? "Photonz won't get that key" : "Photonz won't get those keys"
            } else {
                detail = shots.count == 1 ? "That shot skips the clipboard" : "Those shots skip the clipboard"
            }
            return Notice(title: "macOS holds " + held.map(\.keys).joined(separator: ", "),
                          detail: detail, action: settingsAction)
        }
        let names = failed.count <= 2
            ? failed.map(\.keys).joined(separator: ", ")
            : "\(failed.count) capture keys"
        return Notice(title: "\(names) didn't register",
                      detail: failed.count == 1 ? "Another app may hold it" : "Another app may hold them",
                      action: settingsAction)
    }

    public static let settingsAction = "Keyboard Settings"

    private static func hotkey(for shortcut: SystemScreenshotShortcuts.Shortcut) -> CaptureHotkey {
        switch shortcut {
        case .fullScreen: .captureFullScreen
        case .region: .captureRegion
        case .toolbar: .record
        case .touchBar: .editLastCapture
        }
    }

    private static func keys(of hotkey: CaptureHotkey) -> String {
        switch hotkey {
        case .captureFullScreen: "⇧⌘3"
        case .captureRegion: "⇧⌘4"
        case .record: "⇧⌘5"
        case .editLastCapture: "⇧⌘6"
        case .stopRecording: "⌃⇧F5"
        case .toggleHistory: "⇧⌘H"
        }
    }

    private static func name(of hotkey: CaptureHotkey) -> String {
        switch hotkey {
        case .captureFullScreen: CaptureMenuNames.captureFullScreen
        case .captureRegion: CaptureMenuNames.captureRegion
        case .record: CaptureMenuNames.startRecording
        case .editLastCapture: CaptureMenuNames.editLastCapture
        case .stopRecording: CaptureMenuNames.stopRecording
        case .toggleHistory: CaptureMenuNames.history
        }
    }
}
