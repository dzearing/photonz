import CoreImage
import CoreGraphics
import Foundation
import PhotonzCore

/// The renderer's half of keying a colour out and of borrowing a shape from
/// the layer below (`PhotonzCore/LayerCompositing.swift`).
///
/// **Nothing decides anything here.** What a key does to a colour is arithmetic
/// and it lives in `ChromaKey.applied(to:)`, where it is tested one pixel at a
/// time. This file's whole job is to get that arithmetic onto a frame fast
/// enough to scrub with, which means it is asked for every colour there is
/// ONCE, packed into a lookup table, and handed to the GPU — after which a
/// twelve megapixel frame costs one pass over the texture whatever the key's
/// numbers are.
enum ChromaKeyFilter {

    /// How finely the lookup table is cut, per channel. 64 is Apple's own
    /// figure for this filter and it is not arbitrary: 32 visibly steps on a
    /// gradual edge, and 128 is eight times the table for no difference
    /// anybody can see.
    static let side = 64

    /// The keyed picture. Two passes, and the second one is the point:
    ///
    ///  1. the lookup table, which decides what every colour becomes, and
    ///  2. the source's OWN transparency put back over the result.
    ///
    /// Without the second pass a rounded corner, a letter's edge and the
    /// margin round a shape would all fill in with whatever the table says
    /// about black, because the table replaces alpha rather than adjusting it.
    static func keyed(_ image: CIImage, with key: ChromaKey) -> CIImage {
        guard key.isOn, RGBA(hex: key.colorHex) != nil else { return image }
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": side,
            "inputCubeData": table(for: key),
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB) as Any,
            kCIInputImageKey: image
        ]), let looked = filter.outputImage else { return image }
        return looked.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: image.extent),
            kCIInputMaskImageKey: image
        ])
    }

    /// `over` cut to the shape, or to the brightness, of `under`.
    ///
    /// Both pictures are already in canvas space by the time they get here, so
    /// the mask lines up with what it is masking without anything being moved.
    static func matted(_ over: CIImage, by under: CIImage,
                       kind: LayerMatte, extent: CGRect) -> CIImage {
        let mask: CIImage
        switch kind {
        case .shape:
            mask = under
        case .brightness:
            // Brightness moved into transparency: white shows, black hides,
            // and what was already transparent stays hidden, since a picture
            // Core Image holds is premultiplied and its empty parts are black.
            //
            // Read in the numbers the colour was WRITTEN in, not in light.
            // Core Image works in linear light, where a mid grey is about five
            // per cent rather than half — so a black to white ramp used as a
            // matte would be almost entirely hidden, and the mid grey somebody
            // picked to mean "half there" would come out a twentieth there.
            // The tone curve first puts the picture back into the numbers the
            // colour picker showed.
            mask = under
                .applyingFilter("CILinearToSRGBToneCurve")
                .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
            ])
        }
        return over.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent),
            kCIInputMaskImageKey: mask
        ]).cropped(to: extent)
    }

    // MARK: - The lookup table

    /// The tables built so far, behind their own lock.
    ///
    /// A box rather than a pair of static variables because a static that can
    /// be written is shared mutable state, which Swift 6 refuses outright. The
    /// lock is what makes the box safe, and `@unchecked` is the note saying so.
    private final class Tables: @unchecked Sendable {
        /// Enough for a document whose layers are each keyed differently, and
        /// few enough that the tables together stay under a few megabytes.
        static let capacity = 8
        static let shared = Tables()
        private let lock = NSLock()
        private var built: [ChromaKey: Data] = [:]
        private var order: [ChromaKey] = []

        func cached(_ key: ChromaKey) -> Data? {
            lock.lock()
            defer { lock.unlock() }
            return built[key]
        }

        func keep(_ data: Data, for key: ChromaKey) {
            lock.lock()
            defer { lock.unlock() }
            guard built[key] == nil else { return }
            built[key] = data
            order.append(key)
            if order.count > Tables.capacity { built[order.removeFirst()] = nil }
        }
    }

    /// What every colour there is becomes under this key, premultiplied, which
    /// is the form `CIColorCube` reads. Red runs fastest, then green, then
    /// blue: Apple's layout, and getting it wrong swaps the channels rather
    /// than failing.
    ///
    /// Cached, because a slider being dragged asks for a new table every frame
    /// and the ones either side of it are asked for again on the way back.
    static func table(for key: ChromaKey) -> Data {
        if let hit = Tables.shared.cached(key) { return hit }

        let steps = side - 1
        var values = [Float](repeating: 0, count: side * side * side * 4)
        var at = 0
        for blue in 0..<side {
            let b = Double(blue) / Double(steps)
            for green in 0..<side {
                let g = Double(green) / Double(steps)
                for red in 0..<side {
                    let out = key.applied(to: RGBA(r: Double(red) / Double(steps), g: g, b: b))
                    values[at] = Float(out.r * out.alpha)
                    values[at + 1] = Float(out.g * out.alpha)
                    values[at + 2] = Float(out.b * out.alpha)
                    values[at + 3] = Float(out.alpha)
                    at += 4
                }
            }
        }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        Tables.shared.keep(data, for: key)
        return data
    }
}

/// Where one click of **Key it** gets its colour: the wall, read off the
/// picture rather than asked for with an eyedropper.
///
/// The edges of a frame are the wall. A subject stands in the middle of the
/// shot, so a ring round the outside of it is almost all backdrop — and the
/// question is not "what is the average colour of that ring", which for a
/// half-lit wall is a colour that appears nowhere in it, but "which colour
/// turns up most often in it".
public enum ChromaKeySampler {

    /// How far in from each edge counts as the ring: a tenth of the shorter
    /// side, with a floor so a thumbnail still has a ring at all.
    static let ringShare = 0.1
    /// What share of the ring one colour has to hold before it is worth
    /// offering as a key. Below this there is no wall, just a busy picture, and
    /// keying the commonest colour in it would take a bite out of the subject.
    static let wallShare = 0.45

    /// The colour of the wall, or nil when the edges of this picture are not
    /// one colour.
    public static func wallColour(of image: CGImage) -> RGBA? {
        let width = image.width
        let height = image.height
        guard width >= 8, height >= 8 else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let inset = max(2, Int(Double(min(width, height)) * ringShare))
        // Buckets coarse enough that a lit wall and a shaded one land together,
        // and fine enough that green and teal do not.
        let step = 32
        var counts: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        var seen = 0
        for y in 0..<height {
            let edgeRow = y < inset || y >= height - inset
            for x in 0..<width {
                guard edgeRow || x < inset || x >= width - inset else { continue }
                let i = (y * width + x) * 4
                guard data[i + 3] > 200 else { continue }
                let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
                let bucket = (r / step) << 16 | (g / step) << 8 | (b / step)
                var entry = counts[bucket] ?? (0, 0, 0, 0)
                entry.count += 1
                entry.r += r
                entry.g += g
                entry.b += b
                counts[bucket] = entry
                seen += 1
            }
        }
        guard seen > 0, let best = counts.values.max(by: { $0.count < $1.count }) else { return nil }
        guard Double(best.count) / Double(seen) >= wallShare else { return nil }
        // The average of the bucket rather than the middle of it, so the key
        // lands on the colour that is actually there.
        let n = Double(best.count)
        return RGBA(r: Double(best.r) / n / 255,
                    g: Double(best.g) / n / 255,
                    b: Double(best.b) / n / 255)
    }
}
