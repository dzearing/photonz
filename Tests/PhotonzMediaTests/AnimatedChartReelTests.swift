import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
@testable import PhotonzMedia
@testable import PhotonzRender
import Testing
import UniformTypeIdentifiers

/// The reel for the user to judge (task `animated-charts-you-can-drop-into-a-video`):
/// every chart filmed by the real renderer from its first frame to its way off
/// as an MP4 and a GIF, and a contact sheet of each at five moments of its in.
///
/// Not part of the suite: it writes files the audit carries. Run it with
///
///     PHOTONZ_REEL=1 PHOTONZ_REEL_DIR=queue/audits Scripts/test.sh --filter AnimatedChartReel
@Suite("A reel of the charts building in", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_REEL"] == "1"))
struct AnimatedChartReelTests {

    static let canvas = CGSize(width: 1280, height: 720)
    static let lengthMS = 6_500

    static func document(_ kind: ChartKind) throws -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.durationMS = lengthMS
        let landed = doc.insertTitle(chart: kind, atTimeMS: 250, motionBlur: true)
        let inserted = try #require(landed)
        return (doc, inserted.layerID)
    }

    @Test("Film every chart, write the contact sheet")
    func film() async throws {
        TextMeasurement.use { text, maxWidth in TextRasterizer.naturalSize(text, maxWidth: maxWidth) }
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PHOTONZ_REEL_DIR"]
                            ?? FileManager.default.temporaryDirectory.path)
        let prefix = "2026-10-17-chart-reel"
        let store = ImageStore()
        var rows: [(String, [CGImage])] = []
        for kind in ChartKind.allCases {
            let (doc, id) = try Self.document(kind)
            let mp4 = directory.appendingPathComponent("\(prefix)-\(kind.rawValue).mp4")
            let gif = directory.appendingPathComponent("\(prefix)-\(kind.rawValue).gif")
            try? FileManager.default.removeItem(at: mp4)
            try? FileManager.default.removeItem(at: gif)
            let moviePlan = DocumentVideoExport.plan(durationMS: Self.lengthMS, canvasSize: Self.canvas,
                                                     format: .mp4, quality: .high)
            try await DocumentMovieWriter.write(plan: moviePlan, mix: [], soundURLs: [:], to: mp4,
                                                frames: { ms in DocumentRenderer().render(doc.drawn(atTimeMS: ms), store: store) })
            let gifPlan = DocumentVideoExport.plan(durationMS: Self.lengthMS, canvasSize: Self.canvas,
                                                   format: .gif, quality: .small)
            try await DocumentMovieWriter.writeAnimated(plan: gifPlan, format: .gif, to: gif,
                                                        frames: { ms in
                                                            DocumentRenderer().render(doc.drawn(atTimeMS: ms), store: store)
                                                        })
            let arrived = doc.titleArrivalMS(layerID: id)
            let stills = [0.0, 0.25, 0.5, 0.75, 1.0].compactMap { share -> CGImage? in
                DocumentRenderer().render(doc.drawn(atTimeMS: 250 + Int(Double(arrived) * share)), store: store)
            }
            rows.append((kind.name, stills))
            print("[reel] \(kind.name): \(mp4.lastPathComponent), \(gif.lastPathComponent)")
        }
        let sheet = try #require(DepthReelStudyTests.contactSheet(rows))
        let sheetURL = directory.appendingPathComponent("\(prefix)-contact.png")
        let destination = try #require(CGImageDestinationCreateWithURL(sheetURL as CFURL,
                                                                       UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, sheet, nil)
        #expect(CGImageDestinationFinalize(destination))
        print("[reel] contact sheet \(sheetURL.path)")
    }
}
