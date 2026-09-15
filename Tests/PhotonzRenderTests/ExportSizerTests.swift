import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// Weighing a picture export before it is written.
///
/// The claim the Export sheet makes is a strong one: the number beside the
/// quality slider is not an estimate, it is the size of the file you are about
/// to save. These tests hold it to that, by saving the file and looking.
@Suite("What a picture export will weigh")
struct ExportSizerTests {

    /// Something with detail in it, so the encoder has real work to do and the
    /// quality actually changes the answer. A flat colour compresses to nearly
    /// nothing at every quality and would prove nothing.
    private func busyDocument(width: Int, height: Int) -> PhotonzDocument {
        var layers: [Layer] = []
        var seed: UInt64 = 0x5EED
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(UInt32.max)
        }
        for _ in 0..<160 {
            let x = next() * Double(width)
            let y = next() * Double(height)
            let w = 6 + next() * 90
            let h = 6 + next() * 90
            let hex = String(format: "#%02X%02X%02X",
                             Int(next() * 255), Int(next() * 255), Int(next() * 255))
            layers.append(Layer(name: "Box",
                                content: .annotation(AnnotationContent(
                                    shape: .rectangle, strokeWidth: 0, colorHex: hex,
                                    start: .zero, end: CGPoint(x: w, y: h),
                                    fillColorHex: hex)),
                                frame: CGRect(x: x, y: y, width: w, height: h)))
        }
        return PhotonzDocument(canvasSize: CGSize(width: width, height: height), layers: layers)
    }

    private func sizer() -> ExportSizer {
        ExportSizer(renderer: DocumentRenderer(), store: ImageStore())
    }

    /// The whole point. Not "close to", not "about": the same number.
    @Test func theNumberIsTheSizeOfTheFileThatGetsSaved() async throws {
        let document = busyDocument(width: 600, height: 400)
        let sizer = sizer()
        for quality in [30, 60, 100] {
            let fraction = ExportQuality.fraction(quality)
            let shown = try #require(await sizer.byteCount(of: document, frameID: nil, scale: 1,
                                                          format: .jpeg, quality: fraction))
            let data = try #require(await sizer.data(of: document, frameID: nil, scale: 1,
                                                    format: .jpeg, quality: fraction))
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("export-sizer-\(quality)-\(UUID().uuidString).jpg")
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let onDisk = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
            #expect(onDisk == shown)
        }
    }

    @Test func lessQualityIsFewerBytes() async throws {
        let document = busyDocument(width: 600, height: 400)
        let sizer = sizer()
        let rough = try #require(await sizer.byteCount(of: document, frameID: nil, scale: 1,
                                                      format: .jpeg, quality: 0.3))
        let best = try #require(await sizer.byteCount(of: document, frameID: nil, scale: 1,
                                                     format: .jpeg, quality: 1))
        #expect(rough < best)
    }

    /// The scale row and the quality slider are two halves of the same
    /// question: 2x is a different file and has to weigh a different number.
    @Test func twiceTheScaleIsADifferentFile() async throws {
        let document = busyDocument(width: 600, height: 400)
        let sizer = sizer()
        let once = try #require(await sizer.byteCount(of: document, frameID: nil, scale: 1,
                                                     format: .jpeg, quality: 0.9))
        let twice = try #require(await sizer.byteCount(of: document, frameID: nil, scale: 2,
                                                      format: .jpeg, quality: 0.9))
        #expect(twice > once)
    }

    /// Kept renders are the reason a slider does not crawl. They are keyed by
    /// what the render depends on, so a second answer at the same scale must
    /// not come back with the first scale's picture in it.
    @Test func keepingTheRenderDoesNotMixUpTheScales() async throws {
        let document = busyDocument(width: 400, height: 300)
        let sizer = sizer()
        let firstAtOne = try #require(await sizer.byteCount(of: document, frameID: nil, scale: 1,
                                                           format: .jpeg, quality: 0.9))
        _ = await sizer.byteCount(of: document, frameID: nil, scale: 2, format: .jpeg, quality: 0.9)
        let againAtOne = try #require(await sizer.byteCount(of: document, frameID: nil, scale: 1,
                                                           format: .jpeg, quality: 0.9))
        #expect(firstAtOne == againAtOne)
    }

    /// A frame is exported on its own, so it weighs its own contents and not
    /// the canvas around it.
    @Test func aPickedFrameWeighsOnlyItself() async throws {
        var document = busyDocument(width: 1200, height: 900)
        let frame = Layer.frameLayer(name: "Card", origin: CGPoint(x: 100, y: 100),
                                     size: CGSize(width: 200, height: 160))
        document.layers.append(frame)
        let sizer = sizer()
        let whole = try #require(await sizer.byteCount(of: document, frameID: nil, scale: 1,
                                                      format: .jpeg, quality: 0.9))
        let card = try #require(await sizer.byteCount(of: document, frameID: frame.id, scale: 1,
                                                     format: .jpeg, quality: 0.9))
        #expect(card < whole)
        // The same scoping Export itself uses, so the two can never disagree.
        let scoped = try #require(DocumentRenderer().render(document.exportTarget(frameID: frame.id),
                                                            store: ImageStore(), scale: 1))
        let direct = try #require(ImageCodec.encode(scoped, format: .jpeg, quality: 0.9))
        #expect(direct.count == card)
    }

    /// PNG throws nothing away, so its size does not move with the slider. This
    /// is why the sheet shows no quality control for it rather than one that
    /// does nothing.
    @Test func aLosslessFormatIgnoresTheQuality() async throws {
        let document = busyDocument(width: 300, height: 200)
        let sizer = sizer()
        let low = try #require(await sizer.byteCount(of: document, frameID: nil, scale: 1,
                                                    format: .png, quality: 0.3))
        let high = try #require(await sizer.byteCount(of: document, frameID: nil, scale: 1,
                                                     format: .png, quality: 1))
        #expect(low == high)
    }

    /// The number the acceptance list asked for. Not a pass/fail on a
    /// millisecond count, which would flake on a loaded machine: this prints
    /// what a twelve megapixel document costs to render once and to re-encode
    /// per slider stop, which is what the audit reports.
    @Test func weighingATwelveMegapixelDocumentIsPrintedForTheAudit() async throws {
        let document = busyDocument(width: 4000, height: 3000)
        let sizer = sizer()
        let firstStart = Date()
        let first = try #require(await sizer.byteCount(of: document, frameID: nil, scale: 1,
                                                      format: .jpeg, quality: 0.9))
        let firstMS = Date().timeIntervalSince(firstStart) * 1000
        let againStart = Date()
        _ = await sizer.byteCount(of: document, frameID: nil, scale: 1, format: .jpeg, quality: 0.6)
        let againMS = Date().timeIntervalSince(againStart) * 1000
        print("""
            [export-quality] 12 MP (4000x3000): first weigh \(Int(firstMS)) ms \
            (render + encode), next quality \(Int(againMS)) ms (encode only, render kept). \
            JPEG at 90% is \(ExportQuality.fileSize(bytes: first)).
            """)
        // Loose enough never to flake, tight enough to catch the kept render
        // being dropped, which would put a whole render back on every stop.
        #expect(againMS < firstMS)
    }
}
