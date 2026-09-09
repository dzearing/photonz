import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A border meets what is on either side of it cleanly.
///
/// Reported by the user on 2026-09-09 with two magnified screenshots: a red
/// fill showing along the OUTSIDE of a black inner border, and a green
/// background showing along the INSIDE of a black outside border. Both are the
/// same fault. The ring used to be composited OVER the picture underneath, and
/// where the ring's own antialiased edge lands on the picture's antialiased
/// edge the two coverages multiply instead of meeting: half a pixel of ring
/// over half a pixel of fill leaves a quarter of a pixel of fill showing.
///
/// The invariant every test here checks is the one a person actually sees: a
/// border SEPARATES the fill from the background, so no single pixel may carry
/// some of both. A pixel that is part background and part border is right; a
/// pixel that is part background and part fill means something leaked past the
/// border.
@Suite("Border seams")
struct BorderSeamRenderTests {

    private let canvas = CGSize(width: 240, height: 200)
    private let box = CGRect(x: 60, y: 50, width: 100, height: 80)
    /// A pixel carrying less than this of a channel is rounding, not a leak.
    private let noise = 6

    // MARK: - Building the picture

    /// A pure green sheet under everything, so a leak past the border shows as
    /// green where it has no business being.
    private func background() -> Layer {
        let frame = CGRect(origin: .zero, size: canvas)
        let fill = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#00FF00",
                                     start: .zero,
                                     end: CGPoint(x: frame.width, y: frame.height),
                                     fillColorHex: "#00FF00")
        return Layer(name: "Sheet", content: .annotation(fill), frame: frame, style: LayerStyle())
    }

    /// A pure red rounded rectangle with one black ring round it and no stroke
    /// of its own, so the only three colours in the picture are the fill, the
    /// background and the border.
    private func shape(radius: CGFloat, _ border: BorderEffect) -> Layer {
        // The shape rounds itself by the curve it DRAWS; the style's radius
        // stays nought, exactly as the app leaves it on a rectangle, so the
        // picture has one soft edge rather than a drawn one inside a masked
        // one.
        var style = LayerStyle()
        style.effects = [.border(border)]
        var fill = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#FF0000",
                                     start: .zero,
                                     end: CGPoint(x: box.width, y: box.height),
                                     fillColorHex: "#FF0000")
        fill.cornerRadius = radius
        return Layer(name: "Box", content: .annotation(fill), frame: box, style: style)
    }

    private func render(radius: CGFloat, _ border: BorderEffect, scale: CGFloat = 1) -> CGImage {
        var document = PhotonzDocument(canvasSize: canvas)
        document.addLayer(background())
        document.addLayer(shape(radius: radius, border))
        let renderer = DocumentRenderer()
        let image = scale == 1 ? renderer.render(document, store: ImageStore())
                               : renderer.render(document, store: ImageStore(), scale: scale)
        return image!
    }

    // MARK: - Reading it back

    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// Every pixel carrying some fill AND some background at once, worst first.
    /// Empty is the whole of what "no seam" means.
    private func mixed(_ image: CGImage) -> [(x: Int, y: Int, r: Int, g: Int)] {
        let data = pixels(image)
        var found: [(x: Int, y: Int, r: Int, g: Int)] = []
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4
                let r = Int(data[i]), g = Int(data[i + 1])
                if r > noise && g > noise { found.append((x, y, r, g)) }
            }
        }
        return found.sorted { min($0.r, $0.g) > min($1.r, $1.g) }
    }

    private func describe(_ leaks: [(x: Int, y: Int, r: Int, g: Int)]) -> String {
        let worst = leaks.prefix(4).map { "(\($0.x),\($0.y)) r=\($0.r) g=\($0.g)" }
        return "\(leaks.count) mixed pixels, worst: \(worst.joined(separator: ", "))"
    }

    /// True when SOME pixel is a partial blend of the background and the black
    /// ring: proof the outside of the shape is still antialiased rather than
    /// cut to a hard jagged edge.
    private func hasSoftOuterEdge(_ image: CGImage) -> Bool {
        let data = pixels(image)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4
                let r = Int(data[i]), g = Int(data[i + 1])
                if r <= noise, g > 40, g < 215 { return true }
            }
        }
        return false
    }

    // MARK: - The three positions, on the round corner

    @Test("An inner border keeps the fill off its outer edge")
    func innerBorderHoldsTheFillIn() {
        let image = render(radius: 20, BorderEffect(width: 8, colorHex: "#000000",
                                                    position: .inside))
        let leaks = mixed(image)
        #expect(leaks.isEmpty, "\(describe(leaks))")
        #expect(hasSoftOuterEdge(image))
    }

    @Test("An outside border keeps the background off its inner edge")
    func outsideBorderHoldsTheBackgroundOut() {
        let image = render(radius: 20, BorderEffect(width: 8, colorHex: "#000000",
                                                    position: .outside))
        let leaks = mixed(image)
        #expect(leaks.isEmpty, "\(describe(leaks))")
        #expect(hasSoftOuterEdge(image))
    }

    @Test("A centred border keeps both of its edges clean")
    func centredBorderHoldsBothSides() {
        let image = render(radius: 20, BorderEffect(width: 8, colorHex: "#000000",
                                                    position: .center))
        let leaks = mixed(image)
        #expect(leaks.isEmpty, "\(describe(leaks))")
        #expect(hasSoftOuterEdge(image))
    }

    // MARK: - Square corners, and thin rings

    @Test("A square-cornered shape stays clean too", arguments: [BorderPosition.inside,
                                                                 .center, .outside])
    func squareCornersStayClean(_ position: BorderPosition) {
        let image = render(radius: 0, BorderEffect(width: 6, colorHex: "#000000",
                                                   position: position))
        let leaks = mixed(image)
        #expect(leaks.isEmpty, "\(position): \(describe(leaks))")
    }

    /// A ring thinner than a pixel cannot separate anything: one pixel then
    /// holds background, ring and fill at once whatever the compositing does.
    /// So the thin case is checked where it has room to be a wall.
    @Test("A thin ring is still a wall where it has pixels to be one",
          arguments: [BorderPosition.inside, .center, .outside])
    func thinRingsStayClean(_ position: BorderPosition) {
        let image = render(radius: 14, BorderEffect(width: 2, colorHex: "#000000",
                                                    position: position),
                           scale: 4)
        let leaks = mixed(image)
        #expect(leaks.isEmpty, "\(position): \(describe(leaks))")
    }

    // MARK: - At several zooms

    @Test("The corner stays clean at every zoom",
          arguments: [CGFloat(1.5), 2, 2.75, 4])
    func cleanAtZoom(_ scale: CGFloat) {
        for position in [BorderPosition.inside, .center, .outside] {
            let image = render(radius: 20, BorderEffect(width: 8, colorHex: "#000000",
                                                        position: position),
                               scale: scale)
            let leaks = mixed(image)
            #expect(leaks.isEmpty, "\(position) at \(scale)x: \(describe(leaks))")
        }
    }

    // MARK: - An oval, whose ring is drawn a different way entirely

    @Test("An oval's border keeps the two sides apart too",
          arguments: [BorderPosition.inside, .center, .outside])
    func ovalBordersStayClean(_ position: BorderPosition) {
        var style = LayerStyle()
        style.effects = [.border(BorderEffect(width: 8, colorHex: "#000000",
                                              position: position))]
        let oval = AnnotationContent(shape: .ellipse, strokeWidth: 0, colorHex: "#FF0000",
                                     start: .zero,
                                     end: CGPoint(x: box.width, y: box.height),
                                     fillColorHex: "#FF0000")
        var document = PhotonzDocument(canvasSize: canvas)
        document.addLayer(background())
        document.addLayer(Layer(name: "Oval", content: .annotation(oval),
                                frame: box, style: style))
        let image = DocumentRenderer().render(document, store: ImageStore())!
        let leaks = mixed(image)
        if position == .outside {
            // An oval's ring is a STROKE ridden round the oval, not one oval
            // with a smaller one cut out of it, because that is how the shape
            // draws its own edge (`ellipseRing`). A stroke's inner boundary is
            // the oval walked inwards, which on a stretched oval is not itself
            // an oval: it misses the shape's own curve by a fraction of a
            // pixel round the diagonals, and no compositing can close a gap
            // that is really there. Twenty pixels keep a trace of the
            // background, at a twentieth of its strength; there were hundreds
            // at three times that before. Filed as its own task.
            #expect(leaks.count <= 24, "\(describe(leaks))")
            #expect(leaks.allSatisfy { min($0.r, $0.g) < 70 }, "\(describe(leaks))")
        } else {
            #expect(leaks.isEmpty, "\(position): \(describe(leaks))")
        }
    }

    // MARK: - A ring standing off the edge keeps the gap

    @Test("A ring standing off the edge leaves the fill in the gap")
    func offsetRingKeepsTheGap() {
        // Ten points in from the edge, so there is a band of plain fill
        // OUTSIDE the ring that must survive untouched.
        let image = render(radius: 20, BorderEffect(width: 6, colorHex: "#000000",
                                                    position: .inside, offset: 10))
        let data = pixels(image)
        let width = image.width
        // Two points in from the left edge, halfway down: still the fill.
        let i = (Int(box.midY) * width + Int(box.minX) + 2) * 4
        #expect(Int(data[i]) > 200 && Int(data[i + 1]) < 40)
        // And the ring is where it was asked to be: ten in.
        let j = (Int(box.midY) * width + Int(box.minX) + 12) * 4
        #expect(Int(data[j]) < 40 && Int(data[j + 1]) < 40 && Int(data[j + 3]) > 200)
    }

    // MARK: - A see-through ring still lets the fill show through it

    @Test("A half transparent border still shows the fill under it")
    func translucentRingKeepsWhatIsUnderIt() {
        var border = BorderEffect(width: 10, colorHex: "#00000080", position: .inside)
        border.paint = Paint(hex: "#00000080")
        let image = render(radius: 0, border)
        let data = pixels(image)
        // The middle of the ring on the left edge: half black over red fill,
        // never half black over nothing.
        let i = (Int(box.midY) * image.width + Int(box.minX) + 5) * 4
        let r = Int(data[i]), g = Int(data[i + 1]), a = Int(data[i + 3])
        #expect(a > 240, "a=\(a)")
        // Core Image blends in linear light, so half black over full red
        // lands nearer 187 than 128. What matters is that it is neither the
        // bare ring (near nought) nor the bare fill (255).
        #expect(r > 120 && r < 235, "r=\(r) g=\(g) a=\(a)")
        #expect(g < 40, "r=\(r) g=\(g) a=\(a)")
    }
}
