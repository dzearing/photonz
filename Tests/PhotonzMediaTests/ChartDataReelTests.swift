import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
@testable import PhotonzMedia
@testable import PhotonzRender
import Testing
import UniformTypeIdentifiers

/// The reel and the measured bar for the user to judge (task
/// `a-chart-is-your-data-given-to-it-the-obvious-way`): charts made from a
/// pasted table of 2025 and 2026, filmed by the real renderer as they move from
/// one set of numbers to the next, a contact sheet across the change, and each
/// bar's drawn height measured in pixels against its value.
///
/// Not part of the suite: it writes files the audit carries. Run it with
///
///     PHOTONZ_REEL=1 PHOTONZ_REEL_DIR=queue/audits Scripts/test.sh --filter ChartDataReel
@Suite("A reel of charts moving between sets", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_REEL"] == "1"))
struct ChartDataReelTests {

    static let canvas = CGSize(width: 1280, height: 720)
    static let table = "Quarter,2025,2026\nQ1,40,55\nQ2,-25,15\nQ3,60,45\nQ4,30,70"

    static func document(_ kind: ChartKind, _ text: String = table) throws -> (PhotonzDocument, UUID, ChartSpec) {
        let spec = ChartSpec(table: try #require(ChartTable.reading(text)), kind: kind)
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.durationMS = spec.clipLengthMS
        let landed = doc.insertTitle(chart: kind, spec: spec, atTimeMS: 0)
        let inserted = try #require(landed)
        return (doc, inserted.layerID, spec)
    }

    /// The longest run of pixels down column `x` within reach of `hex`.
    static func run(in image: CGImage, x: Int, hex: String) -> Int {
        guard let colour = RGBA(hex: hex), let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        let perRow = image.bytesPerRow
        let step = image.bitsPerPixel / 8
        var best = 0, current = 0
        for y in 0..<image.height {
            let p = bytes + y * perRow + x * step
            // Premultiplied BGRA or RGBA alike: the bars are opaque, so the
            // three channels are compared both ways and the nearer kept.
            let a = (Double(p[0]), Double(p[1]), Double(p[2]))
            let target = (colour.r * 255, colour.g * 255, colour.b * 255)
            func distance(_ c: (Double, Double, Double)) -> Double {
                abs(c.0 - target.0) + abs(c.1 - target.1) + abs(c.2 - target.2)
            }
            let near = min(distance(a), distance((a.2, a.1, a.0))) < 60
            current = near ? current + 1 : 0
            best = max(best, current)
        }
        return best
    }

    @Test("Film the charts changing, measure the bars, write the contact sheet")
    func film() async throws {
        TextMeasurement.use { text, maxWidth in TextRasterizer.naturalSize(text, maxWidth: maxWidth) }
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PHOTONZ_REEL_DIR"]
                            ?? FileManager.default.temporaryDirectory.path)
        let prefix = "2026-10-20-chart-data"
        let store = ImageStore()
        var rows: [(String, [CGImage])] = []
        let moneyTable = "Revenue,2025,2026\nRevenue,1.2M,2.4M"
        let charts: [(ChartKind, String)] = [(.bar, Self.table), (.line, Self.table), (.bigNumber, moneyTable)]
        for (kind, text) in charts {
            let (doc, _, spec) = try Self.document(kind, text)
            let length = spec.clipLengthMS
            let mp4 = directory.appendingPathComponent("\(prefix)-\(kind.rawValue).mp4")
            let gif = directory.appendingPathComponent("\(prefix)-\(kind.rawValue).gif")
            try? FileManager.default.removeItem(at: mp4)
            try? FileManager.default.removeItem(at: gif)
            let moviePlan = DocumentVideoExport.plan(durationMS: length, canvasSize: Self.canvas, format: .mp4,
                                                     quality: .high)
            try await DocumentMovieWriter.write(plan: moviePlan, mix: [], soundURLs: [:], to: mp4,
                                                frames: { ms in DocumentRenderer().render(doc.drawn(atTimeMS: ms), store: store) })
            let gifPlan = DocumentVideoExport.plan(durationMS: length, canvasSize: Self.canvas, format: .gif,
                                                   quality: .small)
            try await DocumentMovieWriter.writeAnimated(plan: gifPlan, format: .gif, to: gif, frames: { ms in
                DocumentRenderer().render(doc.drawn(atTimeMS: ms), store: store)
            })
            // Across the change: before it, a quarter, half and three
            // quarters through, and arrived.
            let arrives = spec.steps?.first?.atMS ?? 0
            let starts = arrives - ChartSpec.changeMS
            let moments = [starts - 300, starts + ChartSpec.changeMS / 4, starts + ChartSpec.changeMS / 2,
                           starts + ChartSpec.changeMS * 3 / 4, arrives + 200]
            rows.append((kind.name, moments.compactMap { DocumentRenderer().render(doc.drawn(atTimeMS: $0), store: store) }))
            print("[reel] \(kind.name): \(mp4.lastPathComponent), \(gif.lastPathComponent)")
        }

        // The measured bar: each bar's drawn height in pixels at the end of
        // the change against its new value, and half way between.
        let (doc, id, spec) = try Self.document(.bar)
        let arrives = try #require(spec.steps?.first?.atMS)
        let colour = try #require(doc.chartRowColours(layerID: id).first)
        let first = try #require(DocumentRenderer().render(doc.drawn(atTimeMS: arrives - ChartSpec.changeMS - 300), store: store))
        let half = try #require(DocumentRenderer().render(doc.drawn(atTimeMS: arrives - ChartSpec.changeMS / 2), store: store))
        let last = try #require(DocumentRenderer().render(doc.drawn(atTimeMS: arrives + 200), store: store))
        let middles = (1...4).compactMap { index in
            doc.drawn(atTimeMS: arrives).layer(id: id).flatMap { TitleDesign.find("Bar \(index)", in: $0) }?.frame.midX
        }
        // Q4's 70 in 2026 is the most either set shows, so the axis is
        // Q3's first height (60) grown to 70.
        let axis = Double(Self.run(in: first, x: Int(middles[2]), hex: colour)) * 70 / 60
        var lines: [String] = []
        let old = spec.rows.map(\.value)
        let new = try #require(spec.steps?.first?.values)
        for index in 0..<4 {
            let x = Int(middles[index])
            let end = Double(Self.run(in: last, x: x, hex: colour))
            let expected = axis * abs(new[index]) / 70
            let middle = Double(Self.run(in: half, x: x, hex: colour))
            let error = abs(end - expected) / axis * 100
            lines.append(String(format: "Q%d: %.0f to %.0f; end %.0fpx, value says %.1fpx, off by %.2f%% of the axis; half way %.0fpx",
                                index + 1, old[index], new[index], end, expected, error, middle))
            #expect(error <= 1, "Q\(index + 1) ends \(end)px, its value says \(expected)px")
        }
        let measure = directory.appendingPathComponent("\(prefix)-measured.txt")
        try (["Axis (70): \(Int(axis))px"] + lines).joined(separator: "\n").write(to: measure, atomically: true, encoding: .utf8)
        print("[reel] " + lines.joined(separator: "\n[reel] "))

        let sheet = try #require(DepthReelStudyTests.contactSheet(rows))
        let sheetURL = directory.appendingPathComponent("\(prefix)-contact.png")
        let destination = try #require(CGImageDestinationCreateWithURL(sheetURL as CFURL,
                                                                       UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, sheet, nil)
        #expect(CGImageDestinationFinalize(destination))
        print("[reel] contact sheet \(sheetURL.path)")
    }
}
