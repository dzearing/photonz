import AppKit
import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// A layer turned in space is drawn where the camera sees it
/// (`layers-can-turn-about-x-and-y-and-move-in-depth`, `Space3D.swift`).
///
/// Every check reads the pixels back and holds them against the corners the
/// model says the layer lands on (`PhotonzDocument.drawnQuad`), which is also
/// what the outline and the click use, so the three cannot drift apart.
@Suite("2.5D: a turned layer draws where the camera sees it")
struct Space3DRenderTests {

    /// The picture as rows of RGBA, top row first.
    struct Pixels {
        let width: Int
        let height: Int
        let data: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            data = bytes
        }

        /// The colour at a point in the document's top-left space.
        func at(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let index = (y * width + x) * 4
            return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
        }

        func at(_ p: CGPoint) -> (r: Int, g: Int, b: Int) { at(Int(p.x), Int(p.y)) }

        func isRed(_ p: CGPoint) -> Bool { let c = at(p); return c.r > 200 && c.g < 60 && c.b < 60 }
        func isGreen(_ p: CGPoint) -> Bool { let c = at(p); return c.g > 200 && c.r < 60 }
        func isBlack(_ p: CGPoint) -> Bool { let c = at(p); return c.r < 30 && c.g < 30 && c.b < 30 }

