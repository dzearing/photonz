import CoreGraphics
import Foundation

/// A clicked window captured the way the built-in macOS window capture does
/// it: rendered on its own by the window server, with its drop shadow around
/// it and see-through rounded corners, instead of a rectangle cut out of the
/// frozen screen picture with the desktop showing through the corners.
///
/// This decides which look a click asks for and whether what came back is a
/// faithful shot of the window. The capture itself is the app layer's job.
public enum WindowShot {

    public enum Style: Sendable, Equatable {
        /// The window and its shadow, transparent around and in the corners.
        case withShadow
        /// The window's own bounds only, transparent in the corners.
        case bareBounds
    }

    /// Which look a click asks for. `includeShadow` is the setting; holding
    /// Option while clicking gives the other choice, the way Option drops the
    /// shadow in the built-in capture.
    public static func style(includeShadow: Bool, optionHeld: Bool) -> Style {
        (includeShadow != optionHeld) ? .withShadow : .bareBounds
    }

    /// Pixels of rounding a shot may miss the window by and still be the window.
    public static let tolerance: CGFloat = 1

    /// Whether an image `pixelSize` big is a faithful shot of a window
    /// `windowSize` points wide at `scale` pixels per point. A bare shot must
    /// cover the whole window (bigger is fine: a sheet may hang outside it). A
    /// shadowed shot must be larger than the window in both directions, since
    /// a shadow adds margin on every side; one that comes back at the window's
    /// own size had the shadow squeezed inside, shrinking the window, or
    /// dropped, and is not the shot that was asked for.
    public static func isFaithful(pixelSize: CGSize, windowSize: CGSize, scale: CGFloat,
                                  style: Style) -> Bool {
        guard pixelSize.width > 0, pixelSize.height > 0,
              windowSize.width > 0, windowSize.height > 0, scale > 0 else { return false }
        let wanted = CGSize(width: (windowSize.width * scale).rounded(),
                            height: (windowSize.height * scale).rounded())
        switch style {
        case .bareBounds:
            return pixelSize.width >= wanted.width - tolerance
                && pixelSize.height >= wanted.height - tolerance
        case .withShadow:
            return pixelSize.width > wanted.width + tolerance
                && pixelSize.height > wanted.height + tolerance
        }
    }
}
