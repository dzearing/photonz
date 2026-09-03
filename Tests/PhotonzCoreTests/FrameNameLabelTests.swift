import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Where a frame's name draws on the canvas, and what a click on it hits.
@Suite("Frame name labels")
struct FrameNameLabelTests {

    /// A frame drawn at (100, 200) 300 x 400 in view space.
    private let frame = CGRect(x: 100, y: 200, width: 300, height: 400)

    @Test("The name sits above the frame's top left corner, clear of its edge")
    func boxHangsAboveTheFrame() {
        let box = FrameNameLabels.box(forFrameRect: frame)
        #expect(box.minX == frame.minX)
        #expect(box.maxY == frame.minY - FrameNameLabels.gap)
        #expect(box.height == FrameNameLabels.height)
        #expect(box.maxY < frame.minY, "the label must never touch the frame edge")
    }

    @Test("A wide frame's name box stops at the cap, a narrow frame's at its own width")
    func boxWidthIsCapped() {
        #expect(FrameNameLabels.box(forFrameRect: frame).width == FrameNameLabels.maximumWidth)
        let narrow = CGRect(x: 0, y: 100, width: 120, height: 100)
        #expect(FrameNameLabels.box(forFrameRect: narrow).width == 120)
        let tiny = CGRect(x: 0, y: 100, width: 8, height: 100)
        #expect(FrameNameLabels.box(forFrameRect: tiny).width == FrameNameLabels.minimumWidth)
    }

    @Test("The clickable area is the width of the text, not the width of the box")
    func hitBoxFollowsTheText() {
        let hit = FrameNameLabels.hitBox(forFrameRect: frame, textWidth: 42)
        #expect(hit.width < FrameNameLabels.maximumWidth)
        // Slop on both sides, so a 10pt name is still an easy target.
        #expect(hit.width > 42)
        #expect(hit.minX < frame.minX)
    }

    @Test("A one letter name still gets a target big enough to click")
    func shortNamesStayClickable() {
        let hit = FrameNameLabels.hitBox(forFrameRect: frame, textWidth: 4)
        #expect(hit.width >= FrameNameLabels.minimumHitWidth)
    }

    @Test("A name longer than its box does not answer clicks past the box")
    func hitBoxNeverOutgrowsTheBox() {
        let hit = FrameNameLabels.hitBox(forFrameRect: frame, textWidth: 4000)
        #expect(hit.maxX <= frame.minX + FrameNameLabels.maximumWidth + 4)
    }

    @Test("The clickable area leaves the frame's own top edge alone")
    func hitBoxStaysOffTheFrame() {
        let hit = FrameNameLabels.hitBox(forFrameRect: frame, textWidth: 60)
        #expect(hit.maxY < frame.minY, "clicking the frame's top edge must reach the frame")
    }

    @Test("A click on a name picks that frame")
    func clickOnNameHits() {
        let id = UUID()
        let labels = [FrameNameLabel(id: id, frameRect: frame, textWidth: 60)]
        let box = FrameNameLabels.box(forFrameRect: frame)
        #expect(FrameNameLabels.hit(at: CGPoint(x: box.minX + 4, y: box.midY), labels: labels) == id)
    }

    @Test("A click on blank canvas beside a short name hits nothing")
    func clickBesideNameMisses() {
        let labels = [FrameNameLabel(id: UUID(), frameRect: frame, textWidth: 30)]
        let box = FrameNameLabels.box(forFrameRect: frame)
        #expect(FrameNameLabels.hit(at: CGPoint(x: box.minX + 200, y: box.midY), labels: labels) == nil)
    }

    @Test("A click inside the frame itself hits no name")
    func clickInsideFrameMisses() {
        let labels = [FrameNameLabel(id: UUID(), frameRect: frame, textWidth: 60)]
        #expect(FrameNameLabels.hit(at: CGPoint(x: frame.minX + 4, y: frame.minY + 2),
                                    labels: labels) == nil)
    }

    @Test("Where two names overlap, the one drawn on top wins")
    func topmostNameWins() {
        let under = UUID()
        let over = UUID()
        let labels = [
            FrameNameLabel(id: under, frameRect: frame, textWidth: 60),
            FrameNameLabel(id: over, frameRect: frame.offsetBy(dx: 2, dy: 0), textWidth: 60),
        ]
        let box = FrameNameLabels.box(forFrameRect: frame)
        #expect(FrameNameLabels.hit(at: CGPoint(x: box.minX + 10, y: box.midY), labels: labels) == over)
    }

    @Test("No frames means no name to click")
    func emptyMisses() {
        #expect(FrameNameLabels.hit(at: .zero, labels: []) == nil)
    }
}
