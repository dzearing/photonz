import Foundation

/// The app's system-wide capture shortcuts, by what they do rather than by
/// key, so the rule about what each one does to the corner is one table.
///
/// The user, 2026-10-02: "if I press [the capture shortcuts], please clear the
/// toast. The toasts are fine to show but if I'm trying to take a screenshot or
/// video or open last session, they're just noise." A toast left in the corner
/// is in the frozen picture a region capture drags over, in a full-screen shot
/// and in the first frame of a recording.
public enum CaptureHotkey: String, CaseIterable, Sendable, Codable {
    /// ⇧⌘3
    case captureFullScreen
    /// ⇧⌘4
    case captureRegion
    /// ⇧⌘5: open the recording setup, or stop a recording in progress.
    case record
    /// ⇧⌘6: open the newest capture in an editor.
    case editLastCapture
    /// ⌃⇧F5
    case stopRecording
    /// ⇧⌘H
    case toggleHistory

    /// Whether pressing it takes every toast down first. Stopping a recording
    /// is about to say something in the corner itself, and history is not a
    /// capture, so both leave the corner as it is.
    public var clearsToasts: Bool {
        switch self {
        case .captureFullScreen, .captureRegion, .record, .editLastCapture: true
        case .stopRecording, .toggleHistory: false
        }
    }

    /// The ⇧⌘ number-row family a person names a shortcut by: "3" to "6".
    public init?(digit: String) {
        switch digit {
        case "3": self = .captureFullScreen
        case "4": self = .captureRegion
        case "5": self = .record
        case "6": self = .editLastCapture
        default: return nil
        }
    }
}

/// Which toasts are still wanted after the corner has been cleared.
///
/// Some toasts are asked for now and shown later: a save's progress bar after
/// its quiet window, a GIF's "copied" once the encode lands, a recording's
/// "still being saved" while its file closes. Clearing the corner for a capture
/// has to stop those too, or one pops up a beat later inside the picture. Work
/// that will say something takes a `ticket` when it starts; the corner shows it
/// only if nothing was cleared in between. A toast asked for after the clear,
/// the capture's own "Copied to clipboard!" included, shows as normal.
public struct ToastHush: Sendable, Equatable {
    public struct Ticket: Sendable, Equatable {
        fileprivate let clears: Int
    }

    private var clears = 0

    public init() {}

    /// What a toast asked for right now carries.
    public var ticket: Ticket { Ticket(clears: clears) }

    /// The corner was cleared: every ticket handed out before now goes stale.
    public mutating func clear() { clears += 1 }

    /// Whether a toast asked for with `ticket` should still be shown.
    public func stillWanted(_ ticket: Ticket) -> Bool { ticket.clears == clears }
}
