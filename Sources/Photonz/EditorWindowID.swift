import Foundation

/// Identity for an editor window. The editor is a value-based
/// `WindowGroup(for: EditorWindowID.self)`: `openWindow(value:)` with an id that
/// is already on screen **reuses that window** (giving "focus the existing
/// window editing this image" for free — see phase 11.5), and opens a fresh one
/// otherwise. `AppCoordinator` opens windows by handing one of these to SwiftUI.
///
/// The three cases are the three things an editor window can hold:
/// - `.capture` — a screenshot from the `CaptureStore` history (keyed by its
///   `CaptureEntry` id, so re-editing the same capture focuses its window).
/// - `.file` — an image or `.photonz` package opened from disk (keyed by URL,
///   so re-opening the same file focuses its window).
/// - `.fresh` — a brand-new empty document (shows the onboarding card); a
///   unique id means every New opens its own window.
/// - `.clipboard` — a new window seeded from the clipboard image (⌘N, Preview
///   convention); unique id per invocation.
enum EditorWindowID: Hashable, Codable, Sendable {
    case capture(UUID)
    case file(URL)
    case fresh(UUID)
    case clipboard(UUID)
}
