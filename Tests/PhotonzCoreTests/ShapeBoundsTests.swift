import CoreGraphics
import Foundation
import PhotonzCore
import Testing

private typealias Capture = PaintedCapture

/// Whether `rect` is `expected` to within `slack` px on every side. The
/// acceptance bar for a measured shape is 1 px at 1x and 2 px at 2x, so these
/// specimens are held to 1.
private func expectEdges(_ rect: CGRect?, _ expected: CGRect, slack: CGFloat = 1,
                         sourceLocation: SourceLocation = #_sourceLocation) {
    guard let rect else {
        Issue.record("expected \(expected), got nothing", sourceLocation: sourceLocation)
        return
    }
    let ok = abs(rect.minX - expected.minX) <= slack && abs(rect.minY - expected.minY) <= slack
        && abs(rect.maxX - expected.maxX) <= slack && abs(rect.maxY - expected.maxY) <= slack
    if !ok { Issue.record("expected \(expected), got \(rect)", sourceLocation: sourceLocation) }
}

/// Round avatars, icons on tiles, badges and stacks: the things a pair of
/// straight boundaries cannot see (the user, 2026-10-11: "i hover over the
/// avatar and it won't size it. or the stacked set of avatars").
@Suite("Shapes Size mode reads by separating them from their background")
struct ShapeBoundsTests {

    private func shape(_ c: Capture, _ x: Double, _ y: Double,
                       minElement: Double = 20) -> ShapeBounds.Reading? {
        ShapeBounds.shape(at: CGPoint(x: x, y: y), in: c.luma, minElement: minElement)
    }

    // MARK: One shape under the pointer

    @Test func aRoundPhotoAvatarReadsToItsOuterEdge() {
        var c = Capture(w: 240, h: 200, background: 255)
        let avatar = CGRect(x: 40, y: 50, width: 64, height: 64)
        c.portrait(avatar)
        // From the face, the hair, the shirt and the backdrop: the same circle.
        for (x, y) in [(72.0, 80.0), (72.0, 62.0), (72.0, 108.0), (48.0, 82.0)] {
            expectEdges(shape(c, x, y)?.bounds, avatar)
        }
    }

    @Test func aDiscAtOneXReadsWithinAPixel() {
        var c = Capture(w: 120, h: 100, background: 242)
        let dot = CGRect(x: 30, y: 20, width: 32, height: 32)
        c.disc(dot, 60)
        expectEdges(shape(c, 46, 36, minElement: 10)?.bounds, dot)
        // Off the grid: the antialiased fringe is the edge, not a pixel past it.
        var d = Capture(w: 120, h: 100, background: 242)
        let odd = CGRect(x: 30.5, y: 20.5, width: 25, height: 25)
        d.disc(odd, 60)
        expectEdges(shape(d, 43, 33, minElement: 10)?.bounds, odd)
    }

    @Test func anInitialsAvatarReadsTheSameFromOverItsLetters() {
        var c = Capture(w: 200, h: 160, background: 255)
        let avatar = CGRect(x: 40, y: 40, width: 64, height: 64)
        c.disc(avatar, 110)
        // Two white letters cut out of the middle.
        c.fill(CGRect(x: 56, y: 62, width: 6, height: 20), 255)
        c.fill(CGRect(x: 66, y: 62, width: 6, height: 20), 255)
        c.fill(CGRect(x: 76, y: 62, width: 12, height: 20), 255)
        let fromFill = shape(c, 50, 72)
        expectEdges(fromFill?.bounds, avatar)
        #expect(fromFill?.onBody == true)
        let fromLetter = shape(c, 59, 72)
        expectEdges(fromLetter?.bounds, avatar)
        #expect(fromLetter?.onBody == true, "a letter is a cut-out of the avatar, not a thing in a hole")
        expectEdges(ElementBounds.candidates(at: CGPoint(x: 59, y: 72), in: c.map,
                                             luma: c.luma, readsShapes: true).first, avatar)
    }

    @Test func anIconOnATintedTileReadsTheTile() {
        var c = Capture(w: 200, h: 160, background: 255)
        let tile = CGRect(x: 40, y: 40, width: 80, height: 80)
        c.roundedRect(tile, radius: 18, 120)
        c.disc(tile.insetBy(dx: 22, dy: 22), 255)
        expectEdges(shape(c, 50, 80)?.bounds, tile)
        expectEdges(ElementBounds.candidates(at: CGPoint(x: 50, y: 80), in: c.map,
                                             luma: c.luma, readsShapes: true).first, tile)
    }

    @Test func aPillBadgeReadsItsCapsule() {
        var c = Capture(w: 200, h: 120, background: 255)
        let pill = CGRect(x: 40, y: 40, width: 80, height: 40)
        c.roundedRect(pill, radius: 20, 70)
        c.text(x: 62, y: 53, glyphs: 3, tone: 255, glyphWidth: 8, gap: 6, height: 14)
        expectEdges(shape(c, 46, 60)?.bounds, pill)
        expectEdges(ElementBounds.candidates(at: CGPoint(x: 46, y: 60), in: c.map,
                                             luma: c.luma, readsShapes: true).first, pill)
    }

