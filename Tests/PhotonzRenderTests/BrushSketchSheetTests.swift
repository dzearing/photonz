import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PhotonzCore
@testable import PhotonzRender

/// Paints every SVG sketch in a folder with the Brush the way Ask does
/// (`BrushSketch`, then each call read as paint_stroke reads it), so a
/// change to how a sketch is painted can be looked at without the app. Only
/// when asked: `PHOTONZ_SKETCH_DIR=/some/dir Scripts/test.sh --filter BrushSketchSheet`
/// writes `<name>-<medium>.png` beside each `<name>.svg`, in oil and
/// watercolour unless `PHOTONZ_SKETCH_MEDIA` lists others.
@Suite("Brush sketch sheet")
struct BrushSketchSheetTests {

    private static let folder = ProcessInfo.processInfo.environment["PHOTONZ_SKETCH_DIR"]

    @Test(.enabled(if: folder != nil))
    func paintSketches() throws {
        let folder = try #require(Self.folder)
        let media = (ProcessInfo.processInfo.environment["PHOTONZ_SKETCH_MEDIA"] ?? "oil,watercolour")
            .split(separator: ",").compactMap { BrushMedium(rawValue: String($0)) }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder).filter { $0.hasSuffix(".svg") }
        for name in names {
            let text = try String(contentsOfFile: folder + "/" + name, encoding: .utf8)
            let art = try SVGArtwork.parse(text).get()
            for medium in media {
                let canvas = CGSize(width: 960, height: 640)
                let calls = BrushSketch.calls(BrushSketch.strokes(art, canvas: canvas, medium: medium), medium: medium)
                var strokes: [BrushStroke] = []
                for call in calls {
                    guard case .success(.paintStroke(_, let agent)) = AgentTools.request(tool: "paint_stroke", arguments: call)
                    else { Issue.record("not a stroke: \(call.encodedString())"); continue }
                    let made = AgentPaint.brushStroke(
                        agent, armed: BrushSettings(medium: medium), armedColorHex: "#000000",
                        remembered: { BrushSettings(medium: $0) },
                        startedAt: AgentPaint.startedAt(now: 0, after: strokes.last), seed: 1)
                    strokes.append(try made.get())
                }
                let raster = try #require(PaintRasterizer.rasterize(PaintContent(strokes: strokes), size: canvas, scale: 1))
                let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
                let context = try #require(CGContext(data: nil, width: 960, height: 640, bitsPerComponent: 8, bytesPerRow: 0,
                                                     space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 960, height: 640))
                context.draw(raster, in: CGRect(x: 0, y: 0, width: 960, height: 640))
                let out = URL(fileURLWithPath: folder + "/" + name.replacingOccurrences(of: ".svg", with: "-\(medium.rawValue).png"))
                let destination = try #require(CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
                #expect(CGImageDestinationFinalize(destination))
                print("sketch \(name) \(medium.rawValue): \(calls.count) strokes")
            }
        }
    }
}
