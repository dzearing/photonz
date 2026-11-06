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

    /// The icon sizes: a glyph drawn on a 24 point grid at 512, and an app
    /// icon. Offered where icon frames are, since the rest of the icon tools
    /// are what make these two sizes worth a row of their own.
    public static let iconPresets: [Preset] = [
        Preset(id: "icon", title: "Icon", size: CGSize(width: 512, height: 512)),
        Preset(id: "app-icon", title: "App Icon", size: CGSize(width: 1024, height: 1024)),
    ]

    /// The list the sheet shows.
    public static func presets(withIcons: Bool) -> [Preset] {
        withIcons ? presets + iconPresets : presets
    }

    /// Whether this row of the sheet makes an icon rather than a picture that
    /// happens to be square (`PhotonzDocument.madeAsIcon`).
    public static func makesAnIcon(presetID: String) -> Bool {
        iconPresets.contains { $0.id == presetID }
    }

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
    ///
    /// The front door New Window opens is the one empty window that never
    /// fills itself: it is a small launcher holding no document, so what it
    /// makes opens in an editor window of its own and the front door closes
    /// (`ui-entry-wt.html`, steps 4 and 5).
    public static func destination(windowHasDocument: Bool, isFrontDoor: Bool = false) -> Destination {
        windowHasDocument || isFrontDoor ? .newWindow : .thisWindow
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