        var redCount: Int {
            var count = 0
            for index in stride(from: 0, to: data.count, by: 4)
            where data[index] > 200 && data[index + 1] < 60 { count += 1 }
            return count
        }
    }

    static let canvas = CGSize(width: 400, height: 300)

    static func rect(_ frame: CGRect, hex: String, name: String = "Card") -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: hex,
                                                     start: .zero,
                                                     end: CGPoint(x: frame.width, y: frame.height),
                                                     fillColorHex: hex)),
              frame: frame)
    }

    static func ground() -> Layer { rect(CGRect(origin: .zero, size: canvas), hex: "#000000", name: "Ground") }

    static let cardBox = CGRect(x: 100, y: 75, width: 200, height: 150)

    static func render(_ document: PhotonzDocument) throws -> Pixels {
        Pixels(try #require(DocumentRenderer().render(document, store: ImageStore())))
    }

    /// Whether `p` is inside the convex quad, `margin` points in from every
    /// edge (negative for outside by that much).
    static func inside(_ p: CGPoint, _ quad: [CGPoint], margin: CGFloat) -> Bool {
        for index in quad.indices {
            let a = quad[index], b = quad[(index + 1) % quad.count]
            let edge = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let length = hypot(edge.x, edge.y)
            // Clockwise on a y-down screen: inside is to the right of each edge.
            let cross = (edge.x * (p.y - a.y) - edge.y * (p.x - a.x)) / length
            if cross < margin { return false }
        }
        return true
    }

    @Test("A document nobody turned draws byte for byte as before, default camera or none")
    func flatIsUntouched() throws {
        let plain = PhotonzDocument(canvasSize: Self.canvas,
                                    layers: [Self.ground(), Self.rect(Self.cardBox, hex: "#FF0000")])
        var flat = plain
        flat.camera = SceneCamera()
        flat.layers[1].turn3D = LayerTurn3D(pivotDepth: -50)
        #expect(!flat.isSeenInSpace)
        let a = try Self.render(plain)
        let b = try Self.render(flat)
        #expect(a.data == b.data)
    }

    @Test("A card swung on Y fills exactly the corners the camera sees, at three moments of a flip")
    func flipFillsItsQuad() throws {
        for degrees in [30.0, 60.0, 150.0] {
            var card = Self.rect(Self.cardBox, hex: "#FF0000")
            card.turn3D = LayerTurn3D(rotationY: degrees)
            let document = PhotonzDocument(canvasSize: Self.canvas, layers: [Self.ground(), card])
            let quad = try #require(document.drawnQuad(of: card.id))
            let front = Space3D.facesViewer(quad)
            // Past a quarter turn the card shows its back, so the corners run
            // the other way round; inside is then on the other side of each
            // edge.
            let ordered = front ? quad : quad.reversed()
            let pixels = try Self.render(document)
            var checkedIn = 0, checkedOut = 0, wrong = 0
            for y in stride(from: 2, to: 298, by: 4) {
                for x in stride(from: 2, to: 398, by: 4) {
                    let p = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    if Self.inside(p, ordered, margin: 1.5) {
                        checkedIn += 1
                        if !pixels.isRed(p) { wrong += 1 }
                    } else if !Self.inside(p, ordered, margin: -1.5) {
                        checkedOut += 1
                        if !pixels.isBlack(p) { wrong += 1 }
                    }
                }
            }
            #expect(checkedIn > 100, "at \(degrees)°")
            #expect(checkedOut > 1000, "at \(degrees)°")
            #expect(wrong == 0, "at \(degrees)°: \(wrong) pixels off the projected card")
        }
    }

    /// A picture red on its left half and green on its right.
    static func halves(_ store: ImageStore) throws -> Layer {
        let w = 200, h = 150
        let context = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h))
        let image = try #require(context.makeImage())
        let ref = ImageRef(pixelSize: CGSize(width: w, height: h))
        store.register(image, as: ref)
        return Layer(name: "Halves", content: .image(ref), frame: cardBox)
    }

    @Test("Turned a little it reads the right way round; past a quarter turn its back is the mirror")
    func picturesKeepTheirSides() throws {
        let store = ImageStore()
        var card = try Self.halves(store)
        card.turn3D = LayerTurn3D(rotationY: 30)
        let front = Pixels(try #require(DocumentRenderer().render(
            PhotonzDocument(canvasSize: Self.canvas, layers: [Self.ground(), card]), store: store)))
        #expect(front.isRed(CGPoint(x: 150, y: 150)))
        #expect(front.isGreen(CGPoint(x: 230, y: 150)))
        card.turn3D?.rotationY = 150
        let back = Pixels(try #require(DocumentRenderer().render(
            PhotonzDocument(canvasSize: Self.canvas, layers: [Self.ground(), card]), store: store)))
        #expect(back.isGreen(CGPoint(x: 170, y: 150)))
        #expect(back.isRed(CGPoint(x: 230, y: 150)))
        // Tipped on X the top goes away and the picture stays upright.
        card.turn3D = LayerTurn3D(rotationX: 40)
        let tipped = Pixels(try #require(DocumentRenderer().render(
            PhotonzDocument(canvasSize: Self.canvas, layers: [Self.ground(), card]), store: store)))
        #expect(tipped.isRed(CGPoint(x: 150, y: 150)))
        #expect(tipped.isGreen(CGPoint(x: 250, y: 150)))
    }

    @Test("A card that hides its back draws nothing once it has turned away")
    func hiddenBack() throws {
        var card = Self.rect(Self.cardBox, hex: "#FF0000")
        card.turn3D = LayerTurn3D(rotationY: 150, showsBackFace: false)
        let hidden = try Self.render(PhotonzDocument(canvasSize: Self.canvas, layers: [Self.ground(), card]))
        #expect(hidden.redCount == 0)
        card.turn3D?.rotationY = 30
        let shown = try Self.render(PhotonzDocument(canvasSize: Self.canvas, layers: [Self.ground(), card]))
        #expect(shown.redCount > 10_000)
    }

    @Test("Pushed back it draws smaller, brought near it draws bigger, about the middle")
    func depthScales() throws {
        var card = Self.rect(CGRect(x: 175, y: 125, width: 50, height: 50), hex: "#FF0000")
        card.turn3D = LayerTurn3D(depth: Projection3D(camera: nil, canvas: Self.canvas).eyeDistance / 2)
        let near = try Self.render(PhotonzDocument(canvasSize: Self.canvas, layers: [Self.ground(), card]))
        // Twice the size: 100 by 100 about the middle.
        #expect(near.isRed(CGPoint(x: 152, y: 102)))
        #expect(near.isBlack(CGPoint(x: 148, y: 98)))
        #expect(abs(near.redCount - 10_000) < 500)
    }

    @Test("In a group keeping 3D the nearer card draws on top, whatever the stack says")
    func keptGroupDrawsNearestLast() throws {
        var green = Self.rect(CGRect(x: 0, y: 0, width: 200, height: 150), hex: "#00FF00", name: "Near")
        green.turn3D = LayerTurn3D(depth: 100)
        let red = Self.rect(CGRect(x: 40, y: 30, width: 200, height: 150), hex: "#FF0000", name: "Far")
        var content = GroupContent(children: [green, red])
        content.keeps3D = true
        let group = Layer(name: "Box", content: .group(content), frame: CGRect(x: 60, y: 60, width: 0, height: 0))
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [Self.ground(), group])
        let overlap = CGPoint(x: 200, y: 150)
        #expect(try Self.render(document).isGreen(overlap))
        // A flattened group keeps the stack's order.
        var flat = document
        flat.updateLayer(id: group.id) { layer in
            if case .group(var inside) = layer.content {
                inside.keeps3D = nil
                layer.content = .group(inside)
            }
        }
        #expect(try Self.render(flat).isRed(overlap))
    }

    @Test("A turned group turns as one card, its child's own tilt riding on it")
    func groupTurnsAsOne() throws {
        let child = Self.rect(CGRect(x: 0, y: 0, width: 200, height: 150), hex: "#FF0000")
        var group = Layer(name: "Card", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 100, y: 75, width: 0, height: 0))
        group.turn3D = LayerTurn3D(rotationY: 50)
        group.style.opacity = 0.999
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [Self.ground(), group])
        let quad = try #require(document.drawnQuad(of: child.id))
        let pixels = try Self.render(document)
        let middle = CGPoint(x: (quad[0].x + quad[2].x) / 2, y: (quad[0].y + quad[2].y) / 2)
        #expect(pixels.isRed(middle))
        // The right edge went away: just inside the box's right edge, but
        // outside the projected card, is ground.
        #expect(pixels.isBlack(CGPoint(x: 296, y: 150)))
    }

    @Test("Depth of field blurs a card by its distance from the focus")
    func depthOfField() throws {
        var card = Self.rect(Self.cardBox, hex: "#FF0000")
        card.turn3D = LayerTurn3D(depth: -400)
        var document = PhotonzDocument(canvasSize: Self.canvas, layers: [Self.ground(), card])
        let sharp = try Self.render(document)
        document.camera = SceneCamera(focus: CameraFocus(depth: 0, amount: 4))
        let soft = try Self.render(document)
        let quad = try #require(document.drawnQuad(of: card.id))
        // A few points outside the card's drawn left edge: dark when sharp,
        // lit by the blur when out of focus.
        let outside = CGPoint(x: quad[0].x - 4, y: (quad[0].y + quad[3].y) / 2)
        #expect(sharp.at(outside).r < 10)
        #expect(soft.at(outside).r > 20)
    }

    @Test("A camera moved across moves every flat layer the other way")
    func cameraPans() throws {
        var document = PhotonzDocument(canvasSize: Self.canvas,
                                       layers: [Self.ground(), Self.rect(Self.cardBox, hex: "#FF0000")])
        document.camera = SceneCamera(x: 50)
        let pixels = try Self.render(document)
        #expect(pixels.isRed(CGPoint(x: 52, y: 150)))
        #expect(pixels.isBlack(CGPoint(x: 260, y: 150)))
    }

    @Test("The canvas's own frame and the export's frame agree at three moments of a keyed flip")
    func canvasAndExportAgree() throws {
        var card = Self.rect(Self.cardBox, hex: "#FF0000")
        card.time = LayerTime(inMS: 0, outMS: 2000)
        var document = PhotonzDocument(canvasSize: Self.canvas, layers: [Self.ground(), card])
        document.durationMS = 2000
        document.startKeying(layerID: card.id, .motion(.rotationY), atDocumentTimeMS: 0)
        document.setKeyedValue(.number(180), layerID: card.id, .motion(.rotationY), atDocumentTimeMS: 1200)
        let canvas = DocumentRenderer()
        for ms in [300, 600, 900] {
            let shown = document.drawn(atTimeMS: ms)
            // The canvas draws through the incremental path into its own
            // buffer; the still and movie exports draw the whole frame.
            let live = Pixels(try #require(canvas.renderInteractive(shown, store: ImageStore())))
            let exported = Pixels(try #require(DocumentRenderer().render(shown, store: ImageStore(), scale: 1)))
            var differ = 0
            for index in stride(from: 0, to: live.data.count, by: 4)
            where abs(Int(live.data[index]) - Int(exported.data[index])) > 2 { differ += 1 }
            print("[3d] canvas vs export at \(ms)ms: \(differ) of \(live.width * live.height) pixels differ")
            #expect(differ == 0, "at \(ms)ms")
        }
    }
    @Test("An SVG of a still with a turned card draws what the canvas draws, at three moments of a flip")
    func svgAgrees() throws {
        for degrees in [30.0, 60.0, 150.0] {
            var card = Self.rect(Self.cardBox, hex: "#FF0000")
            card.turn3D = LayerTurn3D(rotationY: degrees, depth: 40)
            let document = PhotonzDocument(canvasSize: Self.canvas, layers: [Self.ground(), card])
            let store = ImageStore()
            let result = SVGExporter.export(document, store: store)
            #expect(result.fallbacks.contains { $0.reason == "it is turned in 3D" })
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("photonz-svg-3d-\(UUID().uuidString).svg")
            try result.text.write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }
            let theirs = try #require(SVGExportRenderTests.rasterize(url, size: Self.canvas))
            let canvas = try #require(DocumentRenderer().render(document, store: store))
            let mine = SVGExportRenderTests.pixels(of: canvas, size: Self.canvas)
            let mean = SVGExportRenderTests.meanDifference(between: mine, and: theirs)
            var far = 0
            for index in stride(from: 0, to: mine.count, by: 4)
            where abs(Int(mine[index]) - Int(theirs[index])) > 48 { far += 1 }
            print(String(format: "[3d] SVG vs canvas at %.0f°: mean difference %.2f, %d of %d pixels off",
                         degrees, mean, far, mine.count / 4))
            // The picture rides in the file at twice the canvas's pixels and
            // is drawn back down, so the card's edge is a pixel softer: about
            // as many pixels as its outline, the same as any picture an SVG
            // carries (a 2D-turned card with a glow measured 688 on
            // 2026-10-11). Anywhere else would be thousands.
            #expect(mean < 1, "at \(degrees)°")
            #expect(far < mine.count / 4 / 100, "at \(degrees)°")
        }
    }
}
