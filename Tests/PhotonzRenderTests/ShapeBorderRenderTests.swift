import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A Border that follows the shape, actually drawn: round a group of parts as
/// one thing, along an arrow, round a cut-out's visible edge, and still round
/// the box on an opaque picture or when the row says Box. White canvas and a
/// blue ring, so every blue pixel is the ring (`ShapeOutline.swift`).
@Suite("A border follows the shape it is on, drawn")
struct ShapeBorderRenderTests {

    private let canvas = CGSize(width: 400, height: 300)

    private func white(_ size: CGSize) -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()!
    }

    /// A clear square with a solid red disc in it: a sticker.
    private func sticker(side: Int) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 10, dy: 10))
        return context.makeImage()!
    }

    private struct Picture {
        let data: [UInt8]
        let width: Int
        /// Whether the pixel at (x, y), top-left, is the blue ring's.
        func isBlue(_ x: Int, _ y: Int) -> Bool {
            let i = (y * width + x) * 4
            return data[i + 2] > 150 && data[i] < 110 && data[i + 1] < 110
        }
        /// How many blue pixels lie in `rect`.
        func blue(in rect: CGRect) -> Int {
            var count = 0
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) where isBlue(x, y) { count += 1 }
            }
            return count
        }
    }

    private func render(_ layers: [Layer], store: ImageStore = ImageStore()) -> Picture {
        let base = store.register(white(canvas))
        var doc = PhotonzDocument.withBaseImage(base)
        for layer in layers { doc.addLayer(layer) }
        let image = DocumentRenderer().render(doc, store: store)!
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Picture(data: data, width: w)
    }

    private func ring(_ follows: BorderFollows = .shape, width: CGFloat = 4) -> LayerEffect {
        var border = BorderEffect(width: width, colorHex: "#0000FF", position: .outside)
        border.follows = follows
        return .border(border)
    }

    private func oval(_ box: CGRect) -> Layer {
        Layer(name: "Oval",
              content: .annotation(AnnotationContent(shape: .ellipse, strokeWidth: 0,
                                                     colorHex: "#FF0000", start: .zero,
                                                     end: CGPoint(x: box.width, y: box.height),
                                                     fillColorHex: "#FF0000")),
              frame: box)
    }

    /// Two ovals side by side, overlapping, in a group: x 50...200 and
    /// 150...300, y 50...200.
    private func cloud(_ follows: BorderFollows = .shape) -> Layer {
        var group = Layer(name: "Cloud",
                          content: .group(GroupContent(children: [
                              oval(CGRect(x: 50, y: 50, width: 150, height: 150)),
                              oval(CGRect(x: 150, y: 50, width: 150, height: 150))
                          ])),
                          frame: .zero)
        group.style.effects = [ring(follows)]
        return group
    }

    /// One ring round the whole group: on the outline beside each oval, none
    /// in the group box's empty corners, and none down the middle where the
    /// two ovals meet.
    @Test func aGroupIsRingedAsOneShape() {
        let picture = render([cloud()])
        // Just left of the left oval, and just right of the right one.
        #expect(picture.blue(in: CGRect(x: 44, y: 120, width: 6, height: 10)) > 0)
        #expect(picture.blue(in: CGRect(x: 300, y: 120, width: 6, height: 10)) > 0)
        // The group's box reaches its corners; the ovals do not.
        #expect(picture.blue(in: CGRect(x: 46, y: 46, width: 12, height: 12)) == 0)
        #expect(picture.blue(in: CGRect(x: 292, y: 192, width: 12, height: 12)) == 0)
        // Inside the shape, where the left oval's edge runs through the right
        // one: no ring there, since it is one shape.
        #expect(picture.blue(in: CGRect(x: 185, y: 90, width: 30, height: 70)) == 0)
    }

    /// The row says Box: the ring goes round the group's box, corners and all.
    @Test func aGroupWhoseBorderSaysBoxIsBoxed() {
        let picture = render([cloud(.box)])
        #expect(picture.blue(in: CGRect(x: 46, y: 46, width: 6, height: 6)) > 0)
    }

    /// An arrow is ringed along its shaft and round its head as one shape,
    /// never as a rectangle round its box.
    @Test func anArrowIsRingedAlongItsShaft() {
        var arrow = Layer(name: "Arrow",
                          content: .annotation(AnnotationContent(shape: .arrow, strokeWidth: 6,
                                                                 colorHex: "#FF0000",
                                                                 start: CGPoint(x: 10, y: 60),
                                                                 end: CGPoint(x: 290, y: 60))),
                          frame: CGRect(x: 50, y: 50, width: 300, height: 120))
        arrow.style.effects = [ring()]
        let picture = render([arrow])
        // Above and below the shaft, half way along it.
        #expect(picture.blue(in: CGRect(x: 190, y: 100, width: 20, height: 8)) > 0)
        #expect(picture.blue(in: CGRect(x: 190, y: 113, width: 20, height: 8)) > 0)
        // The box's corners and its empty middle are left alone.
        #expect(picture.blue(in: CGRect(x: 44, y: 44, width: 14, height: 14)) == 0)
        #expect(picture.blue(in: CGRect(x: 150, y: 140, width: 100, height: 30)) == 0)
    }

    /// A cut-out picture is ringed round the edge its transparency makes; an
    /// opaque one, a screenshot, round its box as it always was.
    @Test func aCutOutIsRingedRoundItsVisibleEdge() {
        let store = ImageStore()
        let ref = store.register(sticker(side: 200))
        var layer = Layer(name: "Sticker", content: .image(ref),
                          frame: CGRect(x: 100, y: 50, width: 200, height: 200))
        layer.style.effects = [ring()]
        let picture = render([layer], store: store)
        // Just outside the disc at its left and its top.
        #expect(picture.blue(in: CGRect(x: 104, y: 140, width: 6, height: 20)) > 0)
        #expect(picture.blue(in: CGRect(x: 190, y: 54, width: 20, height: 6)) > 0)
        // The square's corners stay bare.
        #expect(picture.blue(in: CGRect(x: 94, y: 44, width: 14, height: 14)) == 0)
    }

    @Test func anOpaquePictureIsStillBoxed() {
        let store = ImageStore()
        let ref = store.register(white(CGSize(width: 200, height: 140)))
        var layer = Layer(name: "Screenshot", content: .image(ref),
                          frame: CGRect(x: 100, y: 80, width: 200, height: 140))
        layer.style.effects = [ring()]
        #expect(PictureEdges.edge(for: ref, store: store) == nil)
        let picture = render([layer], store: store)
        // A square corner, ringed.
        #expect(picture.blue(in: CGRect(x: 96, y: 76, width: 4, height: 4)) > 0)
    }

    /// Dragging a group's border wider is the same outline every frame, so
    /// it is merged once and every later frame reads it back.
    @Test func widerRingsRoundTheSameGroupReuseItsOutline() {
        let renderer = DocumentRenderer()
        let store = ImageStore()
        let base = store.register(white(canvas))
        var doc = PhotonzDocument.withBaseImage(base)
        var group = cloud()
        doc.addLayer(group)
        _ = renderer.render(doc, store: store)
        for width in stride(from: 5, through: 12, by: 1) {
            group.style.effects = [ring(width: CGFloat(width))]
            doc.layers[doc.layers.count - 1] = group
            #expect(renderer.render(doc, store: store) != nil)
        }
        #expect(renderer.followedOutlinesMerged == 1)
    }

    /// The file says the same: a group's ring is written round its outline,
    /// not as a rectangle.
    @Test func anSVGRingsTheGroupsOutline() {
        let doc = PhotonzDocument(canvasSize: canvas, layers: [cloud()])
        let svg = SVGExport.write(doc).text
        #expect(svg.contains("mask id=\"ring-"))
        #expect(!svg.contains("<rect x=\"48\" y=\"48\""))
    }
}

