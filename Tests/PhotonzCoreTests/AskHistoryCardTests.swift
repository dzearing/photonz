import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Hovering a row of the Agent group's history shows a card to the left of the
/// panel: how Ask understood the request, and small before and after pictures
/// (the user, 2026-11-04). These are the words on it and where it sits.
@Suite("Ask: the history card")
struct AskHistoryCardTests {

    static func step(_ tool: String, _ arguments: AgentJSON = [:]) -> AskStep {
        AskStep(tool: tool, arguments: arguments)
    }

    // MARK: How it understood the request

    @Test("The model's own sentence comes first, then what each kind of step did")
    func summaryThenSteps() {
        let lines = AskUnderstanding.lines(summary: "A pricing card on brand.", steps: [
            Self.step("add_shape"), Self.step("add_shape"),
            Self.step("add_text", ["text": "Pro"]),
        ])
        #expect(lines == ["A pricing card on brand.", "Drew 2 shapes", "Added the text \u{201C}Pro\u{201D}"])
    }

    @Test("A drawing's plan is what Ask took the words to mean, so it is shown")
    func drawingPlanStatements() {
        let lines = AskUnderstanding.lines(summary: "", steps: [
            Self.step("add_drawing", ["subject": "a cat", "plan": ["The cat sits on a red mat", "It faces left"]]),
        ])
        #expect(lines.contains("The cat sits on a red mat"))
        #expect(lines.contains("It faces left"))
    }

    @Test("A few plain lines: past the most it says how many more")
    func aFewLines() {
        let steps = ["add_shape", "add_text", "add_title", "add_measurement", "set_layout", "apply_style", "cut"]
            .map { Self.step($0) }
        let lines = AskUnderstanding.lines(summary: "", steps: steps)
        #expect(lines.count == AskUnderstanding.mostLines + 1)
        #expect(lines.last == "and 2 more")
    }

    @Test("No line twice, no blank line, no stand-in words and no em dash")
    func tidyLines() {
        let lines = AskUnderstanding.lines(summary: "  Two boxes \u{2014} side by side  ", steps: [
            Self.step("add_shape"), Self.step("set_layer", ["x": 4]), Self.step("set_layer", ["x": 8]),
            Self.step("list_styles"),
        ])
        #expect(lines.first == "Two boxes, side by side")
        #expect(Set(lines).count == lines.count)
        #expect(!lines.contains(AskChangeWords.fallback))
        #expect(lines.allSatisfy { !$0.isEmpty && !$0.contains("\u{2014}") })
    }

    @Test("A very long sentence from the model is cut to a line a person reads")
    func longSummary() throws {
        let long = String(repeating: "word ", count: 80)
        let first = try #require(AskUnderstanding.lines(summary: long, steps: []).first)
        #expect(first.count <= AskUnderstanding.lineBudget)
        #expect(first.hasSuffix("\u{2026}"))
    }

    @Test("Nothing to say says nothing")
    func nothing() {
        #expect(AskUnderstanding.lines(summary: "", steps: []).isEmpty)
    }

    // MARK: Where it sits

    static let window = CGRect(x: 0, y: 0, width: 1280, height: 840)
    static let panelLeft: CGFloat = 1016
    static let row = CGRect(x: 1030, y: 200, width: 240, height: 22)
    static let card = CGSize(width: 288, height: 260)

    @Test("It sits left of the panel, level with its row, and never over the panel")
    func leftOfThePanel() {
        let box = AskHistoryCardPlacement.frame(size: Self.card, row: Self.row, panelLeft: Self.panelLeft,
                                                bounds: Self.window, avoiding: nil)
        #expect(box.maxX == Self.panelLeft - AskHistoryCardPlacement.gap)
        #expect(box.minY == Self.row.minY)
        #expect(box.size == Self.card)
    }

    @Test("A row near the foot of the window keeps its card inside the window")
    func staysInTheWindow() {
        let low = CGRect(x: 1030, y: 800, width: 240, height: 22)
        let box = AskHistoryCardPlacement.frame(size: Self.card, row: low, panelLeft: Self.panelLeft,
                                                bounds: Self.window, avoiding: nil)
        #expect(box.maxY == Self.window.maxY - AskHistoryCardPlacement.margin)
    }

    @Test("In a narrow window it keeps to the window's left edge and still clears the panel")
    func narrowWindow() {
        let narrow = CGRect(x: 0, y: 0, width: 500, height: 840)
        let box = AskHistoryCardPlacement.frame(size: Self.card, row: Self.row, panelLeft: 236,
                                                bounds: narrow, avoiding: nil)
        #expect(box.minX >= AskHistoryCardPlacement.margin)
        #expect(box.maxX <= 236 - AskHistoryCardPlacement.gap)
    }

    @Test("It slides off the thing the row made when there is room above or below it")
    func slidesOffTheObject() {
        let object = CGRect(x: 800, y: 150, width: 200, height: 200)
        let box = AskHistoryCardPlacement.frame(size: Self.card, row: Self.row, panelLeft: Self.panelLeft,
                                                bounds: Self.window, avoiding: object)
        #expect(!box.intersects(object))
        #expect(box.maxX == Self.panelLeft - AskHistoryCardPlacement.gap)
    }

    @Test("With no room off the object it stays by its row")
    func noRoomStaysPut() {
        let object = CGRect(x: 100, y: 10, width: 1000, height: 820)
        let box = AskHistoryCardPlacement.frame(size: Self.card, row: Self.row, panelLeft: Self.panelLeft,
                                                bounds: Self.window, avoiding: object)
        #expect(box.minY == Self.row.minY)
    }

    @Test("A thumbnail's scale fits the canvas's longest side, and never enlarges")
    func thumbnailScale() {
        #expect(AskHistoryCardPlacement.thumbnailScale(canvas: CGSize(width: 2000, height: 1000)) == 0.136)
        #expect(AskHistoryCardPlacement.thumbnailScale(canvas: CGSize(width: 100, height: 50)) == 1)
        #expect(AskHistoryCardPlacement.thumbnailScale(canvas: .zero) == 1)
    }
}
