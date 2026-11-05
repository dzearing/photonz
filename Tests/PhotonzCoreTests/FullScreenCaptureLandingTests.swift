import CoreGraphics
import Testing
@testable import PhotonzCore

@Suite("A full screen capture on several displays")
struct FullScreenCaptureLandingTests {

    private let left = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let right = CGRect(x: 1728, y: 0, width: 2560, height: 1440)

    @Test func oneDisplayGoesOnTheClipboard() {
        #expect(FullScreenCaptureLanding.steps(displays: [left], pointer: CGPoint(x: 10, y: 10))
                == [.init(display: 0, goesOnClipboard: true)])
    }

    @Test func theDisplayUnderThePointerIsTheOneOnTheClipboardWhicheverItIs() {
        let onLeft = FullScreenCaptureLanding.steps(displays: [left, right], pointer: CGPoint(x: 100, y: 100))
        #expect(onLeft == [.init(display: 1, goesOnClipboard: false),
                           .init(display: 0, goesOnClipboard: true)])
        let onRight = FullScreenCaptureLanding.steps(displays: [left, right], pointer: CGPoint(x: 2000, y: 100))
        #expect(onRight == [.init(display: 0, goesOnClipboard: false),
                            .init(display: 1, goesOnClipboard: true)])
    }

    @Test func everyDisplayLandsAndExactlyOneIsCopied() {
        let third = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let steps = FullScreenCaptureLanding.steps(displays: [left, right, third], pointer: CGPoint(x: -5, y: 5))
        #expect(Set(steps.map(\.display)) == [0, 1, 2])
        #expect(steps.filter(\.goesOnClipboard).map(\.display) == [2])
    }

    /// `NSEvent.mouseLocation` reads y == maxY with the pointer at the very top
    /// of a display, and a rect does not contain its own far edge.
    @Test func aPointerOnTheFarEdgeBelongsToTheDisplayItIsTouching() {
        let steps = FullScreenCaptureLanding.steps(displays: [left, right], pointer: CGPoint(x: 2000, y: 1440))
        #expect(steps.last == .init(display: 1, goesOnClipboard: true))
    }

    @Test func noDisplaysLandNothing() {
        #expect(FullScreenCaptureLanding.steps(displays: [], pointer: .zero).isEmpty)
    }
}
