import CoreGraphics
import Foundation

/// Where the background is READ FROM around a piece of ANY outline.
///
/// `PatchDecision` never knew what shape a piece was: it is handed a bag of
/// samples with `u` and `v` coordinates and decides from those alone. This is
/// the half that lets a shape which is not a rectangle hand it a ring at all —
/// an ellipse, a wand blob, a marquee with a bite out of it.
///
/// The rule is one line: a ring sample is a pixel that is NOT part of the
/// shape and sits within `width` pixels of one that is. For a solid rectangle
/// that is the same four-sided band `LayerSeparator` has always read. For an
/// ellipse it follows the curve, so the corners of the box the ellipse is
/// inscribed in stop voting on what is behind it — and the pixels between the
/// curve and those corners, which a four-sided band could never reach, start.
public enum PatchRingWalk {

    /// One place to read the background, in image pixels (top-left origin),
    /// with where it sits against the piece's own box.
    public struct Spot: Equatable, Sendable {
        public let x: Int
        public let y: Int
        /// 0 at the piece's left edge, 1 at its right. A sample just outside
        /// sits a little past 0 or 1, which is exactly where a fit wants it.
        public let u: Double
        /// 0 at the piece's top edge, 1 at its bottom.
        public let v: Double

        public init(x: Int, y: Int, u: Double, v: Double) {
            self.x = x
            self.y = y
            self.u = u
            self.v = v
        }
    }

    /// How wide the band is, in pixels. The same three `LayerSeparator` reads:
    /// wide enough for a real reading, narrow enough that it is still the
    /// background right THERE.
    public static let defaultWidth = 3

    /// How many bands right against the outline are left OUT of the ring.
    ///
    /// One, because the pixel touching the outline is usually half of the
    /// thing being cut. A wand follows the ink exactly and an ellipse drawn
    /// snug round a round button sits on its antialiased rim, so the pixel
    /// immediately outside either one is a mix of the piece and the page. Read
    /// as background it poisons the whole reading: a tenth of a white letter
    /// is 25 levels off the panel colour, which is a dozen times the tolerance
    /// the flat case runs at, so a panel that should come back exact comes
    /// back as a guess instead.
    public static let defaultGap = 1

    /// Every place to read the background around the shape `inside` describes.
    ///
    /// `inside` is a row-major mask over `rect`, which is the shape's own
    /// integral box in image pixels. `clip` is the picture: nothing off the
    /// edge of it is ever a sample, because there is nothing there to read.
    /// `gap` bands right against the outline are left out (`defaultGap`), so
    /// the band actually read runs from `gap + 1` to `gap + width` pixels out.
    ///
    /// Empty when the shape has no background left to read, which is the
    /// honest answer for a marquee flung round the whole picture.
    public static func spots(inside: [Bool], rect: CGRect, clip: CGRect,
                             width: Int = defaultWidth,
                             gap: Int = 0) -> [Spot] {
        let w = Int(rect.width), h = Int(rect.height)
        guard w > 0, h > 0, inside.count == w * h, width >= 1, gap >= 0 else { return [] }
        let reach = width + gap
        let x0 = Int(rect.minX), y0 = Int(rect.minY)
        let cx0 = Int(clip.minX), cy0 = Int(clip.minY)
        let cx1 = Int(clip.maxX), cy1 = Int(clip.maxY)

        func isInside(_ gx: Int, _ gy: Int) -> Bool {
            let lx = gx - x0, ly = gy - y0
            guard lx >= 0, ly >= 0, lx < w, ly < h else { return false }
            return inside[ly * w + lx]
        }

        /// Whether anything within `gap` of this pixel is part of the shape,
        /// which is what makes it too close to the outline to read.
        func touchesTheShape(_ gx: Int, _ gy: Int) -> Bool {
            guard gap > 0 else { return false }
            for dy in -gap...gap {
                for dx in -gap...gap where isInside(gx + dx, gy + dy) { return true }
            }
            return false
        }

        // Only the shape's own EDGE reaches out: the middle of a big marquee
        // has nothing near it that is not the marquee, so walking its
        // neighbourhood too is the difference between a command that is
        // instant and one that is not.
        //
        // The pass walks the mask in ITS OWN indices rather than going out to
        // `isInside` and back. A marquee over half a twelve megapixel photo is
        // five million pixels, and four coordinate conversions each is most of
        // a second of doing nothing.
        let edges = inside.withUnsafeBufferPointer { bits -> [Int] in
            var found: [Int] = []
            for ly in 0..<h {
                let row = ly * w
                for lx in 0..<w where bits[row + lx] {
                    let left = lx > 0 && bits[row + lx - 1]
                    let right = lx < w - 1 && bits[row + lx + 1]
                    let up = ly > 0 && bits[row - w + lx]
                    let down = ly < h - 1 && bits[row + w + lx]
                    if left && right && up && down { continue }
                    found.append(row + lx)
                }
            }
            return found
        }

        // Marked on a grid of its own so no pixel can ever be a sample twice.
        // A ring that counts a pixel twice weights it twice in the median, and
        // the flat case stops being exact.
        let bx0 = x0 - reach, by0 = y0 - reach
        let bw = w + 2 * reach, bh = h + 2 * reach
        var marked = [Bool](repeating: false, count: bw * bh)
        var spots: [Spot] = []

        for edge in edges {
            let gx = x0 + edge % w, gy = y0 + edge / w
            for dy in -reach...reach {
                for dx in -reach...reach {
                    let nx = gx + dx, ny = gy + dy
                    guard nx >= cx0, ny >= cy0, nx < cx1, ny < cy1,
                          !isInside(nx, ny) else { continue }
                    let index = (ny - by0) * bw + (nx - bx0)
                    guard index >= 0, index < marked.count, !marked[index] else { continue }
                    marked[index] = true
                    guard !touchesTheShape(nx, ny) else { continue }   // decided against
                    spots.append(Spot(x: nx, y: ny,
                                      u: (Double(nx - x0) + 0.5) / rect.width,
                                      v: (Double(ny - y0) + 0.5) / rect.height))
                }
            }
        }
        return spots
    }
}
