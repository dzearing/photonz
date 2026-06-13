import CoreGraphics

/// Arrow-key nudging for the selected layer: 1pt per press, 10pt with ⇧
/// (macOS convention). Deltas are in document coordinates (y grows down).
public enum Nudge {
    /// The move for a key press, or nil when the key is not an arrow.
    /// Key codes: 123 ←, 124 →, 125 ↓, 126 ↑.
    public static func delta(keyCode: UInt16, large: Bool) -> CGVector? {
        let step: CGFloat = large ? 10 : 1
        switch keyCode {
        case 123: return CGVector(dx: -step, dy: 0)
        case 124: return CGVector(dx: step, dy: 0)
        case 125: return CGVector(dx: 0, dy: step)
        case 126: return CGVector(dx: 0, dy: -step)
        default: return nil
        }
    }
}
