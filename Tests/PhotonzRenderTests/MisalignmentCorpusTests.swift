import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Synchronization
import Testing

/// "Find the misalignments" scored on screenshots with KNOWN planted faults:
/// small web UIs rendered at 2x by Chrome (`Scripts/misalign-corpus/make-corpus.mjs`),
/// each once clean and once with one fault (an element 1, 2 or 3 points off,
/// an uneven gap, a card with different padding, a 2 point border among 1
/// point ones), the answer written down in `truth.json` from the page's own
/// layout. The `climb` set was tuned against; the `held-out` set was written
/// after and is never tuned against.
///
/// The bar (the task's acceptance): precision and recall at least 0.9 on the
/// 2 and 3 point faults and at least 0.75 on 1 point, and a clean screenshot
/// gets no more than one false mark.
@Suite("Find the misalignments on screenshots with planted faults")
struct MisalignmentCorpusTests {

    struct Truth: Decodable {
        let scale: Double
        let cases: [Case]
        struct Case: Decodable { let name: String; let set: String; let faults: [Fault] }
        struct Fault: Decodable {
            let kind: String
            let pt: Double
            let axis: String?
            let alternative: Bool?
            let box: Box
        }
        struct Box: Decodable {
            let x, y, width, height: Double
            var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
        }
    }

    static func load() throws -> Truth {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/misalign/truth", withExtension: "json"))
        return try JSONDecoder().decode(Truth.self, from: Data(contentsOf: url))
    }

    static func picture(_ name: String) throws -> LumaField {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/misalign/\(name)", withExtension: "png"))
        let image = try #require(ImageCodec.decode(try Data(contentsOf: url)))
        return EdgeMapAnalyzer.analyzeFully(image).luma
    }

    static func share(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull else { return 0 }
        return i.width * i.height / max(1, min(a.width * a.height, b.width * b.height))
    }

    /// A finding is right when it is the planted fault: the same kind, on the
    /// same thing (or, for a pair with nothing else to judge by, its twin),
    /// and the same size to within half a point.
    static func matches(_ f: Misalignment, _ t: Truth.Fault) -> Bool {
        guard abs(abs(f.delta) - CGFloat(t.pt)) <= 0.5 else { return false }
        let box = t.box.rect
        switch (t.kind, f.kind) {
        case ("edge", .edge), ("padding", .padding), ("border", .border):
            if t.kind == "edge", let axis = t.axis, axis != f.axis.rawValue { return false }
            return share(f.subject, box) >= 0.6 || (f.others.count == 1 && share(f.others[0], box) >= 0.6)
        case ("gap", .gap):
            return f.subject.insetBy(dx: -2, dy: -2).intersects(box)
                || (f.others.count == 1 && f.others[0].insetBy(dx: -2, dy: -2).intersects(box))
        default:
            return false
        }
    }

    struct Score: CustomStringConvertible {
        var right = 0, wrong = 0
        var found1 = 0, planted1 = 0, found23 = 0, planted23 = 0
        var worstClean = 0
        var precision: Double { Double(right) / Double(max(1, right + wrong)) }
        var recall1: Double { Double(found1) / Double(max(1, planted1)) }
        var recall23: Double { Double(found23) / Double(max(1, planted23)) }
        var description: String {
            String(format: "precision %.2f (%d/%d), recall 1 pt %.2f (%d/%d), 2-3 pt %.2f (%d/%d), worst clean %d",
                   precision, right, right + wrong, recall1, found1, planted1, recall23, found23, planted23, worstClean)
        }
    }

    /// What the scan finds on every page of the corpus, worked out once for
    /// the whole suite and spread over the cores. The whole corpus and its
    /// held-out pages were each scanned page by page, the held-out ones twice,
    /// and that was 70 s of this Mac's time one test after another
    /// (2026-10-26).
    static let scanned: Result<[String: [Misalignment]], any Error> = Result {
        let cases = try load().cases
        let found = Mutex([String: Result<[Misalignment], any Error>]())
        DispatchQueue.concurrentPerform(iterations: cases.count) { index in
            let one = Result { MisalignmentScan.findings(luma: try picture(cases[index].name), pixelScale: 2) }
            found.withLock { $0[cases[index].name] = one }
        }
        return try found.withLock { $0 }.mapValues { try $0.get() }
    }

    static func score(_ set: String?) throws -> (Score, [String]) {
        var score = Score()
        var misses: [String] = []
        let scanned = try Self.scanned.get()
        for c in try load().cases where set == nil || c.set == set {
            let found = try #require(scanned[c.name])
            for f in found {
                if c.faults.contains(where: { matches(f, $0) }) { score.right += 1 } else {
                    score.wrong += 1
                    misses.append("\(c.name): false mark \(f.chip) at \(f.subject)")
                }
            }
            for t in c.faults where t.alternative != true {
                let hit = c.faults.filter { $0.pt == t.pt }.contains { alt in found.contains { matches($0, alt) } }
                if t.pt <= 1 { score.planted1 += 1; if hit { score.found1 += 1 } } else {
                    score.planted23 += 1; if hit { score.found23 += 1 }
                }
                if !hit { misses.append("\(c.name): missed \(t.kind) \(t.pt) pt") }
            }
            if c.faults.isEmpty { score.worstClean = max(score.worstClean, found.count) }
        }
        return (score, misses)
    }

    @Test("Every case in the corpus has a picture and at least twenty carry a fault")
    func corpusIsWhole() throws {
        let truth = try Self.load()
        #expect(truth.cases.filter { !$0.faults.isEmpty }.count >= 20)
        #expect(truth.cases.contains { $0.set == "held-out" })
        for c in truth.cases {
            let url = try #require(Bundle.module.url(forResource: "Fixtures/misalign/\(c.name)", withExtension: "png"))
            #expect(ImageCodec.decode(try Data(contentsOf: url)) != nil, "\(c.name)")
        }
    }

    @Test("The whole corpus clears the bar")
    func clearsTheBar() throws {
        let (score, misses) = try Self.score(nil)
        print("misalignment corpus, all: \(score)")
        #expect(score.precision >= 0.9, "\(score)\n\(misses.joined(separator: "\n"))")
        #expect(score.recall23 >= 0.9, "\(score)\n\(misses.joined(separator: "\n"))")
        #expect(score.recall1 >= 0.75, "\(score)\n\(misses.joined(separator: "\n"))")
        #expect(score.worstClean <= 1, "\(score)")
    }

    @Test("The held-out pages clear the bar too")
    func heldOutClearsTheBar() throws {
        let (score, misses) = try Self.score("held-out")
        print("misalignment corpus, held out: \(score)")
        #expect(score.precision >= 0.9, "\(score)\n\(misses.joined(separator: "\n"))")
        #expect(score.recall23 >= 0.9, "\(score)\n\(misses.joined(separator: "\n"))")
        #expect(score.worstClean <= 1, "\(score)")
    }

    @Test("The real settings screenshot's indented label is the one thing marked")
    func realSettingsPane() throws {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/settings-pane-2x", withExtension: "png"))
        let image = try #require(ImageCodec.decode(try Data(contentsOf: url)))
        let found = MisalignmentScan.findings(luma: EdgeMapAnalyzer.analyzeFully(image).luma, pixelScale: 2)
        #expect(found.count == 1)
        // "File name prefix" sits 4 points in from the labels above and below it.
        #expect(found.first.map { Self.share($0.subject, CGRect(x: 104, y: 570, width: 192, height: 30)) >= 0.6 } == true,
                "\(found.map(\.chip))")
        #expect(found.first?.kind == .edge)
    }
}
