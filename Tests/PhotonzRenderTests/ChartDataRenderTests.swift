import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// A chart moving from one set of numbers to the next, drawn by the real
/// renderer (task `a-chart-is-your-data-given-to-it-the-obvious-way`).
///
/// The frames a chart is posed with at a moment are right in the model on
/// their own; this is the claim that the PICTURE follows them. A bar that grew
/// was once drawn at its old size and clipped by its new box, so a bar going
/// up stayed where it was while every frame read correct.
@Suite("Chart sets drawn")
struct ChartDataRenderTests {

    static let canvas = CGSize(width: 1280, height: 720)

    /// The longest run of pixels down column `x` close to `hex`.
    static func run(in image: CGImage, x: Int, hex: String) -> Int {
        guard let colour = RGBA(hex: hex), let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        let step = image.bitsPerPixel / 8
        let target = (colour.r * 255, colour.g * 255, colour.b * 255)
        var best = 0, current = 0
        for y in 0..<image.height {
            let p = bytes + y * image.bytesPerRow + x * step
            let a = (Double(p[0]), Double(p[1]), Double(p[2]))
            func distance(_ c: (Double, Double, Double)) -> Double {
                abs(c.0 - target.0) + abs(c.1 - target.1) + abs(c.2 - target.2)
            }
            current = min(distance(a), distance((a.2, a.1, a.0))) < 60 ? current + 1 : 0
            best = max(best, current)
        }
        return best
    }

    @Test("Bars that grow and bars that shrink are drawn at the height of their new numbers")
    func barsDrawnAtNewHeights() throws {
        let table = try #require(ChartTable.reading("Quarter,2025,2026\nQ1,40,55\nQ2,-25,15\nQ3,60,45\nQ4,30,70"))
        let spec = ChartSpec(table: table)
        var doc = PhotonzDocument(canvasSize: Self.canvas)
        doc.durationMS = spec.clipLengthMS
        let landed = doc.insertTitle(chart: .bar, spec: spec, atTimeMS: 0)
        let id = try #require(landed?.layerID)
        let at = try #require(spec.steps?.first?.atMS) + 200
        let drawn = doc.drawn(atTimeMS: at)
        let image = try #require(DocumentRenderer().render(drawn, store: ImageStore(), scale: 1))
        let colour = try #require(doc.chartRowColours(layerID: id).first)
        for index in 1...4 {
            let bar = try #require(drawn.layer(id: id).flatMap { TitleDesign.find("Bar \(index)", in: $0) })
            let pixels = Self.run(in: image, x: Int(bar.frame.midX), hex: colour)
            #expect(abs(CGFloat(pixels) - bar.frame.height) <= 3, "Bar \(index) is \(pixels)px for a \(bar.frame.height)pt box")
        }
    }
}
