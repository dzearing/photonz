import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Capture loupe (magnified pixels beside the pointer during a region capture)")
struct CaptureLoupeTests {

    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let size = CGSize(width: 133, height: 190)
    private let gap: CGFloat = 16

    // MARK: - Placement

    @Test func hoveringPutsTheLoupeBelowAndRightOfThePointer() {
        let pointer = CGPoint(x: 600, y: 400)
        let origin = CaptureLoupe.origin(pointer: pointer, anchor: nil, size: size, gap: gap, within: screen)
        #expect(origin == CGPoint(x: 616, y: 416))
    }

    @Test func draggingKeepsTheLoupeOutsideTheBoxOnThePointersSide() {
        // Drag from the top-left toward the bottom-right: the pointer is the
        // box's bottom-right corner, so the loupe sits beyond it, outside.
        let anchor = CGPoint(x: 300, y: 300)
        let pointer = CGPoint(x: 600, y: 500)
        let down = CaptureLoupe.origin(pointer: pointer, anchor: anchor, size: size, gap: gap, within: screen)
        #expect(down == CGPoint(x: 616, y: 516))

        // Drag the other way: the pointer is the top-left corner, so the loupe
        // sits above and to its left, again outside the box.
        let up = CaptureLoupe.origin(pointer: anchor, anchor: pointer, size: size, gap: gap, within: screen)
        let frame = CGRect(origin: up, size: size)
        #expect(frame.maxX == anchor.x - gap)
        #expect(frame.maxY == anchor.y - gap)
        #expect(!frame.intersects(CGRect(x: 300, y: 300, width: 300, height: 200)))
    }

    @Test func mixedDirectionsPickEachAxisSeparately() {
        // Dragging from the bottom-left corner up and to the right.
        let anchor = CGPoint(x: 300, y: 600)
        let pointer = CGPoint(x: 700, y: 300)
        let frame = CGRect(origin: CaptureLoupe.origin(pointer: pointer, anchor: anchor, size: size,
                                                        gap: gap, within: screen), size: size)
        #expect(frame.minX == pointer.x + gap)
        #expect(frame.maxY == pointer.y - gap)
    }

    @Test func aDragWithNoWidthOrHeightStillHasASide() {
        // Pointer level with the anchor: treated like "away" is right/down, so
        // the loupe does not flicker between sides on a perfectly straight drag.
        let anchor = CGPoint(x: 300, y: 300)
        let pointer = CGPoint(x: 300, y: 500)
        let origin = CaptureLoupe.origin(pointer: pointer, anchor: anchor, size: size, gap: gap, within: screen)
        #expect(origin == CGPoint(x: 316, y: 516))
    }

    @Test func nearTheRightEdgeTheLoupeStepsToTheLeft() {
        let pointer = CGPoint(x: 1700, y: 400)
        let frame = CGRect(origin: CaptureLoupe.origin(pointer: pointer, anchor: nil, size: size,
                                                        gap: gap, within: screen), size: size)
        #expect(frame.maxX == pointer.x - gap)
        #expect(frame.minY == pointer.y + gap)
        #expect(screen.contains(frame))
    }

    @Test func nearTheBottomEdgeTheLoupeStepsAbove() {
        let pointer = CGPoint(x: 400, y: 1100)
        let frame = CGRect(origin: CaptureLoupe.origin(pointer: pointer, anchor: nil, size: size,
                                                        gap: gap, within: screen), size: size)
        #expect(frame.maxY == pointer.y - gap)
        #expect(frame.minX == pointer.x + gap)
        #expect(screen.contains(frame))
    }

    @Test func inACornerWhileDraggingBothAxesFlipAndTheCornerStaysClear() {
        // Dragging toward the bottom-right corner of the display: "away from
        // the anchor" would leave the screen, so the loupe flips to the other
        // side on both axes but still never sits on the active corner.
        let anchor = CGPoint(x: 1200, y: 800)
        let pointer = CGPoint(x: 1720, y: 1110)
        let frame = CGRect(origin: CaptureLoupe.origin(pointer: pointer, anchor: anchor, size: size,
                                                        gap: gap, within: screen), size: size)
        #expect(screen.contains(frame))
        #expect(!frame.contains(pointer))
        #expect(frame.maxX == pointer.x - gap)
        #expect(frame.maxY == pointer.y - gap)
    }

    @Test func theLoupeNeverCoversThePointerAnywhereOnANormalDisplay() {
        for x in stride(from: 0, through: 1728, by: 32) {
            for y in stride(from: 0, through: 1117, by: 32) {
                let pointer = CGPoint(x: x, y: y)
                for anchor in [nil, CGPoint(x: 864, y: 558)] {
                    let frame = CGRect(origin: CaptureLoupe.origin(pointer: pointer, anchor: anchor, size: size,
                                                                    gap: gap, within: screen), size: size)
                    #expect(!frame.contains(pointer), "pointer \(pointer) anchor \(String(describing: anchor))")
                    #expect(screen.contains(frame), "pointer \(pointer)")
                }
            }
        }
    }

