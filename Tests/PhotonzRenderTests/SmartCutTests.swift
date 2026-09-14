import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// Cutting a piece out of a picture and healing the space it came from, over
/// a fixture with a flat surround, a gradient surround, a non-rectangular
/// marquee, and a surround that justifies nothing.
///
/// Everything here is checked by SAMPLING PIXELS. "Looks whole" is not a claim
/// a test can make and not one worth making.
@Suite("Cutting a piece out and healing behind it")
struct SmartCutTests {

    // MARK: - Fixtures

    /// A picture painted by `paint`, in image pixels, top-left origin.
    private func picture(_ w: Int, _ h: Int, _ paint: (CGContext, Int) -> Void) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        paint(context, h)
        return context.makeImage()!
    }

    /// A flat panel with something sitting on it, which is the thing to cut.
    private func panelWithAMark(_ w: Int = 120, _ h: Int = 90) -> CGImage {
        picture(w, h) { context, height in
            context.setFillColor(CGColor(srgbRed: 0.04, green: 0.51, blue: 0.98, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            // Top-left (40,30,40,30) flipped into the context.
            context.fill(CGRect(x: 40, y: CGFloat(height - 60), width: 40, height: 30))
        }
    }

    /// A flat panel with a ROUND mark on it, which is the thing somebody would
    /// draw an elliptical marquee round.
    private func panelWithARoundMark(_ w: Int = 120, _ h: Int = 90) -> CGImage {
        picture(w, h) { context, height in
            context.setFillColor(CGColor(srgbRed: 0.04, green: 0.51, blue: 0.98, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 40, y: CGFloat(height - 60), width: 40, height: 30))
        }
    }

    /// A flat panel with a mark that has a hole through it, like the letter O.
    /// The hole is panel, so a wand that picked the ink has panel on BOTH
    /// sides of it and its ring has to read the inside as well as the outside.
    private func panelWithARingMark(_ w: Int = 120, _ h: Int = 90) -> CGImage {
        picture(w, h) { context, height in
            context.setFillColor(CGColor(srgbRed: 0.04, green: 0.51, blue: 0.98, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 40, y: CGFloat(height - 60), width: 40, height: 30))
            context.setFillColor(CGColor(srgbRed: 0.04, green: 0.51, blue: 0.98, alpha: 1))
            context.fill(CGRect(x: 52, y: CGFloat(height - 50), width: 16, height: 10))
        }
    }

    /// An even top-to-bottom ramp with a mark sitting on it.
    private func rampWithAMark(_ w: Int = 120, _ h: Int = 90) -> CGImage {
        picture(w, h) { context, height in
            for y in 0..<h {
                let t = (Double(y) + 0.5) / Double(h)
                context.setFillColor(CGColor(srgbRed: 0.2 + 0.5 * t, green: 0.2 + 0.5 * t,
                                             blue: 0.2 + 0.5 * t, alpha: 1))
                context.fill(CGRect(x: 0, y: CGFloat(height - y - 1), width: CGFloat(w), height: 1))
            }
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 40, y: CGFloat(height - 60), width: 40, height: 30))
        }
    }

    /// Noise no straight line and no flat colour can account for.
    private func staticNoise(_ w: Int = 120, _ h: Int = 90) -> CGImage {
        var seed = UInt64(20260914)
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFF) / 255
        }
        return picture(w, h) { context, height in
            for y in 0..<h {
                for x in 0..<w {
                    context.setFillColor(CGColor(srgbRed: next(), green: next(), blue: next(), alpha: 1))
                    context.fill(CGRect(x: CGFloat(x), y: CGFloat(height - y - 1), width: 1, height: 1))
                }
            }
        }
    }

    private func box(_ rect: CGRect) -> CGPath { CGPath(rect: rect, transform: nil) }
    private func ellipse(_ rect: CGRect) -> CGPath { CGPath(ellipseIn: rect, transform: nil) }

    // MARK: - Reading a result back

    /// One pixel of an image, unpremultiplied, at top-left coordinates.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> RGBA {
        let bytes = LayerSeparator.read(image)!
        let i = (y * image.width + x) * 4
        let a = Double(bytes[i + 3]) / 255
        let scale = a > 0 ? 1 / a : 0
        return RGBA(r: Double(bytes[i]) / 255 * scale, g: Double(bytes[i + 1]) / 255 * scale,
                    b: Double(bytes[i + 2]) / 255 * scale, a: a)
    }

    /// Every distinct byte quadruple inside `rect` of an image.
    private func colors(_ image: CGImage, in rect: CGRect) -> Set<[UInt8]> {
        let bytes = LayerSeparator.read(image)!
        var seen: Set<[UInt8]> = []
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let i = (y * image.width + x) * 4
                seen.insert([bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]])
            }
        }
        return seen
    }

    private let mark = CGRect(x: 40, y: 30, width: 40, height: 30)

    // MARK: - The flat case

    /// The headline: cut the white mark off the blue panel and the panel is
    /// one colour where the mark was, byte for byte. A fill that is nearly
    /// right is a visible smudge on flat UI, which is most of what this app
    /// is pointed at.
    @Test func aPieceCutFromASolidPanelLeavesThatPanelOneColourExactly() throws {
        let source = panelWithAMark()
        let cut = try #require(SmartCut.cut(source, path: box(mark)))
        #expect(cut.heal == .matched)
        #expect(cut.fill == .solid(pixel(source, 5, 5)))

        // The healed picture: the space the mark came from is the panel colour
        // and nothing else, and it is the SAME bytes the panel already had.
        let inTheSpace = colors(cut.patched, in: mark)
        #expect(inTheSpace.count == 1)
        let elsewhere = colors(cut.patched, in: CGRect(x: 0, y: 0, width: 20, height: 20))
        #expect(inTheSpace == elsewhere)
        // Nothing of the white mark survives anywhere in the picture.
        #expect(pixel(cut.patched, 50, 40).r < 0.2)
    }

    /// The piece is the piece, at full strength, and it is the size of the
    /// piece rather than the size of the picture.
    @Test func thePieceComesOutWholeAndTheSizeOfThePiece() throws {
        let cut = try #require(SmartCut.cut(panelWithAMark(), path: box(mark)))
        #expect(cut.pieceRect == mark)
        #expect(cut.piece.width == 40)
        #expect(cut.piece.height == 30)
        let middle = pixel(cut.piece, 20, 15)
        #expect(middle.a == 1)
        #expect(middle.r > 0.98)
        #expect(middle.g > 0.98)
        #expect(middle.b > 0.98)
    }

    /// Moving the piece must reveal the FILL, not a hole and not a second copy
    /// of the piece. Proved by sampling: the space is opaque, it is the panel
    /// colour, and it is not white.
    @Test func movingThePieceRevealsAFilledBackgroundAndNotASecondCopy() throws {
        let cut = try #require(SmartCut.cut(panelWithAMark(), path: box(mark)))
        for point in [(41, 31), (60, 45), (78, 58)] {
            let behind = pixel(cut.patched, point.0, point.1)
            #expect(behind.a == 1)                      // not a hole
            #expect(behind.b > 0.9 && behind.r < 0.1)   // the panel, not the white mark
        }
    }

    /// A piece the size of the whole layer would be cut with nothing around it
    /// to read. The space it came from is honestly empty rather than filled
    /// with a colour nobody could justify.
    @Test func aPieceThatTakesTheWholePictureLeavesAnHonestlyEmptySpace() throws {
        let source = panelWithAMark(40, 40)
        let cut = try #require(SmartCut.cut(source, path: box(CGRect(x: 0, y: 0, width: 40, height: 40))))
        #expect(cut.heal == .cleared)
        #expect(cut.fill == nil)
        #expect(pixel(cut.patched, 20, 20).a == 0)
    }

    // MARK: - The gradient case

    /// Cut a mark off an even ramp and the space it came from carries the ramp
    /// on: the fill at the top of the space matches the picture just above it,
    /// and at the bottom matches just below it.
    @Test func aPieceCutFromAnEvenRampLeavesARampThatMatchesItsSurroundings() throws {
        let source = rampWithAMark()
        let cut = try #require(SmartCut.cut(source, path: box(mark)))
        #expect(cut.heal == .matched)
        if case .gradient(_, _, let axis) = cut.fill { #expect(axis == .down) }
        else { Issue.record("expected a ramp, got \(String(describing: cut.fill))") }

        // A ramp, not a flat: the top of the space is plainly darker than the
        // bottom of it.
        let top = pixel(cut.patched, 60, 31), bottom = pixel(cut.patched, 60, 58)
        #expect(bottom.r - top.r > 0.1)
        // And it joins what is around it, within a level or two out of 255.
        #expect(abs(pixel(cut.patched, 60, 30).r - pixel(cut.patched, 60, 29).r) < 3.0 / 255)
        #expect(abs(pixel(cut.patched, 60, 59).r - pixel(cut.patched, 60, 60).r) < 3.0 / 255)
        // Nothing of the red mark is left.
        #expect(pixel(cut.patched, 60, 45).r - pixel(cut.patched, 60, 45).g < 0.05)
    }

    // MARK: - A marquee that is not a rectangle

    /// An ellipse: the piece is round, the corners of its box stay with the
    /// picture, and the space inside the ellipse is filled.
    @Test func anEllipticalMarqueeCutsARoundPieceAndHealsARoundSpace() throws {
        let source = panelWithARoundMark()
        let cut = try #require(SmartCut.cut(source, path: ellipse(mark)))
        // The ring follows the curve, so the corners of the box the ellipse is
        // inscribed in never vote: the reading is the panel, exactly.
        #expect(cut.heal == .matched)
        #expect(cut.fill == .solid(pixel(source, 5, 5)))
        // The middle of the piece is the white mark; the corner of its box is
        // outside the ellipse and so is not part of the piece at all.
        #expect(pixel(cut.piece, 20, 15).a > 0.99)
        #expect(pixel(cut.piece, 0, 0).a == 0)
        // In the healed picture the middle of the ellipse is panel.
        #expect(pixel(cut.patched, 60, 45).b > 0.9)
        #expect(pixel(cut.patched, 60, 45).r < 0.1)
        // And the healing stayed inside the outline: the corner of the box the
        // ellipse sits in is untouched, byte for byte.
        #expect(colors(cut.patched, in: CGRect(x: 40, y: 30, width: 3, height: 3))
                    == colors(source, in: CGRect(x: 40, y: 30, width: 3, height: 3)))
    }

    /// What the wand hands over: a path with a bite out of it, which is not a
    /// rectangle and not a convex shape either. The bite's own walls are read
    /// as background, so the fill is still the panel colour.
    @Test func aWandShapedMarqueeWithABiteOutOfItIsCutAndHealed() throws {
        let source = panelWithARingMark()
        let path = CGMutablePath()
        path.addRect(mark)
        path.addRect(CGRect(x: 52, y: 40, width: 16, height: 10))  // the hole (even-odd)
        let cut = try #require(SmartCut.cut(source, path: path))
        // The hole's own walls are read as background too, which is the whole
        // reason the ring walks the outline instead of the box.
        #expect(cut.heal == .matched)
        #expect(cut.fill == .solid(pixel(source, 5, 5)))
        // Nothing inside the hole was ever part of the piece.
        #expect(pixel(cut.piece, 60 - 40, 45 - 30).a == 0)
        // Outside the hole but inside the marquee, the panel came back where
        // the white ink was.
        #expect(pixel(cut.patched, 44, 34).b > 0.9)
        #expect(pixel(cut.patched, 44, 34).r < 0.1)
        // The whole marquee is one colour now: the ink and the hole it went
        // round have become the same panel.
        #expect(colors(cut.patched, in: mark).count == 1)
    }

    // MARK: - When the surroundings justify nothing

    /// A person chose this piece and pressed a key. Refusing to cut would be
    /// ignoring an instruction, so it cuts anyway, fills with the middle
    /// colour of what was around it, and SAYS the fill was a guess.
    @Test func aSurroundThatJustifiesNothingStillCutsAndSaysTheFillWasAGuess() throws {
        let source = staticNoise()
        let cut = try #require(SmartCut.cut(source, path: box(mark)))
        #expect(cut.heal == .guessed)
        // One flat colour, because a guess should not pretend to detail it
        // does not have.
        #expect(colors(cut.patched, in: mark).count == 1)
        guard case .solid(let guessed)? = cut.fill else {
            Issue.record("a guess is always one flat colour")
            return
        }
        // The middle of the ring, so it sits in the noise rather than off it.
        #expect(guessed.r > 0.2 && guessed.r < 0.8)
        // And the piece still came out whole: the noise inside the marquee is
        // on the piece, not left in the picture.
        #expect(pixel(cut.piece, 20, 15).a == 1)
        #expect(pixel(cut.piece, 20, 15) == pixel(source, 60, 45))
    }

    // MARK: - Refusals

    @Test func aMarqueeThatMissesThePictureCutsNothing() {
        let source = panelWithAMark()
        #expect(SmartCut.cut(source, path: box(CGRect(x: 500, y: 500, width: 10, height: 10))) == nil)
        #expect(SmartCut.cut(source, path: box(.zero)) == nil)
    }

    /// A marquee over a part of the layer that is entirely transparent has no
    /// piece in it, so there is nothing to put on a layer of its own.
    @Test func aMarqueeOverNothingAtAllCutsNothing() {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let empty = CGContext(data: nil, width: 60, height: 60, bitsPerComponent: 8,
                              bytesPerRow: 240, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        #expect(SmartCut.cut(empty, path: box(CGRect(x: 10, y: 10, width: 20, height: 20))) == nil)
    }

    /// The layer keeps its box: the healed picture is the same size as the one
    /// that went in, always. That is what lets the locked Background stay the
    /// size of the picture without needing a case of its own.
    @Test func theHealedPictureIsAlwaysTheSizeItWentInAt() throws {
        for path in [box(mark), ellipse(mark)] {
            let cut = try #require(SmartCut.cut(panelWithAMark(), path: path))
            #expect(cut.patched.width == 120)
            #expect(cut.patched.height == 90)
        }
    }
}