/// What a Width drag on a drawn package costs: the user's own case, a group of
/// eight faces on a 1440 by 1024 canvas, redrawn at 2x the way a retina canvas
/// draws it, once per new width. The bar is a frame, 16 ms (`CLAUDE.md`), and
/// the guard here is looser than that only so a busy machine cannot fail it;
/// the measured numbers are printed and go in the task's log.
@Suite("A Width drag on a drawn package stays inside a frame")
struct ShapeBorderDragCostTests {

    /// Eight faces of a box drawn in paths, the way Ask draws one.
    static func package() -> Layer {
        func face(_ points: [CGPoint], _ hex: String) -> Layer {
            let xs = points.map(\.x), ys = points.map(\.y)
            let origin = CGPoint(x: xs.min()!, y: ys.min()!)
            let anchors = points.map { PathAnchor(point: CGPoint(x: $0.x - origin.x, y: $0.y - origin.y)) }
            let content = PathContent(anchors: anchors, isClosed: true, strokeWidth: 0,
                                      fill: Paint(hex: hex))
            return Layer(name: "Face", content: .path(content),
                         frame: CGRect(x: origin.x, y: origin.y,
                                       width: xs.max()! - origin.x, height: ys.max()! - origin.y))
        }
        let top = [CGPoint(x: 600, y: 650), CGPoint(x: 780, y: 520), CGPoint(x: 960, y: 650), CGPoint(x: 780, y: 780)]
        let left = [CGPoint(x: 600, y: 650), CGPoint(x: 780, y: 780), CGPoint(x: 780, y: 970), CGPoint(x: 600, y: 840)]
        let right = [CGPoint(x: 780, y: 780), CGPoint(x: 960, y: 650), CGPoint(x: 960, y: 840), CGPoint(x: 780, y: 970)]
        let tape = [CGPoint(x: 660, y: 610), CGPoint(x: 700, y: 585), CGPoint(x: 900, y: 730), CGPoint(x: 860, y: 755)]
        let tapeSide = [CGPoint(x: 860, y: 755), CGPoint(x: 900, y: 730), CGPoint(x: 900, y: 790), CGPoint(x: 860, y: 815)]
        let seam = [CGPoint(x: 770, y: 785), CGPoint(x: 790, y: 785), CGPoint(x: 790, y: 965), CGPoint(x: 770, y: 965)]
        let shade = [CGPoint(x: 600, y: 700), CGPoint(x: 700, y: 770), CGPoint(x: 700, y: 900), CGPoint(x: 600, y: 830)]
        let glint = [CGPoint(x: 900, y: 690), CGPoint(x: 950, y: 660), CGPoint(x: 950, y: 700), CGPoint(x: 900, y: 730)]
        let faces = [face(top, "#D29F82"), face(left, "#5E241A"), face(right, "#B76E58"),
                     face(tape, "#E4E7EB"), face(tapeSide, "#9AA5AF"), face(seam, "#D29F82"),
                     face(shade, "#4A1C14"), face(glint, "#C7866F")]
        return Layer(name: "Product Package", content: .group(GroupContent(children: faces)),
                     frame: .zero)
    }

