import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PhotonzCore
@testable import PhotonzRender

/// Writes the airbrush sheets the audit shows: a sheet of strokes per setting,
/// pressure and speed, the cross profile plotted against the round tip, the
/// blind sheet (one unlabelled row per medium and the round tip, in a fixed
/// shuffle) and the measured bars. Only when asked:
/// `PHOTONZ_STROKE_SHEET=/some/dir Scripts/test.sh --filter AirbrushSheet`.
@Suite("Airbrush sheet")
struct AirbrushSheetTests {

    private static let folder = ProcessInfo.processInfo.environment["PHOTONZ_STROKE_SHEET"]
    private let scale: CGFloat = 2
    private let ink = "#1E1E1E"

    /// A pass through `points` at `speed` points a millisecond, with an
    /// optional pen press along it (0...1 of the way).
    private func path(_ points: [CGPoint], speed: Double = 0.6,
                      pressure: ((Double) -> Double)? = nil) -> [StrokeSample] {
        var out: [StrokeSample] = []
        var t = 0.0
        var total = 0.0
        for (a, b) in zip(points, points.dropFirst()) { total += Double(hypot(b.x - a.x, b.y - a.y)) }
        var gone = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let length = Double(hypot(b.x - a.x, b.y - a.y))
            let steps = max(2, Int(length / 6))
            for i in 0..<steps {
                let f = CGFloat(i) / CGFloat(steps)
                let along = (gone + length * Double(f)) / max(total, 1)
                out.append(StrokeSample(point: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f),
                                        pressure: pressure.map { $0(along) }, ms: t))
                t += length / Double(steps) / speed
            }
            gone += length
        }
        if let last = points.last { out.append(StrokeSample(point: last, pressure: pressure.map { $0(1) }, ms: t)) }
        return out
    }

    private func wave(_ y: CGFloat, from x0: CGFloat, to x1: CGFloat, amplitude: CGFloat) -> [CGPoint] {
        (0...24).map { i in
            let t = CGFloat(i) / 24
            return CGPoint(x: x0 + (x1 - x0) * t, y: y + sin(t * .pi * 2) * amplitude)
        }
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

    private func s(_ samples: [StrokeSample], _ values: [String: Double] = [:], medium: BrushMedium = .airbrush,
                   hex: String? = nil, seed: UInt32) -> BrushStroke {
        BrushStroke(samples: samples, settings: BrushSettings(medium: medium, values: values),
                    colorHex: hex ?? ink, seed: seed)
    }

    /// A row of three: a wave, a pass held a second half way, and a straight
    /// pass, all at `values`.
    private func trio(_ values: [String: Double], hex: String? = nil, seed: UInt32) -> [BrushStroke] {
        [s(path(wave(60, from: 40, to: 300, amplitude: 18)), values, hex: hex, seed: seed),
         s(pause(60, from: 380, to: 640, ms: 1000), values, hex: hex, seed: seed + 1),
         s(path([CGPoint(x: 720, y: 60), CGPoint(x: 960, y: 60)]), values, hex: hex, seed: seed + 2)]
    }

    @Test(.enabled(if: folder != nil))
    func writeSheets() throws {
        let folder = try #require(Self.folder)
        let blue = "#2E7BE6", pink = "#E8508A"
        try write(folder, "airbrush-defaults.png", rows: [
            ("Airbrush at its defaults", trio([:], seed: 1)),
            ("In colour", trio([:], hex: blue, seed: 4)),
            ("Round tip, for comparison", [
                s(path(wave(60, from: 40, to: 300, amplitude: 18)), ["size": 40, "opacity": 40], medium: .oil, seed: 7),
                s(pause(60, from: 380, to: 640, ms: 1000), ["size": 40, "opacity": 40], medium: .oil, seed: 8),
                s(path([CGPoint(x: 720, y: 60), CGPoint(x: 960, y: 60)]), ["size": 40, "opacity": 40], medium: .oil,
                  seed: 9)]),
        ])
        try write(folder, "airbrush-flow.png", rows: [10.0, 35, 70, 100].enumerated().map { i, flow in
            ("Flow \(Int(flow))", trio(["flow": flow], hex: i == 3 ? pink : nil, seed: UInt32(20 + i * 3)))
        })
        try write(folder, "airbrush-spread.png", rows: [0.0, 55, 100].enumerated().map { i, spread in
            ("Spread \(Int(spread))", trio(["spread": spread], seed: UInt32(40 + i * 3)))
        })
        try write(folder, "airbrush-droplet.png", rows: [0.0, 25, 60, 100].enumerated().map { i, droplet in
            ("Droplet Size \(Int(droplet))", trio(["droplet": droplet, "flow": 50], seed: UInt32(60 + i * 3)))
        })
        try write(folder, "airbrush-buildup.png", rows: [0.0, 50, 100].enumerated().map { i, buildUp in
            ("Build-up \(Int(buildUp))", trio(["buildup": buildUp], seed: UInt32(80 + i * 3)))
        })
        // Pressure: a pen pressing light to hard, light and hard; then speed.
        let line = [CGPoint(x: 200, y: 60), CGPoint(x: 900, y: 60)]
        try write(folder, "airbrush-pressure-speed.png", rows: [
            ("Pen, light to hard", [s(path(line, pressure: { 0.05 + 0.95 * $0 }), seed: 100)]),
            ("Pen, light", [s(path(line, pressure: { _ in 0.25 }), seed: 101)]),
            ("Pen, hard", [s(path(line, pressure: { _ in 1 }), seed: 102)]),
            ("Pen, hard at Flow 100", [s(path(line, pressure: { _ in 1 }), ["flow": 100], seed: 103)]),
            ("Mouse, slow", [s(path(line, speed: 0.2), seed: 104)]),
            ("Mouse, brisk", [s(path(line, speed: 1), seed: 105)]),
            ("Mouse, fast", [s(path(line, speed: 3), seed: 106)]),
        ])
        try writeProfile(folder)
        try writeBlind(folder)
        try writeReel(folder)
        try measures().write(toFile: folder + "/airbrush-measures.txt", atomically: true, encoding: .utf8)
    }

    // MARK: - The reel

    /// Frames of strokes being sprayed, 30 a second, drawn the way the canvas
    /// draws a stroke under the pointer (`PaintRasterizer.LiveMarker` fed by
    /// the placement walker as the samples arrive): a pass, a pass that stops
    /// half way to build up, and a heavy spatter pass pressed hard.
    private func writeReel(_ folder: String) throws {
        let reel = folder + "/reel"
        try FileManager.default.createDirectory(atPath: reel, withIntermediateDirectories: true)
        let size = CGSize(width: 640, height: 300)
        let strokes = [
            s(path([CGPoint(x: 60, y: 70), CGPoint(x: 580, y: 80)], speed: 0.5), ["size": 40], hex: "#2E7BE6", seed: 400),
            s(pause(150, from: 60, to: 580, ms: 1200).map {
                StrokeSample(point: $0.point, ms: $0.ms * 1.6)
            }, ["size": 40], seed: 401),
            s(path([CGPoint(x: 60, y: 230), CGPoint(x: 580, y: 225)], speed: 0.4, pressure: { _ in 1 }),
              ["size": 40, "flow": 100], hex: "#E8508A", seed: 402),
        ]
        let width = Int(size.width * scale), height = Int(size.height * scale)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        var landed: [CGImage] = []
        var frame = 0
        for stroke in strokes {
            let overlay = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                                 bytesPerRow: width * 4, space: space, bitmapInfo: info))
            let live = try #require(PaintRasterizer.LiveMarker(
                stroke: stroke, bitmap: overlay, pointsToPixels: CGAffineTransform(scaleX: scale, y: scale),
                clip: CGRect(x: 0, y: 0, width: width, height: height)))
            var walker = BrushPlacement.Walker(settings: stroke.settings, seed: stroke.seed)
            var next = 0
            let end = stroke.samples.last?.ms ?? 0
            var clock = 0.0
            while next < stroke.samples.count {
                while next < stroke.samples.count, stroke.samples[next].ms <= clock {
                    live.mark(walker.add(stroke.samples[next]))
                    next += 1
                }
                if next == stroke.samples.count { live.mark(walker.finish()) }
                try saveFrame(&frame, reel, landed: landed, live: try #require(overlay.makeImage()), size: size)
                clock += 1000 / 30
                if clock > end + 1000 { break }
            }
            landed.append(try #require(overlay.makeImage()))
        }
        for _ in 0..<20 { try saveFrame(&frame, reel, landed: landed, live: nil, size: size) }
    }

    private func saveFrame(_ frame: inout Int, _ folder: String, landed: [CGImage], live: CGImage?,
                           size: CGSize) throws {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let all = CGRect(x: 0, y: 0, width: width, height: height)
        context.fill(all)
        for image in landed { context.draw(image, in: all) }
        if let live { context.draw(live, in: all) }
        try save(try #require(context.makeImage()), to: folder + String(format: "/frame-%04d.png", frame))
        frame += 1
    }

    // MARK: - The blind sheet

    /// One unlabelled row per medium and the round tip, the same marks in
    /// each at its own default size, in a fixed shuffle; the key beside it.
    private func writeBlind(_ folder: String) throws {
        let media: [(String, BrushMedium)] = [("marker", .marker), ("charcoal", .charcoal), ("airbrush", .airbrush),
                                              ("pencil", .pencil), ("watercolour", .watercolour),
                                              ("round tip", .oil), ("crayon", .crayon), ("chalk", .chalk)]
        let colour = "#2B3550"
        try write(folder, "airbrush-blind.png", rows: media.enumerated().map { i, entry in
            let values = ["size": BrushSettings(medium: entry.1).size]
            return (entry.0, [
                s(path(wave(60, from: 40, to: 420, amplitude: 22)), values, medium: entry.1, hex: colour,
                  seed: UInt32(200 + i)),
                s(path([CGPoint(x: 500, y: 25), CGPoint(x: 560, y: 95), CGPoint(x: 620, y: 25), CGPoint(x: 680, y: 95),
                        CGPoint(x: 740, y: 25), CGPoint(x: 800, y: 95), CGPoint(x: 860, y: 25), CGPoint(x: 920, y: 95)]),
                  values, medium: entry.1, hex: colour, seed: UInt32(300 + i)),
            ])
        }, labelled: false)
        try media.enumerated().map { "row \($0 + 1): \($1.0)" }.joined(separator: "\n")
            .write(toFile: folder + "/airbrush-blind-key.txt", atomically: true, encoding: .utf8)
    }

    // MARK: - The profile, plotted

    /// The darkness across a straight stroke, airbrush against the round tip,
    /// each averaged along its middle, as two lines on one chart.
    private func writeProfile(_ folder: String) throws {
        let box = CGSize(width: 300, height: 160)
        let a = CGPoint(x: 30, y: 80), b = CGPoint(x: 270, y: 80)
        func profile(_ medium: BrushMedium, _ values: [String: Double]) throws -> [(at: Double, alpha: Double)] {
            let image = try #require(PaintRasterizer.rasterize(
                PaintContent(strokes: [s(path([a, b]), ["size": 40].merging(values) { $1 }, medium: medium, seed: 9)]),
                size: box, scale: scale))
            return PaintMeasures.crossProfile(image, from: a, to: b, reach: 30, scale: scale)
        }
        let lines: [(String, [(at: Double, alpha: Double)], CGColor)] = [
            ("Airbrush, Spread 55", try profile(.airbrush, [:]), CGColor(srgbRed: 0.18, green: 0.48, blue: 0.9, alpha: 1)),
            ("Airbrush, Spread 0", try profile(.airbrush, ["spread": 0]), CGColor(srgbRed: 0.1, green: 0.6, blue: 0.4, alpha: 1)),
            ("Airbrush, Spread 100", try profile(.airbrush, ["spread": 100]), CGColor(srgbRed: 0.5, green: 0.3, blue: 0.8, alpha: 1)),
            ("Round tip", try profile(.oil, ["opacity": 40]), CGColor(srgbRed: 0.85, green: 0.3, blue: 0.2, alpha: 1)),
        ]
        let width = 900.0, height = 420.0, margin = 60.0
        let context = try #require(CGContext(
            data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Axes: across the stroke, -30 to 30 points; darkness 0 to 1, peaks scaled to one.
        let plot = CGRect(x: margin, y: margin, width: width - 2 * margin, height: height - 2 * margin - 40)
        context.setStrokeColor(CGColor(srgbRed: 0.75, green: 0.75, blue: 0.75, alpha: 1))
        context.setLineWidth(1)
        for x in stride(from: -30.0, through: 30, by: 10) {
            let px = plot.minX + (x + 30) / 60 * plot.width
            context.move(to: CGPoint(x: px, y: plot.minY))
            context.addLine(to: CGPoint(x: px, y: plot.maxY))
            label(String(format: "%+.0f pt", x), at: CGPoint(x: px - 18, y: plot.minY - 24), in: context)
        }
        context.strokePath()
        for (index, line) in lines.enumerated() {
            let peak = max(line.1.map(\.alpha).max() ?? 1, 0.001)
            context.setStrokeColor(line.2)
            context.setLineWidth(2.5)
            for (i, point) in line.1.enumerated() {
                let p = CGPoint(x: plot.minX + (point.at + 30) / 60 * plot.width,
                                y: plot.minY + point.alpha / peak * plot.height)
                if i == 0 { context.move(to: p) } else { context.addLine(to: p) }
            }
            context.strokePath()
            context.setFillColor(line.2)
            let key = CGPoint(x: margin + Double(index) * 200, y: height - 34)
            context.fill(CGRect(x: key.x, y: key.y + 4, width: 18, height: 8))
            label(line.0, at: CGPoint(x: key.x + 24, y: key.y), in: context)
        }
        label("Darkness across the stroke, each scaled to its own peak (Size 40)",
              at: CGPoint(x: margin, y: 14), in: context)
        try save(try #require(context.makeImage()), to: folder + "/airbrush-profile.png")
    }

    // MARK: - The numbers

    private func measures() throws -> String {
        let box = CGSize(width: 300, height: 160)
        let a = CGPoint(x: 30, y: 80), b = CGPoint(x: 270, y: 80)
        func render(_ strokes: [BrushStroke]) throws -> CGImage {
            try #require(PaintRasterizer.rasterize(PaintContent(strokes: strokes), size: box, scale: scale))
        }
        func pass(_ medium: BrushMedium, speed: Double = 0.6, pressure: Double? = nil,
                  _ values: [String: Double] = [:]) -> BrushStroke {
            s(path([a, b], speed: speed, pressure: pressure.map { p in { _ in p } }),
              ["size": 40].merging(values) { $1 }, medium: medium, seed: 9)
        }
        func core(_ image: CGImage) -> Double {
            PaintMeasures.meanAlpha(image, around: CGPoint(x: 150, y: 80), radius: 5, scale: scale)
        }
        var out = ["Airbrush bars at Size 40, 2x. The round tip is the oil paint's until its own slice."]
        let mark = { (pass: Bool) in pass ? "passes" : "fails" }
        for (label, medium, values) in [("Airbrush", BrushMedium.airbrush, [String: Double]()),
                                        ("Round tip", .oil, ["opacity": 40])] {
            let image = try render([pass(medium, values)])
            let feather = PaintMeasures.featherShare(image, from: a, to: b, diameter: 40, scale: scale)
            let drops = PaintMeasures.edgeDroplets(image, from: a, to: b, diameter: 40, scale: scale)
            out.append(String(format: "%@\tedge feather %.2f (bar %.2f: %@)\tedge droplets %.2f a square point (bar %.2f: %@)",
                              label, feather, PaintMeasures.airbrushFeatherBar,
                              mark(feather >= PaintMeasures.airbrushFeatherBar), drops,
                              PaintMeasures.airbrushEdgeDropletBar, mark(drops >= PaintMeasures.airbrushEdgeDropletBar)))
        }
        for (label, medium, values) in [("Airbrush", BrushMedium.airbrush, [String: Double]()),
                                        ("Round tip", .oil, ["opacity": 40])] {
            var curve: [String] = []
            var first = 0.0, atSecond = 0.0
            for ms in [0.0, 250, 500, 1000, 2000] {
                let mid = CGPoint(x: 150, y: 80)
                var samples = path([a, mid])
                let at = samples.last?.ms ?? 0
                if ms > 0 { samples += stride(from: 33.0, through: ms, by: 33).map { StrokeSample(point: mid, ms: at + $0) } }
                let resume = samples.last?.ms ?? 0
                samples += path([mid, b]).dropFirst().map { StrokeSample(point: $0.point, ms: resume + $0.ms) }
                let value = core(try render([s(samples, ["size": 40].merging(values) { $1 }, medium: medium, seed: 9)]))
                if ms == 0 { first = value }
                if ms == 1000 { atSecond = value }
                curve.append(String(format: "%.0f ms %.2f", ms, value))
            }
            let ratio = atSecond / max(first, 0.001)
            out.append(String(format: "%@\tdarkness held: %@; a second over none %.2fx (bar %.1f: %@)", label,
                              curve.joined(separator: ", "), ratio, PaintMeasures.airbrushBuildUpBar,
                              mark(ratio >= PaintMeasures.airbrushBuildUpBar)))
        }
        for (label, medium, values) in [("Airbrush", BrushMedium.airbrush, [String: Double]()),
                                        ("Round tip", .oil, ["opacity": 40])] {
            let slow = core(try render([pass(medium, speed: 0.25, pressure: 0.6, values)]))
            let fast = core(try render([pass(medium, speed: 3, pressure: 0.6, values)]))
            let ratio = slow / max(fast, 0.001)
            out.append(String(format: "%@\tslow pass %.2f, fast pass %.2f, %.2fx (bar %.1f: %@)", label, slow, fast,
                              ratio, PaintMeasures.airbrushSlowOverFastBar,
                              mark(ratio >= PaintMeasures.airbrushSlowOverFastBar)))
        }
        let light = core(try render([pass(.airbrush, pressure: 0.2)]))
        let hard = core(try render([pass(.airbrush, pressure: 1)]))
        out.append(String(format: "Airbrush\tpen light (0.2) %.2f, hard (1.0) %.2f, %.2fx", light, hard,
                          hard / max(light, 0.001)))
        for spread in [0.0, 55, 100] {
            let image = try render([pass(.airbrush, ["spread": spread])])
            out.append(String(format: "Airbrush Spread %.0f\twidth at half darkness %.1f pt, edge feather %.2f",
                              spread, PaintMeasures.lineProfile(image, from: a, to: b, reach: 30, scale: scale).width,
                              PaintMeasures.featherShare(image, from: a, to: b, diameter: 40, scale: scale)))
        }
        for droplet in [0.0, 25, 100] {
            let image = try render([pass(.airbrush, ["droplet": droplet])])
            out.append(String(format: "Airbrush Droplet Size %.0f\tfringe specks %.2f a square point, %.2f pt across",
                              droplet, PaintMeasures.edgeDroplets(image, from: a, to: b, diameter: 40, scale: scale),
                              PaintMeasures.speckSize(image, from: a, to: b, diameter: 40, scale: scale)))
        }
        for flow in [25.0, 100] {
            let image = try render([pass(.airbrush, pressure: 1, ["flow": flow])])
            out.append(String(format: "Airbrush Flow %.0f, pressed hard\tcore %.2f, spatter %.3f a square point",
                              flow, core(image),
                              PaintMeasures.edgeDroplets(image, from: a, to: b, diameter: 40, scale: scale, lift: 0.3)))
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Drawing

    private func write(_ folder: String, _ name: String, rows: [(String, [BrushStroke])],
                       labelled: Bool = true) throws {
        let rowHeight: CGFloat = 120, width: CGFloat = 1000
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
            let caption = labelled ? row.0 : "\(index + 1)"
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            label(caption, at: CGPoint(x: 12, y: size.height - top - 18), in: context)
            context.restoreGState()
        }
        try save(try #require(context.makeImage()), to: folder + "/" + name)
    }

    private func save(_ image: CGImage, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                                       1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func label(_ text: String, at point: CGPoint, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(srgbRed: 0.4, green: 0.1, blue: 0.1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
