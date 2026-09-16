import Testing
import Foundation
import CoreGraphics
@testable import PhotonzCore

@Suite("Trim track blocks")
struct VideoTrimTrackTests {

    /// Three six second pieces of an eighteen second recording, on a track 318
    /// points wide with the usual 18 point breathing room at each end, so the
    /// drawable part is 300 points and each piece is 100 of them.
    private let inset: CGFloat = 18
    private let trackWidth: CGFloat = 300
    private let gap: CGFloat = 4

    private func threePieces() -> VideoCutList {
        var cuts = VideoCutList(duration: 18)
        _ = cuts.split(atTimeline: 6)
        _ = cuts.split(atTimeline: 12)
        return cuts
    }

    private func blocks(from: TimeInterval, to: TimeInterval,
                        cuts: VideoCutList? = nil) -> [VideoTrimTrackBlock] {
        let list = cuts ?? threePieces()
        return VideoTrimTrackBlock.blocks(
            for: list.piecesUnderTrim(fromTimeline: from, toTimeline: to),
            duration: list.timelineDuration,
            inset: inset, trackWidth: trackWidth, joinGap: gap)
    }

    @Test("Each piece gets its own block, as wide as it is long, with the cut as a gap")
    func blocksAreTheLengthOfTheirPieces() {
        let laid = blocks(from: 0, to: 18)
        #expect(laid.count == 3)
        #expect(laid[0].x == inset + gap / 2)
        #expect(laid[0].width == 100 - gap)
        #expect(laid[1].x == inset + 100 + gap / 2)
        #expect(laid[2].x + laid[2].width == inset + trackWidth - gap / 2)
        // The gap at a cut is the only space between two blocks.
        #expect(abs((laid[1].x - (laid[0].x + laid[0].width)) - gap) < 1e-9)
    }

    @Test("A whole window lights every block end to end")
    func wholeWindowFillsEveryBlock() {
        for block in blocks(from: 0, to: 18) {
            #expect(block.keptX == block.x)
            #expect(block.keptWidth == block.width)
            #expect(!block.isDropped)
        }
    }

    @Test("A handle inside a piece splits that block where the handle is")
    func handleSplitsItsBlock() {
        let laid = blocks(from: 3, to: 18)
        // 3 seconds in on an 18 second recording is 50 points along the track.
        #expect(laid[0].keptX == inset + 50)
        #expect(abs(laid[0].keptWidth - (laid[0].x + laid[0].width - (inset + 50))) < 1e-9)
        #expect(!laid[0].isDropped)
    }

    @Test("A piece the window has let go of has nothing lit in it")
    func droppedBlockIsNotLit() {
        let laid = blocks(from: 7, to: 9)
        #expect(laid[0].isDropped)
        #expect(laid[0].keptWidth == 0)
        #expect(laid[2].isDropped)
        #expect(!laid[1].isDropped)
        #expect(laid[1].keptWidth > 0)
    }

    @Test("The lit part never escapes the block it belongs to")
    func litPartStaysInsideItsBlock() {
        for window in [(0.0, 18.0), (0.0, 6.0), (5.9, 12.1), (6.0, 12.0), (17.5, 18.0)] {
            for block in blocks(from: window.0, to: window.1) {
                #expect(block.keptX >= block.x - 1e-9)
                #expect(block.keptX + block.keptWidth <= block.x + block.width + 1e-9)
            }
        }
    }

    @Test("A recording of no length lays out without dividing by it")
    func zeroLengthRecording() {
        let laid = VideoTrimTrackBlock.blocks(
            for: VideoCutList(duration: 0).piecesUnderTrim(fromTimeline: 0, toTimeline: 0),
            duration: 0, inset: inset, trackWidth: trackWidth, joinGap: gap)
        #expect(laid.count == 1)
        #expect(laid[0].width >= 0)
        #expect(laid[0].keptWidth >= 0)
    }
}
