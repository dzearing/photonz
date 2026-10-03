import Foundation
import Testing
@testable import PhotonzCore

/// **The Around menu ends with Somewhere else** (`the-around-menu-ends-with-
/// somewhere-else-as-the`): the mock's last row, its key, and the move button
/// beside the menu all hand you the pivot to put down on the canvas.
@Suite("Placing the pivot on the canvas")
struct MotionPivotPlacingTests {

    @Test("The row reads the way the mock draws it, with Y beside it")
    func theRowIsTheMocks() {
        #expect(MotionPivot.PlaceOnCanvas.menuTitle == "Somewhere else\u{2026}")
        #expect(MotionPivot.PlaceOnCanvas.key == "y")
        #expect(MotionPivot.PlaceOnCanvas.buttonHelp == "Move the pivot on the canvas (Y)")
    }

    @Test("No tool already answers Y, so the key does one thing")
    func noToolOwnsTheKey() {
        let key = MotionPivot.PlaceOnCanvas.key
        #expect(!Tool.allCases.contains { $0.shortcutKey == key })
    }

    @Test("The timeline leaves Y to the canvas, so a video window never takes it first")
    func theTimelineLeavesIt() {
        #expect(TimelineKeys.leavesToTheCanvas(MotionPivot.PlaceOnCanvas.key))
    }

    @Test("The menu bar row fits the chrome's label budget")
    func theMenuBarRowIsALabel() {
        #expect(MotionPivot.PlaceOnCanvas.menuBarTitle == "Move the Pivot")
        #expect(MotionPivot.PlaceOnCanvas.menuBarTitle.count <= 30)
    }
}
