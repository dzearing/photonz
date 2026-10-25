import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PhotonzCore
@testable import PhotonzRender

/// Writes the marker and airbrush sheet the audit shows: rows of strokes on
/// white paper by the real rasterizer, beside the round tip, and the measured
/// bars. Only when asked:
/// `PHOTONZ_STROKE_SHEET=/some/dir Scripts/test.sh --filter MarkerAirbrushSheet`.
@Suite("Marker and airbrush sheet")
struct MarkerAirbrushSheetTests {

    private static let folder = ProcessInfo.processInfo.environment["PHOTONZ_STROKE_SHEET"]
    private let scale: CGFloat = 2

    private func path(_ points: [CGPoint], every ms: Double = 16) -> [StrokeSample] {
        var out: [StrokeSample] = []
        var t = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let steps = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 10))
            for i in 0..<steps {
                let f = CGFloat(i) / CGFloat(steps)
                out.append(StrokeSample(point: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f), ms: t))
                t += ms
            }
        }
        if let last = points.last { out.append(StrokeSample(point: last, ms: t)) }
        return out
    }

    private func wave(_ y: CGFloat, from x0: CGFloat, to x1: CGFloat, amplitude: CGFloat) -> [CGPoint] {
        (0...24).map { i in
            let t = CGFloat(i) / 24
            return CGPoint(x: x0 + (x1 - x0) * t, y: y + sin(t * .pi * 2) * amplitude)
        }
    }

    private func s(_ medium: BrushMedium, _ samples: [StrokeSample], _ values: [String: Double] = [:],
                   hex: String, seed: UInt32) -> BrushStroke {
        BrushStroke(samples: samples, settings: BrushSettings(medium: medium, values: values),
                    colorHex: hex, seed: seed)
    }

    /// A pass that stops for `ms` at its middle.
    private func pause(_ y: CGFloat, from x0: CGFloat, to x1: CGFloat, ms: Double) -> [StrokeSample] {
        let mid = (x0 + x1) / 2
        var out = path([CGPoint(x: x0, y: y), CGPoint(x: mid, y: y)])
        let at = out.last?.ms ?? 0
        out += stride(from: 33.0, through: ms, by: 33).map { StrokeSample(point: CGPoint(x: mid, y: y), ms: at + $0) }
        let resume = out.last?.ms ?? 0
        out += path([CGPoint(x: mid, y: y), CGPoint(x: x1, y: y)]).dropFirst()
            .map { StrokeSample(point: $0.point, ms: resume + $0.ms) }
        return out
    }

    private func rows() -> [(String, [BrushStroke])] {
        let yellow = "#F2C230", pink = "#E8508A", blue = "#2E7BE6", ink = "#1E1E1E"
        return [
            ("Marker, round", [
                s(.marker, path(wave(60, from: 30, to: 330, amplitude: 22)), ["size": 18], hex: yellow, seed: 1),
                s(.marker, path([CGPoint(x: 380, y: 50), CGPoint(x: 640, y: 50), CGPoint(x: 646, y: 60),
                                 CGPoint(x: 380, y: 62)]), ["size": 18], hex: yellow, seed: 2),
                s(.marker, path([CGPoint(x: 700, y: 60), CGPoint(x: 960, y: 60)]), ["size": 18], hex: pink, seed: 3),
                s(.marker, path([CGPoint(x: 760, y: 20), CGPoint(x: 900, y: 100)]), ["size": 18], hex: pink, seed: 4),
                s(.marker, path([CGPoint(x: 900, y: 20), CGPoint(x: 760, y: 100)]), ["size": 18], hex: blue, seed: 5),
            ]),
            ("Marker, chisel", [
                s(.marker, path(wave(60, from: 30, to: 330, amplitude: 30)), ["size": 22, "tip": 1], hex: blue, seed: 6),
                s(.marker, path([CGPoint(x: 400, y: 100), CGPoint(x: 470, y: 20), CGPoint(x: 540, y: 100),
                                 CGPoint(x: 610, y: 20)]), ["size": 22, "tip": 1], hex: ink, seed: 7),
                s(.marker, path([CGPoint(x: 700, y: 40), CGPoint(x: 960, y: 40)]), ["size": 22, "tip": 1, "flow": 30],
                  hex: ink, seed: 8),
                s(.marker, path([CGPoint(x: 700, y: 80), CGPoint(x: 960, y: 80)]), ["size": 22, "tip": 1, "flow": 95],
                  hex: ink, seed: 9),
            ]),
            ("Airbrush", [
                s(.airbrush, path(wave(60, from: 40, to: 320, amplitude: 18)), [:], hex: blue, seed: 10),
                s(.airbrush, pause(60, from: 400, to: 640, ms: 1000), [:], hex: ink, seed: 11),
                s(.airbrush, path([CGPoint(x: 720, y: 60), CGPoint(x: 960, y: 60)]), ["flow": 80], hex: pink, seed: 12),
            ]),
            ("Airbrush softness", [
                s(.airbrush, path([CGPoint(x: 40, y: 60), CGPoint(x: 320, y: 60)]), ["softness": 0, "flow": 50],
                  hex: ink, seed: 13),
                s(.airbrush, path([CGPoint(x: 400, y: 60), CGPoint(x: 640, y: 60)]), ["softness": 100, "flow": 50],
                  hex: ink, seed: 14),
                s(.airbrush, path([CGPoint(x: 720, y: 60), CGPoint(x: 960, y: 60)]),
                  ["size": 12, "flow": 70], hex: ink, seed: 15),
            ]),
            ("Round tip", [
                s(.oil, path(wave(60, from: 30, to: 330, amplitude: 22)), ["size": 18, "opacity": 60], hex: yellow,
                  seed: 16),
                s(.oil, pause(60, from: 400, to: 640, ms: 1000), ["size": 40, "opacity": 40], hex: ink, seed: 17),
            ]),
        ]
    }

    @Test(.enabled(if: folder != nil))
    func writeSheet() throws {
        let folder = try #require(Self.folder)
        let rows = rows()
        let rowHeight: CGFloat = 120, width: CGFloat = 1000
        for labelled in [false, true] {
            let size = CGSize(width: width, height: rowHeight * CGFloat(rows.count))
            let context = try #require(CGContext(
                data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
            for (index, row) in rows.enumerated() {
                let raster = try #require(PaintRasterizer.rasterize(PaintContent(strokes: row.1),
                                                                    size: CGSize(width: width, height: rowHeight),
                                                                    scale: scale))
                let top = CGFloat(index) * rowHeight
                context.draw(raster, in: CGRect(x: 0, y: (size.height - top - rowHeight) * scale,
                                                width: width * scale, height: rowHeight * scale))
                if labelled { draw(row.0, at: CGPoint(x: 12 * scale, y: (size.height - top - 18) * scale), in: context) }
            }
            let image = try #require(context.makeImage())
            let url = URL(fileURLWithPath: folder)
                .appendingPathComponent(labelled ? "marker-airbrush-sheet-labelled.png" : "marker-airbrush-sheet.png")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
        }
        try measures().write(toFile: folder + "/marker-airbrush-measures.txt", atomically: true, encoding: .utf8)
    }

    /// The two measured bars, each medium against the round tip.
    private func measures() throws -> String {
        let box = CGSize(width: 300, height: 160)
        func render(_ strokes: [BrushStroke]) throws -> CGImage {
            try #require(PaintRasterizer.rasterize(PaintContent(strokes: strokes), size: box, scale: scale))
        }
        var out = ["Bars at defaults, 2x, mouse press."]
        for (label, medium) in [("Marker", BrushMedium.marker), ("Round tip", .oil)] {
            let back = s(medium, path([CGPoint(x: 30, y: 70), CGPoint(x: 260, y: 70), CGPoint(x: 265, y: 77),
                                       CGPoint(x: 30, y: 77)]), ["size": 20], hex: "#2060E0", seed: 1)
            let flat = PaintMeasures.flatShare(try render([back]))
            out.append(String(format: "%@\tflat share of a stroke that doubles back %.3f (bar %.2f: %@)", label, flat,
                              PaintMeasures.markerFlatBar, flat >= PaintMeasures.markerFlatBar ? "passes" : "fails"))
        }
        for (label, medium) in [("Airbrush", BrushMedium.airbrush), ("Round tip", .oil)] {
            let image = try render([s(medium, pause(80, from: 30, to: 270, ms: 1000), ["size": 40],
                                      hex: "#000000", seed: 2)])
            let held = PaintMeasures.meanAlpha(image, around: CGPoint(x: 150, y: 80), radius: 6, scale: scale)
            let passed = PaintMeasures.meanAlpha(image, around: CGPoint(x: 70, y: 80), radius: 6, scale: scale)
            let ratio = held / max(passed, 0.001)
            out.append(String(format: "%@\theld a second %.2f, a pass %.2f, build-up %.2fx (bar %.1f: %@)", label,
                              held, passed, ratio, PaintMeasures.airbrushBuildUpBar,
                              ratio >= PaintMeasures.airbrushBuildUpBar ? "passes" : "fails"))
        }
        let a = CGPoint(x: 30, y: 80), b = CGPoint(x: 270, y: 80)
        for (label, medium, values) in [("Airbrush", BrushMedium.airbrush, ["size": 40.0]),
                                        ("Round tip", .oil, ["size": 40, "opacity": 40])] {
            let grain = PaintMeasures.fringeGrain(try render([s(medium, path([a, b]), values, hex: "#000000",
                                                                seed: 3)]),
                                                  from: a, to: b, diameter: 40, scale: scale)
            out.append(String(format: "%@\tfringe grain %.4f", label, grain))
        }
        for softness in [0.0, 100] {
            let edge = PaintMeasures.edgeSoftness(try render([s(.airbrush, path([a, b]),
                                                               ["size": 40, "softness": softness, "flow": 60],
                                                               hex: "#000000", seed: 4)]),
                                                  from: a, to: b, diameter: 40, scale: scale)
            out.append(String(format: "Airbrush softness %.0f\tedge fall-off %.2f of the radius", softness, edge))
        }
        return out.joined(separator: "\n")
    }

    private func draw(_ text: String, at point: CGPoint, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 22, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 0.4, green: 0.1, blue: 0.1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
