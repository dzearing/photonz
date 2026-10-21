import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// "Find the misalignments": reading a UI screenshot into the things on it
/// (`LayoutRead`), finding what is inconsistent among them
/// (`MisalignmentScan`), and the mark each finding becomes. The detector is
/// scored on real rendered UIs in `MisalignmentCorpusTests`; these pin the
/// rules on pictures painted to the pixel.
@Suite("Find the misalignments")
struct MisalignmentTests {

    /// A flat picture painted box by box, in the picture's own pixels.
    struct Painting {
        let w: Int, h: Int
        var l: [UInt8], rg: [UInt8], yb: [UInt8]
        init(w: Int, h: Int, page: UInt8 = 242) {
            self.w = w
            self.h = h
            l = [UInt8](repeating: page, count: w * h)
            rg = [UInt8](repeating: 128, count: w * h)
            yb = [UInt8](repeating: 128, count: w * h)
        }
        mutating func fill(_ r: CGRect, _ v: UInt8, rg c: UInt8 = 128) {
            for y in Int(r.minY)..<Int(r.maxY) { for x in Int(r.minX)..<Int(r.maxX) {
                l[y * w + x] = v
                rg[y * w + x] = c
            } }
        }
        /// A box with a border ring of `border` pixels.
        mutating func box(_ r: CGRect, fill v: UInt8, border: Int = 0, ink: UInt8 = 120) {
            fill(r, border > 0 ? ink : v)
            if border > 0 { fill(r.insetBy(dx: CGFloat(border), dy: CGFloat(border)), v) }
        }
        /// A "word": glyph-like bars two pixels apart.
        mutating func word(x: Int, y: Int, letters: Int, height: Int = 18) {
            for i in 0..<letters { fill(CGRect(x: x + i * 8, y: y, width: 6, height: height), 30) }
        }
        var luma: LumaField { LumaField(width: w, height: h, samples: l, redGreen: rg, yellowBlue: yb) }
    }

    // MARK: Reading the picture

    @Test("A card on the page is a box, and what sits inside it is its children")
    func readsNesting() {
        var p = Painting(w: 400, h: 300)
        p.box(CGRect(x: 20, y: 20, width: 360, height: 260), fill: 255)
        for (i, y) in [40, 120, 200].enumerated() {
            p.fill(CGRect(x: 280, y: y, width: 80, height: 48), 200, rg: 90 + UInt8(i))
        }
        let nodes = LayoutRead.read(p.luma, pixelScale: 2)
        let cards = nodes.indices.filter { nodes[$0].kind == .box && nodes[$0].parent == nil }
        #expect(cards.count == 1)
        let card = try? #require(cards.first)
        #expect(nodes[card ?? 0].rect == CGRect(x: 20, y: 20, width: 360, height: 260))
        let inside = nodes.filter { $0.parent == card }
        #expect(inside.count == 3, "\(nodes)")
        #expect(inside.allSatisfy { $0.kind == .box && $0.rect.width == 80 && $0.rect.height == 48 })
    }

    @Test("Letters side by side read as one line of words, with its baseline")
    func readsWords() {
        var p = Painting(w: 300, h: 100)
        p.word(x: 40, y: 30, letters: 6)
        let nodes = LayoutRead.read(p.luma, pixelScale: 2)
        #expect(nodes.count == 1)
        #expect(nodes.first?.kind == .text)
        #expect(nodes.first?.rect == CGRect(x: 40, y: 30, width: 46, height: 18))
        #expect(nodes.first?.baseline == 48)
    }

    @Test("A box's border is read in pixels on every side")
    func readsBorders() {
        var p = Painting(w: 300, h: 200, page: 255)
        p.box(CGRect(x: 40, y: 40, width: 200, height: 100), fill: 250, border: 4)
        let nodes = LayoutRead.read(p.luma, pixelScale: 2)
        #expect(nodes.first?.border == [4, 4, 4, 4])
        #expect(nodes.first?.borderWidth == 4)
    }

    // MARK: Finding what is off

    static func nodes(_ rects: [CGRect], kind: LayoutNode.Kind = .box) -> [LayoutNode] {
        rects.map { LayoutNode(rect: $0, kind: kind) }
    }
    static let canvas = CGRect(x: 0, y: 0, width: 800, height: 800)

    @Test("One box in a column 2 points left of the others is marked, with both numbers")
    func edgeOff() throws {
        let nodes = Self.nodes([40, 40, 44, 40].enumerated().map { i, x in
            CGRect(x: CGFloat(x), y: 40 + CGFloat(i) * 100, width: 120, height: 60)
        })
        let found = MisalignmentScan.findings(in: nodes, canvas: Self.canvas, pixelScale: 2)
        #expect(found.count == 1)
        let f = try #require(found.first)
        #expect(f.kind == .edge)
        #expect(f.axis == .x)
        #expect(f.subject == nodes[2].rect)
        #expect(f.chip == "Left edge 2 pt off: 22 vs 20")
        #expect(f.line == 40)
        #expect(f.actual == 44)
    }

