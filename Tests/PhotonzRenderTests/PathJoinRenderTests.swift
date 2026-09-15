import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Welding several shapes into one path does not change the picture.
///
/// The join is allowed to change exactly one thing a person can see: an outline
/// that comes back to where it started CLOSES, and the question says so before
/// it happens. Everything else has to look identical, which is a claim about
/// PIXELS, so these tests composite the document twice — once as the separate
/// shapes and once as the path they became — and compare the two bitmaps byte
/// for byte (`PathJoining.swift`).
@Suite("Joining shapes keeps the picture")
struct PathJoinRenderTests {

    private let canvas = CGSize(width: 400, height: 320)

    private func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return data }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    private func rgba(_ document: PhotonzDocument) throws -> [UInt8] {
        rgba(try #require(DocumentRenderer().render(document, store: ImageStore())))
    }

    private func line(_ from: CGPoint, _ to: CGPoint, width: CGFloat = 6) -> Layer {
        let shape = AnnotationContent(shape: .line, strokeWidth: width, colorHex: "#FF3B30",
                                      start: .zero, end: .zero)
        return AnnotationBuilder.layer(content: shape, from: from, to: to)
    }


    /// Where the two pictures differ, as document points, and how far the worst
    /// one is off.
    ///
    /// Row 0 of the buffer is document y = 0: `orientationProbe` asserts it
    /// rather than assuming it, because a claim about WHERE pixels differ is
    /// worth nothing if the y is upside down.
    private func differingPoints(_ before: [UInt8], _ after: [UInt8]) -> (points: [CGPoint], worst: Int) {
        let width = Int(canvas.width)
        var points: [CGPoint] = []
        var worst = 0
        var seen = Set<Int>()
        for i in 0..<min(before.count, after.count) {
            let d = abs(Int(before[i]) - Int(after[i]))
            guard d > 0 else { continue }
            worst = max(worst, d)
            let pixel = i / 4
            guard seen.insert(pixel).inserted else { continue }
            points.append(CGPoint(x: CGFloat(pixel % width), y: CGFloat(pixel / width)))
        }
        return (points, worst)
    }

    /// Proof that row 0 of the buffer is the top of the document: one short
    /// line drawn in the top left corner only covers rows near zero.
    @Test("The pixel buffer is read the same way up as the document")
    func orientationProbe() throws {
        var document = PhotonzDocument(canvasSize: canvas)
        document.addLayer(line(CGPoint(x: 20, y: 10), CGPoint(x: 20, y: 30)))
        let pixels = try rgba(document)
        let width = Int(canvas.width)
        let covered = (0..<(pixels.count / 4)).filter { pixels[$0 * 4 + 3] > 0 }
        let rows = covered.map { $0 / width }
        #expect((rows.min() ?? 0) < 12)
        #expect((rows.max() ?? 999) < 40)
    }

    private let a = CGPoint(x: 200, y: 60)
    private let b = CGPoint(x: 330, y: 260)
    private let c = CGPoint(x: 70, y: 260)

    @Test("Two lines welded at one end paint exactly what the two lines painted")
    func weldingTwoLinesKeepsThePicture() throws {
        var document = PhotonzDocument(canvasSize: canvas)
        let lines = [line(a, b), line(b, c)]
        for made in lines { document.addLayer(made) }
        let before = try rgba(document)

        let plan = document.turnLayersIntoPath(ids: Set(lines.map(\.id)))
        #expect(plan.leaves == 1)
        #expect(plan.closed == 0)
        let after = try rgba(document)

        // A round cap on each of two lines meeting at a point paints the disc
        // one round join paints, so the joint keeps its shape. Two things do
        // move, and both are a softened edge rather than the shape: at the
        // JOINT two separate layers each laid down their own half-covered edge
        // and the pair composited to less than solid, where one continuous
        // outline is simply solid; and at the free ENDS the outline is now
        // rasterized against one box instead of two, so the cap's curve lands
        // on the pixel grid a fraction differently. A handful of pixels, all of
        // them at a corner or an end, and none of them anywhere along a run.
        let moved = differingPoints(before, after)
        #expect(moved.points.count < 20, "\(moved.points.count) pixels moved, worst \(moved.worst)")
        for point in moved.points {
            #expect([a, b, c].contains { hypot(point.x - $0.x, point.y - $0.y) <= 10 },
                    "a pixel at \(point) moved, and it is not at a corner or an end")
        }
    }

    @Test("Three lines that close into a triangle change only by closing")
    func closingIsTheOneVisibleChange() throws {
        var document = PhotonzDocument(canvasSize: canvas)
        let lines = [line(a, b), line(b, c), line(c, a)]
        for made in lines { document.addLayer(made) }
        let before = try rgba(document)

        let plan = document.turnLayersIntoPath(ids: Set(lines.map(\.id)))
        #expect(plan.closed == 1)
        let after = try rgba(document)

        // Closing a triangle whose three sides were already drawn adds no new
        // run: the last end WAS the first. So the picture is the same triangle,
        // and the only pixels that move are the three seams where the separate
        // layers used to meet.
        let moved = differingPoints(before, after)
        #expect(moved.points.count < 60, "\(moved.points.count) pixels moved, worst \(moved.worst)")
        for point in moved.points {
            #expect([a, b, c].contains { hypot(point.x - $0.x, point.y - $0.y) <= 10 },
                    "a pixel at \(point) moved, and it is not at a corner")
        }
    }

    @Test("The triangle really can be filled once it is closed")
    func aClosedResultCanBeFilled() throws {
        var document = PhotonzDocument(canvasSize: canvas)
        let lines = [line(a, b), line(b, c), line(c, a)]
        for made in lines { document.addLayer(made) }
        document.turnLayersIntoPath(ids: Set(lines.map(\.id)))
        let hollow = try rgba(document)

        let survivor = try #require(document.layers.first)
        document.updateLayer(id: survivor.id) { layer in
            guard var outline = layer.path else { return }
            outline.fillColorHex = "#3478F6"
            layer.content = .path(outline)
        }
        let filled = try rgba(document)

        // The middle of the triangle was transparent and is now blue: the
        // shape has an inside, which is the whole point of closing it.
        let middle = (Int(canvas.height) / 2 * Int(canvas.width) + Int(canvas.width) / 2) * 4
        #expect(hollow[middle + 3] == 0)
        #expect(filled[middle + 3] > 200)
        #expect(filled[middle + 2] > filled[middle])
    }
}
