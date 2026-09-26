import CoreGraphics
import Foundation

// A recording opens on a sharp first frame (`docs/design/video.md` §3, item 6).
//
// A frame is read at the size the canvas shows it (`MovieRef.decodePixelSize`),
// and the first one is asked for the moment a recording opens, before the
// canvas has fitted itself to the window. That read is small. The fit asks for
// the same frame again at full size a moment later, and a frame already being
// read used to be skipped outright, so the small read landed, was filed, and
// was drawn stretched until the playhead moved.
//
// So a read under way only answers for asks at its size or smaller: a bigger
// ask starts a read of its own, and whichever lands last never replaces a
// bigger picture with a smaller one.

/// Which frames are being read, and at what size, for one window.
///
/// Frame ids and widths only; the reading and the pixels are the app's.
public struct MovieFrameReads: Equatable, Sendable {

    /// The widest read under way for each frame.
    private var reading: [UUID: CGFloat] = [:]

    public init() {}

    /// Whether anything is reading this frame right now.
    public func isReading(_ frame: UUID) -> Bool { reading[frame] != nil }

    /// Whether to start reading `frame` at `width`, given the width it is
    /// already filed at (nil when it is not filed). A yes records the read as
    /// under way.
    ///
    /// A pixel of slack either way, since sizes come from rounding.
    public mutating func start(_ frame: UUID, width: CGFloat, filedWidth: CGFloat?) -> Bool {
        if let filedWidth, filedWidth >= width - 1 { return false }
        if let under = reading[frame], under >= width - 1 { return false }
        reading[frame] = width
        return true
    }

    /// A read of `frame` started at `width` finished with a picture
    /// `landedWidth` wide, or nil when the file gave nothing up. Answers
    /// whether to file it over what is filed now (`filedWidth`).
    public mutating func finish(_ frame: UUID, width: CGFloat, landedWidth: CGFloat?,
                                filedWidth: CGFloat?) -> Bool {
        // A bigger read that overtook this one is still under way and stays so.
        if reading[frame] == width { reading[frame] = nil }
        guard let landedWidth else { return false }
        if let filedWidth, filedWidth >= landedWidth { return false }
        return true
    }
}