    @Test("A column that agrees is not marked")
    func clean() {
        let nodes = Self.nodes((0..<4).map { CGRect(x: 40, y: 40 + CGFloat($0) * 100, width: 120, height: 60) })
        #expect(MisalignmentScan.findings(in: nodes, canvas: Self.canvas, pixelScale: 2).isEmpty)
    }

    @Test("Things more than 8 points apart differ on purpose")
    func farApartIsDesign() {
        let nodes = Self.nodes([40, 40, 80, 40].enumerated().map { i, x in
            CGRect(x: CGFloat(x), y: 40 + CGFloat(i) * 100, width: 120, height: 60)
        })
        #expect(MisalignmentScan.findings(in: nodes, canvas: Self.canvas, pixelScale: 2).isEmpty)
    }

    @Test("A narrower shape centred among wide ones is placed on purpose")
    func centredIsFine() {
        let nodes = Self.nodes([CGRect(x: 40, y: 40, width: 120, height: 60), CGRect(x: 40, y: 140, width: 120, height: 60),
                                CGRect(x: 44, y: 240, width: 112, height: 50), CGRect(x: 40, y: 340, width: 120, height: 60)])
        #expect(MisalignmentScan.findings(in: nodes, canvas: Self.canvas, pixelScale: 2).isEmpty)
    }

    @Test("The one uneven gap in a row of like things is marked")
    func gapOff() throws {
        var x: CGFloat = 20
        var rects: [CGRect] = []
        for gap in [16, 16, 20, 16, 0] {
            rects.append(CGRect(x: x, y: 40, width: 64, height: 64))
            x += 64 + CGFloat(gap)
        }
        let found = MisalignmentScan.findings(in: Self.nodes(rects), canvas: Self.canvas, pixelScale: 2)
        #expect(found.count == 1)
        let f = try #require(found.first)
        #expect(f.kind == .gap)
        #expect(f.chip == "Gap 2 pt wider: 10 vs 8")
        #expect(f.subject == CGRect(x: rects[2].maxX, y: 40, width: 20, height: 64))
    }

    @Test("A thing moved between two even gaps is marked as moved, not as two gaps")
    func movedBetweenGaps() throws {
        // Gaps of 16, 16, 20, 12 and 16: the fourth thing sits 2 points right.
        let rects = [20, 100, 180, 264, 340, 420].map { CGRect(x: CGFloat($0), y: 40, width: 64, height: 64) }
        let found = MisalignmentScan.findings(in: Self.nodes(rects), canvas: Self.canvas, pixelScale: 2)
        #expect(found.count == 1)
        #expect(found.first?.kind == .edge)
        #expect(found.first?.subject == rects[3])
    }

    @Test("A border twice as thick as its twins' is marked")
    func borderOff() throws {
        let rects = [20, 200, 380].map { CGRect(x: CGFloat($0), y: 40, width: 160, height: 120) }
        var nodes = Self.nodes(rects)
        for i in nodes.indices { nodes[i].border = i == 2 ? [4, 4, 4, 4] : [2, 2, 2, 2]; nodes[i].fill = 0xFF8080 }
        let found = MisalignmentScan.findings(in: nodes, canvas: Self.canvas, pixelScale: 2)
        #expect(found.map(\.kind) == [.border])
        #expect(found.first?.chip == "Border 1 pt thicker: 2 vs 1")
        #expect(found.first?.subject == rects[2])
    }

    @Test("A card whose content all sits further in than its twins' has different padding")
    func paddingOff() throws {
        var nodes: [LayoutNode] = []
        for (i, inset) in [32, 32, 36].enumerated() {
            let card = CGRect(x: 40, y: 40 + CGFloat(i) * 200, width: 400, height: 160)
            nodes.append(LayoutNode(rect: card, kind: .box))
            let p = nodes.count - 1
            nodes.append(LayoutNode(rect: CGRect(x: card.minX + CGFloat(inset), y: card.minY + 40, width: 80, height: 80),
                                    kind: .box, parent: p))
            nodes.append(LayoutNode(rect: CGRect(x: card.minX + CGFloat(inset), y: card.minY + 130, width: 200, height: 10),
                                    kind: .rule, parent: p))
        }
        let found = MisalignmentScan.findings(in: nodes, canvas: Self.canvas, pixelScale: 2)
        #expect(found.map(\.kind) == [.padding], "\(found.map(\.chip))")
        #expect(found.first?.subject == nodes[6].rect)
        #expect(found.first?.chip == "Padding 2 pt more: 18 vs 16")
    }

    @Test("Every readout fits the chrome's 30 characters")
    func chipsAreShort() {
        let worst = Misalignment(kind: .padding, axis: .x, reading: .bottom, subject: .zero, others: [],
                                 expected: 112.5, found: 120.5)
        #expect(worst.chip.count <= 30, "\(worst.chip)")
        let edge = Misalignment(kind: .edge, axis: .y, reading: .baseline, subject: .zero, others: [],
                                expected: 210.5, found: 218.5)
        #expect(edge.chip.count <= 30, "\(edge.chip)")
        let left = Misalignment(kind: .edge, axis: .x, reading: .left, subject: .zero, others: [],
                                expected: 17, found: 18.5)
        #expect(left.chip == "Left 1.5 pt off: 18.5 vs 17")
    }

