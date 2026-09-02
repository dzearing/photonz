import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Window pick (capture a window by clicking it)")
struct WindowPickTests {

    // Front-to-back, the way the window server lists them.
    private func window(_ id: Int, _ frame: CGRect, layer: Int = 0, alpha: Double = 1,
                        owner: String = "App") -> ScreenWindow {
        ScreenWindow(id: id, frame: frame, layer: layer, alpha: alpha, ownerName: owner)
    }

    @Test func picksTheFrontmostWindowUnderThePoint() {
        let front = window(1, CGRect(x: 100, y: 100, width: 300, height: 200))
        let back = window(2, CGRect(x: 0, y: 0, width: 800, height: 600))
        let picked = WindowPick.frontmost(at: CGPoint(x: 150, y: 150), in: [front, back])
        #expect(picked?.id == 1)
        // Outside the front window the one behind it wins.
        #expect(WindowPick.frontmost(at: CGPoint(x: 10, y: 10), in: [front, back])?.id == 2)
    }

    @Test func nothingUnderThePointPicksNothing() {
        let w = window(1, CGRect(x: 100, y: 100, width: 300, height: 200))
        #expect(WindowPick.frontmost(at: CGPoint(x: 50, y: 50), in: [w]) == nil)
        #expect(WindowPick.frontmost(at: CGPoint(x: 50, y: 50), in: []) == nil)
    }

    @Test func edgesCountAsInsideOnTheNearSideOnly() {
        // A window's frame is half-open, like every rect on screen: the pixel
        // at maxX belongs to whatever sits to the right.
        let w = window(1, CGRect(x: 100, y: 100, width: 300, height: 200))
        #expect(WindowPick.frontmost(at: CGPoint(x: 100, y: 100), in: [w])?.id == 1)
        #expect(WindowPick.frontmost(at: CGPoint(x: 400, y: 300), in: [w]) == nil)
    }

    @Test func onlyNormalLayerOpaqueWindowsArePickable() {
        // The menu bar, the Dock, floating panels and invisible helper windows
        // all sit under the pointer without being something you would capture.
        let menuBar = window(1, CGRect(x: 0, y: 0, width: 800, height: 24), layer: 24)
        let invisible = window(2, CGRect(x: 0, y: 0, width: 800, height: 600), alpha: 0)
        let real = window(3, CGRect(x: 0, y: 0, width: 800, height: 600))
        let picked = WindowPick.frontmost(at: CGPoint(x: 10, y: 10), in: [menuBar, invisible, real])
        #expect(picked?.id == 3)
    }

    @Test func excludedWindowsAreSkipped() {
        // The capture overlay's own shield panels cover the whole screen and
        // are in front of everything; they must never be the answer.
        let shield = window(9, CGRect(x: 0, y: 0, width: 800, height: 600))
        let real = window(3, CGRect(x: 0, y: 0, width: 800, height: 600))
        let picked = WindowPick.frontmost(at: CGPoint(x: 10, y: 10), in: [shield, real], excluding: [9])
        #expect(picked?.id == 3)
    }

    @Test func tinyWindowsAreNotPickable() {
        // Some apps park 1x1 helper windows at layer 0; picking one would
        // capture a speck.
        let speck = window(1, CGRect(x: 10, y: 10, width: 1, height: 1))
        let real = window(2, CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(WindowPick.frontmost(at: CGPoint(x: 10, y: 10), in: [speck, real])?.id == 2)
        #expect(WindowPick.minimumSide > 1)
    }

    @Test func aClickIsAPressThatBarelyMoved() {
        let start = CGPoint(x: 100, y: 100)
        #expect(WindowPick.isClick(from: start, to: start))
        #expect(WindowPick.isClick(from: start, to: CGPoint(x: 102, y: 101)))
        #expect(!WindowPick.isClick(from: start, to: CGPoint(x: 100, y: 100 + WindowPick.dragThreshold)))
        #expect(!WindowPick.isClick(from: start, to: CGPoint(x: 140, y: 100)))
    }

    @Test func captureRectIsTheWindowClampedToTheDisplayAndWholePoints() {
        let display = CGRect(x: 0, y: 0, width: 800, height: 600)
        // Straddling the right edge: only the part on this display exists in
        // the frozen picture.
        let straddling = window(1, CGRect(x: 700, y: 100.4, width: 300, height: 200.2))
        let rect = WindowPick.captureRect(for: straddling, within: display)
        #expect(rect == CGRect(x: 700, y: 100, width: 100, height: 201))
        // Fully off this display: nothing to capture here.
        let elsewhere = window(2, CGRect(x: 900, y: 0, width: 100, height: 100))
        #expect(WindowPick.captureRect(for: elsewhere, within: display) == nil)
    }

    @Test func labelNamesTheAppAndTheSizeInWholePoints() {
        let w = window(1, CGRect(x: 0, y: 0, width: 1440.6, height: 900), owner: "Safari")
        #expect(WindowPick.label(for: w) == "Safari  1441 × 900")
        let anonymous = window(2, CGRect(x: 0, y: 0, width: 300, height: 200), owner: "")
        #expect(WindowPick.label(for: anonymous) == "300 × 200")
        #expect(WindowPick.sizeLabel(for: CGSize(width: 300, height: 200)) == "300 × 200")
    }

    @Test func labelSitsInsideTheWindowsTopLeftWhenItFitsElseBelowOrOnScreen() {
        let display = CGRect(x: 0, y: 0, width: 800, height: 600)
        let label = CGSize(width: 120, height: 22)
        // Roomy window: label inset from its top-left corner.
        let roomy = CGRect(x: 100, y: 100, width: 400, height: 300)
        let inside = WindowPick.labelOrigin(for: roomy, labelSize: label, inset: 8, within: display)
        #expect(inside == CGPoint(x: 108, y: 108))
        // Too small to hold the label: it goes just below the window instead.
        let small = CGRect(x: 100, y: 100, width: 60, height: 20)
        let below = WindowPick.labelOrigin(for: small, labelSize: label, inset: 8, within: display)
        #expect(below == CGPoint(x: 100, y: 128))
        // Small and at the bottom of the display: it goes above.
        let bottom = CGRect(x: 100, y: 570, width: 60, height: 20)
        let above = WindowPick.labelOrigin(for: bottom, labelSize: label, inset: 8, within: display)
        #expect(above == CGPoint(x: 100, y: 540))
        // Whatever happens, the label stays on the display.
        let corner = CGRect(x: 760, y: 590, width: 60, height: 20)
        let clamped = WindowPick.labelOrigin(for: corner, labelSize: label, inset: 8, within: display)
        #expect(display.contains(CGRect(origin: clamped, size: label)))
    }
}