    @Test func aPaleAvatarThatNearlyMeltsIntoThePageStillReads() {
        var c = Capture(w: 240, h: 200, background: 255)
        let avatar = CGRect(x: 40, y: 50, width: 80, height: 80)
        c.portrait(avatar, backdrop: (232, 205))
        expectEdges(shape(c, 52, 70)?.bounds, avatar)
    }

    @Test func aSoftPhotoReadsItsFrame() {
        var c = Capture(w: 300, h: 220, background: 250)
        let photo = CGRect(x: 30, y: 30, width: 200, height: 120)
        c.paint(within: photo, inside: { x, y in photo.contains(CGPoint(x: x, y: y)) }) { x, y in
            120 + 60 * sin(x / 17) * cos(y / 11)
        }
        expectEdges(shape(c, 130, 90)?.bounds, photo)
    }

    @Test func theOpenPageIsNotAShape() {
        var c = Capture(w: 200, h: 160, background: 255)
        c.disc(CGRect(x: 40, y: 40, width: 64, height: 64), 110)
        #expect(shape(c, 150, 120) == nil)
    }

    @Test func somethingSmallerThanTheFloorIsNotOffered() {
        var c = Capture(w: 200, h: 160, background: 255)
        c.disc(CGRect(x: 40, y: 40, width: 12, height: 12), 60)
        #expect(shape(c, 46, 46, minElement: 20) == nil)
    }

    @Test func aWhiteButtonInAFilledBannerIsAHoleNotTheBanner() {
        // The pointer is on white inside a bordered control sitting in a dark
        // banner: the control is the shape, never the banner it sits in, and
        // the ladder keeps the button first, as it always did.
        var c = Capture(w: 400, h: 200, background: 255)
        c.fill(CGRect(x: 20, y: 40, width: 360, height: 100), 60)
        let button = CGRect(x: 120, y: 60, width: 160, height: 60)
        c.box(button, border: 40, inside: 255, width: 2)
        let reading = shape(c, 200, 90)
        if let reading { expectEdges(reading.bounds, button, slack: 2) }
        let ladder = ElementBounds.candidates(at: CGPoint(x: 200, y: 90), in: c.map, luma: c.luma, readsShapes: true)
        expectEdges(ladder.first, button, slack: 3)
    }

    // MARK: A stack

    /// Three 48 px avatars every 32 px, each wearing a 4 px ring of page that
    /// cuts it out of the one before, the way a facepile is drawn.
    private func stack() -> (Capture, [CGRect], CGRect) {
        var c = Capture(w: 320, h: 160, background: 255)
        var avatars: [CGRect] = []
        for i in 0..<3 {
            let r = CGRect(x: 60 + 32 * i, y: 50, width: 48, height: 48)
            c.disc(r.insetBy(dx: -4, dy: -4), 255)
            c.portrait(r, backdrop: (Double(150 + 20 * i), Double(90 + 15 * i)))
            avatars.append(r)
        }
        return (c, avatars, CGRect(x: 60, y: 50, width: 112, height: 48))
    }

    @Test func aStackedAvatarReadsAsTheWholeCircleItIs() {
        // The first two are crescents: only the last is whole on screen. A
        // spec quotes the avatar's size, so the hidden part is filled back in
        // from the arc that shows.
        let (c, avatars, _) = stack()
        expectEdges(shape(c, 70, 74)?.bounds, avatars[0])
        expectEdges(shape(c, 104, 74)?.bounds, avatars[1])
        expectEdges(shape(c, 150, 74)?.bounds, avatars[2])
    }

    @Test func rightBracketStepsOutFromOneAvatarToTheStack() {
        let (c, avatars, whole) = stack()
        let ladder = ElementBounds.candidates(at: CGPoint(x: 104, y: 74), in: c.map, luma: c.luma, readsShapes: true)
        expectEdges(ladder.first, avatars[1])
        #expect(ladder.count >= 2)
        if ladder.count >= 2 { expectEdges(ladder[1], whole) }
    }

    @Test func avatarsSpacedApartStillGroupButANameBesideThemDoesNot() {
        var c = Capture(w: 400, h: 160, background: 255)
        let a = CGRect(x: 40, y: 50, width: 48, height: 48)
        let b = CGRect(x: 96, y: 50, width: 48, height: 48)
        c.portrait(a)
        c.portrait(b)
        c.text(x: 170, y: 66, glyphs: 6)
        let reading = shape(c, 64, 74)
        expectEdges(reading?.bounds, a)
        guard let reading else { return }
        expectEdges(ShapeBounds.group(of: reading, in: c.luma), CGRect(x: 40, y: 50, width: 104, height: 48))
    }

    @Test func aLoneAvatarHasNoGroup() {
        var c = Capture(w: 300, h: 160, background: 255)
        c.portrait(CGRect(x: 40, y: 50, width: 48, height: 48))
        c.text(x: 108, y: 66, glyphs: 6)
        guard let reading = shape(c, 64, 74) else {
            Issue.record("no avatar")
            return
        }
        #expect(ShapeBounds.group(of: reading, in: c.luma) == nil)
    }

