import CoreGraphics
import Foundation

/// The heading of a group in the dock, the way every mock draws `.dgrp-h`
/// (`docs/design/mocks/shared/components/dock.css`): a chevron, a small caps
/// title in the faint ink, a chip right beside it saying what the group holds
/// (`Title`, `Media`, `2`), and the group's own buttons at the far edge. There
/// is no grip: the header itself is what you drag to reorder.
///
/// Next only (`next-dock-headers`). The app draws it; the words and numbers
/// live here so they can be tested.
public enum DockGroupHeader {
    /// `font-size:10px`.
    public static let titleSize: CGFloat = 10
    /// `letter-spacing:.09em`, in points at `titleSize`.
    public static let titleTracking: CGFloat = titleSize * 0.09
    /// The chip's `padding:1px 6px`.
    public static let chipHorizontalPadding: CGFloat = 6
    public static let chipVerticalPadding: CGFloat = 1

    /// The title in capitals, as `text-transform:uppercase` sets it.
    public static func title(_ name: String) -> String {
        name.uppercased(with: Locale(identifier: "en_US_POSIX"))
    }

    /// A chip that counts: the number, or no chip at all when there is nothing
    /// to count, because an empty group says so by being empty.
    public static func countChip(_ count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }

    /// A chip that names something: the word, or no chip when there is none.
    public static func chip(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
