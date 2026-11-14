import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Synchronization
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

    /// Every screen of `screens`, read once for the whole suite and spread
    /// over the cores: the tests asked for the four of them sixteen times
    /// between them (2026-10-26). What a test then does with a read is its
    /// own, since a `Read` is a value.
    static let readOnce: [String: Result<Read, any Error>] = {
        let read = Mutex([String: Result<Read, any Error>]())
        DispatchQueue.concurrentPerform(iterations: screens.count) { index in
            let name = screens[index]
            let one = Result { try reading(name) }
            read.withLock { $0[name] = one }
        }
        return read.withLock { $0 }
    }()

    static func read(_ name: String) throws -> Read {
        if let once = readOnce[name] { return try once.get() }
        return try reading(name)
    }

    static func reading(_ name: String) throws -> Read {
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

    @Test("The spacing a designer marks: padding, row height, section gap, the gap between buttons; never a margin to where the screenshot was cropped")
    func spacingRoles() throws {
        let r = try Self.read(Self.settings)
        let roles = Set(r.marks.map(\.role))
        for role in [RedlineMark.Role.padding, .rhythm, .sectionGap, .gap] {
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

    static func regions(_ r: Read) -> [CGRect] {
        RedlinePlan.regions(in: r.nodes, canvas: CGRect(origin: .zero, size: r.canvas), pixelScale: 2)
    }

    /// Every caliper the redline draws, placed as the app places them.
    static func laid(_ r: Read) -> [MeasureContent] {
        // The Measure tool's own default styles, as the app lays them.
        let size = MeasureStyles().content(for: .size)
        let spacing = MeasureStyles().content(for: .spacing)
        let obstacles = RedlinePlan.obstacles(in: r.nodes, canvas: CGRect(origin: .zero, size: r.canvas), pixelScale: 2)
        return RedlineLayout.lay(r.marks, obstacles: obstacles, edges: Self.edges(r), regions: Self.regions(r),
                                 canvas: r.canvas,
                                 size: size, spacing: spacing).flatMap(\.calipers)
    }

    @Test("No readout overlaps another, or sits on words or a control, and every one is on the picture")
    func readoutsClear() throws {
        for name in Self.screens {
            let r = try Self.read(name)
            let calipers = Self.laid(r)
            if name == Self.settings {
                // Every size is laid; spacing is left out only when its
                // number has no tidy spot, and most of the redline stays.
                let laid = RedlineLayout.lay(r.marks, obstacles: RedlinePlan.obstacles(in: r.nodes, canvas: CGRect(origin: .zero, size: r.canvas), pixelScale: 2), edges: Self.edges(r),
                                             regions: Self.regions(r), canvas: r.canvas,
                                             size: MeasureStyles().content(for: .size), spacing: MeasureStyles().content(for: .spacing))
                #expect(laid.filter { $0.mark.role == .size }.count == r.marks.filter { $0.role == .size }.count,
                        "\(laid.map(\.mark.what)) of \(r.marks.map(\.what))")
                #expect(laid.count >= 5, "\(laid.map(\.mark.what)) of \(r.marks.map(\.what))")
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

    /// The judge on the settings redline, 2026-11-11: "the 16 pt badge sits
    /// on a row divider", "the 18 pt pill lands inside the second card", "a
    /// diagonal leader cuts across the row". A number about spacing sits in
    /// the region its line is in, off every card edge and divider, on a
    /// straight leader or none; with no such spot it is left out. (A
    /// screen where that would leave fewer than three marks is laid the
    /// looser way, numbers on edges and all, as before.)
    @Test("A spacing number keeps to its line's own card or to the page between cards, off every edge, on a straight leader")
    func spacingStaysTidy() throws {
        let name = Self.settings
        let r = try Self.read(name)
        let regions = Self.regions(r), edges = Self.edges(r)
        let laid = RedlineLayout.lay(r.marks, obstacles: RedlinePlan.obstacles(in: r.nodes, canvas: CGRect(origin: .zero, size: r.canvas), pixelScale: 2),
                                     edges: edges, regions: regions, canvas: r.canvas,
                                     size: MeasureStyles().content(for: .size), spacing: MeasureStyles().content(for: .spacing))
        for drawn in laid where drawn.mark.role != .size {
            for c in drawn.calipers {
                let chip = c.labelRect(chipSize: c.estimatedLabelSize)
                for e in edges where chip.intersects(e) {
                    Issue.record("\(name): \(drawn.mark.what)'s number \(chip) sits on the edge \(e)")
                }
                let g = c.caliperGeometry()
                let mid = CGPoint(x: (g.headA.x + g.headB.x) / 2, y: (g.headA.y + g.headB.y) / 2)
                let home = regions.filter { $0.contains(mid) }.min { $0.width * $0.height < $1.width * $1.height }
                for region in regions where chip.intersects(region) {
                    let ok = home.map { region.contains($0) } ?? false
                    if !ok { Issue.record("\(name): \(drawn.mark.what)'s number \(chip) strays into \(region)") }
                }
                if let home { #expect(home.contains(chip), "\(name): \(drawn.mark.what)'s number leaves its card") }
                if let run = RedlineLayout.leader(of: c) {
                    #expect(abs(run.1.x - run.0.x) <= 1 || abs(run.1.y - run.0.y) <= 1,
                            "\(name): \(drawn.mark.what)'s leader slants from \(run.0) to \(run.1)")
                }
            }
        }
    }

    @Test("A button whose words sit in its middle gets no label inset: its width says it")
    func centredWordsNoInset() throws {
        let r = try Self.read(Self.settings)
        #expect(!r.marks.contains { $0.role == .inset }, "\(r.marks.map(\.what))")
    }

    @Test("A size's calipers sit on the box they measure, and never reach past the picture")
    func sizeCalipersHug() throws {
        let r = try Self.read(Self.settings)
        let canvas = CGRect(origin: .zero, size: r.canvas)
        let size = MeasureStyles().content(for: .size)
        let laid = RedlineLayout.lay(r.marks, obstacles: RedlinePlan.obstacles(in: r.nodes, canvas: CGRect(origin: .zero, size: r.canvas), pixelScale: 2), edges: Self.edges(r),
                                     regions: Self.regions(r), canvas: r.canvas, size: size, spacing: size)
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

    /// The judge on the calm redline, 2026-10-21: "the brackets don't clearly
    /// mark what they measure (26 px, 30 px, 17 px)" and "there are no end
    /// ticks to show what is being measured". A readout parked over the whole
    /// of a short span hid the very line it labels.
    @Test("Every dimension line shows both its ends: no readout covers its own line, and a straight line has a tick at each edge",
          arguments: screens)
    func everyLineShowsItsEnds(_ name: String) throws {
        let r = try Self.read(name)
        for c in Self.laid(r) where c.alignment == nil {
            #expect(!c.labelHidesItsLine(chipSize: c.estimatedLabelSize),
                    "\(name): the \(c.label(pixelScale: 2)) readout covers the line it measures")
            if abs(c.headOffset) < MeasureBuilder.endTickHalf {
                #expect(c.endTicks.count == 2, "\(name): \(c.label(pixelScale: 2)) has no ticks at its ends")
            }
        }
    }

    // MARK: Screens unlike the settings pane

    /// A dark inspector panel cropped from a window: the window's one pixel
    /// edge runs its whole height and a divider its whole width, so the two
    /// are one piece of ink that spans the picture. Until 2026-11-09 every
    /// word on the panel was joined to that piece as one "line", so the
    /// panel read as a single mark and its redline measured almost nothing.
    @Test("A window edge joined to a full width divider reads as dividers, and the words beside them still read as words")
    func frameLinesStayDividers() throws {
        let luma = try Self.picture("effects-panel-2x")
        let nodes = LayoutRead.read(luma, pixelScale: 2)
        let area = CGFloat(luma.width * luma.height)
        let huge = nodes.filter { $0.kind != .box && $0.rect.width * $0.rect.height > area / 4 }
        #expect(huge.isEmpty, "\(huge.map(\.rect))")
        // Corner Radius, Effects, Border 1, Style, Color, Position, Width, Offset, Border 2 and the readouts.
        #expect(nodes.filter { $0.kind == .text }.count >= 9, "\(nodes.filter { $0.kind == .text }.map(\.rect))")
        #expect(nodes.contains { $0.kind == .rule && $0.rect.width >= CGFloat(luma.width) * 0.9 })
        let marks = RedlinePlan.marks(in: nodes, canvas: CGRect(x: 0, y: 0, width: luma.width, height: luma.height), pixelScale: 2)
        #expect(marks.filter { $0.role != .size }.count >= 2, "\(marks.map(\.what))")
    }

    /// A call to action on a dark web page: a pill filled with a gradient,
    /// glowing on the page. It is a button, not a photo, so it gets a size.
    @Test("A button filled with a gradient is read as a button and measured, not as a photo")
    func gradientButtonIsAControl() throws {
        let luma = try Self.picture("download-pill-2x")
        let nodes = LayoutRead.read(luma, pixelScale: 2)
        let marks = RedlinePlan.marks(in: nodes, canvas: CGRect(x: 0, y: 0, width: luma.width, height: luma.height), pixelScale: 2)
        // The pill is about 548 by 125 pixels at (492, 270); its glow is not part of it.
        let size = try #require(marks.first { $0.role == .size && ($0.box?.width ?? 0) > 400 }, "\(marks.map(\.what))")
        let box = try #require(size.box)
        #expect(abs(box.minX - 492) <= 8 && abs(box.maxX - 1040) <= 8, "\(box)")
        #expect(abs(box.minY - 270) <= 8 && abs(box.maxY - 395) <= 8, "\(box)")
        // And how far it sits under the paragraph above it: 186 to 270 pixels.
        let above = try #require(marks.first { $0.role == .gap && $0.axis == .vertical }, "\(marks.map(\.what))")
        #expect(abs(above.start.y - 186) <= 4 && abs(above.end.y - 270) <= 4, "\(above.start) \(above.end)")
    }

    /// The same panel's redline: the colour well and the dropdown are what a
    /// developer builds, not the disclosure chevrons; the rows of labels give
    /// the row height; and two things across the panel from each other are
    /// not neighbours with a gap between them.
    @Test("A panel of labelled rows gets its controls sized, its row height, and no gap across the whole panel")
    func panelOfRows() throws {
        let luma = try Self.picture("effects-panel-2x")
        let nodes = LayoutRead.read(luma, pixelScale: 2)
        let marks = RedlinePlan.marks(in: nodes, canvas: CGRect(x: 0, y: 0, width: luma.width, height: luma.height), pixelScale: 2)
        let sizes = marks.filter { $0.role == .size }
        // Nothing under 10 points across is sized: a chevron is not a control.
        for s in sizes { #expect(max(s.box?.width ?? 0, s.box?.height ?? 0) >= 20, "\(s.what) \(s.reading(pixelScale: 2))") }
        // The colour well (221, 301) and the dropdown (221, 351) both get sizes.
        #expect(sizes.contains { $0.box?.minY == 301 }, "\(sizes.map { $0.box ?? .zero })")
        #expect(sizes.contains { $0.box?.minY == 351 }, "\(sizes.map { $0.box ?? .zero })")
        #expect(marks.contains { $0.role == .rhythm }, "\(marks.map(\.what))")
        for m in marks where m.role == .gap { #expect(m.value(pixelScale: 2) <= 64, "\(m.what) \(m.reading(pixelScale: 2))") }
    }

    /// "Measure the padding inside the meeting card": a model passes the
    /// card's own box as the region. Read as a crop, the card's edge was the
    /// crop's edge and there was no padding to find; read as a focus on the
    /// whole picture, the card is a card.
    @Test("A region round one card measures that card: its padding and the gaps between what is stacked in it")
    func focusOnOneCard() throws {
        let luma = try Self.picture("people-panel-2x")
        let nodes = LayoutRead.read(luma, pixelScale: 2)
        let card = CGRect(x: 562, y: 26, width: 331, height: 355)   // as a model gave it, a little inside the border
        let marks = RedlinePlan.marks(in: nodes, canvas: CGRect(x: 0, y: 0, width: luma.width, height: luma.height),
                                      pixelScale: 2, focus: card)
        let grown = card.insetBy(dx: -48, dy: -48)
        for m in marks {
            let r = m.box ?? CGRect(x: min(m.start.x, m.end.x), y: min(m.start.y, m.end.y),
                                    width: abs(m.end.x - m.start.x), height: abs(m.end.y - m.start.y))
            #expect(grown.contains(r), "\(m.what) \(r) is outside the card")
        }
        #expect(marks.contains { $0.role == .padding && $0.start.x == 560 }, "\(marks.map(\.what))")
        // The title (ends at 267) over the time (starts at 285).
        #expect(marks.contains { $0.axis == .vertical && abs($0.start.y - 267) <= 2 && abs($0.end.y - 285) <= 2 },
                "\(marks.map { "\($0.what) \($0.start) \($0.end)" })")
    }
}