    @Test func aDisplaySmallerThanTheLoupeClampsRatherThanCrashing() {
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 100)
        let origin = CaptureLoupe.origin(pointer: CGPoint(x: 50, y: 50), anchor: nil, size: size,
                                         gap: gap, within: tiny)
        #expect(origin == .zero)
    }

    @Test func aSecondDisplayUsesItsOwnBounds() {
        // Overlays draw in their display's local top-left space, but the rule
        // must still respect a bounds rect that does not start at zero.
        let offset = CGRect(x: 2000, y: 100, width: 800, height: 600)
        let frame = CGRect(origin: CaptureLoupe.origin(pointer: CGPoint(x: 2780, y: 680), anchor: nil,
                                                        size: size, gap: gap, within: offset), size: size)
        #expect(offset.contains(frame))
    }

    // MARK: - Sampling the frozen picture

    @Test func theSampleIsCentredOnThePixelUnderThePointer() {
        // 2x display: the point (100.3, 50.7) is pixel (200, 101).
        let sample = CaptureLoupe.sample(pointer: CGPoint(x: 100.3, y: 50.7), scale: 2, pixelsAcross: 25,
                                         imageSize: CGSize(width: 3456, height: 2234), square: 125)
        #expect(sample?.source == CGRect(x: 188, y: 89, width: 25, height: 25))
        #expect(sample?.destination == CGRect(x: 0, y: 0, width: 125, height: 125))
    }

    @Test func aOneXDisplayUsesThePointAsThePixel() {
        let sample = CaptureLoupe.sample(pointer: CGPoint(x: 40, y: 40), scale: 1, pixelsAcross: 25,
                                         imageSize: CGSize(width: 1728, height: 1117), square: 125)
        #expect(sample?.source == CGRect(x: 28, y: 28, width: 25, height: 25))
    }

    @Test func atTheEdgeOfThePictureTheMissingPixelsLeaveAGap() {
        // Pointer on the top-left pixel: only the bottom-right quarter of the
        // patch exists, and it lands in the bottom-right of the square so the
        // pointer's pixel stays in the middle.
        let sample = CaptureLoupe.sample(pointer: CGPoint(x: 0, y: 0), scale: 1, pixelsAcross: 25,
                                         imageSize: CGSize(width: 1728, height: 1117), square: 125)
        #expect(sample?.source == CGRect(x: 0, y: 0, width: 13, height: 13))
        #expect(sample?.destination == CGRect(x: 60, y: 60, width: 65, height: 65))
    }

    @Test func atTheFarEdgeThePatchIsCutOnTheFarSide() {
        let sample = CaptureLoupe.sample(pointer: CGPoint(x: 1727.5, y: 500), scale: 1, pixelsAcross: 25,
                                         imageSize: CGSize(width: 1728, height: 1117), square: 125)
        #expect(sample?.source == CGRect(x: 1715, y: 488, width: 13, height: 25))
        #expect(sample?.destination == CGRect(x: 0, y: 0, width: 65, height: 125))
    }

    @Test func aPointerOffThePictureSamplesNothing() {
        let sample = CaptureLoupe.sample(pointer: CGPoint(x: 5000, y: 5000), scale: 2, pixelsAcross: 25,
                                         imageSize: CGSize(width: 3456, height: 2234), square: 125)
        #expect(sample == nil)
    }

    @Test func thePointersPixelCellSitsInTheMiddleOfTheSquare() {
        let cell = CaptureLoupe.centerCell(pixelsAcross: 25, square: 125)
        #expect(cell == CGRect(x: 60, y: 60, width: 5, height: 5))
        #expect(CaptureLoupe.centerCell(pixelsAcross: 11, square: 110) == CGRect(x: 50, y: 50, width: 10, height: 10))
    }

    // MARK: - Readout

    // The loupe names sizes the way the editor does: "px" is the logical,
    // on-screen size the editor reads by default, and "actual px" is the raw
    // device pixel the editor's Actual mode reads. One number, one name,
    // whichever side of the capture you are on.

    @Test func theReadoutGivesLogicalAndActualPixelsOnARetinaDisplay() {
        let lines = CaptureLoupe.readout(pointer: CGPoint(x: 412.5, y: 233.2), scale: 2, selection: nil)
        #expect(lines == ["412, 233 px", "825, 466 actual px"])
    }

    @Test func theReadoutSkipsTheActualLineOnAOneXDisplay() {
        // At 1x logical and actual are the same pixel, so one line says it all.
        let lines = CaptureLoupe.readout(pointer: CGPoint(x: 412, y: 233), scale: 1, selection: nil)
        #expect(lines == ["412, 233 px"])
    }

    @Test func theReadoutAddsTheSelectionSizeWhileDragging() {
        // The selection is the size the editor will read once the capture
        // opens (logical, its default), under the same "px" name.
        let lines = CaptureLoupe.readout(pointer: CGPoint(x: 412, y: 233), scale: 2,
                                         selection: CGSize(width: 300.4, height: 199.6))
        #expect(lines == ["412, 233 px", "824, 466 actual px", "300 × 200 px"])
    }

    @Test func theReadoutFloorsRatherThanRoundsThePointer() {
        // The pixel under the pointer is the one the crop will start on, so
        // 99.9 reads as 99, never 100.
        let lines = CaptureLoupe.readout(pointer: CGPoint(x: 99.9, y: 0.4), scale: 2, selection: nil)
        #expect(lines == ["99, 0 px", "199, 0 actual px"])
    }

    @Test func theReadoutNeverSaysPt() {
        // The editor never says "pt" for a size, so neither does the loupe.
        for scale: CGFloat in [1, 2, 3] {
            let lines = CaptureLoupe.readout(pointer: CGPoint(x: 10, y: 10), scale: scale,
                                             selection: CGSize(width: 20, height: 30))
            #expect(lines.allSatisfy { $0.hasSuffix(" px") }, "scale \(scale): \(lines)")
        }
    }
}
