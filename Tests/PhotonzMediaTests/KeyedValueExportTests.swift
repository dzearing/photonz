import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import PhotonzRender
import Testing

/// **A keyed value moves in the exported file**, not only on the canvas
/// (task `every-value-in-the-panel-has-a-key-diamond`).
///
/// The writer is handed the same `drawn(atTimeMS:)` picture the canvas is, so
/// the claim is checked where it has to be true: a real movie is written, then
/// opened again and read at three moments.
@Suite("A keyed value survives the export", .serialized)
struct KeyedValueExportTests {

    static let canvas = CGSize(width: 160, height: 120)

    /// Black ground, and over it a red panel whose opacity is keyed from
    /// nothing at 1s to full at 3s.
    static func document() -> PhotonzDocument {
        let box = CGRect(origin: .zero, size: canvas)
        let ground = Layer(name: "Ground",
                           content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                                  colorHex: "#000000", start: .zero,
                                                                  end: CGPoint(x: box.width, y: box.height),
                                                                  fillColorHex: "#000000")),
                           frame: box)
        var panel = Layer(name: "Panel",
                          content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                                 colorHex: "#FF0000", start: .zero,
                                                                 end: CGPoint(x: box.width, y: box.height),
                                                                 fillColorHex: "#FF0000")),
                          frame: box)
        panel.time = LayerTime(inMS: 0, outMS: 4000)
        var document = PhotonzDocument(canvasSize: canvas, layers: [ground, panel])
        document.durationMS = 4000
        let id = panel.id
        document.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        document.setKeyedValue(.number(0), layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        document.setKeyedValue(.number(100), layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        return document
    }

    @Test("The file is dark before the first key, red after the last, and between on the way")
    func theFileFollowsTheKeys() async throws {
        let document = Self.document()
        let store = ImageStore()
        let plan = DocumentVideoExport.plan(durationMS: document.documentDurationMS,
                                            canvasSize: document.canvasSize,
                                            format: .mp4, quality: .standard)
        let out = TestTone.scratch().appendingPathComponent("keyed-opacity.mp4")
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out,
                                            frames: { ms in
                                                DocumentRenderer().render(document.drawn(atTimeMS: ms),
                                                                          store: store)
                                            })
        let before = try await TransitionExportTests.colour(of: out, atSeconds: 0.5)
        // Early in the fade: the curve leaves quickly and settles slowly, so
        // half way through the time is already most of the way to red.
        let between = try await TransitionExportTests.colour(of: out, atSeconds: 1.3)
        let after = try await TransitionExportTests.colour(of: out, atSeconds: 3.5)
        #expect(before.r < 40)
        #expect(after.r > 200)
        #expect(between.r > before.r + 30 && between.r < after.r - 30)
    }
}
