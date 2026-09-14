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
