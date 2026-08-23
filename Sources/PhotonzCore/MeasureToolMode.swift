import CoreGraphics
import Foundation

/// What the Measure tool does when you click. The mode is always visible in the
/// tool options and it is the ONLY thing that decides whether anything is drawn
/// under the pointer, so nothing ever appears on the canvas unasked.
///
/// The names say what you GET, not what the app does: a distance between two
/// points you pick, the size of the thing you point at, the gap between two
/// things. `alignment` is the odd one out (it checks rather than measures) and
/// only appears when its flag is on.
public enum MeasureToolMode: String, CaseIterable, Hashable, Codable, Sendable {
    /// The two-point caliper: click a point, click another, click to place the
    /// head. The default, and the only mode that draws no live chrome.
    case distance
    /// The element under the pointer, committed by a click: one width caliper
    /// and one height caliper, in a single undo step.
    case size
    /// The whitespace under the pointer: one caliper across the shorter of the
    /// two spans through the click point.
    case gap
    /// A dashed guide that checks everything it crosses (`next-measure-align`).
    case alignment

    public var title: String {
        switch self {
        case .distance: "Distance"
        case .size: "Size"
        case .gap: "Gap"
        case .alignment: "Alignment"
        }
    }

    /// The glyph the tool button wears while this mode is live (D15: the tool
    /// button shows the active mode, so the bar says what a click will do
    /// without spending a word of text on it). Distance keeps the ruler, since
    /// it is both the default and the tool's own identity.
    public var symbol: String {
        switch self {
        case .distance: "ruler"
        case .size: "arrow.up.and.down.and.arrow.left.and.right"
        case .gap: "arrow.left.and.right"
        case .alignment: "align.horizontal.left"
        }
    }

    /// The tooltip on the tool button, and the line the flyout's row carries:
    /// what a click does in this mode.
    public var help: String {
        switch self {
        case .distance: "Distance: click two points, then click to place the readout"
        case .size: "Size: click the element under the pointer for its width and height"
        case .gap: "Gap: click in the space between two elements for the gap"
        case .alignment: "Alignment: drag a guide along an edge to check everything it crosses"
        }
    }

    /// The first-run hint chip, which lives until the document's first
    /// measurement lands. One short line, phrased as the next thing to do.
    public var hint: String {
        switch self {
        case .distance: "Click two points for a live distance"
        case .size: "Click an element for its width and height. [ and ] pick a smaller or larger one"
        case .gap: "Click in the space between two elements for the gap"
        case .alignment: "Drag a guide along an edge to check what it crosses"
        }
    }

    /// Whether this mode draws a live preview of what a click would commit.
    /// Distance draws nothing under an idle pointer — that is the whole point of
    /// it being the default.
    public var previewsUnderPointer: Bool { self == .size || self == .gap }

    /// Whether a single click commits a whole measurement (no multi-step
    /// placement, no drag).
    public var commitsOnClick: Bool { self == .size || self == .gap }

    /// Whether the `[` / `]` keys grow and shrink the detected pick.
    public var picksAmongCandidates: Bool { self == .size }

    /// The modes offered in the tool button's flyout, in cycle order. Alignment
    /// is gated on its own flag; the other three are always there, so the
    /// current mode is always reachable in at most three presses of the key.
    public static func available(alignmentEnabled: Bool) -> [MeasureToolMode] {
        alignmentEnabled ? [.distance, .size, .gap, .alignment] : [.distance, .size, .gap]
    }

    /// The next mode the tool key lands on (D15: the keyboard is the fast path,
    /// so pressing the tool's own key again cycles rather than re-picking a tool
    /// that is already in hand). Wraps around, and a mode that is no longer
    /// offered falls back to the default rather than sticking.
    public func cycled(alignmentEnabled: Bool) -> MeasureToolMode {
        let modes = Self.available(alignmentEnabled: alignmentEnabled)
        guard let index = modes.firstIndex(of: self) else { return modes[0] }
        return modes[(index + 1) % modes.count]
    }
}
