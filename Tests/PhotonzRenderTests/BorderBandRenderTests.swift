import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Drawing a border costs only the band it covers.
///
/// Sharing a pixel out by area is what stopped the hairline the user reported
/// on 2026-09-09 (`BorderSeamRenderTests`), and it was being done over the
/// whole layer: about ten filters across every pixel of the picture, to change
/// the handful of them the ring actually lands on. A 12-megapixel document
/// with one full-canvas ring paid 9ms a frame for it and 29ms an export.
///
/// Everywhere outside the ring's band the arithmetic is an identity — nothing
/// of the ring is there to share, so the picture keeps the whole pixel — so
/// the work is now confined to four strips round the hole and the rest of the
/// picture is passed straight through.
///
/// The invariant is that confining it changes nothing a person could see:
/// every test here draws the same picture twice, once each way, and compares
/// the two pixel for pixel. They are allowed to differ by up to `rounding`,
/// because a picture asked for in pieces goes through a buffer between the
/// pieces and a picture asked for whole does not. Two parts in 255 is a third
/// of what `BorderSeamRenderTests` already calls rounding rather than a leak,
/// and the seam this replaced was a whole hairline of the wrong colour.
@Suite("Border band confinement")
struct BorderBandRenderTests {

    // MARK: - The strips themselves

    /// The band is covered and the middle is spared. Those are the two halves
    /// of the bargain: miss a pixel of the band and the border has a hole in
    /// it, take the middle and the work was not saved. And no pixel is in two
    /// strips at once, because the strips are added back together.
    @Test func stripsTileTheBandAndSpareTheMiddle() {
        let outer = CGRect(x: 0, y: 0, width: 200, height: 160)
        let hole = CGRect(x: 30, y: 24, width: 140, height: 112)
        let strips = DocumentRenderer.ringStrips(outer: outer, hole: hole)
        #expect(strips.count == 4)
        let slack = DocumentRenderer.ringStripSlack
        for y in stride(from: -slack + 0.5, to: 160 + slack, by: 1) {
            for x in stride(from: -slack + 0.5, to: 200 + slack, by: 1) {
                let point = CGPoint(x: x, y: y)
                let covered = strips.filter { $0.contains(point) }.count
                #expect(covered <= 1, "\(point) is in \(covered) strips at once")
                if outer.contains(point) && !hole.contains(point) {
                    #expect(covered == 1, "\(point) of the band is not drawn")
                }
                if hole.insetBy(dx: 1, dy: 1).contains(point) {
                    #expect(covered == 0, "\(point) of the middle is being drawn for nothing")
                }
            }
        }
    }

    /// The strips reach past the ring's own rectangle, so the join at their
    /// outer edge is off the picture rather than along its edge. Without it
    /// the seam came back along the top of a box at 2.75x zoom, half ring and
    /// half fill, because a layer that lands between two pixels of the canvas
    /// is sampled rather than copied and a hard edge in it is smeared.
    @Test func stripsReachPastTheRing() {
        let outer = CGRect(x: 0, y: 0, width: 200, height: 160)
        let strips = DocumentRenderer.ringStrips(outer: outer,
                                                 hole: CGRect(x: 30, y: 24, width: 140, height: 112))
        let slack = DocumentRenderer.ringStripSlack
        let union = strips.dropFirst().reduce(strips[0]) { $0.union($1) }
        #expect(union == outer.insetBy(dx: -slack, dy: -slack))
    }