    // MARK: Nothing that worked before changes

    @Test func theShapeReaderIsOffUnlessAsked() {
        // Current's calipers read their subjects through the same reader, and
        // Current does not change: only Next's Size mode asks for shapes.
        let (c, avatars, _) = stack()
        let plain = ElementBounds.candidates(at: CGPoint(x: 104, y: 74), in: c.map, luma: c.luma)
        #expect(plain.first != avatars[1])
    }

    @Test func aLineOfTextIsStillReadAsALine() {
        var c = Capture(w: 400, h: 120, background: 255)
        c.text(x: 60, y: 40, glyphs: 10, tone: 30, glyphWidth: 6, gap: 3, height: 16)
        let ladder = ElementBounds.candidates(at: CGPoint(x: 64, y: 48), in: c.map, luma: c.luma, readsShapes: true)
        expectEdges(ladder.first, CGRect(x: 60, y: 40, width: 87, height: 16))
    }

    @Test func anAvatarBesideItsNameReadsTheAvatarNotTheLine() {
        // Close enough that the line reader joins them into one "line".
        var c = Capture(w: 400, h: 140, background: 255)
        let avatar = CGRect(x: 40, y: 40, width: 64, height: 64)
        c.portrait(avatar)
        c.text(x: 114, y: 64, glyphs: 8, tone: 30, glyphWidth: 6, gap: 3, height: 16)
        let ladder = ElementBounds.candidates(at: CGPoint(x: 72, y: 80), in: c.map, luma: c.luma, readsShapes: true)
        expectEdges(ladder.first, avatar)
    }

    @Test func aButtonWithAShadowReadsTheButtonNotItsShadow() {
        var c = Capture(w: 400, h: 240, background: 242)
        let button = CGRect(x: 100, y: 80, width: 160, height: 56)
        // A soft shadow, 10 px of fall-off, a little lower than the button.
        for k in stride(from: 10, through: 1, by: -1) {
            let tone = UInt8(242 - (11 - k) * 2)
            c.fill(button.offsetBy(dx: 0, dy: 3).insetBy(dx: CGFloat(-k), dy: CGFloat(-k)), tone)
        }
        c.box(button, border: 150, inside: 255, width: 2)
        let ladder = ElementBounds.candidates(at: CGPoint(x: 180, y: 108), in: c.map, luma: c.luma, readsShapes: true)
        expectEdges(ladder.first, button, slack: 3)
    }

    // MARK: A box drawn around the thing

    @Test func aLooseBoxAroundOneAvatarSnapsToThatAvatar() {
        let (c, avatars, _) = stack()
        // Loose, and clipping a little of each neighbour.
        let box = CGRect(x: 96, y: 38, width: 56, height: 72)
        expectEdges(ShapeBounds.content(in: box, luma: c.luma), avatars[1])
    }

    @Test func aLooseBoxAroundTheStackSnapsToTheStack() {
        let (c, _, whole) = stack()
        expectEdges(ShapeBounds.content(in: CGRect(x: 40, y: 30, width: 150, height: 90), luma: c.luma),
                    whole)
    }

    @Test func aBoxDrawnALittleTightStillFindsTheEdge() {
        var c = Capture(w: 240, h: 200, background: 255)
        let avatar = CGRect(x: 40, y: 50, width: 64, height: 64)
        c.portrait(avatar)
        expectEdges(ShapeBounds.content(in: avatar.insetBy(dx: 4, dy: 3), luma: c.luma), avatar)
    }

    @Test func aBoxCuttingThroughAWordDropsTheWholeWord() {
        var c = Capture(w: 400, h: 160, background: 255)
        let avatar = CGRect(x: 40, y: 40, width: 64, height: 64)
        c.portrait(avatar)
        c.text(x: 124, y: 64, glyphs: 8, tone: 30, glyphWidth: 6, gap: 3, height: 16)
        // Takes the avatar and the first two letters of the word beside it.
        let box = CGRect(x: 28, y: 28, width: 116, height: 88)
        expectEdges(ShapeBounds.content(in: box, luma: c.luma), avatar)
    }

    @Test func aBoxAroundNothingKeepsNothing() {
        var c = Capture(w: 240, h: 200, background: 255)
        c.portrait(CGRect(x: 40, y: 50, width: 64, height: 64))
        #expect(ShapeBounds.content(in: CGRect(x: 130, y: 20, width: 80, height: 80), luma: c.luma) == nil)
    }

    @Test func aBoxAroundAButtonSnapsToTheButton() {
        var c = Capture(w: 400, h: 200, background: 242)
        let button = CGRect(x: 100, y: 60, width: 160, height: 56)
        c.box(button, border: 150, inside: 255, width: 2)
        c.text(x: 140, y: 80, glyphs: 6)
        expectEdges(ShapeBounds.content(in: CGRect(x: 80, y: 40, width: 210, height: 100), luma: c.luma),
                    button)
    }

    @Test func aBoxOnAnUnanalyzedImageKeepsNothing() {
        #expect(ShapeBounds.content(in: CGRect(x: 0, y: 0, width: 50, height: 50), luma: .empty) == nil)
    }
}
