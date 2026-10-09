import CoreGraphics
import Foundation

/// Identity for an editor window. The editor is a value-based
/// `WindowGroup(for: EditorWindowID.self)`: `openWindow(value:)` with an id that
/// is already on screen **reuses that window** (giving "focus the existing
/// window editing this image" for free — see phase 11.5), and opens a fresh one
/// otherwise. `AppCoordinator` opens windows by handing one of these to SwiftUI.
///
/// The cases are the things an editor window can hold:
/// - `.file` — an image or `.photonz` package opened from disk, including
///   captures (which are now plain files in the capture folder), keyed by URL so
///   re-opening the same file focuses its window.
/// - `.fresh` — a brand-new empty document (shows the onboarding card); a
///   unique id means every New opens its own window.
/// - `.clipboard` — a new window seeded from the clipboard image (⌘N, Preview
///   convention); unique id per invocation.
/// - `.video` — a recording opened in the in-app video editor (phase 13.3),
///   keyed by URL so re-opening the same recording focuses its window.
/// - `.blankCanvas` — a window that starts from nothing (File ▸ New Blank
///   Canvas). A size means the canvas is already decided and the window is
///   born holding it; `nil` means the window opens and asks for the size
///   itself, which is the fallback for asking from a window that has no
///   canvas to hang the question on.
/// - `.blankVideo` — a window that starts a video from nothing (File ▸ New
///   Video): the same rule as `.blankCanvas`, with the length in
///   milliseconds beside the size.
/// - `.uiDesign` — a window that starts a UI design (File ▸ New UI Design):
///   born holding the Design UI starter, a canvas with a Login frame on it.
/// - `tutorial` — a window a guide opened for itself, holding the guide's own
///   sample picture. A guide never teaches over your work: it brings something
///   of its own to point at. The string is the guide's id, so the window knows
///   which sample to put in it and which guide to start once it is up.
enum EditorWindowID: Hashable, Codable, Sendable {
    case file(URL)
    case fresh(UUID)
    case clipboard(UUID)
    case video(URL)
    case blankCanvas(UUID, CGSize?)
    case blankVideo(UUID, CGSize?, Int)
    case uiDesign(UUID)
    case tutorial(UUID, String)

    /// A video-editor id for `url`, standardized so the same recording always
    /// hashes to the same window (re-opening focuses rather than duplicates),
    /// mirroring how `.file` round-trips capture URLs.
    static func video(standardizing url: URL) -> EditorWindowID {
        .video(url.standardizedFileURL)
    }
}
