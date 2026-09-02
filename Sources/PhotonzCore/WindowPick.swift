import CoreGraphics
import Foundation

/// One window as the window server describes it, in whatever coordinate space
/// the caller chose (the capture overlay uses each display's own top-left
/// points space, the same space its selection rectangle lives in).
public struct ScreenWindow: Hashable, Sendable, Codable {
    /// The window server's id for the window.
    public var id: Int
    public var frame: CGRect
    /// The window server's layer: 0 is a normal app window; the menu bar, the
    /// Dock, menus and floating panels sit on other layers.
    public var layer: Int
    public var alpha: Double
    /// The owning app's name, for the highlight's label. Empty when unknown.
    public var ownerName: String

    public init(id: Int, frame: CGRect, layer: Int, alpha: Double, ownerName: String = "") {
        self.id = id
        self.frame = frame
        self.layer = layer
        self.alpha = alpha
        self.ownerName = ownerName
    }
}

/// Capture a window by clicking it: which window sits under the pointer during
/// a region capture, what a click (as opposed to a drag) is, and what the
/// highlight says about the window it found.
public enum WindowPick {

    /// Windows narrower or shorter than this are helper specks, never
    /// something a person meant to capture.
    public static let minimumSide: CGFloat = 8

    /// How far the pointer may travel between press and release and still be
    /// a click on the window under it rather than the start of a region drag.
    public static let dragThreshold: CGFloat = 4

    /// The frontmost pickable window containing `point`. `windows` is
    /// front-to-back, the order the window server lists them in. `excluding`
    /// names windows that can never be the answer, such as the capture
    /// overlay's own full-screen shield panels.
    public static func frontmost(at point: CGPoint, in windows: [ScreenWindow],
                                 excluding: Set<Int> = []) -> ScreenWindow? {
        windows.first { isPickable($0, excluding: excluding) && $0.frame.contains(point) }
    }

    /// A normal-layer, visible, non-excluded window big enough to mean something.
    public static func isPickable(_ window: ScreenWindow, excluding: Set<Int> = []) -> Bool {
        window.layer == 0
            && window.alpha > 0
            && !excluding.contains(window.id)
            && window.frame.width >= minimumSide
            && window.frame.height >= minimumSide
    }

    /// Whether a press at `from` released at `to` counts as a click.
    public static func isClick(from: CGPoint, to: CGPoint) -> Bool {
        abs(to.x - from.x) < dragThreshold && abs(to.y - from.y) < dragThreshold
    }

    /// The part of `window` that exists on a display with `bounds`, snapped to
    /// whole points so the crop lands on pixel boundaries. Nil when the window
    /// is not on that display at all.
    public static func captureRect(for window: ScreenWindow, within bounds: CGRect) -> CGRect? {
        let visible = window.frame.integral.intersection(bounds)
        guard !visible.isNull, visible.width >= 1, visible.height >= 1 else { return nil }
        return visible
    }

    /// "Safari  1440 × 900", or just the size when the owner is unknown.
    public static func label(for window: ScreenWindow) -> String {
        let size = sizeLabel(for: window.frame.size)
        let owner = window.ownerName.trimmingCharacters(in: .whitespaces)
        return owner.isEmpty ? size : "\(owner)  \(size)"
    }

    /// "1440 × 900", in whole points.
    public static func sizeLabel(for size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }

    /// Where the highlight's label goes: tucked inside the window's top-left
    /// corner when it fits, otherwise just below the window, or above it when
    /// the window sits at the bottom of the display. Always kept on the display.
    public static func labelOrigin(for frame: CGRect, labelSize: CGSize, inset: CGFloat,
                                   within bounds: CGRect) -> CGPoint {
        var origin: CGPoint
        if frame.width >= labelSize.width + inset * 2, frame.height >= labelSize.height + inset * 2 {
            origin = CGPoint(x: frame.minX + inset, y: frame.minY + inset)
        } else if frame.maxY + inset + labelSize.height <= bounds.maxY {
            origin = CGPoint(x: frame.minX, y: frame.maxY + inset)
        } else {
            origin = CGPoint(x: frame.minX, y: frame.minY - inset - labelSize.height)
        }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - labelSize.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - labelSize.height)
        return origin
    }
}
