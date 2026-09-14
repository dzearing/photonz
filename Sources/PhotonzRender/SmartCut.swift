import CoreGraphics
import Foundation
import PhotonzCore

/// Takes the piece inside a marquee OUT of a picture and heals the space it
/// came from, so moving the piece leaves something whole behind it.
///
/// Photoshop's Layer Via Cut leaves a hole. That is the whole difference, and
/// the reason this command is worth having: what goes in the space is read off
/// the background right around the piece, whatever outline the piece has.
///
/// None of the reading is new. `PatchRingWalk` says WHERE the background is
/// around a shape of any outline, `PatchDecision` says what goes in the space,
/// and `RegionOps` does the drawing. This is the part that has to touch
/// pixels: reading the ring's colours off the picture and putting the three
/// together.
public enum SmartCut {

    public struct Result: Sendable {
        /// The piece, trimmed to its own pixels, with everything that was not
        /// inside the marquee transparent.
        public let piece: CGImage
        /// Where the piece sat, in the source picture's own pixels, top-left
        /// origin. Already tightened to what is actually drawn there, so a
        /// marquee flung round a small drawing gives a layer the size of the
        /// drawing rather than a big transparent box.
        public let pieceRect: CGRect
        /// The picture with the space the piece came from filled in. ALWAYS
        /// the same size as the picture that went in.
        public let patched: CGImage
        /// What went into the space, or nil when there was nothing around the
        /// piece to read and the space is honestly empty.
        public let fill: PatchFill?
        /// Whether that fill was read off the picture or guessed, which is the
        /// only part of this worth saying out loud (`PatchHeal`).
        public let heal: PatchHeal

        public init(piece: CGImage, pieceRect: CGRect, patched: CGImage,
                    fill: PatchFill?, heal: PatchHeal) {
            self.piece = piece
            self.pieceRect = pieceRect
            self.patched = patched
            self.fill = fill
            self.heal = heal
        }
    }

    /// How wide the ring around the piece is, in pixels, and how far out it
    /// starts. The band right against the outline is skipped
    /// (`PatchRingWalk.defaultGap`): a wand follows the ink exactly, so that
    /// band is half ink and reading it turns an exact panel colour into a
    /// guess.
    public static let ringWidth = PatchRingWalk.defaultWidth
    public static let ringGap = PatchRingWalk.defaultGap

    /// The piece inside `path` taken out of `image`, with the space it came
    /// from filled in. `path` is in `image`'s own pixels, top-left origin, and
    /// selects its interior by the even-odd rule, exactly as a
    /// `SelectionRegion` holds it.
    ///
    /// Nil when there is no piece to take: a marquee that misses the picture,
    /// or one over a part of it that is entirely transparent. An invisible new
    /// layer is worse than an honest refusal.
    public static func cut(_ image: CGImage, path: CGPath) -> Result? {
        let w = image.width, h = image.height
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        let box = path.boundingBoxOfPath.integral.intersection(bounds)
        guard w > 0, h > 0, !box.isNull, box.width >= 1, box.height >= 1 else { return nil }

        // The piece first, because a marquee with nothing under it is a
        // refusal and there is no point reading a ring for it.
        guard let extracted = RegionOps.extracted(image, path: path),
              let trimmed = RegionOps.trimmed(extracted) else { return nil }
        let pieceRect = trimmed.rect.offsetBy(dx: box.minX, dy: box.minY)

        // What the marquee covers, pixel by pixel, so the ring can follow the
        // outline rather than the box round it.
        guard let inside = mask(path, over: box), let pixels = LayerSeparator.read(image)
        else { return nil }
        let spots = PatchRingWalk.spots(inside: inside, rect: box, clip: bounds,
                                        width: ringWidth, gap: ringGap)
        let ring = PatchRing(samples: spots.map { spot in
            let i = (spot.y * w + spot.x) * 4
            let a = Double(pixels[i + 3]) / 255
            // Premultiplied on the way in, so a translucent pixel has to be
            // divided back out before it can be compared with an opaque one.
            let scale = a > 0 ? 1 / a : 0
            return PatchRing.Sample(u: spot.u, v: spot.v,
                                    color: RGBA(r: Double(pixels[i]) / 255 * scale,
                                                g: Double(pixels[i + 1]) / 255 * scale,
                                                b: Double(pixels[i + 2]) / 255 * scale,
                                                a: a))
        })

        let fill: PatchFill?
        let heal: PatchHeal
        if let read = PatchDecision.decide(ring) {
            fill = read
            heal = .matched
        } else if let guess = PatchDecision.middle(of: ring) {
            // A person chose this piece and pressed a key. Refusing to cut
            // because the background is busy would be ignoring an instruction,
            // so it cuts, fills with the middle of what was around it, and the
            // pill says the fill was a guess (`PatchHeal.guessed`).
            fill = .solid(guess)
            heal = .guessed
        } else {
            // A marquee round the whole layer: no background left to read, and
            // no colour anybody could defend. An empty space is honest.
            fill = nil
            heal = .cleared
        }

        let repaired = fill.flatMap { RegionOps.patched(image, path: path, fill: $0, box: box) }
            ?? RegionOps.erased(image, path: path)
        guard let repaired else { return nil }
        return Result(piece: trimmed.image, pieceRect: pieceRect, patched: repaired,
                      fill: fill, heal: heal)
    }

    /// Which pixels of `box` the marquee covers. Half coverage counts as
    /// inside, so the ring starts just outside the outline the eye sees rather
    /// than inside the antialiased rim of it.
    static func mask(_ path: CGPath, over box: CGRect) -> [Bool]? {
        let w = Int(box.width), h = Int(box.height)
        guard w > 0, h > 0 else { return nil }
        let space = CGColorSpaceCreateDeviceGray()
        // ONE byte a pixel, not four: this is a yes or no per pixel and a
        // marquee over half a twelve megapixel photo is five million of them,
        // so the colour channels would be twenty megabytes of writing nobody
        // reads.
        var coverage = [UInt8](repeating: 0, count: w * h)
        let drew = coverage.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            var toBox = CGAffineTransform(translationX: -box.minX, y: -box.minY)
            let local = path.copy(using: &toBox) ?? path
            var flip = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(h))
            context.addPath(local.copy(using: &flip) ?? local)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fillPath(using: .evenOdd)
            return true
        }
        guard drew else { return nil }
        return coverage.map { $0 >= 128 }
    }
}
