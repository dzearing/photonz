import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The tools a model uses to redline a screenshot: `find_measurements` hands
/// it the marks code chose off the picture, `mark_measurements` lays the ones
/// it confirms. The choosing and the laying out are pinned on real
/// screenshots in `RedlinePlanTests`.
@Suite("Redline tools")
struct RedlineToolTests {

    @Test("find_measurements and mark_measurements are offered and read their arguments")
    func tools() throws {
        let find = try AgentTools.request(tool: "find_measurements",
                                          arguments: AgentJSON.parse(Data(#"{"region":{"x":0,"y":0,"width":100,"height":50}}"#.utf8))).get()
        #expect(find == .findMeasurements(document: nil, region: CGRect(x: 0, y: 0, width: 100, height: 50)))
        let mark = try AgentTools.request(tool: "mark_measurements",
                                          arguments: AgentJSON.parse(Data(#"{"marks":["r1","r3"]}"#.utf8))).get()
        #expect(mark == .markMeasurements(document: nil, region: nil, marks: ["r1", "r3"]))
        guard case .failure = AgentTools.request(tool: "mark_measurements",
                                                 arguments: try AgentJSON.parse(Data(#"{"marks":[]}"#.utf8)))
        else { Issue.record("an empty list of marks was accepted"); return }
        #expect(AskTools.looking.contains("find_measurements"))
        #expect(AskTools.doing.contains("mark_measurements"))
    }

    @Test("The answer names each mark by id with what it is and its reading in points")
    func report() throws {
        let marks = [
            RedlineMark.size("Switch", CGRect(x: 1260, y: 166, width: 84, height: 48), repeats: 4),
            RedlineMark(role: .gap, what: "Gap", start: CGPoint(x: 209, y: 786), end: CGPoint(x: 233, y: 786),
                        axis: .horizontal),
        ]
        let json = RedlinePlan.report(marks, pixelScale: 2)
        #expect(json["count"]?.intValue == 2)
        let list = try #require(json["marks"]?.arrayValue)
        #expect(list[0]["id"]?.stringValue == "r1")
        #expect(list[0]["what"]?.stringValue == "Switch")
        #expect(list[0]["reads"]?.stringValue == "42 × 24")
        #expect(list[0]["repeats"]?.intValue == 4)
        #expect(list[1]["reads"]?.stringValue == "12")
        #expect(list[1]["role"]?.stringValue == "gap")
    }

    @Test("With nothing to measure, the answer says what to do instead")
    func emptyReport() {
        let json = RedlinePlan.report([], pixelScale: 2)
        #expect(json["count"]?.intValue == 0)
        #expect(json["say"]?.stringValue?.contains("add_measurement") == true)
    }

    @Test("A redline is never thrown away for want of a clean spot: too few clean marks and the rest land as the Measure tool would place them")
    func neverEmpty() {
        // A picture far too small for any readout to sit clear of the line.
        let marks = [RedlineMark(role: .gap, what: "Gap", start: CGPoint(x: 20, y: 30), end: CGPoint(x: 40, y: 30),
                                 axis: .horizontal)]
        let laid = RedlineLayout.lay(marks, obstacles: [CGRect(x: 0, y: 0, width: 20, height: 60),
                                                         CGRect(x: 40, y: 0, width: 20, height: 60)],
                                     canvas: CGSize(width: 60, height: 60),
                                     size: MeasureStyles().content(for: .size),
                                     spacing: MeasureStyles().content(for: .spacing))
        #expect(laid.count == 1)
    }

    @Test("Ask is told to lay the marks that answer the request, not always all of them")
    func promptPicks() {
        let words = AskConversation.instructions(documentRead: "")
        #expect(words.contains("find_measurements"))
        #expect(words.contains("only those"))
    }

    @Test("The Ask row counts each mark it lays")
    func rowWords() {
        let step = AskStep(tool: "mark_measurements", arguments: ["marks": .array(["r1", "r2", "r3", "r4"])])
        #expect(AskChangeWords.sentence([step]) == "Added 4 measurements")
        // Laid beside a measurement placed by hand, they add up.
        let hand = AskStep(tool: "add_measurement", arguments: ["kind": "size"])
        #expect(AskChangeWords.sentence([step, hand]) == "Added 5 measurements")
    }

    /// A redline leaves out a mark whose number has no tidy spot, so the row
    /// counts what landed: the panel said "Added 7 measurements" over five on
    /// 2026-11-11.
    @Test("With the picture before and after, the row counts the measurements that landed, not the ids asked for")
    func rowCountsWhatLanded() {
        let step = AskStep(tool: "mark_measurements", arguments: ["marks": .array(["r1", "r2", "r3", "r4"])])
        var c = MeasureContent(mode: .horizontal, unit: .points)
        c.start = CGPoint(x: 10, y: 10)
        c.end = CGPoint(x: 90, y: 10)
        let picture = Layer(name: "Shot", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#000000")),
                            frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let before = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [picture])
        let laid = (0..<3).map { _ in MeasureBuilder.layer(content: c, from: c.start, to: c.end) }
        let after = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [picture] + laid)
        #expect(AskChangeWords.sentence([step], before: before, after: after) == "Added 3 measurements")
    }
}
