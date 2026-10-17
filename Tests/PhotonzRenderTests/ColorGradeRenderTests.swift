import CoreGraphics
import CoreImage
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// A colour grade reaches the pixels, each value the way its name says, keyed
/// values move between their keys, and a grade with every value at its middle
/// draws the picture exactly as it was
/// (task `a-clip-can-be-colour-graded-from-add-effect`).
@Suite("A colour grade changes the picture")
struct ColorGradeRenderTests {

    static let canvas = CGSize(width: 120, height: 80)

    static func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    /// The mean of each channel over the whole picture, nought to 255.
    static func mean(_ image: CGImage) -> (r: Double, g: Double, b: Double, luma: Double, spread: Double) {
        let data = pixels(image)
        var r = 0.0, g = 0.0, b = 0.0, spread = 0.0
        let count = Double(data.count / 4)
        for index in stride(from: 0, to: data.count, by: 4) {
            let pr = Double(data[index]), pg = Double(data[index + 1]), pb = Double(data[index + 2])
            r += pr; g += pg; b += pb
            spread += max(pr, pg, pb) - min(pr, pg, pb)
        }
        r /= count; g /= count; b /= count
        return (r, g, b, 0.2126 * r + 0.7152 * g + 0.0722 * b, spread / count)
    }

    /// A clip stand-in: a picture of four soft colour bands, filling the
    /// canvas, in a four second document, wearing `grade` when one is given.
    static func clip(_ grade: ColorGradeEffect?) -> (PhotonzDocument, UUID, ImageStore) {
        let store = ImageStore()
        let width = Int(canvas.width), height = Int(canvas.height)
        var data = [UInt8](repeating: 255, count: width * height * 4)
        let bands: [(UInt8, UInt8, UInt8)] = [(180, 90, 60), (70, 140, 90), (60, 90, 170), (150, 150, 150)]
        for y in 0..<height {
            for x in 0..<width {
                let band = bands[min(x * bands.count / width, bands.count - 1)]
                let index = (y * width + x) * 4
                data[index] = band.0; data[index + 1] = band.1; data[index + 2] = band.2
            }
        }
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let picture = context.makeImage()!
        let ref = store.register(picture)
        var layer = Layer(name: "Clip", content: .image(ref), frame: CGRect(origin: .zero, size: canvas))
        layer.time = LayerTime(inMS: 0, outMS: 4000)
        if let grade { layer.style.effects = [.colorGrade(grade)] }
        var document = PhotonzDocument(canvasSize: canvas, layers: [layer])
        document.durationMS = 4000
        return (document, layer.id, store)
    }

    static func render(_ grade: ColorGradeEffect?) throws -> CGImage {
        let (document, _, store) = clip(grade)
        return try #require(DocumentRenderer().render(document.drawn(atTimeMS: 1000), store: store, scale: 1))
    }

    @Test func everyValueAtItsMiddleIsTheUntouchedPictureExactly() throws {
        let plain = try Self.render(nil)
        let neutral = try Self.render(.neutral)
        #expect(Self.pixels(plain) == Self.pixels(neutral))
        // ...and a grade that is switched off is not drawn either.
        let off = try Self.render(ColorGradeEffect(temperature: 80, saturation: 0, isOn: false))
        #expect(Self.pixels(plain) == Self.pixels(off))
    }

    @Test func warmerTemperatureRaisesRedOverBlue() throws {
        let plain = Self.mean(try Self.render(nil))
        let warm = Self.mean(try Self.render(ColorGradeEffect(temperature: 100)))
        let cool = Self.mean(try Self.render(ColorGradeEffect(temperature: -100)))
        let before = plain.r - plain.b
        #expect(warm.r - warm.b > before + 30, "warm \(warm.r - warm.b) over \(before)")
        #expect(cool.r - cool.b < before - 30, "cool \(cool.r - cool.b) under \(before)")
    }

    @Test func tintPullsTowardMagentaOrGreen() throws {
        let plain = Self.mean(try Self.render(nil))
        let magenta = Self.mean(try Self.render(ColorGradeEffect(tint: 100)))
        let green = Self.mean(try Self.render(ColorGradeEffect(tint: -100)))
        let greenness = { (m: (r: Double, g: Double, b: Double, luma: Double, spread: Double)) in m.g - (m.r + m.b) / 2 }
        #expect(greenness(magenta) < greenness(plain) - 10)
        #expect(greenness(green) > greenness(plain) + 10)
    }

    @Test func exposureBrightensAndDarkens() throws {
        let plain = Self.mean(try Self.render(nil))
        let up = Self.mean(try Self.render(ColorGradeEffect(exposure: 1)))
        let down = Self.mean(try Self.render(ColorGradeEffect(exposure: -1)))
        #expect(up.luma > plain.luma + 20)
        #expect(down.luma < plain.luma - 20)
    }

    @Test func saturationDrainsToGreyAndPushesPast() throws {
        let plain = Self.mean(try Self.render(nil))
        let grey = Self.mean(try Self.render(ColorGradeEffect(saturation: 0)))
        let rich = Self.mean(try Self.render(ColorGradeEffect(saturation: 200)))
        #expect(grey.spread < 3, "grey has no colour: \(grey.spread)")
        #expect(rich.spread > plain.spread + 10)
    }

    @Test func contrastSpreadsTheBandsApart() throws {
        func range(_ image: CGImage) -> Double {
            let data = Self.pixels(image)
            var lo = 255.0, hi = 0.0
            for index in stride(from: 0, to: data.count, by: 4) {
                let luma = 0.2126 * Double(data[index]) + 0.7152 * Double(data[index + 1])
                    + 0.0722 * Double(data[index + 2])
                lo = min(lo, luma); hi = max(hi, luma)
            }
            return hi - lo
        }
        let plain = range(try Self.render(nil))
        #expect(range(try Self.render(ColorGradeEffect(contrast: 80))) > plain + 10)
        #expect(range(try Self.render(ColorGradeEffect(contrast: -80))) < plain - 10)
    }

    @Test func aKeyedSaturationMovesInThePicture() throws {
        var (document, id, store) = Self.clip(nil)
        document.startKeying(layerID: id, .motion(.gradeSaturation), atDocumentTimeMS: 0, ease: .linear)
        document.setKeyedValue(.number(0), layerID: id, .motion(.gradeSaturation),
                               atDocumentTimeMS: 2000, ease: .linear)
        func spread(at ms: Int) throws -> Double {
            Self.mean(try #require(DocumentRenderer().render(document.drawn(atTimeMS: ms), store: store,
                                                            scale: 1))).spread
        }
        let start = try spread(at: 0), middle = try spread(at: 1000), end = try spread(at: 2000)
        #expect(end < 3)
        #expect(middle < start - 10 && middle > end + 10, "\(start) \(middle) \(end)")
    }
}
