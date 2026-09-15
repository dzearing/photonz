import CoreGraphics
import Testing
@testable import PhotonzCore

/// The row that speaks for four numbers.
///
/// Room and rounding are the same shape of question — one number that is
/// usually one number and occasionally four — and the app answered it twice,
/// differently, before this. These are the two rules that keep the one answer
/// the same in both places.
@Suite("One row for a number that has four sides")
struct FourSidedNumberTests {

    @Test func agreeingSidesLeaveTheBoxToTheNumber() {
        #expect(FourSidedNumber.standIn(uniform: 16) == "")
        #expect(FourSidedNumber.standIn(uniform: 0) == "")
    }

    /// The word, and THE word: a row whose sides differ says what a menu, a
    /// slider and a switch over a mixed selection all say.
    @Test func disagreeingSidesSayTheHouseWord() {
        #expect(FourSidedNumber.standIn(uniform: nil) == MixedValue.text)
    }

    /// The shorthand is deliberately not what the row shows any more. This is
    /// here so that bringing it back is a decision somebody makes on purpose
    /// rather than a drift: the four numbers live in the popout and in the
    /// tooltip, and the row says the one thing every other control says.
    @Test func theRowDoesNotShowTheFourNumbersRunTogether() {
        let uneven = GroupPadding(top: 10, right: 16, bottom: 10, left: 16)
        #expect(uneven.uniform == nil)
        #expect(FourSidedNumber.standIn(uniform: uneven.uniform) != uneven.shorthand)
        let corners = CornerRadii(topLeft: 16, topRight: 16, bottomRight: 0, bottomLeft: 0)
        #expect(FourSidedNumber.standIn(uniform: corners.uniform) != corners.shorthand)
    }

    /// Both places tell you the same way out, in the same words, with only the
    /// name of one of the four changing.
    @Test func thereIsOneWayBackToOneNumber() {
        #expect(FourSidedNumber.levelUp(part: "side")
                == "Type one number to give every side the same.")
        #expect(FourSidedNumber.levelUp(part: "corner")
                == "Type one number to give every corner the same.")
    }
}
