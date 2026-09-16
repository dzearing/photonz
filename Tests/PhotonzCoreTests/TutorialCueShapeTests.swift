import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The ring a guide draws round a control has to take that control's own
/// shape. A pill bar wants a pill, a round tool button wants a circle, and a
/// run of panel rows wants the squarer corner it has always had. The shape is
/// read off the anchor, so it is decided once, here, rather than guessed at
/// the place the ring is drawn.
@Suite("Tutorial cue shape")
struct TutorialCueShapeTests {

    // MARK: The three shapes the acceptance asks for

    @Test func theFloatingToolBarRingsAsAPill() {
        #expect(TutorialAnchor.toolBar.cueShape == .pill)
    }

    @Test func everyToolButtonRingsAsAPillWhichOnASquareButtonIsACircle() {
        for tool in Tool.allCases {
            #expect(TutorialAnchor.tool(tool).cueShape == .pill)
        }
        // A family slot is the same round button wearing whichever member was
        // reached for last, so it rings the same way.
        for group in ToolGroup.allCases {
            #expect(TutorialAnchor.toolGroup(group).cueShape == .pill)
        }
    }

    @Test func aPanelSectionKeepsTheSquarerCornerItAlreadyHad() {
        for id in TutorialAnchor.knownPanelSections {
            let shape = TutorialAnchor.panelSection(id).cueShape
            #expect(shape == .rounded(5))
            // The ring sits outside the control, so what it actually draws is
            // the 10pt corner it has drawn all along.
            #expect(shape.outset(by: 5) == .rounded(10))
        }
    }

    // MARK: Everywhere else a guide can point

    @Test func aSurfaceThatIsJustARectangleRingsAsARoundedRectangle() {
        for anchor in [TutorialAnchor.canvas, .panel, .titleBar, .timingStrip] {
            #expect(anchor.cueShape == .rounded(5))
        }
    }

    @Test func aRecordingsWindowRingsItsPictureSquarerThanItsButtons() {
        // The round buttons on the floating controller.
        for part in [TutorialAnchor.VideoPart.transport, .trim, .save, .copy, .export] {
            #expect(TutorialAnchor.video(part).cueShape == .pill)
        }
        // The picture and the strip under it are drawn as rounded rectangles,
        // so their rings are too.
        #expect(TutorialAnchor.video(.preview).cueShape == .rounded(12))
        #expect(TutorialAnchor.video(.timeline).cueShape == .rounded(6))
        #expect(TutorialAnchor.video(.trimDone).cueShape == .rounded(6))
    }

    @Test func aStartHereRowAndASheetCarryTheirOwnCorners() {
        for action in TutorialAnchor.knownStartActions {
            #expect(TutorialAnchor.startHere(action).cueShape == .rounded(8))
        }
        for dialog in TutorialAnchor.Dialog.allCases {
            #expect(TutorialAnchor.dialog(dialog).cueShape == .rounded(12))
        }
    }

    @Test func everyAnchorTheAppPromisesHasAShape() {
        // Nothing falls through to something unusable: a shape is either a
        // pill or a corner radius that is not negative.
        for anchor in TutorialAnchor.all {
            switch anchor.cueShape {
            case .pill: break
            case .rounded(let radius): #expect(radius >= 0)
            }
        }
    }

    // MARK: The ring sits outside the control and stays concentric

    @Test func pushingARingOutwardsWidensItsCornersToMatch() {
        #expect(TutorialCueShape.rounded(12).outset(by: 5) == .rounded(17))
        // A pill pushed outwards is still a pill: its ends are half circles at
        // any size, so there is no radius to carry.
        #expect(TutorialCueShape.pill.outset(by: 5) == .pill)
        // A square corner pushed outwards picks up the offset, because the
        // ring is further from the middle than the corner it follows.
        #expect(TutorialCueShape.rounded(0).outset(by: 5) == .rounded(5))
        // Pulled inwards further than it is round, a corner goes square rather
        // than inside out.
        #expect(TutorialCueShape.rounded(3).outset(by: -8) == .rounded(0))
    }

    // MARK: Written down and read back

    @Test func anAnchorOffDiskRingsTheSameAsOneTheAppJustMade() throws {
        let anchor = TutorialAnchor.toolBar
        let back = try JSONDecoder().decode(
            TutorialAnchor.self, from: JSONEncoder().encode(anchor))
        #expect(back == anchor)
        #expect(back.cueShape == anchor.cueShape)
        #expect(back.cueShape == .pill)
    }
}
