import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// "Annotate the ux with measurements": what a designer hands a developer.
/// One size of each kind of control, then the spacing that defines the layout,
/// chosen by code off the picture's own layout (`RedlinePlan`) and laid out so
/// no readout sits on another, on words or on a control (`RedlineLayout`).
///
/// The user, 2026-10-20, on twelve measurements with the same switch measured
/// four times and readouts stacked on readouts: "way too noisey".
@Suite("A calm redline of a UI screenshot")
struct RedlinePlanTests {

    static func picture(_ name: String) throws -> LumaField {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "png"))
        let image = try #require(ImageCodec.decode(try Data(contentsOf: url)))
        return EdgeMapAnalyzer.analyzeFully(image).luma
    }

    static let settings = "settings-pane-2x"
    /// Three real screenshots of different shapes: a settings pane of two
    /// cards, a dialog with a row of buttons, a feed of repeated cards.
    static let screens = [settings, "misalign/dialog-clean", "misalign/feed-clean", "misalign/login-clean"]

    struct Read {
        let luma: LumaField
        let nodes: [LayoutNode]
        let marks: [RedlineMark]
        let canvas: CGSize
    }

    static func read(_ name: String) throws -> Read {
        let luma = try picture(name)
        let nodes = LayoutRead.read(luma, pixelScale: 2)
        let canvas = CGSize(width: luma.width, height: luma.height)
        let marks = RedlinePlan.marks(in: nodes, canvas: CGRect(origin: .zero, size: canvas), pixelScale: 2)
        return Read(luma: luma, nodes: nodes, marks: marks, canvas: canvas)
    }

    // MARK: What is measured

    @Test("The settings pane gets six to ten marks: one size of each kind, then its spacing")
    func settingsCount() throws {
        let r = try Self.read(Self.settings)
        #expect((6...10).contains(r.marks.count), "\(r.marks.map(\.what))")
        let sizes = r.marks.filter { $0.role == .size }
        let spacing = r.marks.filter { $0.role != .size }
        #expect(sizes.count >= 2 && sizes.count <= 4, "\(sizes.map(\.what))")
        // Sizes first, the way a redline reads: what things are, then how they sit.
        let firstSpacing = r.marks.firstIndex { $0.role != .size } ?? r.marks.count
        #expect(r.marks[..<firstSpacing].allSatisfy { $0.role == .size })
        #expect(spacing.count >= 4)
    }

    @Test("The four switches and the two fields each get one size, on whichever has the most room for it")
    func repeatsOnce() throws {
        let r = try Self.read(Self.settings)
        let sizes = r.marks.filter { $0.role == .size }
        func points(_ m: RedlineMark) -> CGSize {
            CGSize(width: ((m.box?.width ?? 0) / 2).rounded(), height: ((m.box?.height ?? 0) / 2).rounded())
        }
        let switches = sizes.filter { points($0) == CGSize(width: 42, height: 24) }
        let fields = sizes.filter { points($0) == CGSize(width: 220, height: 26) }
        #expect(switches.count == 1, "\(sizes.map { points($0) })")
        #expect(fields.count == 1, "\(sizes.map { points($0) })")
        #expect(switches.first?.repeats == 4)
        #expect(fields.first?.repeats == 2)
        // On one of the four switches, at the switch column's own place.
        #expect(switches.first?.box?.minX == 1260)
        #expect(switches.first?.what == "Switch")
        #expect(fields.first?.what == "Field")
    }

    @Test("The spacing a designer marks: padding, row height, section gap, the gap between buttons, a label's inset; never a margin to where the screenshot was cropped")
    func spacingRoles() throws {
        let r = try Self.read(Self.settings)
        let roles = Set(r.marks.map(\.role))
        for role in [RedlineMark.Role.padding, .rhythm, .sectionGap, .gap, .inset] {
            #expect(roles.contains(role), "missing \(role): \(r.marks.map(\.what))")
        }
        func value(_ role: RedlineMark.Role) -> CGFloat? { r.marks.first { $0.role == role }?.value(pixelScale: 2) }
        // Nothing measured from the picture's own edge.
        #expect(r.marks.allSatisfy { $0.start.x > 0 && $0.start.y > 0 })
        #expect(abs((value(.padding) ?? 0) - 17) <= 1.5)
        #expect(abs((value(.rhythm) ?? 0) - 44) <= 1.5)
        #expect(abs((value(.sectionGap) ?? 0) - 19) <= 2)
        #expect(abs((value(.gap) ?? 0) - 12) <= 1.5)
    }

    @Test("Nothing measures a whole row or a whole card, and no box or span is measured twice")
    func noFullWidthNoRepeats() throws {
        for name in Self.screens {
            let r = try Self.read(name)
            for m in r.marks {
                if let box = m.box {
                    // A control, not a row: a field may be most of a narrow
                    // dialog's width, never the whole picture's.
                    #expect(box.width < r.canvas.width * 0.9, "\(name): \(m.what) is \(box.width) wide")
                } else {
                    let span = hypot(m.end.x - m.start.x, m.end.y - m.start.y)
                    #expect(span < r.canvas.width * 0.5, "\(name): \(m.what) spans \(span)")
                }
            }
            let sizes = r.marks.compactMap(\.box).map { "\(Int($0.width / 2))x\(Int($0.height / 2))" }
            #expect(Set(sizes).count == sizes.count, "\(name): \(sizes)")
            #expect(r.marks.count <= RedlinePlan.mostMarks)
            #expect(!r.marks.isEmpty, "\(name) got no marks")
        }
    }

    // MARK: Where the readouts go

    static func edges(_ r: Read) -> [CGRect] {
        RedlinePlan.edges(in: r.nodes, canvas: CGRect(origin: .zero, size: r.canvas), pixelScale: 2)
    }

    /// Every caliper the redline draws, placed as the app places them.
    static func laid(_ r: Read) -> [MeasureContent] {
        // The Measure tool's own default styles, as the app lays them.
        let size = MeasureStyles().content(for: .size)
        let spacing = MeasureStyles().content(for: .spacing)
        let obstacles = RedlinePlan.obstacles(in: r.nodes, canvas: CGRect(origin: .zero, size: r.canvas), pixelScale: 2)
        return RedlineLayout.lay(r.marks, obstacles: obstacles, edges: Self.edges(r), canvas: r.canvas,
                                 size: size, spacing: spacing).flatMap(\.calipers)
    }

    @Test("No readout overlaps another, or sits on words or a control, and every one is on the picture")
    func readoutsClear() throws {
        for name in Self.screens {
            let r = try Self.read(name)
            let calipers = Self.laid(r)
            if name == Self.settings {
                // Leaving a mark out is the last resort, not the habit.
                let laid = RedlineLayout.lay(r.marks, obstacles: RedlinePlan.obstacles(in: r.nodes, canvas: CGRect(origin: .zero, size: r.canvas), pixelScale: 2), edges: Self.edges(r),
                                             canvas: r.canvas, size: MeasureStyles().content(for: .size), spacing: MeasureStyles().content(for: .spacing))
                #expect(laid.count == r.marks.count, "\(laid.map(\.mark.what)) of \(r.marks.map(\.what))")
            }
            #expect(!calipers.isEmpty, "\(name) laid nothing")
            let rects = calipers.map { $0.labelRect(chipSize: $0.estimatedLabelSize) }
            let canvas = CGRect(origin: .zero, size: r.canvas)
            let obstacles = RedlinePlan.obstacles(in: r.nodes, canvas: CGRect(origin: .zero, size: r.canvas), pixelScale: 2)
            for (i, a) in rects.enumerated() {
                #expect(canvas.contains(a), "\(name): readout \(i) is off the picture")
                for b in rects[(i + 1)...] where a.intersects(b) {
                    Issue.record("\(name): readouts \(a) and \(b) overlap")
                }
                for o in obstacles where a.intersects(o) {
                    Issue.record("\(name): readout \(i) \(a) sits on \(o)")
                }
            }
        }
    }

    @Test("No readout sits on another measurement's line, and no two leader lines cross")
    func linesClear() throws {
        for name in Self.screens {
            let r = try Self.read(name)
            let calipers = Self.laid(r)
            for (i, c) in calipers.enumerated() {
                let chip = c.labelRect(chipSize: c.estimatedLabelSize)
                for (j, other) in calipers.enumerated() where j != i {
                    for line in other.subjectRects where chip.intersects(line) {
                        Issue.record("\(name): readout \(i) sits on caliper \(j)'s line")
                    }
                }
            }
            let leaders = calipers.compactMap(RedlineLayout.leader(of:))
            // A leader never runs across words or a control, save the one it
            // starts inside (a button's own label inset).
            let obstacles = RedlinePlan.obstacles(in: r.nodes, canvas: CGRect(origin: .zero, size: r.canvas), pixelScale: 2)
            for run in leaders {
                let crossed = RedlineLayout.inWay(of: run.0, among: obstacles)
                    .filter { LabelPlacer.segment(from: run.0, to: run.1, crosses: [$0]) }
                if !crossed.isEmpty { Issue.record("\(name): a leader from \(run.0) runs across \(crossed)") }
            }
            for (i, a) in leaders.enumerated() {
                for b in leaders[(i + 1)...] where RedlineLayout.cross(a, b) {
                    Issue.record("\(name): two leader lines cross")
                }
            }
        }
    }

    @Test("A size's calipers sit on the box they measure, and never reach past the picture")
    func sizeCalipersHug() throws {
        let r = try Self.read(Self.settings)
        let canvas = CGRect(origin: .zero, size: r.canvas)
        let size = MeasureStyles().content(for: .size)
        let laid = RedlineLayout.lay(r.marks, obstacles: RedlinePlan.obstacles(in: r.nodes, canvas: CGRect(origin: .zero, size: r.canvas), pixelScale: 2), edges: Self.edges(r),
                                     canvas: r.canvas, size: size, spacing: size)
        for drawn in laid where drawn.mark.role == .size {
            let box = try #require(drawn.mark.box)
            #expect(drawn.calipers.count == 2)
            for c in drawn.calipers {
                let span = c.mode == .horizontal ? abs(c.end.x - c.start.x) : abs(c.end.y - c.start.y)
                #expect(span == (c.mode == .horizontal ? box.width : box.height))
                let g = c.caliperGeometry()
                for p in [g.footA, g.footB, g.headA, g.headB] {
                    #expect(canvas.contains(p))
                }
                // The head stands off the box by no more than a readout's reach.
                #expect(abs(c.headOffset) <= c.estimatedLabelSize.height * 2)
            }
        }
    }
}
