import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore
@testable import PhotonzRender

/// A finished still picture (an export, a copy, the picture an agent looks
/// at) keeps white white wherever nothing is drawn.
///
/// The eval's component sheet of 2026-11-03 came back with faint boxes beside
/// its Off and On headers, and all three judges named them as ghost marks.
/// They were not left behind by words the sheet had set and taken away: they
/// were patches of the white page drawn at 254 instead of 255. Mixing the way
/// the web does (Next's compositing) works in plain sRGB numbers, and Core
/// Image keeps its in-between pictures in half floats, which hold 1.0 exactly
/// but lose a fraction of a step on every pass through one. A big enough
/// picture splits into several passes, and where the white went through more
/// of them it came out a step darker, in rectangles that moved whenever
/// anything else on the page moved. A still renderer keeps its in-between
/// pictures in full floats.
@Suite("A still picture keeps white white")
struct StillPictureStaysWhiteTests {

    /// The sheet the eval's skill run built: its title and every
    /// add_component call it made, in order, as the app makes them, the
    /// canvas growing under the table the way the app grows it.
    static func sheet() throws -> (PhotonzDocument, ImageStore) {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/component-sheet-calls", withExtension: "json"))
        let calls = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let store = ImageStore()
        func page(_ size: CGSize) throws -> ImageRef {
            store.register(try #require(SolidImage.make(size: size, hex: "#FFFFFF")))
        }
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: [])
        var background = Layer(name: "Background", content: .image(try page(doc.canvasSize)),
                               frame: CGRect(origin: .zero, size: doc.canvasSize))
        background.isLocked = true
        doc.layers = [background]
        let measure: (TextContent, CGFloat?) -> CGSize = { content, width in
            TextRasterizer.naturalSize(content, maxWidth: width ?? .greatestFiniteMagnitude)
        }
        let ink: (TextContent) -> CGVector = { TextRasterizer.inkCentreOffset($0) }
        for call in calls {
            let tool = try #require(call["tool"] as? String)
            let arguments = try AgentJSON.parse(try JSONSerialization.data(withJSONObject: call["arguments"] ?? [:]))
            switch AgentTools.request(tool: tool, arguments: arguments) {
            case .success(.addComponent(nil, let spec)):
                var trial = doc
                guard let made = try? trial.agentAddComponent(spec, measure: measure, ink: ink).get() else { continue }
                doc = trial
                if let sheet = made.sheet {
                    let needed = sheet.canvas(around: doc.canvasSize)
                    if needed != doc.canvasSize {
                        doc.setCanvasSize(needed, anchor: .topLeft)
                        let grown = try page(needed)
                        doc.updateLayer(id: background.id) { layer in
                            layer.content = .image(grown)
                            layer.frame = CGRect(origin: .zero, size: needed)
                        }
                    }
                }
            case .success(.addText(nil, let text)):
                var layer = TextBuilder.layer(content: text.content, at: text.origin,
                                              naturalSize: measure(text.content, nil))
                layer.name = text.name ?? "Text"
                doc.addLayer(layer)
            case .failure:
                // A call the app turned down (two looks too alike) is skipped,
                // as the app skipped it.
                continue
            default:
                Issue.record("the fixture's \(tool) call did not read")
            }
        }
        return (doc, store)
    }

    static func rgba(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixels
    }

    /// The pixels of `picture` that are not pure white where nothing but the
    /// white page is drawn: where `bare`, the same document with its page
    /// hidden, is fully see-through. The outermost pixels are left out: a
    /// scaled canvas can end part way across its last one.
    static func offWhite(_ picture: CGImage, bare: CGImage) -> Int {
        let drawn = rgba(picture), nothing = rgba(bare)
        let w = picture.width, h = picture.height
        guard drawn.count == nothing.count, drawn.count == w * h * 4, w > 2, h > 2 else { return -1 }
        var count = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let at = (y * w + x) * 4
                guard nothing[at + 3] == 0 else { continue }
                if drawn[at] != 255 || drawn[at + 1] != 255 || drawn[at + 2] != 255 { count += 1 }
            }
        }
        return count
    }

    /// `doc` drawn by `renderer` at `scale`, and its off-white count.
    static func offWhite(_ doc: PhotonzDocument, _ store: ImageStore, _ renderer: DocumentRenderer,
                         scale: CGFloat) throws -> Int {
        var bare = doc
        bare.updateLayer(id: doc.layers[0].id) { $0.isVisible = false }
        let picture = try #require(renderer.render(doc, store: store, scale: scale))
        let nothing = try #require(renderer.render(bare, store: store, scale: scale))
        return offWhite(picture, bare: nothing)
    }

    /// The scales the eval's 1600 point look lands on, and its neighbours:
    /// the patches came and went from one scale to the next.
    static let longestSides: [CGFloat] = [1740, 1650, 1600, 1550]

    @Test("The component sheet, mixed the web's way, has no off-white patches", arguments: longestSides)
    func theSheetHasNoOffWhitePatches(longest: CGFloat) throws {
        let (doc, store) = try Self.sheet()
        let scale = min(1, longest / max(doc.canvasSize.width, doc.canvasSize.height))
        let renderer = DocumentRenderer(compositing: .sRGB, forStills: true)
        #expect(try Self.offWhite(doc, store, renderer, scale: scale) == 0,
                "at \(Int(longest)) on its longest side the white page came out a step dark in places")
    }

    /// The same sheet drawn the way the canvas draws it does show the loss, so
    /// the sheet above is a fair test of the still renderer. Recorded rather
    /// than required: whether the half-float passes lose a step here is Core
    /// Image's business, and a later macOS may stop.
    @Test func theCanvasPrecisionShowsTheLossTheStillOneFixes() throws {
        let (doc, store) = try Self.sheet()
        let scale = 1600 / max(doc.canvasSize.width, doc.canvasSize.height)
        let canvas = try Self.offWhite(doc, store, DocumentRenderer(compositing: .sRGB), scale: scale)
        let still = try Self.offWhite(doc, store, DocumentRenderer(compositing: .sRGB, forStills: true), scale: scale)
        print("off-white pixels at 1600: canvas precision \(canvas), still \(still)")
        #expect(still == 0)
    }

    /// Mixing in light (Current) is left exactly as it was: a still renderer
    /// there draws through the same context the canvas does.
    @Test func lightMixingIsUnchanged() throws {
        let (doc, store) = try Self.sheet()
        let scale = 1600 / max(doc.canvasSize.width, doc.canvasSize.height)
        let plain = try #require(DocumentRenderer(compositing: .linearLight).render(doc, store: store, scale: scale))
        let still = try #require(DocumentRenderer(compositing: .linearLight, forStills: true)
            .render(doc, store: store, scale: scale))
        #expect(plain.dataProvider?.data == still.dataProvider?.data)
    }
}