    @Test func dragTheWidth() {
        let store = ImageStore()
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: [])
        var package = Self.package()
        doc.addLayer(package)
        let renderer = DocumentRenderer()
        var timings: [Double] = []
        var boxTimings: [Double] = []
        for follows in [BorderFollows.box, .shape] {
            for step in 0..<24 {
                var border = BorderEffect(width: CGFloat(1 + step), colorHex: "#000000",
                                          position: .outside)
                border.follows = follows
                package.style.effects = [.border(border)]
                doc.layers[doc.layers.count - 1] = package
                let start = DispatchTime.now().uptimeNanoseconds
                let image = renderer.render(doc, store: store, scale: 2)
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                #expect(image != nil)
                // The first frame of each kind pays for its outline once.
                if step > 0 { if follows == .shape { timings.append(ms) } else { boxTimings.append(ms) } }
            }
        }
        let median = timings.sorted()[timings.count / 2]
        let boxMedian = boxTimings.sorted()[boxTimings.count / 2]
        print("Width drag on the package at 2x, 1440x1024: shape ring median \(String(format: "%.1f", median)) ms, worst \(String(format: "%.1f", timings.max() ?? 0)) ms; box ring median \(String(format: "%.1f", boxMedian)) ms")
        #expect(renderer.followedOutlinesMerged == 1)
        // A stopwatch reading: collected without gating where
        // PHOTONZ_PERF_GATE says report (61.9 ms on GitHub's three core VM, two
        // tests at a time, on unchanged code, 2026-10-26).
        if MachineSpeed.isGating {
            #expect(median < 48)
        }
    }
}