    @Test func stripsLandOnWholePixels() {
        let strips = DocumentRenderer.ringStrips(outer: CGRect(x: 10.4, y: 20.6, width: 99.2, height: 60.3),
                                                 hole: CGRect(x: 30.7, y: 40.2, width: 50.1, height: 20.9))
        for strip in strips {
            #expect(strip.minX == strip.minX.rounded() && strip.minY == strip.minY.rounded(),
                    "\(strip) starts between pixels")
            #expect(strip.width == strip.width.rounded() && strip.height == strip.height.rounded(),
                    "\(strip) is a fraction of a pixel wide")
        }
    }

    /// No hole worth cutting means "draw the whole rectangle", which is the
    /// empty list: a ring as thick as the shape has no middle to skip.
    @Test func aRingWithNoMiddleTakesTheWholeRectangle() {
        let outer = CGRect(x: 0, y: 0, width: 40, height: 40)
        #expect(DocumentRenderer.ringStrips(outer: outer, hole: .null).isEmpty)
        #expect(DocumentRenderer.ringStrips(outer: outer, hole: CGRect(x: 19, y: 19, width: 2, height: 2)).isEmpty)
    }

    // MARK: - The picture is the same either way

    /// How far a pixel may move between the two ways of drawing it. One unit
    /// of eight-bit rounding either side of the join, and no more.
    private let rounding = 2

    private let canvas = CGSize(width: 240, height: 200)
    private let box = CGRect(x: 60, y: 50, width: 100, height: 80)

    private func document(radius: CGFloat, _ border: BorderEffect) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: canvas)
        let sheet = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#00FF00",
                                      start: .zero,
                                      end: CGPoint(x: canvas.width, y: canvas.height),
                                      fillColorHex: "#00FF00")
        document.addLayer(Layer(name: "Sheet", content: .annotation(sheet),
                                frame: CGRect(origin: .zero, size: canvas), style: LayerStyle()))
        var style = LayerStyle()
        style.effects = [.border(border)]
        var fill = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#FF0000",
                                     start: .zero,
                                     end: CGPoint(x: box.width, y: box.height),
                                     fillColorHex: "#FF0000")
        fill.cornerRadius = radius
        document.addLayer(Layer(name: "Box", content: .annotation(fill), frame: box, style: style))
        return document
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// The same document drawn both ways, and the worst disagreement between
    /// the two in any channel of any pixel.
    private func worstDifference(radius: CGFloat, _ border: BorderEffect,
                                 scale: CGFloat = 1) -> (off: Int, at: Int) {
        func draw(confined: Bool) -> CGImage {
            let renderer = DocumentRenderer()
            renderer.laysRingsOverTheWholePicture = !confined
            return renderer.render(document(radius: radius, border), store: ImageStore(),
                                   scale: scale)!
        }
        let confined = pixels(draw(confined: true))
        let whole = pixels(draw(confined: false))
        #expect(confined.count == whole.count)
        var worst = 0, at = 0
        for i in 0..<min(confined.count, whole.count) {
            let off = abs(Int(confined[i]) - Int(whole[i]))
            if off > worst { worst = off; at = i }
        }
        return (worst, at)
    }

    @Test(arguments: [BorderPosition.inside, .center, .outside])
    func aBorderDrawsTheSamePictureConfinedAsItDoesWhole(position: BorderPosition) {
        let border = BorderEffect(width: 6, colorHex: "#000000", position: position)
        let (off, at) = worstDifference(radius: 0, border)
        #expect(off <= rounding, "\(position) border differs by \(off) at byte \(at)")
    }

    @Test func aRoundedBorderDrawsTheSamePicture() {
        let border = BorderEffect(width: 5, colorHex: "#000000", position: .inside)
        let (off, at) = worstDifference(radius: 18, border)
        #expect(off <= rounding, "rounded border differs by \(off) at byte \(at)")
    }

    @Test(arguments: ["#0000FF80", "#0000FF1A", "#0000FF0D", "#0000FF03"])
    func aSeeThroughBorderDrawsTheSamePicture(hex: String) {
        let border = BorderEffect(width: 7, colorHex: hex, position: .center)
        let (off, at) = worstDifference(radius: 12, border)
        #expect(off <= rounding, "\(hex) border differs by \(off) at byte \(at)")
    }

    @Test func aGradientBorderDrawsTheSamePicture() {
        var border = BorderEffect(width: 9, colorHex: "#000000", position: .inside)
        border.paint = Paint(hex: "#000000", kind: .linear,
                             stops: [GradientStop(hex: "#000000", position: 0),
                                     GradientStop(hex: "#FFFFFF", position: 1)],
                             angle: 45)
        let (off, at) = worstDifference(radius: 20, border)
        #expect(off <= rounding, "gradient border differs by \(off) at byte \(at)")
    }

    /// Zoomed, where the shape still lands on whole pixels of the canvas.
    @Test(arguments: [CGFloat(1.5), 2, 4])
    func aBorderDrawsTheSamePictureAtEveryZoom(scale: CGFloat) {
        for position in [BorderPosition.inside, .center, .outside] {
            let border = BorderEffect(width: 8, colorHex: "#000000", position: position)
            let (off, at) = worstDifference(radius: 20, border, scale: scale)
            #expect(off <= rounding, "\(position) at \(scale)x differs by \(off) at byte \(at)")
        }
    }

    /// At a zoom that puts the shape BETWEEN two pixels of the canvas, the row
    /// its edge runs through is half the shape and half what is behind it, so
    /// a black border on a green sheet should come out half green.
    ///
    /// This is the one place the two ways of drawing it part company, and the
    /// confined one is the one that is right: at 2.75x this row read 188 of
    /// green confined — dead on half, since half of full green in light is 188
    /// on screen — against 225 laid over the whole picture, which is a border
    /// covering a quarter of a row it covers half of. The seam checks pass
    /// either way; this is the edge being as dark as it looks.
    @Test func theRowTheEdgeRunsThroughIsHalfCovered() {
        let scale: CGFloat = 2.75
        let border = BorderEffect(width: 8, colorHex: "#000000", position: .inside)
        let renderer = DocumentRenderer()
        let image = renderer.render(document(radius: 20, border), store: ImageStore(), scale: scale)!
        let data = pixels(image)
        // The shape's top edge is at 50 points, which is half way through row
        // 137 at this zoom; x is the middle of the straight run between the
        // rounded corners.
        let row = 137, column = 300
        let i = (row * image.width + column) * 4
        let green = Int(data[i + 1])
        #expect(abs(green - 188) <= 6, "the edge row reads \(green) of green, not the 188 half of it is")
    }

    /// A ring thicker than the shape has no middle to pass through, so it
    /// takes the whole-rectangle path; it must still draw the same picture.
    @Test func aRingThickerThanTheShapeDrawsTheSamePicture() {
        let border = BorderEffect(width: 60, colorHex: "#000000", position: .inside)
        let (off, at) = worstDifference(radius: 0, border)
        #expect(off <= rounding, "solid ring differs by \(off) at byte \(at)")
    }
}
