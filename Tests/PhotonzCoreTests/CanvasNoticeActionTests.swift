import Foundation
import Testing
@testable import PhotonzCore

@Suite("Canvas notice action")
struct CanvasNoticeActionTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 2_000)
    private let layerID = UUID()

    // MARK: - What the button says

    @Test func theButtonWearsTheSameNameAsTheMenuRow() {
        // A person who has seen the Layer menu, and a person who has only ever
        // seen the pill, must be looking at the same command. The pill's button
        // drops the ellipsis: the question is one press away either way, and on
        // a button three dots read as "more options".
        let action = CanvasNoticeAction.turnIntoPicture(layer: layerID)
        #expect(action.label == "Turn Into Picture")
        #expect(RasterizePrompt.menuItem.hasPrefix(action.label))
    }

    @Test func theButtonNamesItsKeyboardShortcut() {
        // The pointer is not the only way in. The pill is also where a person
        // learns the key, which keeps working long after the pill has gone.
        let action = CanvasNoticeAction.turnIntoPicture(layer: layerID)
        #expect(action.shortcutHint == "\u{21E7}\u{2318}R")
    }

    @Test func theActionRemembersWhichLayerItWasRaisedOver() {
        // Selection can change between the refusal and the press. The pill must
        // turn the layer the refusal was ABOUT, never whatever is picked now.
        let other = UUID()
        let action = CanvasNoticeAction.turnIntoPicture(layer: layerID)
        #expect(action.layerID == layerID)
        #expect(action != .turnIntoPicture(layer: other))
    }

    // MARK: - A notice that carries one

    @Test func aNoticeWithAnActionStaysUpLongEnoughToReachIt() {
        // Three seconds is enough to READ a refusal and not enough to read it,
        // decide, and travel to a button. A button that leaves while you reach
        // for it is worse than no button.
        let refusal = RegionSliceRefusal(action: .erase, reason: .canBecomeAPicture)
        let notice = CopyConfirmation(subject: .regionSliceRefused(refusal), shownAt: t0,
                                      action: .turnIntoPicture(layer: layerID))
        #expect(notice.lifetime == CopyConfirmation.actionLifetime)
        #expect(notice.lifetime > CopyConfirmation.breakLifetime)
        #expect(notice.isLive(at: t0.addingTimeInterval(5)))
        #expect(!notice.isLive(at: t0.addingTimeInterval(CopyConfirmation.actionLifetime)))
    }

    @Test func aNoticeWithNoActionIsExactlyWhatItWasBefore() {
        // Every other notice in the app stays inert and keeps its own clock.
        let plain = CopyConfirmation(subject: .specList(measurements: 2), shownAt: t0)
        #expect(plain.action == nil)
        #expect(plain.lifetime == CopyConfirmation.lifetime)

        let refusal = RegionSliceRefusal(action: .cut, reason: .adjustedPicture)
        let refused = CopyConfirmation(subject: .regionSliceRefused(refusal), shownAt: t0)
        #expect(refused.action == nil)
        #expect(refused.lifetime == CopyConfirmation.breakLifetime)
    }

    @Test func reshowingCarriesTheNewNoticesOwnAction() {
        // The pill is one slot. A refusal that lands on top of a "Copied" must
        // bring its button with it, and a plain notice landing on top of a
        // refusal must take the button away rather than inherit it.
        let refusal = RegionSliceRefusal(action: .erase, reason: .canBecomeAPicture)
        let copied = CopyConfirmation(subject: .measurements(count: 1), shownAt: t0)
        let refused = copied.reshown(as: .regionSliceRefused(refusal),
                                     at: t0.addingTimeInterval(1),
                                     action: .turnIntoPicture(layer: layerID))
        #expect(refused.action == .turnIntoPicture(layer: layerID))
        let backToPlain = refused.reshown(as: .measurements(count: 2),
                                          at: t0.addingTimeInterval(2))
        #expect(backToPlain.action == nil)
    }

    // MARK: - The line changes when the button is there

    @Test func theLineStopsSendingYouToTheMenuOnceTheButtonIsThere() {
        // Two ways out in one pill is one too many to read, and the previous
        // audit already said the line was too long. The button IS the way out.
        let refusal = RegionSliceRefusal(action: .erase, reason: .canBecomeAPicture)
        let withButton = CopyConfirmation(subject: .regionSliceRefused(refusal), shownAt: t0,
                                          action: .turnIntoPicture(layer: layerID))
        #expect(!withButton.detail.contains("Layer menu"))
        #expect(withButton.detail.contains("Only a picture can have a piece taken out"))

        let withoutButton = CopyConfirmation(subject: .regionSliceRefused(refusal), shownAt: t0)
        #expect(withoutButton.detail.contains("Layer menu"))
    }

    @Test func theTitleIsUntouchedByTheButton() {
        // The verdict is the same refusal either way: what changes is only how
        // far you have to walk to answer it.
        let refusal = RegionSliceRefusal(action: .fill, reason: .canBecomeAPicture)
        let withButton = CopyConfirmation(subject: .regionSliceRefused(refusal), shownAt: t0,
                                          action: .turnIntoPicture(layer: layerID))
        #expect(withButton.title == refusal.title)
        #expect(withButton.title == "Cannot fill a piece")
    }

    // MARK: - Who may offer it

    @Test func onlyARefusalThatHasAWayOutOffersOne() {
        // A measurement or a group can never become a picture, and a cropped
        // picture already is one. Offering a button that cannot help is worse
        // than offering nothing.
        #expect(RegionSliceRefusal(action: .erase, reason: .canBecomeAPicture).offersTurnIntoPicture)
        #expect(!RegionSliceRefusal(action: .erase, reason: .notPixels).offersTurnIntoPicture)
        #expect(!RegionSliceRefusal(action: .erase, reason: .adjustedPicture).offersTurnIntoPicture)
    }
}

@Suite("A held canvas notice")
struct HeldCanvasNoticeTests {

    @Test func aPointerCannotPinANoticeUpForGood() {
        // "The pointer is over it" and "the pointer is parked where it
        // appeared" look the same from the inside, and a notice has no close
        // control, so a hold has to have a ceiling. A walk caught a pill living
        // for the rest of the run because nothing moved the mouse again.
        #expect(CopyConfirmation.heldLifetime > CopyConfirmation.actionLifetime)
        #expect(CopyConfirmation.heldLifetime <= 20)
    }

    @Test func theCeilingStillLeavesRoomToReadIt() {
        // Long enough that somebody genuinely reading a refusal and deciding
        // what to do is never rushed: double the clock it would have had.
        #expect(CopyConfirmation.heldLifetime >= 2 * CopyConfirmation.actionLifetime)
    }
}
