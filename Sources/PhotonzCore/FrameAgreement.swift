import Foundation

/// How far a frame the canvas is showing is from the same document drawn from
/// scratch. The canvas patches its picture in place as things move, so a part
/// it forgot to draw again keeps an earlier frame's pixels; a fresh render has
/// no earlier frame to keep. A walk compares the two on every move of a drag
/// (`expectFresh`), and anything left behind shows up as pixels that differ.
public enum FrameAgreement {

    /// The share of pixels, 0 to 1, where any channel of `shown` is more than
    /// `tolerance` away from `fresh`. Both are four bytes a pixel, the same
    /// size and order. Frames that are not the same size never agree, and
    /// neither do empty ones, since there is nothing to have checked.
    public static func differingShare(_ shown: [UInt8], _ fresh: [UInt8], tolerance: Int = 8) -> Double {
        guard shown.count == fresh.count, shown.count >= 4 else { return 1 }
        let pixels = shown.count / 4
        var differing = 0
        shown.withUnsafeBufferPointer { a in
            fresh.withUnsafeBufferPointer { b in
                var index = 0
                while index + 3 < a.count {
                    for channel in 0..<4 where abs(Int(a[index + channel]) - Int(b[index + channel])) > tolerance {
                        differing += 1
                        break
                    }
                    index += 4
                }
            }
        }
        return Double(differing) / Double(pixels)
    }
}
