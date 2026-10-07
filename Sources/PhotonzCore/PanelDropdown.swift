import CoreGraphics
import Foundation

/// A list that opens over the panel rather than in a window of its own beside
/// it, the mock's `.propPick` (`video.html`): Animate a property's picker.
/// Where it sits, and what a key does to its find box, which reads the keys
/// itself rather than taking the window's keyboard (`PanelPopover.swift`).
public enum PanelDropdown {
    /// The mock's 8pt (`--s2`) between the list and the panel's sides.
    public static let inset: CGFloat = 8

    /// At the top of what it opens over, pushed down when that top has
    /// scrolled away, up when its foot would hang off the bottom, never taller
    /// than the panel, and inside the panel's sides. `height` is the most it
    /// grows to; `over` is in the panel's coordinates, `panel` its size.
    public static func frame(over: CGRect, in panel: CGSize, height: CGFloat) -> CGRect {
        let left = max(over.minX, 0) + inset
        let right = min(over.maxX, panel.width) - inset
        let tall = max(0, min(height, panel.height - inset * 2))
        let top = min(max(over.minY, inset), panel.height - inset - tall)
        return CGRect(x: left, y: max(inset, top), width: max(0, right - left), height: tall)
    }

    /// What a key does to the find box.
    public enum Key: Equatable, Sendable {
        case text(String)
        case deleteBackward
        case submit
    }

    /// Delete, Return and Enter by their key codes; anything else types what
    /// it prints. A control character, an arrow, or a page or function key
    /// (U+F700 to U+F8FF) types nothing.
    public static func key(keyCode: UInt16, characters: String) -> Key? {
        switch keyCode {
        case 51: return .deleteBackward
        case 36, 76: return .submit
        default:
            let printable = characters.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
            }
            return printable.isEmpty ? nil : .text(String(String.UnicodeScalarView(printable)))
        }
    }

    /// The query after a key. Pasted line breaks read as spaces.
    public static func apply(_ key: Key, to query: inout String) {
        switch key {
        case let .text(typed):
            query += typed.split(whereSeparator: \.isNewline).joined(separator: " ")
        case .deleteBackward:
            if !query.isEmpty { query.removeLast() }
        case .submit:
            break
        }
    }
}
