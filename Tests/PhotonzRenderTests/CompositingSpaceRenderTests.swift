import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// The canvas mixes see-through paint the way it is asked to, and in the sRGB
/// space it draws what a browser and the exported file draw
/// (`docs/design/svg-export.md`, "Where see-through paint is mixed").
///
/// Photonz used to mix only in light, Core Image's own default, which drew a
/// 55% black shadow over white at 192 where every SVG reader drew 134: an
/// exported icon came out visibly darker than the one that was approved.
@Suite("Where the canvas mixes see-through paint")
struct CompositingSpaceRenderTests {

    static let canvas = CGSize(width: 200, height: 160)

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let bytes = SVGExportRenderTests.pixels(of: image, size: CGSize(width: image.width,
                                                                        height: image.height))
        let i = (y * image.width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
    }

    private func plate(_ hex: String, _ frame: CGRect, opacity: Double = 1) -> Layer {
        var layer = Layer(name: "Plate",
                          content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                                 colorHex: hex, start: .zero,
                                                                 end: CGPoint(x: frame.width,
                                                                              y: frame.height),
                                                                 fillColorHex: hex)),
                          frame: frame)
        layer.style.opacity = opacity
        return layer
    }

    private func onWhite(_ layers: [Layer], store: ImageStore) throws -> PhotonzDocument {
        let white = try #require(SolidImage.make(size: Self.canvas, hex: "#FFFFFF"))
        var document = PhotonzDocument.withBaseImage(store.register(white))
        document.layers.append(contentsOf: layers)
        return document
    }

    // MARK: - Opacity

    @Test func halfBlackOverWhiteIsTheGreyABrowserDraws() throws {
        let store = ImageStore()
        let document = try onWhite([plate("#000000", CGRect(x: 40, y: 40, width: 120, height: 80),
                                          opacity: 0.5)], store: store)
        let web = try #require(DocumentRenderer(compositing: .sRGB).render(document, store: store))
        let light = try #require(DocumentRenderer(compositing: .linearLight).render(document,
                                                                                   store: store))
        #expect(abs(pixel(web, 100, 80).r - 128) <= 1)
        // Light is still there for Current, and still draws what it drew.
        #expect(abs(pixel(light, 100, 80).r - 188) <= 1)
    }

    @Test func aQuarterBlueKeepsItsOwnHue() throws {
        let store = ImageStore()
        let document = try onWhite([plate("#0A84FF", CGRect(x: 40, y: 40, width: 120, height: 80),
                                          opacity: 0.5)], store: store)
        let web = try #require(DocumentRenderer(compositing: .sRGB).render(document, store: store))
        let p = pixel(web, 100, 80)
        // rgba(10,132,255,.5) over white, as CSS mixes it: 133, 194, 255.
        #expect(abs(p.r - 133) <= 1)
        #expect(abs(p.g - 194) <= 1)
        #expect(p.b >= 254)
    }

    // MARK: - Nothing opaque moves

    /// Only see-through paint depends on where it is mixed. A drawing of solid
    /// colours, a picture and words comes out byte for byte the same.
    @Test func anOpaqueDrawingIsTheSameInEitherSpace() throws {
        let store = ImageStore()
        let checks = SVGExportRenderTests.checkerboard(80, 60)
        var picture = Layer(name: "Picture", content: .image(store.register(checks)),
                            frame: CGRect(x: 100, y: 90, width: 80, height: 60))
        picture.style.opacity = 1
        let words = Layer(name: "Words",
                          content: .text(TextContent(string: "Photonz", fontName: "Helvetica",
                                                     fontSize: 22, colorHex: "#1C1C1E")),
                          frame: CGRect(x: 10, y: 110, width: 90, height: 30))
        let document = try onWhite([
            plate("#FF3B30", CGRect(x: 10, y: 10, width: 60, height: 40)),
            plate("#34C759", CGRect(x: 80, y: 10, width: 60, height: 40)),
            plate("#0A84FF", CGRect(x: 30, y: 60, width: 140, height: 20)),
            picture, words
        ], store: store)
        let size = Self.canvas
        let web = try #require(DocumentRenderer(compositing: .sRGB).render(document, store: store))
        let light = try #require(DocumentRenderer(compositing: .linearLight).render(document,
                                                                                   store: store))
        let a = SVGExportRenderTests.pixels(of: web, size: size)
        let b = SVGExportRenderTests.pixels(of: light, size: size)
        // Away from the edges of the type, where a partly covered pixel is
        // see-through paint like any other, every byte agrees.
        var worst = 0
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) where !(y >= 108 && y < 142 && x < 102) {
                let i = (y * Int(size.width) + x) * 4
                for c in 0..<4 { worst = max(worst, abs(Int(a[i + c]) - Int(b[i + c]))) }
            }
        }
        #expect(worst <= 1, "an opaque drawing moved by \(worst) levels between the two spaces")
    }

    // MARK: - The shadow in the exported file

    /// The case the task was filed for: a card's shadow over a white page,
    /// exported and drawn back by the system's own SVG reader.
    @Test func aShadowOverWhiteComesBackFromTheFileTheShadeTheCanvasDrew() throws {
        let store = ImageStore()
        var card = plate("#FFFFFF", CGRect(x: 40, y: 30, width: 110, height: 80))
        card.style.effects = [.shadow(ShadowStyle(radius: 5, offset: CGSize(width: 4, height: 8),
                                                  colorHex: "#000000", opacity: 0.55))]
        let document = try onWhite([card], store: store)
        let (canvas, file) = try drawnBothWays(document, store: store, name: "shadow-on-white")
        #expect(SVGExportRenderTests.meanDifference(between: canvas, and: file) <= 1)
        // In the shadow under the card's bottom edge, well clear of the card.
        let i = (116 * Int(Self.canvas.width) + 100) * 4
        #expect(Int(canvas[i]) < 230, "the probe pixel is not in the shadow")
        #expect(abs(Int(canvas[i]) - Int(file[i])) <= 1,
                "canvas draws \(canvas[i]) where the file draws \(file[i])")
    }

    /// Over nothing, so the shadow's own colour is all there is to judge. A
    /// navy shadow has to come back navy, not darkened by its own opacity.
    @Test func aColouredShadowOverNothingComesBackTheSameColour() throws {
        let store = ImageStore()
        var card = plate("#FFFFFF", CGRect(x: 40, y: 30, width: 110, height: 80))
        card.style.effects = [.shadow(ShadowStyle(radius: 5, offset: CGSize(width: 4, height: 8),
                                                  colorHex: "#0A2540", opacity: 0.85))]
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [card])
        let (canvas, file) = try drawnBothWays(document, store: store, name: "coloured-shadow")
        #expect(SVGExportRenderTests.meanDifference(between: canvas, and: file) <= 1)
        let i = (116 * Int(Self.canvas.width) + 100) * 4
        #expect(canvas[i + 3] > 40, "the probe pixel is not in the shadow")
        for c in 0..<4 {
            #expect(abs(Int(canvas[i + c]) - Int(file[i + c])) <= 1,
                    "channel \(c): canvas \(canvas[i + c]), file \(file[i + c])")
        }
    }

    private func drawnBothWays(_ document: PhotonzDocument, store: ImageStore,
                               name: String) throws -> (canvas: [UInt8], file: [UInt8]) {
        let renderer = DocumentRenderer(compositing: .sRGB)
        let mine = try #require(renderer.render(document, store: store))
        let result = SVGExporter.export(document, store: store, renderer: renderer)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-svg-\(name)-\(UUID().uuidString).svg")
        try result.text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let theirs = try #require(SVGExportRenderTests.rasterize(url, size: document.canvasSize))
        return (SVGExportRenderTests.pixels(of: mine, size: document.canvasSize), theirs)
    }

    // MARK: - Following the app's setting

    /// A renderer that follows a setting redraws the WHOLE canvas when the
    /// setting changes, rather than patching the old frame, so a canvas that is
    /// open when the switch is flipped never shows the two mixed together.
    @Test func aRendererFollowingTheSettingRedrawsWhenItChanges() throws {
        let store = ImageStore()
        let document = try onWhite([plate("#000000", CGRect(x: 40, y: 40, width: 120, height: 80),
                                          opacity: 0.5)], store: store)
        let setting = CompositingSetting(.linearLight)
        let renderer = DocumentRenderer(following: setting)
        let before = try #require(renderer.renderInteractive(document, store: store))
        #expect(abs(pixel(before, 100, 80).r - 188) <= 1)
        setting.space = .sRGB
        let after = try #require(renderer.renderInteractive(document, store: store))
        #expect(abs(pixel(after, 100, 80).r - 128) <= 1)
        #expect(renderer.compositing == .sRGB)
    }

    /// Nothing asked for: the app's own setting, which is light until the app
    /// says otherwise.
    @Test func aPlainRendererFollowsTheAppsSetting() {
        #expect(CompositingSetting(.linearLight).space == .linearLight)
        #expect(DocumentRenderer(compositing: .sRGB).compositing == .sRGB)
    }

    // MARK: - A matte by brightness

    /// A mid grey below means half there, in either space: the grey is read in
    /// the numbers the colour picker showed, not in light.
    @Test func aMidGreyMatteShowsAboutHalfInEitherSpace() throws {
        let whole = CGRect(origin: .zero, size: Self.canvas)
        var grade = plate("#FF3366", whole)
        grade.style.matte = .brightness
        var document = PhotonzDocument(canvasSize: Self.canvas)
        document.addLayer(plate("#808080", whole))
        document.addLayer(grade)
        for space in CompositingSpace.allCases {
            let image = try #require(DocumentRenderer(compositing: space)
                .render(document, store: ImageStore()))
            let a = pixel(image, 100, 80).a
            #expect(abs(a - 128) <= 4, "\(space): a mid grey matte showed \(a)/255")
        }
    }
}
