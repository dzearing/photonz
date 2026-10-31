import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// The probe's pixel reader for a chip: the words and the plate behind them
/// read off a rendered picture, never off the model, so a walk can say what a
/// person would actually see (`ChipContrastReader`).
@Suite("Chip contrast read off the pixels")
struct ChipContrastReaderTests {

    private func render(_ layer: Layer, on backdrop: ChipStyleRenderingTests.Backdrop) throws -> CGImage {
        let store = ImageStore()
        let doc = ChipStyleRenderingTests.document(backdrop, [layer], store: store)
        return try #require(DocumentRenderer().render(doc, store: store))
    }

    @Test("A chip in its automatic colours reads at 4.5:1 or better, in every style, for a light and a dark custom colour",
          arguments: ChipStyle.allCases)
    func automaticChipReads(style: ChipStyle) throws {
        for ink in ["#7FD18B", "#3A2E8F"] {
            for backdrop in [ChipStyleRenderingTests.Backdrop.white, .black, .photo] {
                let layer = ChipStyleRenderingTests.arrow(style: style, ink: ink)
                let reading = try #require(ChipContrastReader.read(layer, in: try render(layer, on: backdrop)))
                #expect(reading.contrast >= 4.5,
                        "\(style) \(ink) over \(backdrop): \(reading.words.hexString) on \(reading.plate.hexString) = \(reading.contrast)")
            }
        }
    }

    @Test("The words it finds are the words drawn, give or take antialiasing")
    func findsTheWords() throws {
        let layer = ChipStyleRenderingTests.arrow(style: .solid, ink: "#0A84FF")
        let reading = try #require(ChipContrastReader.read(layer, in: try render(layer, on: .white)))
        let drawn = try #require(layer.annotation?.chipLook?.text)
        #expect(InkPlate.contrast(reading.words, drawn) < 1.2)
    }

    @Test("Words painted by hand into the plate's own colour read as unreadable")
    func catchesABadPair() throws {
        var layer = ChipStyleRenderingTests.arrow(style: .solid, ink: "#0A84FF")
        guard var a = layer.annotation else { return }
        a.setCaptionPartByHand(.text, hex: "#4A90E2")
        layer.content = .annotation(a)
        let reading = try #require(ChipContrastReader.read(layer, in: try render(layer, on: .white)))
        #expect(reading.contrast < 4.5)
    }

    @Test("An arrow with no words has no chip to read")
    func noWordsNoReading() throws {
        let layer = AnnotationBuilder.layer(content: AnnotationContent(shape: .arrow, colorHex: "#FF3B30"),
                                            from: CGPoint(x: 20, y: 40), to: CGPoint(x: 200, y: 40))
        #expect(ChipContrastReader.read(layer, in: try render(layer, on: .white)) == nil)
    }
}
