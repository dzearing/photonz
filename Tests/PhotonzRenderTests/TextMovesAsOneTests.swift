import CoreGraphics
import CoreText
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// Words that scale, drift or turn over time move as one solid piece: no
/// letter slips against the others from one frame to the next.
@Suite("Text that scales in a video moves as one piece")
struct TextMovesAsOneTests {

    struct Case: CustomStringConvertible, Sendable {
        var font: String; var size: CGFloat; var weight: TextWeight = .regular
        var canvas: CGSize; var from: Double; var to: Double; var frames: Int
        var contentScale: CGFloat = 1
        var description: String {
            "\(font) \(size) on \(Int(canvas.width)) x\(contentScale) \(from)->\(to)%"
        }
    }

    // Just round the words: the size of the type, not of the frame, is what
    // a 1080p or a 4K title is here.
    static let hd = CGSize(width: 1000, height: 200)
    static let uhd = CGSize(width: 2000, height: 400)

    static let cases: [Case] = [
        Case(font: "SF Pro", size: 120, weight: .bold, canvas: hd, from: 50, to: 100, frames: 20),
        Case(font: "SF Pro", size: 28, canvas: hd, from: 50, to: 100, frames: 20),
        Case(font: "Helvetica Neue", size: 64, canvas: hd, from: 50, to: 100, frames: 20),
        Case(font: "New York", size: 90, canvas: hd, from: 50, to: 100, frames: 20),
        Case(font: "SF Pro", size: 240, weight: .bold, canvas: uhd, from: 50, to: 100, frames: 12),
        Case(font: "SF Pro", size: 60, weight: .semibold, canvas: hd, from: 100, to: 102, frames: 20),
        Case(font: "SF Pro", size: 120, canvas: uhd, from: 100, to: 102, frames: 12),
        Case(font: "SF Pro", size: 60, canvas: hd, from: 50, to: 100, frames: 12, contentScale: 2),
    ]

    static func document(_ c: Case, canvas: CGSize? = nil, scaleMotion: Bool = true) -> PhotonzDocument {
        let canvas = canvas ?? c.canvas
        var words = TextContent(string: "Hnmow", fontName: c.font, fontSize: c.size, colorHex: "#FFFFFF",
                                weight: c.weight, alignment: .center)
        words.tracking = 0.3
        let size = TextRasterizer.naturalSize(words)
        var layer = Layer(name: "Title", content: .text(words),
                          frame: CGRect(x: ((canvas.width - size.width) / 2).rounded(),
                                        y: ((canvas.height - size.height) / 2).rounded(),
                                        width: size.width, height: size.height))
        layer.style.shadows = []
        if scaleMotion {
            layer.motions = [LayerMotion(property: .scale, from: .number(c.from), to: .number(c.to),
                                         timing: MotionTiming(startMS: 0, durationMS: 1000),
                                         curve: .linear, repeats: .once)]
        }
        var doc = PhotonzDocument(canvasSize: canvas, layers: [layer])
        doc.layers.insert(Layer(name: "Black", content: .annotation(
            AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#000000", start: .zero,
                              end: CGPoint(x: canvas.width, y: canvas.height), fillColorHex: "#000000")),
            frame: CGRect(origin: .zero, size: canvas)), at: 0)
        return doc
    }

    /// The word drawn whole at `times` its size off its outlines, on black:
    /// where its letters truly sit.
    static func reference(_ c: Case, times: CGFloat = 2) throws -> ([GlyphSteadiness.Letter], CGPoint) {
        let doc = document(c, scaleMotion: false)
        let layer = try #require(doc.layers.last)
        guard case .text(let words) = layer.content else { throw CancellationError() }
        let path = try #require(TextRasterizer.outlinePath(words, size: layer.frame.size))
        let width = Int(layer.frame.width * times), height = Int(layer.frame.height * times)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: times, y: -times)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(path)
        context.fillPath()
        let image = try #require(context.makeImage())
        return (GlyphSteadiness.letters(image), CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2))
    }

    static func measure(_ c: Case) throws -> GlyphSteadiness.Report {
        let (reference, middle) = try reference(c)
        let doc = document(c)
        let renderer = DocumentRenderer(compositing: .sRGB)
        let store = ImageStore()
        var frames: [(CGImage, Double)] = []
        for i in 0...c.frames {
            let ms = i * 1000 / c.frames
            let scale = (c.from + (c.to - c.from) * Double(ms) / 1000) / 100
            let image = try #require(renderer.render(doc.moved(toMotionTimeMS: ms), store: store,
                                                     scale: c.contentScale))
            frames.append((image, scale * Double(c.contentScale)))
        }
        let frame = doc.layers.last!.frame
        return GlyphSteadiness.read(frames, reference: reference,
                                    middle: CGPoint(x: frame.midX * c.contentScale, y: frame.midY * c.contentScale),
                                    referenceMiddle: middle, referenceScale: 2)
    }

    @Test(arguments: cases) func everyLetterKeepsItsPlaceInTheWord(_ c: Case) throws {
        let report = try Self.measure(c)
        print("STEADY \(c): \(String(format: "%.3f", report.worstDeviation)) px off its line, "
            + "\(String(format: "%.3f", report.worstJump)) between frames")
        #expect(report.unread == 0)
        #expect(report.worstDeviation < 0.1)
        for (a, b) in zip(report.scales, report.scales.dropFirst()) { #expect(b > a) }
    }

    /// How sharp the edges of a picture of light words are, and how much ink.
    private func edges(_ image: CGImage) -> (sharp: Double, ink: Double) {
        let found = GlyphSteadiness.ink(image)
        func at(_ x: Int, _ y: Int) -> Double {
            x >= 0 && y >= 0 && x < found.width && y < found.height ? Double(found.values[y * found.width + x]) : 0
        }
        var squares = 0.0, sum = 0.0, ink = 0.0
        for y in -1..<found.height {
            for x in -1..<found.width {
                let here = at(x, y), across = at(x + 1, y) - here, down = at(x, y + 1) - here
                ink += here
                squares += across * across + down * down
                sum += (across * across + down * down).squareRoot()
            }
        }
        return (squares / max(sum, 1), ink / 255)
    }

    /// Words that hold still in a video are as sharp, and weigh the same, as
    /// the same words on a picture, which the system draws.
    @Test(arguments: [CGFloat(14), 20, 28, 40, 60, 120])
    func stillWordsAreAsSharpAsThePictures(_ size: CGFloat) throws {
        var still = Self.document(Case(font: "SF Pro", size: size, weight: .semibold,
                                       canvas: CGSize(width: 1000, height: 200), from: 100, to: 100, frames: 1),
                                  scaleMotion: false)
        let renderer = DocumentRenderer(compositing: .sRGB)
        let picture = edges(try #require(renderer.render(still, store: ImageStore(), scale: 1)))
        still.durationMS = 2000
        let video = edges(try #require(renderer.render(still.drawn(atTimeMS: 500), store: ImageStore(), scale: 1)))
        print("SHARP \(size): \(video.sharp / picture.sharp) ink \(video.ink / picture.ink)")
        #expect(video.sharp / picture.sharp > 0.99)
        #expect(abs(video.ink / picture.ink - 1) < 0.02)
    }
}
