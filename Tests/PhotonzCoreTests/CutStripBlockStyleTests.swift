import Testing
import Foundation
import CoreGraphics
@testable import PhotonzCore

@Suite("Cut strip block style")
struct CutStripBlockStyleTests {

    private func picked(_ played: Double) -> CutStripBlockStyle {
        CutStripBlockStyle.block(isPicked: true, playedFraction: played)
    }

    private func unpicked(_ played: Double) -> CutStripBlockStyle {
        CutStripBlockStyle.block(isPicked: false, playedFraction: played)
    }

    /// The bug this type exists to stop, written as the two numbers it was.
    ///
    /// The strip used to fill a picked block at 0.30 and a played one at 0.55,
    /// so a piece somebody had already watched was drawn louder than the piece
    /// Delete would take. The quietest part of the picked block has to beat the
    /// loudest part of any block that is not picked.
    @Test("A picked block is never quieter than an unpicked one")
    func pickedBeatsPlayed() {
        for played in stride(from: 0.0, through: 1.0, by: 0.05) {
            let mine = picked(played)
            for theirs in stride(from: 0.0, through: 1.0, by: 0.05) {
                let other = unpicked(theirs)
                #expect(mine.quietestFill > other.loudestFill)
                #expect(mine.height > other.height)
            }
        }
    }

    /// Progress is still drawn, it just stops shouting. A block whose playhead
    /// has been through it must read differently from one nobody has reached,
    /// picked or not.
    @Test("Progress still reads inside a block")
    func progressStillReads() {
        for isPicked in [true, false] {
            let style = CutStripBlockStyle.block(isPicked: isPicked, playedFraction: 0.5)
            // Something substantial is drawn over the watched part, and it is
            // different from what is under it: brighter in the same colour on
            // an unpicked block, a different colour entirely on the picked one,
            // which is already as bright as its own colour goes.
            #expect(style.playedOpacity >= 0.2)
            #expect(style.playedTint != style.tint || style.playedOpacity > style.baseOpacity)
        }
        #expect(unpicked(0.5).playedOpacity > unpicked(0.5).baseOpacity)
        #expect(picked(0.5).playedTint != picked(0.5).tint)
    }

    /// The pick speaks in colour and size. Only the picked block is ever drawn
    /// in the accent, so the accent never means anything but "this one".
    /// Two signals in one currency is how the picked block lost the argument in
    /// the first place.
    @Test("Only the picked block wears the accent")
    func onlyThePickWearsAccent() {
        #expect(picked(0).tint == .accent)
        #expect(picked(1).tint == .accent)
        #expect(unpicked(0).tint == .neutral)
        #expect(unpicked(1).tint == .neutral)
    }

    /// A hairline round the picked block, and only round it. It is drawn in
    /// white rather than the accent so it still reads once the block underneath
    /// it has filled with accent, which is the case that made an accent outline
    /// disappear into its own block.
    @Test("The hairline marks the pick and survives a full block")
    func hairlineMarksThePick() {
        #expect(picked(0).strokeWidth > 0)
        #expect(picked(1).strokeWidth > 0)
        #expect(picked(1).strokeOpacity > 0.5)
        #expect(unpicked(0).strokeWidth == 0)
        #expect(unpicked(1).strokeWidth == 0)
    }

    /// A playhead sitting outside a piece, or arithmetic that overshoots, must
    /// not draw a fill wider than the block.
    @Test("The played fraction is clamped to the block")
    func playedFractionIsClamped() {
        #expect(picked(-3).playedFraction == 0)
        #expect(picked(9).playedFraction == 1)
        #expect(unpicked(Double.nan).playedFraction == 0)
    }

    /// The strip is 22 points tall whatever is picked, so switching pieces
    /// never changes how much room the row needs.
    @Test("The row height does not depend on what is picked")
    func rowHeightIsConstant() {
        #expect(CutStripBlockStyle.rowHeight >= picked(0).height)
        #expect(CutStripBlockStyle.rowHeight >= unpicked(0).height)
    }
}
