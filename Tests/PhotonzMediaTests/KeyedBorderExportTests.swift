import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import PhotonzRender
import Testing

/// **A keyed border leaves in the file the way it plays**
/// (task `a-border-s-width-and-colour-key-like-any-other-v`).
///
/// A picture whose frame grows from nothing over two seconds, and turns from
/// red to green as it does, is written to a real MP4 through the ordinary
/// renderer, and the file is opened again: at the first key there is no
/// frame, half way it is half as wide and part way between the colours, and at
/// the last key it is the whole width and green.
@Suite("A keyed border reaches the exported movie", .serialized)
struct KeyedBorderExportTests {

    static let folder = TestTone.scratch()
    static let canvas = CGSize(width: 200, height: 100)

    static func box(_ name: String, _ rect: CGRect, hex: String) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: hex,
                                                     start: .zero,
                                                     end: CGPoint(x: rect.width, y: rect.height),
                                                     fillColorHex: hex)),
              frame: rect)
    }

    /// The colour of the written file at a moment, at a point of the picture
    /// given in document coordinates.
    static func colour(of url: URL, atSeconds seconds: Double,
                       at point: CGPoint) async throws -> (r: Int, g: Int, b: Int) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        let width = frame.width, height = frame.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = data.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw TestTone.Failure.noBuffer }
        let x = Int(point.x * CGFloat(width) / canvas.width)
        let y = Int(point.y * CGFloat(height) / canvas.height)
        let index = ((height - 1 - y) * width + x) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
    }

    @Test("A border keyed wider and greener grows and turns in the file, and half way between the keys")
    func aKeyedBorderIsInTheFile() async throws {
        let ground = Self.box("Ground", CGRect(origin: .zero, size: Self.canvas), hex: "#FFFFFF")
        var square = Self.box("Picture", CGRect(x: 40, y: 30, width: 40, height: 40), hex: "#0000FF")
        square.time = LayerTime(inMS: 0, outMS: 4000)
        square.style.effects = [.border(BorderEffect(width: 0, colorHex: "#FF0000", position: .outside))]
        var document = PhotonzDocument(canvasSize: Self.canvas, layers: [ground, square])
        document.durationMS = 4000
        document.startKeying(layerID: square.id, .motion(.borderWidth), atDocumentTimeMS: 1000, ease: .linear)
        document.setKeyedValue(.number(20), layerID: square.id, .motion(.borderWidth),
                               atDocumentTimeMS: 3000, ease: .linear)
        document.startKeying(layerID: square.id, .motion(.borderColor), atDocumentTimeMS: 1000, ease: .linear)
        document.setKeyedValue(.color("#00FF00"), layerID: square.id, .motion(.borderColor),
                               atDocumentTimeMS: 3000, ease: .linear)

        let plan = DocumentVideoExport.plan(durationMS: 4000, canvasSize: Self.canvas,
                                            format: .mp4, quality: .standard)
        let out = Self.folder.appendingPathComponent("keyed-border.mp4")
        let drawing = document
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out) { ms in
            DocumentRenderer().render(drawing.drawn(atTimeMS: ms), store: ImageStore())
        }

        let bare = try await Self.colour(of: out, atSeconds: 0.5, at: CGPoint(x: 84, y: 50))
        #expect(bare.r > 180 && bare.g > 180 && bare.b > 180,
                "at the first key there is no frame: right of the picture is white: \(bare)")
        let halfIn = try await Self.colour(of: out, atSeconds: 2.0, at: CGPoint(x: 85, y: 50))
        #expect(halfIn.r > 60 && halfIn.g > 60 && halfIn.b < 90,
                "half way the frame reaches 10 out, part red and part green: \(halfIn)")
        let halfOut = try await Self.colour(of: out, atSeconds: 2.0, at: CGPoint(x: 95, y: 50))
        #expect(halfOut.r > 180 && halfOut.g > 180, "half way it has not reached 15 out: \(halfOut)")
        let wide = try await Self.colour(of: out, atSeconds: 3.5, at: CGPoint(x: 95, y: 50))
        #expect(wide.g > 180 && wide.r < 90, "at the last key it is 20 wide and green: \(wide)")
    }
}
