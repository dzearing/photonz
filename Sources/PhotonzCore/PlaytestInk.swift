import CoreGraphics
import Foundation

/// How thick the ink is through one point of a rendered picture, counted
/// straight up and down from that point.
///
/// This is how a walk proves a line got thicker ON THE CANVAS rather than in
/// the panel's number: on 2026-10-19 Thickness read 26 while the line was
/// still drawn 4 pixels thick, because it was drawn inside a box that never
/// grew (`OutlineWidth.swift`). A walk that read the number passed; a walk
/// that counts the pixels does not (`PlaytestStep.expectInk`).
public enum PlaytestInk {

    /// How far a channel may stray from the colour at the point and still be
    /// the same ink. Wide enough for the soft pixel at a line's edge, narrow
    /// enough that red on white never reads as one colour.
    public static let tolerance = 24

    /// The number of pixels in the run of one colour through (`x`, `y`),
    /// counted down the column, in a picture of `width` by `height` RGBA
    /// pixels, top row first. Nil when the point is off the picture.
    public static func thickness(rgba bytes: [UInt8], width: Int, height: Int,
                                 x: Int, y: Int) -> Int? {
        guard x >= 0, x < width, y >= 0, y < height, bytes.count >= width * height * 4
        else { return nil }
        func pixel(_ row: Int) -> Int { (row * width + x) * 4 }
        let ink = pixel(y)
        func matches(_ row: Int) -> Bool {
            let p = pixel(row)
            for channel in 0..<4
            where abs(Int(bytes[p + channel]) - Int(bytes[ink + channel])) > tolerance {
                return false
            }
            return true
        }
        var top = y, bottom = y
        while top > 0, matches(top - 1) { top -= 1 }
        while bottom < height - 1, matches(bottom + 1) { bottom += 1 }
        return bottom - top + 1
    }
}
