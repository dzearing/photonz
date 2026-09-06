import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Saying what the lines on screen are actually worth.
///
/// A grid set to four points does not draw four point lines at 100%: they would
/// be four screen points apart and read as a grey wash, so the canvas draws the
/// thirty two point rung instead and a drag lands on that. The setting and the
/// picture disagreeing in silence is what made snapping feel broken. These
/// tests hold the readout to the picture.
@Suite("Grid live spacing readout")
struct GridLiveSpacingTests {

    private func settings(_ spacing: CGFloat,
                          minimumCell: CGFloat = CanvasGridSettings.noMinimumCell,
                          snaps: Bool = true) -> CanvasGridSettings {
        CanvasGridSettings(isVisible: true, snapsToGrid: snaps, spacing: spacing,
                           minimumCell: minimumCell)
    }

    // MARK: The number the lines are worth

    @Test func theLiveSpacingIsWhatTheCanvasIsDrawing() {
        // The user's report: set 4, look at 100%, the lines are worth 32.
        #expect(settings(4).liveSpacing(atZoom: 1) == 32)
        #expect(settings(4).liveSpacing(atZoom: 0.25) == 256)
    }

    @Test func theLiveSpacingIsTheSetSpacingOnceItIsBigEnoughToRead() {
        #expect(settings(16).liveSpacing(atZoom: 1) == 16)
        #expect(settings(4).liveSpacing(atZoom: 4) == 4)
        #expect(settings(64).liveSpacing(atZoom: 1) == 64)
    }

    /// The number on the chip and the number a drag lands on are the same
    /// number, always. Two readouts of the same thing that can disagree is the
    /// bug this task exists to close.
    @Test func theLiveSpacingIsExactlyWhatADragLandsOn() {
        for spacing in [CGFloat(1), 2, 4, 6, 8, 12, 16, 32, 100, 128] {
            for zoom in stride(from: 0.1, through: 12.0, by: 0.05).map({ CGFloat($0) }) {
                let g = settings(spacing)
                guard let pull = g.snapSpacing(atZoom: zoom) else { continue }
                #expect(g.liveSpacing(atZoom: zoom) == pull)
            }
        }
    }

    /// Turning the magnet off changes nothing about what the lines are worth:
    /// the readout describes the picture, not the pull.
    @Test func switchingSnappingOffLeavesTheReadoutAlone() {
        #expect(settings(4, snaps: false).liveSpacing(atZoom: 1) == 32)
        #expect(settings(4, snaps: false).snapSpacing(atZoom: 1) == nil)
    }

    @Test func aSmallestCellRaisesWhatTheLinesAreWorth() {
        #expect(settings(4, minimumCell: 8).liveSpacing(atZoom: 4) == 8)
    }

    @Test func aZoomThatIsNotANumberFallsBackToTheGridYouSet() {
        #expect(settings(4).liveSpacing(atZoom: .nan) == 4)
        #expect(settings(4).liveSpacing(atZoom: 0) == 4)
        #expect(settings(4).liveSpacing(atZoom: -3) == 4)
    }

    // MARK: How it reads

    @Test func theChipReadsOneNumberWhenTheGridYouSetIsTheGridYouSee() {
        #expect(settings(16).spacingChipText(atZoom: 1) == "16 pt")
        #expect(settings(4).spacingChipText(atZoom: 4) == "4 pt")
    }

    @Test func theChipReadsBothNumbersWhenTheyDisagree() {
        // Left of the arrow the grid you set, right of it the grid you see.
        #expect(settings(4).spacingChipText(atZoom: 1) == "4 \u{2192} 32 pt")
        #expect(settings(4).spacingChipText(atZoom: 0.25) == "4 \u{2192} 256 pt")
    }

    @Test func theChipNeverCarriesAnEmDash() {
        #expect(!settings(4).spacingChipText(atZoom: 1).contains("\u{2014}"))
    }

    // MARK: The line that explains it

    @Test func thereIsNothingToExplainWhenTheTwoAgree() {
        #expect(settings(16).liveSpacingNote(atZoom: 1) == nil)
    }

    @Test func theNoteNamesBothNumbersAndSaysHowToGetTheFinerOne() {
        let note = settings(4).liveSpacingNote(atZoom: 1)
        #expect(note != nil)
        let text = note ?? ""
        #expect(text.contains("32"))
        #expect(text.contains("4"))
        #expect(text.localizedCaseInsensitiveContains("zoom"))
        #expect(!text.contains("\u{2014}"))
        #expect(text.hasSuffix("."))
    }

    /// With the magnet off the note must not claim a drag lands on anything.
    @Test func theNoteOnlyMentionsTheDragWhenTheMagnetIsOn() {
        let on = settings(4).liveSpacingNote(atZoom: 1) ?? ""
        let off = settings(4, snaps: false).liveSpacingNote(atZoom: 1) ?? ""
        #expect(on.localizedCaseInsensitiveContains("drag"))
        #expect(!off.localizedCaseInsensitiveContains("drag"))
        #expect(off.contains("32"))
    }
}
