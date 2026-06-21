import CoreGraphics

/// A corner of a display, for placing floating overlays. Codable/Sendable so it
/// can become a user preference later (the Quick Access Overlay corner).
public enum ScreenCorner: String, Codable, Sendable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// Placement + entrance geometry for the post-capture Quick Access Overlay
/// (phase 11.7): a small floating thumbnail that appears in a screen corner
/// after every capture, then auto-closes.
///
/// Pure, testable core (mirrors `HistoryOverlayLayout`): given a display rect in
/// macOS bottom-left screen coordinates (pass `visibleFrame` so it clears the
/// menu bar + Dock), it yields the panel's resting frame in the chosen corner
/// and a `hiddenFrame` slid off the nearest horizontal edge for the slide-in.
/// The AppKit shell just animates between the two while fading alpha.
public struct QuickAccessLayout: Equatable, Sendable {
    /// The panel rect at rest, inset into the chosen corner.
    public let restingFrame: CGRect
    /// Off-screen start/end for the entrance/exit slide (below for bottom
    /// corners, above for top corners; same x as `restingFrame`).
    public let hiddenFrame: CGRect

    /// - Parameters:
    ///   - screen: the target display's frame (use `visibleFrame`), bottom-left
    ///     origin. Non-zero origins (secondary displays) are honored.
    ///   - size: the panel size.
    ///   - corner: which corner to dock into.
    ///   - margin: gap from both screen edges of the corner.
    public init(screen: CGRect,
                size: CGSize,
                corner: ScreenCorner = .bottomLeft,
                margin: CGFloat = 24) {
        let x: CGFloat
        switch corner {
        case .topLeft, .bottomLeft: x = screen.minX + margin
        case .topRight, .bottomRight: x = screen.maxX - size.width - margin
        }
        let y: CGFloat
        switch corner {
        case .bottomLeft, .bottomRight: y = screen.minY + margin
        case .topLeft, .topRight: y = screen.maxY - size.height - margin
        }
        restingFrame = CGRect(x: x, y: y, width: size.width, height: size.height)

        let hiddenY: CGFloat
        switch corner {
        case .bottomLeft, .bottomRight: hiddenY = screen.minY - size.height // fully below
        case .topLeft, .topRight: hiddenY = screen.maxY                     // fully above
        }
        hiddenFrame = CGRect(x: x, y: hiddenY, width: size.width, height: size.height)
    }
}
