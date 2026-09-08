import CoreGraphics
import Foundation

/// The foreground and background pair, and the rules the two fill keys follow.
///
/// The pair paints in three places, and only one of them shows swatches:
/// ⌥⌫ fills what you have picked with the foreground, ⌫ on a locked background
/// clears it to the background, and growing the canvas outward paints the new
/// space with the background. `Tool.colorControl` gives the swatches a home on
/// the bucket alone, so under Select or crop those three still happen with
/// nothing on the bar to say what colour they are about to use.
///
/// Both answers live here rather than in the views that need them, because two
/// surfaces ask each question — the key press and the Edit menu row ask what
/// there is to fill, and the canvas drag and the commit ask which space is
/// new — and a menu row that says yes while the key says no is the exact way
/// this drifts.
public enum FillColors {
    /// Whether ⌥⌫ has anything to paint: the layer you picked, or a pixel
    /// region on a tool that acts on pixels. A marquee belonging to a tool
    /// that does not act on pixels is not a target, which is the same rule the
    /// canvas presses the key under.
    public static func canFill(hasPickedLayer: Bool, targetsPixels: Bool, hasRegion: Bool) -> Bool {
        hasPickedLayer || (targetsPixels && hasRegion)
    }

    /// The parts of `proposed` that lie outside `canvas`: the space a resize is
    /// about to paint with the background colour, and nothing else.
    ///
    /// Up to four strips that never overlap, so a translucent preview reads
    /// evenly instead of doubling up in the corners. Trimming a side
    /// contributes nothing — space taken away is not space to paint.
    public static func newSpace(canvas: CGRect, proposed: CGRect) -> [CGRect] {
        guard proposed.width > 0, proposed.height > 0 else { return [] }
        guard canvas.width > 0, canvas.height > 0, proposed.intersects(canvas) else { return [proposed] }

        var strips: [CGRect] = []
        // The full-width bands above and below the canvas first, so the
        // left/right strips only have to cover the band beside it.
        if proposed.minY < canvas.minY {
            strips.append(CGRect(x: proposed.minX, y: proposed.minY,
                                 width: proposed.width, height: canvas.minY - proposed.minY))
        }
        if proposed.maxY > canvas.maxY {
            strips.append(CGRect(x: proposed.minX, y: canvas.maxY,
                                 width: proposed.width, height: proposed.maxY - canvas.maxY))
        }
        let bandTop = max(proposed.minY, canvas.minY)
        let bandBottom = min(proposed.maxY, canvas.maxY)
        let bandHeight = bandBottom - bandTop
        if bandHeight > 0 {
            if proposed.minX < canvas.minX {
                strips.append(CGRect(x: proposed.minX, y: bandTop,
                                     width: canvas.minX - proposed.minX, height: bandHeight))
            }
            if proposed.maxX > canvas.maxX {
                strips.append(CGRect(x: canvas.maxX, y: bandTop,
                                     width: proposed.maxX - canvas.maxX, height: bandHeight))
            }
        }
        return strips
    }
}
