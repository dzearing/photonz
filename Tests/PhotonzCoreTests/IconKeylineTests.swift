import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The space an icon has to live inside, drawn on an icon frame
/// (`next-icon-frames`).
///
/// A set of icons looks like a set because every glyph in it keeps its drawing
/// inside the same margin and lines up on the same handful of lines. This is
/// the arithmetic of that margin and those lines: what is drawn, where, and on
/// which frames.
@Suite("An icon frame shows the space an icon has to live inside")
struct IconKeylineTests {

    private func square(_ side: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: side, height: side)
    }

    // MARK: - The margin

    @Test("A 24 pixel frame reads as a 20 by 20 live area")
    func twentyFourIsTwenty() {
        let guides = IconKeylines.guides(in: square(24))
        #expect(guides?.liveArea == CGRect(x: 2, y: 2, width: 20, height: 20))
    }

    @Test("Every icon size gets a margin on whole pixels")
    func marginPerSize() {
        // A twelfth of the frame on each side, rounded: the icon grid IS
        // pixels, and a dashed line sitting half on one is the smear the whole
        // feature exists to help somebody avoid.
        #expect(IconKeylines.margin(forSide: 16) == 1)
        #expect(IconKeylines.margin(forSide: 24) == 2)
        #expect(IconKeylines.margin(forSide: 32) == 3)
        #expect(IconKeylines.margin(forSide: 48) == 4)
        #expect(IconKeylines.margin(forSide: 64) == 5)
        #expect(IconKeylines.margin(forSide: 512) == 43)
    }

    @Test("The live area is the frame less its margin on all four sides")
    func liveAreaPerSize() {
        #expect(IconKeylines.guides(in: square(16))?.liveArea
            == CGRect(x: 1, y: 1, width: 14, height: 14))
        #expect(IconKeylines.guides(in: square(64))?.liveArea
            == CGRect(x: 5, y: 5, width: 54, height: 54))
    }

    @Test("The guides move with the frame")
    func guidesFollowTheFrame() {
        let box = CGRect(x: 300, y: 120, width: 24, height: 24)
        let guides = IconKeylines.guides(in: box)
        #expect(guides?.liveArea == CGRect(x: 302, y: 122, width: 20, height: 20))
        #expect(guides?.centerX == 312)
        #expect(guides?.centerY == 132)
    }

    // MARK: - The center lines

    @Test("The center lines cross in the middle of the frame")
    func centerLines() {
        let guides = IconKeylines.guides(in: square(24))
        #expect(guides?.centerX == 12)
        #expect(guides?.centerY == 12)
    }

    // MARK: - The square and the circle

    @Test("A 24 pixel frame reads as an 18 square and a 20 circle")
    func twentyFourShapes() {
        let guides = IconKeylines.guides(in: square(24))
        // The pair every mainstream icon set is drawn to: the square a boxy
        // glyph fills is SMALLER than the circle a round one fills, which is
        // the whole point — equal widths would make the circle look shrunken.
        #expect(guides?.squareKeyline == CGRect(x: 3, y: 3, width: 18, height: 18))
        #expect(guides?.circleKeyline == CGRect(x: 2, y: 2, width: 20, height: 20))
    }

    @Test("The square is inset on whole pixels at every icon size")
    func squareInsetPerSize() {
        // Three twenty-fourths of the frame on each side, rounded, for the
        // same reason the margin rounds: the icon grid IS pixels.
        #expect(IconKeylines.squareInset(forSide: 16) == 2)
        #expect(IconKeylines.squareInset(forSide: 24) == 3)
        #expect(IconKeylines.squareInset(forSide: 32) == 4)
        #expect(IconKeylines.squareInset(forSide: 48) == 6)
        #expect(IconKeylines.squareInset(forSide: 64) == 8)
        #expect(IconKeylines.squareInset(forSide: 512) == 64)
    }

    @Test("The circle fills the live area, so it is tangent to it on all four sides")
    func circleFillsTheLiveArea() {
        for side in [CGFloat(16), 24, 32, 48, 64, 512] {
            let guides = IconKeylines.guides(in: square(side))
            #expect(guides?.circleKeyline == guides?.liveArea)
        }
    }

    @Test("The square always sits inside the live area, never on it")
    func squareIsInsideTheLiveArea() {
        for side in [CGFloat(16), 24, 32, 40, 48, 64, 512] {
            guard let guides = IconKeylines.guides(in: square(side)),
                  let box = guides.squareKeyline else {
                Issue.record("no square at \(side)")
                continue
            }
            let live = guides.liveArea
            #expect(box.width < live.width)
            #expect(live.insetBy(dx: -0.01, dy: -0.01).contains(box))
            // Centred: the same gap on the left as on the right.
            #expect(box.minX - live.minX == live.maxX - box.maxX)
        }
    }

    @Test("The shapes move with the frame")
    func shapesFollowTheFrame() {
        let guides = IconKeylines.guides(in: CGRect(x: 300, y: 120, width: 24, height: 24))
        #expect(guides?.squareKeyline == CGRect(x: 303, y: 123, width: 18, height: 18))
        #expect(guides?.circleKeyline == CGRect(x: 302, y: 122, width: 20, height: 20))
    }

    @Test("A frame too small to hold a square inside the margin draws no square")
    func tinyFramesSkipTheSquare() {
        // At six and eight points the square rounds onto the live area itself,
        // and a guide drawn on top of another guide is not a guide.
        #expect(IconKeylines.guides(in: square(6))?.squareKeyline == nil)
        #expect(IconKeylines.guides(in: square(8))?.squareKeyline == nil)
        // Twelve is the first size with room for both.
        #expect(IconKeylines.guides(in: square(12))?.squareKeyline
            == CGRect(x: 2, y: 2, width: 8, height: 8))
    }

    // MARK: - Marked out as a guide, not as a selection

    @Test("The margin is a band to wash over, not an outline to trace")
    func marginIsABand() {
        // A traced rectangle on the live area is the selection's own kind of
        // mark (UX-PATTERNS D16 rule 3: the selection outline owns the traced
        // border), so the margin is handed over as the two rectangles a wash
        // fills between: the frame, and the hole in it.
        let box = CGRect(x: 300, y: 120, width: 24, height: 24)
        let guides = IconKeylines.guides(in: box)
        #expect(guides?.frame == box)
        #expect(guides?.liveArea == CGRect(x: 302, y: 122, width: 20, height: 20))
    }

    @Test("The square is handed over as four hairlines that run off the frame's edges")
    func squareIsFourHairlines() {
        let guides = IconKeylines.guides(in: CGRect(x: 300, y: 120, width: 24, height: 24))
        // Square is x 303...321, y 123...141; frame is x 300...324, y 120...144.
        #expect(guides?.squareGuideLines == [
            IconKeylineLine(from: CGPoint(x: 303, y: 120), to: CGPoint(x: 303, y: 144)),
            IconKeylineLine(from: CGPoint(x: 321, y: 120), to: CGPoint(x: 321, y: 144)),
            IconKeylineLine(from: CGPoint(x: 300, y: 123), to: CGPoint(x: 324, y: 123)),
            IconKeylineLine(from: CGPoint(x: 300, y: 141), to: CGPoint(x: 324, y: 141)),
        ])
    }

    @Test("Every square hairline runs the whole way across the frame, so none of them closes a rectangle")
    func hairlinesNeverClose() {
        for side in [CGFloat(12), 16, 24, 32, 48, 64, 512] {
            let box = CGRect(x: 0, y: 0, width: side, height: side)
            guard let guides = IconKeylines.guides(in: box) else {
                Issue.record("no guides at \(side)")
                continue
            }
            #expect(guides.squareGuideLines.count == 4)
            for line in guides.squareGuideLines {
                let vertical = line.from.x == line.to.x
                if vertical {
                    #expect(line.from.y == box.minY)
                    #expect(line.to.y == box.maxY)
                } else {
                    #expect(line.from.x == box.minX)
                    #expect(line.to.x == box.maxX)
                }
            }
        }
    }

    @Test("A frame with no square has no square hairlines either")
    func tinyFramesHaveNoHairlines() {
        #expect(IconKeylines.guides(in: square(6))?.squareGuideLines == [])
        #expect(IconKeylines.guides(in: square(8))?.squareGuideLines == [])
    }

    @Test("The center lines run the whole frame, not just the live area")
    func centerLinesRunTheFrame() {
        let guides = IconKeylines.guides(in: CGRect(x: 300, y: 120, width: 24, height: 24))
        #expect(guides?.centerGuideLines == [
            IconKeylineLine(from: CGPoint(x: 312, y: 120), to: CGPoint(x: 312, y: 144)),
            IconKeylineLine(from: CGPoint(x: 300, y: 132), to: CGPoint(x: 324, y: 132)),
        ])
    }

    // MARK: - Which frames get them at all

    @Test("A screen gets nothing")
    func screensGetNothing() {
        #expect(IconKeylines.guides(in: CGRect(x: 0, y: 0, width: 1440, height: 1024)) == nil)
        #expect(IconKeylines.guides(in: CGRect(x: 0, y: 0, width: 390, height: 844)) == nil)
    }

    @Test("A frame too small to hold a margin draws nothing rather than a line on its own edge")
    func tooSmallForAMargin() {
        // At five points and under a twelfth rounds to nothing, and a live area
        // exactly on the frame's edge would be the frame's own hairline drawn
        // twice rather than a margin anybody can see.
        #expect(IconKeylines.guides(in: square(4)) == nil)
        #expect(IconKeylines.guides(in: square(5)) == nil)
        // Six points is the smallest frame with a margin of its own, and it is
        // still an honest one point in from every edge.
        #expect(IconKeylines.guides(in: square(6))?.liveArea
            == CGRect(x: 1, y: 1, width: 4, height: 4))
        #expect(IconKeylines.guides(in: square(8))?.liveArea
            == CGRect(x: 1, y: 1, width: 6, height: 6))
    }

    @Test("A square somebody typed a size into is still an icon")
    func typedSizesCount() {
        // Deliberately the same rule the previews strip uses: a frame somebody
        // typed 40 into is plainly an icon and would be baffled to find the
        // guides gone.
        #expect(IconKeylines.guides(in: square(40))?.liveArea
            == CGRect(x: 3, y: 3, width: 34, height: 34))
    }

    @Test("A size that is not a number draws nothing")
    func nonsenseDrawsNothing() {
        #expect(IconKeylines.guides(in: CGRect(x: 0, y: 0, width: CGFloat.nan, height: CGFloat.nan)) == nil)
        #expect(IconKeylines.guides(in: .zero) == nil)
    }

    // MARK: - Which frames a document offers

    @Test("A document says whether anything in it is an icon at all")
    func documentKnowsItsIcons() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 1100))
        #expect(!document.hasIconFrames)

        _ = document.addFrame(origin: CGPoint(x: 800, y: 100),
                              size: CGSize(width: 1440, height: 1024))
        #expect(!document.hasIconFrames)

        _ = document.addFrame(origin: CGPoint(x: 100, y: 100),
                              size: CGSize(width: 24, height: 24))
        #expect(document.hasIconFrames)
    }
}
