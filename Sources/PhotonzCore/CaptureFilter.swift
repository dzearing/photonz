import Foundation

/// The history overlay's segmented filter: show everything, only screenshots, or
/// only recordings. Pure list policy so the segmented control and its filtering
/// are testable away from SwiftUI.
public enum CaptureFilter: String, CaseIterable, Hashable, Sendable, Codable {
    case all
    case screenshots
    case videos

    /// Segment label (plain, human copy).
    public var title: String {
        switch self {
        case .all: return "All"
        case .screenshots: return "Screenshots"
        case .videos: return "Videos"
        }
    }

    /// Whether a capture of this kind survives the filter.
    public func matches(_ kind: CaptureKind) -> Bool {
        switch self {
        case .all: return true
        case .screenshots: return kind == .image
        case .videos: return kind == .video
        }
    }

    /// The entries that pass the filter, order preserved.
    public func apply(to entries: [CaptureEntry]) -> [CaptureEntry] {
        entries.filter { matches($0.kind) }
    }
}

/// Keyboard selection math for the history strip: moving Left/Right and keeping
/// the index valid as the list changes. Pure so it's testable; the view owns the
/// `@State`.
public enum HistorySelection {
    /// Move the selection within `[0, count)`. A `nil` starting index (nothing
    /// selected yet) lands on the first item; the result is clamped to the ends
    /// (no wraparound). Returns `nil` for an empty list.
    public static func move(_ index: Int?, by delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let index else { return 0 }
        let next = index + delta
        return min(max(0, next), count - 1)
    }

    /// Keep an index valid after the list changes (e.g. an item was deleted).
    /// Returns `nil` when the list is empty or there was no selection.
    public static func clamp(_ index: Int?, count: Int) -> Int? {
        guard count > 0, let index else { return nil }
        return min(max(0, index), count - 1)
    }
}
