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
        #expect(WindowPick.label(for: w).text == "Safari  1441 × 900")
        let anonymous = window(2, CGRect(x: 0, y: 0, width: 300, height: 200), owner: "")
        #expect(WindowPick.label(for: anonymous).text == "300 × 200")
        #expect(WindowPick.sizeLabel(for: CGSize(width: 300, height: 200)) == "300 × 200")
    }

    // MARK: Window title in the label

    private func titled(_ title: String, owner: String = "Safari",
                        frame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900)) -> ScreenWindow {
        ScreenWindow(id: 1, frame: frame, layer: 0, alpha: 1, ownerName: owner, title: title)
    }

    @Test func labelPutsTheTitleBetweenTheAppAndTheSize() {
        let label = WindowPick.label(for: titled("Apple"))
        #expect(label.app == "Safari")
        #expect(label.title == "Apple")
        #expect(label.size == "1440 × 900")
        #expect(label.text == "Safari · Apple  1440 × 900")
        // No title (no Screen Recording grant, or an untitled window): app and size only.
        #expect(WindowPick.label(for: titled("")).text == "Safari  1440 × 900")
        #expect(WindowPick.label(for: titled("   ")).title == nil)
        // A title with no app name to hang off still reads.
        #expect(WindowPick.label(for: titled("Apple", owner: "")).text == "Apple  1440 × 900")
        // Asking for the plain label leaves the title out.
        #expect(WindowPick.label(for: titled("Apple"), includingTitle: false).text == "Safari  1440 × 900")
    }

    @Test func titleIsTidiedBeforeItIsShown() {
        // Surrounding whitespace and line breaks never reach the pill.
        #expect(WindowPick.displayTitle("  Apple\nStart ", app: "Safari") == "Apple Start")
        // A window titled after its own app says nothing new.
        #expect(WindowPick.displayTitle("Calculator", app: "Calculator") == nil)
        #expect(WindowPick.displayTitle("calculator", app: "Calculator") == nil)
        // Browsers and Electron apps suffix the app name; the pill already has it.
        #expect(WindowPick.displayTitle("Apple - Microsoft Edge", app: "Microsoft Edge") == "Apple")
        #expect(WindowPick.displayTitle("Apple — Google Chrome", app: "Google Chrome") == "Apple")
        #expect(WindowPick.displayTitle("Apple – Google Chrome", app: "Google Chrome") == "Apple")
        #expect(WindowPick.displayTitle("Apple | Slack", app: "Slack") == "Apple")
        // Some apps lead with their name instead.
        #expect(WindowPick.displayTitle("Photonz — Untitled 2", app: "Photonz") == "Untitled 2")
        // Only the app name at an end goes; a name in the middle is content.
        #expect(WindowPick.displayTitle("Why Safari beats Chrome", app: "Safari") == "Why Safari beats Chrome")
        // Nothing left once the app name goes: no title.
        #expect(WindowPick.displayTitle(" - Microsoft Edge", app: "Microsoft Edge") == nil)
    }

    /// A fake measure: every character is 10 pt wide, so widths are easy to
    /// reason about.
    private func tenPerCharacter(_ label: WindowLabel) -> CGFloat {
        CGFloat(label.text.count) * 10
    }

    @Test func longTitlesAreShortenedToFitAndTheAppAndSizeNeverAre() {
        let w = titled("A very long page title that goes on and on")
        // Plenty of room: the whole label.
        let whole = WindowPick.label(for: w, fitting: 10_000, measure: tenPerCharacter)
        #expect(whole.text == "Safari · A very long page title that goes on and on  1440 × 900")
        // Tight: the title loses its tail and gains an ellipsis; app and size stay whole.
        let tight = WindowPick.label(for: w, fitting: 300, measure: tenPerCharacter)
        #expect(tight.app == "Safari")
        #expect(tight.size == "1440 × 900")
        #expect(tight.title?.hasSuffix("…") == true)
        #expect(tenPerCharacter(tight) <= 300)
        // The shortening takes as much of the title as fits, not less.
        #expect(tight.text.count == 30)
        #expect(tight.text == "Safari · A very l…  1440 × 900")
        // Fits exactly: no ellipsis.
        let exact = WindowPick.label(for: titled("Apple"), fitting: 260, measure: tenPerCharacter)
        #expect(exact.title == "Apple")
    }

    @Test func aTitleThatWouldShrinkToAStubIsDroppedInstead() {
        let w = titled("A very long page title")
        // Room for "Safari · " and "  1440 × 900" (21 characters) plus three:
        // a title of "A…" would say nothing, so it goes.
        let stub = WindowPick.label(for: w, fitting: 240, measure: tenPerCharacter)
        #expect(stub.title == nil)
        #expect(stub.text == "Safari  1440 × 900")
        // Not even the plain label fits: it is still the answer, whole.
        let cramped = WindowPick.label(for: w, fitting: 50, measure: tenPerCharacter)
        #expect(cramped.text == "Safari  1440 × 900")
        #expect(WindowPick.minimumTitleLength == 3)
    }

    @Test func shorteningKeepsWholeCharacters() {
        // Grapheme clusters (flags, emoji with skin tones) never get split.
        let w = titled("🇬🇧🇬🇧🇬🇧🇬🇧🇬🇧🇬🇧🇬🇧🇬🇧")
        let short = WindowPick.label(for: w, fitting: 250, measure: tenPerCharacter)
        #expect(short.title?.hasSuffix("…") == true)
        #expect(short.title?.hasPrefix("🇬🇧🇬🇧🇬🇧") == true)
        #expect(short.title?.dropLast().allSatisfy { $0 == "🇬🇧" } == true)
    }

    @Test func fittedLabelStaysInsideTheWindowOrElseTheDisplay() {
        let display = CGRect(x: 0, y: 0, width: 800, height: 600)
        // The pill's size: 10 pt per character, 22 pt tall.
        func pill(_ label: WindowLabel) -> CGSize { CGSize(width: tenPerCharacter(label), height: 22) }
        let title = "A very long page title that goes on and on"
        // A 400 pt wide window holds the plain label, so the pill lives inside
        // it and the title is cut to keep it there (400 minus 8 pt insets each side).
        let roomy = titled(title, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        let inside = WindowPick.fittedLabel(for: roomy, in: roomy.frame, within: display, inset: 8, measure: pill)
        #expect(inside.title?.hasSuffix("…") == true)
        #expect(pill(inside).width <= 400 - 16)
        #expect(pill(inside).width > 300)
        // A window too narrow for even the plain label puts the pill below
        // itself, where the display is the limit, so more of the title survives.
        let narrow = titled(title, frame: CGRect(x: 100, y: 100, width: 100, height: 300))
        let below = WindowPick.fittedLabel(for: narrow, in: narrow.frame, within: display, inset: 8, measure: pill)
        #expect(pill(below).width > pill(inside).width)
        #expect(pill(below).width <= WindowPick.maxLabelWidth)
        // A window too short for the pill does the same, however wide it is.
        let short = titled(title, frame: CGRect(x: 100, y: 100, width: 700, height: 20))
        let beside = WindowPick.fittedLabel(for: short, in: short.frame, within: display, inset: 8, measure: pill)
        #expect(pill(beside).width == pill(below).width)
        // The result always lands where labelOrigin will put it, inside the display.
        for (window, label) in [(roomy, inside), (narrow, below), (short, beside)] {
            let origin = WindowPick.labelOrigin(for: window.frame, labelSize: pill(label), inset: 8, within: display)
            #expect(display.contains(CGRect(origin: origin, size: pill(label))))
        }
    }

    @Test func fittedLabelNeverGrowsPastTheCapOnAHugeWindow() {
        let display = CGRect(x: 0, y: 0, width: 5120, height: 2880)
        func pill(_ label: WindowLabel) -> CGSize { CGSize(width: tenPerCharacter(label), height: 22) }
        let title = String(repeating: "word ", count: 40)
        let huge = titled(title, frame: display)
        let label = WindowPick.fittedLabel(for: huge, in: huge.frame, within: display, inset: 8, measure: pill)
        #expect(pill(label).width <= WindowPick.maxLabelWidth)
        #expect(label.title?.hasSuffix("…") == true)
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