    // MARK: The mark

    @Test("An edge finding is an alignment guide on the others' line with the subject bracketed")
    func edgeMark() throws {
        let nodes = Self.nodes([40, 40, 44, 40].enumerated().map { i, x in
            CGRect(x: CGFloat(x), y: 40 + CGFloat(i) * 100, width: 120, height: 60)
        })
        let f = try #require(MisalignmentScan.findings(in: nodes, canvas: Self.canvas, pixelScale: 2).first)
        let mark = try #require(MisalignmentMark(f, pixelScale: 2))
        #expect(mark.mode == .vertical)
        #expect(mark.start.x == 40 && mark.end.x == 40)
        #expect(mark.start.y <= 40 && mark.end.y >= 400)
        let check = try #require(mark.alignment)
        let verdict = try #require(check.verdict)
        #expect(verdict.reference == 40)
        #expect(verdict.outlierIndex.map { check.items[$0].edge } == 44)
        #expect(mark.chip == "Left edge 2 pt off: 22 vs 20")
    }

    @Test("A gap finding is a caliper across the gap")
    func gapMark() throws {
        let f = Misalignment(kind: .gap, axis: .x, subject: CGRect(x: 100, y: 40, width: 20, height: 64),
                             others: [], expected: 8, found: 10)
        let mark = try #require(MisalignmentMark(f, pixelScale: 2))
        #expect(mark.mode == .horizontal)
        #expect(mark.start == CGPoint(x: 100, y: 72))
        #expect(mark.end == CGPoint(x: 120, y: 72))
        #expect(mark.alignment == nil)
    }

    @Test("A measurement carrying a finding reads it, and keeps it through saving")
    func findingReadout() throws {
        var content = MeasureContent(start: .zero, end: CGPoint(x: 20, y: 0))
        content.finding = "Gap 2 pt wider: 10 vs 8"
        #expect(content.chipText(pixelScale: 2) == "Gap 2 pt wider: 10 vs 8")
        #expect(content.label(pixelScale: 2) == "10 vs 8")
        let back = try JSONDecoder().decode(MeasureContent.self, from: JSONEncoder().encode(content))
        #expect(back.finding == content.finding)
        let plain = try JSONDecoder().decode(MeasureContent.self, from: JSONEncoder().encode(MeasureContent()))
        #expect(plain.finding == nil)
    }

    // MARK: The tools

    @Test("find_misalignments and mark_misalignments are offered and read their arguments")
    func tools() throws {
        let find = try AgentTools.request(tool: "find_misalignments",
                                          arguments: AgentJSON.parse(Data(#"{"region":{"x":0,"y":0,"width":100,"height":50}}"#.utf8))).get()
        #expect(find == .findMisalignments(document: nil, region: CGRect(x: 0, y: 0, width: 100, height: 50)))
        let mark = try AgentTools.request(tool: "mark_misalignments",
                                          arguments: AgentJSON.parse(Data(#"{"findings":["m1","m3"]}"#.utf8))).get()
        #expect(mark == .markMisalignments(document: nil, region: nil, findings: ["m1", "m3"]))
        guard case .failure = AgentTools.request(tool: "mark_misalignments",
                                                 arguments: try AgentJSON.parse(Data(#"{"findings":[]}"#.utf8)))
        else { Issue.record("an empty list of findings was accepted"); return }
        #expect(AskTools.looking.contains("find_misalignments"))
        #expect(AskTools.doing.contains("mark_misalignments"))
    }

    @Test("The answer names each finding by id with its words, numbers and box")
    func report() throws {
        let f = Misalignment(kind: .gap, axis: .x, subject: CGRect(x: 100, y: 40, width: 20, height: 64),
                             others: [], expected: 8, found: 10)
        let json = MisalignmentScan.report([f, f])
        #expect(json["count"]?.intValue == 2)
        let first = try #require(json["findings"]?.arrayValue?.first)
        #expect(first["id"]?.stringValue == "m1")
        #expect(first["what"]?.stringValue == "Gap 2 pt wider: 10 vs 8")
        #expect(first["box"]?["width"]?.doubleValue == 20)
        #expect(MisalignmentScan.report([])["say"]?.stringValue == "Nothing is out of line.")
    }

    @Test("The Ask row says how many it found")
    func rowWords() {
        let step = AskStep(tool: "mark_misalignments",
                           arguments: ["findings": .array(["m1", "m2", "m3", "m4", "m5", "m6"])])
        #expect(AskChangeWords.sentence([step]) == "Found 6 misalignments")
        let one = AskStep(tool: "mark_misalignments", arguments: ["findings": .array(["m2"])])
        #expect(AskChangeWords.sentence([one]) == "Found a misalignment")
    }
}
