import CoreGraphics
import Foundation

/// Starting a picture from nothing: the sizes offered when a new window is
/// asked for a blank canvas, and the rules for a size typed by hand.
///
/// The list is deliberately short and UI-shaped rather than photo-shaped —
/// this is the front door for building interfaces, so the sizes are the
/// surfaces interfaces get built for.
public enum BlankCanvas {

    /// One offered starting size.
    public struct Preset: Hashable, Sendable, Identifiable {
        public let id: String
        /// What the picker shows, without the dimensions (the picker prints
        /// those from `size`, so the two can never disagree).
        public let title: String
        public let size: CGSize

        public init(id: String, title: String, size: CGSize) {
            self.id = id
            self.title = title
            self.size = size
        }
    }

    /// The smallest and largest side a canvas may have. The cap is a memory
    /// guard: the blank canvas is a real bitmap, and 8192 × 8192 is already
    /// 256 MB of pixels.
    public static let minimumSide: CGFloat = 1
    public static let maximumSide: CGFloat = 8192

    public static let presets: [Preset] = [
        Preset(id: "desktop", title: "Desktop", size: CGSize(width: 1440, height: 1024)),
        Preset(id: "phone", title: "Phone", size: CGSize(width: 390, height: 844)),
        Preset(id: "tablet", title: "Tablet", size: CGSize(width: 1024, height: 768)),
        Preset(id: "square", title: "Square", size: CGSize(width: 1000, height: 1000)),
    ]

    /// What the sheet opens on, so Return alone makes a canvas.
    public static let defaultPreset = presets[0]

    /// Where the canvas lands once a size has been chosen. Starting from
    /// nothing must never cost you the picture you were already looking at,
    /// and it must never leave a window nobody asked for, so the answer is
    /// simply whether the window that asked is already holding something.
    public enum Destination: Sendable, Equatable {
        /// Fill the window that asked. It is empty, so a second window would
        /// be one more thing to close.
        case thisWindow
        /// Open a new window. The asking window holds a picture, and that
        /// picture stays exactly as it was.
        case newWindow
    }

    /// The rule above, in one place, so every route to a blank canvas (the
    /// empty window's card, the File menu) agrees on where it lands.
    public static func destination(windowHasDocument: Bool) -> Destination {
        windowHasDocument ? .newWindow : .thisWindow
    }

    /// A typed size made safe to build: whole pixels, inside the legal range,
    /// and never NaN.
    public static func normalized(_ size: CGSize) -> CGSize {
        CGSize(width: clampSide(size.width), height: clampSide(size.height))
    }

    /// Whether a size can be used as typed — the Create button's enablement.
    public static func isValid(_ size: CGSize) -> Bool {
        normalized(size) == size
    }

    private static func clampSide(_ side: CGFloat) -> CGFloat {
        guard side.isFinite else { return minimumSide }
        return min(max(side.rounded(), minimumSide), maximumSide)
    }
}
