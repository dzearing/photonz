import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the Corner Radius row draws when part of its range belongs to
/// something else.
///
/// `UX-PATTERNS.md` §4, "A control that can only act over part of its range":
/// a control that WORKS and simply does not reach everywhere is neither dimmed
/// nor removed. The refused stretch of its track is drawn spent, the fill
/// starts at the wall, and a range spent to nothing keeps its row. These are
/// the three numbers and the one sentence the row draws that from.
struct ClampedCornerRadiusTests {

    private func rectangle(_ frame: CGRect, radius: CGFloat = 0) -> Layer {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 0, start: .zero,
                                        end: CGPoint(x: frame.width, y: frame.height))
        content.cornerRadius = radius
        return Layer(name: "Rectangle", content: .annotation(content), frame: frame)
    }

    private func label(_ frame: CGRect) -> Layer {
        Layer(name: "Save", content: .text(TextContent(string: "Save")), frame: frame)
    }

    /// A frame with a card inside it filling it edge to edge. A frame never
    /// hands the row to its contents, so it is the everyday way to meet a
    /// wall: the frame masks its own corners and a mask can take a corner away
    /// but never put one back.
    private func card(radius: CGFloat, maskRadius: CGFloat = 0) -> Layer {
        let box = CGRect(x: 0, y: 0, width: 360, height: 120)
        return Layer(name: "Screen",
                     content: .group(GroupContent(children: [rectangle(box, radius: radius),
                                                             label(CGRect(x: 60, y: 40,
                                                                          width: 48, height: 33))],
                                                  isFrame: true)),
                     frame: CGRect(x: 240, y: 180, width: 360, height: 120),
                     style: LayerStyle(cornerRadius: CornerRadii(maskRadius)))
    }

    private func row(_ layer: Layer) -> CornerRadiusSelection {
        PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: [layer])
            .cornerRadiusSelection(layerIDs: [layer.id], readingWhatShows: true)
    }

    // MARK: - Where the wall is

    /// Contents rounded 18 in a box whose fully round is 60: the wall stands
    /// three tenths of the way along, which is where the knob rests too. The
    /// old row put that same knob hard at the far left, where it looked exactly
    /// like a knob at nothing.
    @Test func theWallStandsWhereTheContentsAlreadyAre() {
        let row = row(card(radius: 18))
        #expect(row.floor == 18)
        #expect(row.limit == 60)
        #expect(abs(row.wall - 0.3) < 0.0001)
        #expect(row.hasWall)
        #expect(!row.isSpent)
    }

    @Test func nothingClampedHasNoWallToDraw() {
        let row = row(card(radius: 0))
        #expect(row.floor == 0)
        #expect(!row.hasWall)
        #expect(!row.isSpent)
        #expect(row.wall == 0)
        #expect(row.wallSentence == nil)
    }

    /// A pill inside the box: its contents are as round as a box of that size
    /// goes, so the whole track is spent. The row stays, and it is NOT the same
    /// thing as a row with nothing picked.
    @Test func contentsAsRoundAsTheyGoSpendTheWholeTrack() {
        let row = row(card(radius: 60))
        #expect(row.floor == 60)
        #expect(row.limit == 60)
        #expect(row.wall == 1)
        #expect(row.isSpent)
        #expect(row.hasWall)
    }

    /// Rounder than fully round is still fully round, so the wall never runs
    /// off the end of its own track.
    @Test func theWallNeverRunsPastTheEndOfTheTrack() {
        let row = row(card(radius: 200))
        #expect(row.wall == 1)
        #expect(row.isSpent)
    }

    /// The lowest floor in the pick wins, the way the highest ceiling does, so
    /// one clamped layer never walls off a plain box picked beside it.
    @Test func aPlainBoxPickedBesideItTakesTheWallAway() {
        let framed = card(radius: 18)
        let plain = rectangle(CGRect(x: 0, y: 0, width: 40, height: 40))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024),
                                  layers: [framed, plain])
        let row = doc.cornerRadiusSelection(layerIDs: [framed.id, plain.id],
                                            readingWhatShows: true)
        #expect(!row.hasWall)
        #expect(row.wall == 0)
    }

    @Test func anEmptyRowHasNoWall() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [])
        let row = doc.cornerRadiusSelection(layerIDs: [], readingWhatShows: true)
        #expect(!row.hasWall)
        #expect(!row.isSpent)
        #expect(row.wall == 0)
    }

    // MARK: - What the wall says

    /// One constant, so the sentence on the track, the sentence a click puts
    /// under the section and the sentence in the hover tip can never drift
    /// apart. It names the owner with the noun on screen and gives ONE thing
    /// to do.
    @Test func theWallNamesWhatPutItThereAndWhatToDo() {
        let said = row(card(radius: 18)).wallSentence
        #expect(said == "What is inside this is already rounded 18 px. "
                      + "Round the contents less to take it lower.")
    }

    @Test func aSpentTrackSaysThereIsNothingLeft() {
        let said = row(card(radius: 60)).wallSentence
        #expect(said == "What is inside this is already as round as a box goes. "
                      + "Round the contents less to take it lower.")
    }

    /// The number in the sentence is the number on the row, so a floor of 18.4
    /// does not say 18.4 px in a panel that shows whole points everywhere else.
    @Test func theSentenceSaysTheWholeNumberTheRowShows() {
        let said = row(card(radius: 17.6)).wallSentence
        #expect(said?.hasPrefix("What is inside this is already rounded 18 px.") == true)
    }

    // MARK: - A number TYPED into the row

    /// The box's own ends are the ends of the slider, so a number asked for
    /// past fully round comes back as fully round rather than as a number over
    /// a knob resting at the top.
    @Test func aNumberPastFullyRoundLandsOnFullyRound() {
        let typed = row(card(radius: 0)).typed(200)
        #expect(typed.radius == 60)
        #expect(!typed.refused)
    }

    /// Under the wall is the case the four opened corners already answer: the
    /// number lands ON the wall AND the row owes an answer, because settling
    /// in silence is the one thing it must not do.
    @Test func aNumberUnderTheWallLandsOnTheWallAndIsRefused() {
        let typed = row(card(radius: 18)).typed(4)
        #expect(typed.radius == 18)
        #expect(typed.refused)
    }

    @Test func aNumberAboveTheWallIsTakenWhole() {
        let typed = row(card(radius: 18)).typed(30)
        #expect(typed.radius == 30)
        #expect(!typed.refused)
    }

    /// Nothing is walled off here, so nought is nought and there is nothing to
    /// explain.
    @Test func noughtOnAnUnwalledRowIsTakenWhole() {
        let typed = row(card(radius: 0)).typed(0)
        #expect(typed.radius == 0)
        #expect(!typed.refused)
    }

    /// A track spent end to end still takes a typed number: it lands on the
    /// one value left, and it says why.
    @Test func aSpentRowHoldsEveryNumberAtTheWall() {
        let typed = row(card(radius: 60)).typed(10)
        #expect(typed.radius == 60)
        #expect(typed.refused)
    }

    /// A negative number is not a smaller corner, it is not a corner at all.
    @Test func aNegativeNumberCannotGoBelowSquare() {
        let typed = row(card(radius: 0)).typed(-10)
        #expect(typed.radius == 0)
        #expect(!typed.refused)
    }
}
