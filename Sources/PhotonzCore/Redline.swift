import CoreGraphics
import Foundation

/// One measurement in a redline of a UI screenshot, the kind a designer hands
/// a developer: the size of one kind of control, or one piece of the spacing
/// that defines the layout. Read off the picture by `RedlinePlan`, in the
/// picture's own pixels, top-left origin.
public struct RedlineMark: Hashable, Sendable {
    public enum Role: String, Codable, Sendable, CaseIterable {
        /// Width and height of one kind of control, measured on the first of them.
        case size
        /// From the picture's edge to the first card or panel.
        case margin
        /// From a card's edge to what sits inside it.
        case padding
        /// Row height: divider to divider, or one repeated row to the next.
        case rhythm
        /// Between two cards stacked one above the other.
        case sectionGap
        /// Between two neighbouring controls in a row.
        case gap
        /// From a control's edge to its own label: a button's padding.
        case inset
    }

    public var role: Role
    /// What a designer would call it: "Switch", "Padding", "Row height".
    public var what: String
    /// A size's box. Nil for spacing.
    public var box: CGRect?
    /// A spacing caliper's feet (for a size, the box's top-left and
    /// bottom-right corners). The line between them is clear of the picture's
    /// words and controls.
    public var start: CGPoint
    public var end: CGPoint
    public var axis: MeasureMode
    /// How many things like it the picture has: four switches, three rows.
    public var repeats: Int

    public init(role: Role, what: String, box: CGRect? = nil, start: CGPoint, end: CGPoint,
                axis: MeasureMode, repeats: Int = 1) {
        self.role = role
        self.what = what
        self.box = box
        self.start = start
        self.end = end
        self.axis = axis
        self.repeats = repeats
    }

    public static func size(_ what: String, _ box: CGRect, repeats: Int) -> RedlineMark {
        RedlineMark(role: .size, what: what, box: box, start: box.origin,
                    end: CGPoint(x: box.maxX, y: box.maxY), axis: .horizontal, repeats: repeats)
    }

    /// The span in points (pixels over `pixelScale`).
    public func value(pixelScale: CGFloat) -> CGFloat {
        let raw = axis == .horizontal ? abs(end.x - start.x) : abs(end.y - start.y)
        return raw / max(pixelScale, 1)
    }

    /// "42 × 24" for a size, "16" for spacing, in points.
    public func reading(pixelScale: CGFloat) -> String {
        if let box {
            return "\(Misalignment.number(box.width / max(pixelScale, 1))) × \(Misalignment.number(box.height / max(pixelScale, 1)))"
        }
        return Misalignment.number(value(pixelScale: pixelScale))
    }
}

/// What to measure on a UI screenshot when someone asks for "measurements
/// around the major ui elements", chosen in code off the picture's layout
/// (`LayoutRead`) rather than by a model guessing at boxes: one size of each
/// kind of control (the four switches are measured once, on the first), then
/// the spacing that defines the layout in a redline's order: the margin, a
/// card's padding, the row height, the gap between sections, the gap between
/// neighbouring buttons, a button's label inset. Never a whole row or a whole
/// card. A repeat that differs from its kind is left to "find the
/// misalignments", not measured again.
public enum RedlinePlan {
    /// At most this many sizes, so a busy screen still reads as a redline.
    public static let mostSizes = 4
    /// At most this many marks in all.
    public static let mostMarks = 10

    public static func marks(luma: LumaField, pixelScale: CGFloat, region: CGRect? = nil) -> [RedlineMark] {
        let nodes = LayoutRead.read(luma, pixelScale: pixelScale, region: region)
        let canvas = region ?? CGRect(x: 0, y: 0, width: luma.width, height: luma.height)
        return marks(in: nodes, canvas: canvas, pixelScale: pixelScale)
    }

    public static func marks(in nodes: [LayoutNode], canvas: CGRect, pixelScale: CGFloat) -> [RedlineMark] {
        Scan(nodes: nodes, canvas: canvas, scale: max(pixelScale, 1)).run()
    }

    /// What a readout must never sit on and a leader never cross: every line
    /// of words, every mark and every control. Cards, panels and dividers are not in it: the empty
    /// middle of a card is where a readout belongs.
    public static func obstacles(in nodes: [LayoutNode], canvas: CGRect, pixelScale: CGFloat) -> [CGRect] {
        let scan = Scan(nodes: nodes, canvas: canvas, scale: max(pixelScale, 1))
        return nodes.indices.compactMap { i in
            switch nodes[i].kind {
            // Words inside a control count on their own too: a leader that
            // starts inside a button (its label inset) still never crosses
            // the button's words.
            case .text, .mark: return nodes[i].rect
            case .box, .picture: return scan.isControl(i) ? nodes[i].rect : nil
            case .rule: return nil
            }
        }
    }

    public static func id(_ index: Int) -> String { "r\(index + 1)" }

    /// The marks as the find_measurements tool hands them to a model: an id,
    /// what it is, its reading in points, and its box or feet in canvas points.
    public static func report(_ marks: [RedlineMark], pixelScale: CGFloat) -> AgentJSON {
        func n(_ v: CGFloat) -> AgentJSON { .number(Double((v * 10).rounded() / 10)) }
        let list: [AgentJSON] = marks.enumerated().map { i, m in
            var o: [String: AgentJSON] = [
                "id": .string(id(i)), "role": .string(m.role.rawValue), "what": .string(m.what),
                "reads": .string(m.reading(pixelScale: pixelScale)),
            ]
            if let box = m.box {
                o["box"] = .object(["x": n(box.minX), "y": n(box.minY), "width": n(box.width), "height": n(box.height)])
            } else {
                o["from"] = .object(["x": n(m.start.x), "y": n(m.start.y)])
                o["to"] = .object(["x": n(m.end.x), "y": n(m.end.y)])
            }
            if m.repeats > 1 { o["repeats"] = .number(Double(m.repeats)) }
            return .object(o)
        }
        return .object([
            "marks": .array(list),
            "count": .number(Double(list.count)),
            "unit": .string(pixelScale > 1 ? "points (the picture is \(Misalignment.number(pixelScale))x)" : "points"),
        ])
    }

    struct Scan {
        let nodes: [LayoutNode]
        let canvas: CGRect
        let scale: CGFloat
        let children: [Int?: [Int]]

        init(nodes: [LayoutNode], canvas: CGRect, scale: CGFloat) {
            self.nodes = nodes
            self.canvas = canvas
            self.scale = scale
            children = Dictionary(grouping: nodes.indices, by: { nodes[$0].parent })
        }

        func kids(_ i: Int?) -> [Int] { children[i] ?? [] }
        func pt(_ v: CGFloat) -> CGFloat { v / scale }

        /// A thing a person uses: a box no taller than a tall button, with at
        /// most a label or a knob inside it, never a divider.
        func isControl(_ i: Int) -> Bool {
            let n = nodes[i]
            guard n.kind == .box, !insideControl(i) else { return false }
            let w = pt(n.rect.width), h = pt(n.rect.height)
            guard h >= 8, w >= 8, h <= 72 else { return false }
            if !canvas.isNull, n.rect.width > canvas.width * 0.9 { return false }
            return holdsAtMostALabel(i)
        }

        /// A control holds a label, a knob, an icon beside its words: two
        /// things at most and one line of words at most. A row with a name
        /// over a detail line beside an avatar is a card, however short.
        func holdsAtMostALabel(_ i: Int) -> Bool {
            let inside = kids(i)
            guard inside.count <= 2, inside.filter({ nodes[$0].kind == .text }).count <= 1 else { return false }
            return inside.allSatisfy { k in
                nodes[k].kind != .rule && (nodes[k].kind != .box || kids(k).isEmpty)
            }
        }

        func insideControl(_ i: Int) -> Bool {
            var p = nodes[i].parent
            while let q = p {
                if isControlShape(q) { return true }
                p = nodes[q].parent
            }
            return false
        }

        /// `isControl` without the check on its own parents, so asking about
        /// a knob does not recurse forever.
        private func isControlShape(_ i: Int) -> Bool {
            let n = nodes[i]
            guard n.kind == .box else { return false }
            let w = pt(n.rect.width), h = pt(n.rect.height)
            guard h >= 8, w >= 8, h <= 72 else { return false }
            if !canvas.isNull, n.rect.width > canvas.width * 0.9 { return false }
            return holdsAtMostALabel(i)
        }

        func isContainer(_ i: Int) -> Bool {
            nodes[i].kind == .box && !isControl(i) && !insideControl(i) && kids(i).count >= 2
        }

        /// A mark small enough to be an icon and big enough to measure.
        func isIcon(_ r: CGRect) -> Bool {
            let lo = pt(min(r.width, r.height)), hi = pt(max(r.width, r.height))
            return lo >= 4 && hi <= 64 && hi / max(lo, 0.1) <= 2
        }

        /// What a control's shape says it is.
        func name(_ i: Int) -> String {
            if nodes[i].kind == .mark { return "Icon" }
            let r = nodes[i].rect
            let inside = kids(i)
            let aspect = r.width / max(r.height, 1)
            if inside.contains(where: { nodes[$0].kind == .text }) { return "Button" }
            if let knob = inside.first(where: { nodes[$0].kind == .box }),
               (1.3...2.6).contains(aspect),
               nodes[knob].rect.height >= r.height * 0.6 { return "Switch" }
            if inside.isEmpty, aspect >= 3 { return "Field" }
            if abs(aspect - 1) < 0.15 { return "Icon" }
            return "Control"
        }

        /// Top to bottom, rows read left to right.
        func readingOrder(_ a: Int, _ b: Int) -> Bool {
            let ra = nodes[a].rect, rb = nodes[b].rect
            if abs(ra.midY - rb.midY) > min(ra.height, rb.height) / 2 { return ra.midY < rb.midY }
            return ra.minX < rb.minX
        }

        func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
            min(a.maxY, b.maxY) - max(a.minY, b.minY) > min(a.height, b.height) / 2
        }

        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= 1.5 * scale }

        struct Kind {
            var name: String
            var members: [Int]
        }

        func kinds(_ controls: [Int]) -> [Kind] {
            var kinds: [Kind] = []
            for c in controls {
                let r = nodes[c].rect, nm = name(c)
                if let k = kinds.firstIndex(where: { kind in
                    guard kind.name == nm else { return false }
                    let first = nodes[kind.members[0]].rect
                    if near(first.width, r.width) && near(first.height, r.height) { return true }
                    // Buttons side by side in one row are one kind of button
                    // whatever their words make their widths.
                    // So are buttons of one height and one fill anywhere:
                    // the same badge in three cards.
                    return nm == "Button" && near(first.height, r.height)
                        && kind.members.contains { m in
                            (nodes[m].parent == nodes[c].parent && sameRow(nodes[m].rect, r))
                                || (nodes[m].fill != nil && nodes[m].fill == nodes[c].fill)
                        }
                }) {
                    kinds[k].members.append(c)
                } else {
                    kinds.append(Kind(name: nm, members: [c]))
                }
            }
            return kinds
        }

        /// Where along `range` a line across `band` (on the other axis) meets
        /// nothing: the middle of the widest clear stretch.
        func clearLine(across band: ClosedRange<CGFloat>, along range: ClosedRange<CGFloat>,
                       vertical: Bool, obstacles: [CGRect]) -> CGFloat {
            var blocked: [ClosedRange<CGFloat>] = []
            for o in obstacles {
                let lo = vertical ? o.minY : o.minX, hi = vertical ? o.maxY : o.maxX
                guard hi > band.lowerBound, lo < band.upperBound else { continue }
                let a = vertical ? o.minX : o.minY, b = vertical ? o.maxX : o.maxY
                blocked.append(a...b)
            }
            blocked.sort { $0.lowerBound < $1.lowerBound }
            var best: (CGFloat, CGFloat) = (range.lowerBound, range.lowerBound)
            var cursor = range.lowerBound
            for b in blocked {
                if b.lowerBound > cursor, b.lowerBound - cursor > best.1 - best.0 {
                    best = (cursor, min(b.lowerBound, range.upperBound))
                }
                cursor = max(cursor, b.upperBound)
                if cursor >= range.upperBound { break }
            }
            if range.upperBound - cursor > best.1 - best.0 { best = (cursor, range.upperBound) }
            return ((best.0 + best.1) / 2).rounded()
        }

        func run() -> [RedlineMark] {
            // What gets a size: the controls, and icons that stand on their
            // own (an unread dot, a glyph beside a row), never one inside a
            // control.
            let controls = nodes.indices.filter { i in
                isControl(i) || (nodes[i].kind == .mark && !insideControl(i) && isIcon(nodes[i].rect))
            }.sorted(by: readingOrder)
            let obstacles = RedlinePlan.obstacles(in: nodes, canvas: canvas, pixelScale: scale)
            var sizes: [RedlineMark] = []
            let kinds = kinds(controls)
            for kind in kinds.prefix(mostSizes) {
                let first = kind.members[0]
                sizes.append(.size(kind.name, nodes[first].rect, repeats: kind.members.count))
            }

            var spacing: [RedlineMark] = []
            let containers = nodes.indices.filter(isContainer).sorted(by: readingOrder)
            let minimum = 2 * scale

            // The margin: the picture's edge to the first card on it, or,
            // with no card, to the leftmost thing on the page.
            let pageLeft = nodes.indices.filter { nodes[$0].parent == nil && nodes[$0].kind != .rule }
                .min { nodes[$0].rect.minX < nodes[$1].rect.minX }
            if let card = containers.first(where: { nodes[$0].parent == nil }) ?? pageLeft {
                let r = nodes[card].rect
                if r.minX - canvas.minX >= minimum, r.minX - canvas.minX <= canvas.width * 0.25 {
                    let y = clearLine(across: canvas.minX...r.minX, along: r.minY...r.maxY,
                                      vertical: false, obstacles: obstacles)
                    spacing.append(RedlineMark(role: .margin, what: "Margin", start: CGPoint(x: canvas.minX, y: y),
                                               end: CGPoint(x: r.minX, y: y), axis: .horizontal))
                }
            }

            // A card's padding: its edge to the nearest thing inside it, left
            // and, when it differs, right.
            if let card = containers.first {
                let r = nodes[card].rect
                let inside = kids(card).filter { nodes[$0].kind != .rule }
                if let left = inside.min(by: { nodes[$0].rect.minX < nodes[$1].rect.minX }) {
                    let l = nodes[left].rect
                    let padL = l.minX - r.minX
                    if padL >= minimum {
                        let y = l.midY.rounded()
                        spacing.append(RedlineMark(role: .padding, what: "Padding", start: CGPoint(x: r.minX, y: y),
                                                   end: CGPoint(x: l.minX, y: y), axis: .horizontal))
                    }
                    if let right = inside.max(by: { nodes[$0].rect.maxX < nodes[$1].rect.maxX }) {
                        let rr = nodes[right].rect
                        let padR = r.maxX - rr.maxX
                        // Only when something sits against the right edge: a row's
                        // empty right half is not padding.
                        if padR >= minimum, abs(padR - padL) > 2 * scale, padR <= max(2 * padL, 32 * scale) {
                            let y = rr.midY.rounded()
                            spacing.append(RedlineMark(role: .padding, what: "Right padding",
                                                       start: CGPoint(x: rr.maxX, y: y),
                                                       end: CGPoint(x: r.maxX, y: y), axis: .horizontal))
                        }
                    }
                }
            }

            // The row height: divider to divider in the first card that has
            // two; failing that, one repeated control to the next below it.
            if let rhythm = rowHeight(containers, controls: controls, obstacles: obstacles) {
                spacing.append(rhythm)
            }

            // The gap between two cards stacked one above the other.
            outer: for (ai, a) in containers.enumerated() {
                for b in containers[(ai + 1)...] where nodes[b].parent == nodes[a].parent {
                    let ra = nodes[a].rect, rb = nodes[b].rect
                    let overlap = min(ra.maxX, rb.maxX) - max(ra.minX, rb.minX)
                    guard rb.minY - ra.maxY >= minimum, overlap > min(ra.width, rb.width) * 0.5 else { continue }
                    let x = clearLine(across: ra.maxY...rb.minY, along: max(ra.minX, rb.minX)...min(ra.maxX, rb.maxX),
                                      vertical: true, obstacles: obstacles)
                    spacing.append(RedlineMark(role: .sectionGap, what: "Section gap", start: CGPoint(x: x, y: ra.maxY),
                                               end: CGPoint(x: x, y: rb.minY), axis: .vertical))
                    break outer
                }
            }

            // The gap between neighbouring controls in a row, buttons first.
            let pairs = controls.enumerated().flatMap { i, a in
                controls[(i + 1)...].compactMap { b -> (Int, Int)? in
                    let ra = nodes[a].rect, rb = nodes[b].rect
                    guard nodes[a].parent == nodes[b].parent, sameRow(ra, rb) else { return nil }
                    let (l, r) = ra.minX < rb.minX ? (a, b) : (b, a)
                    guard nodes[r].rect.minX - nodes[l].rect.maxX >= minimum else { return nil }
                    // Only next-door neighbours: nothing between them.
                    let between = controls.contains { c in
                        c != l && c != r && sameRow(nodes[c].rect, ra)
                            && nodes[c].rect.minX >= nodes[l].rect.maxX && nodes[c].rect.maxX <= nodes[r].rect.minX
                    }
                    return between ? nil : (l, r)
                }
            }
            // Failing two controls, a control and the words beside it: an
            // avatar and its name, a switch and its label close by.
            let beside = controls.compactMap { c -> (Int, Int)? in
                let rc = nodes[c].rect
                let words = kids(nodes[c].parent).filter { t in
                    nodes[t].kind == .text && sameRow(nodes[t].rect, rc) && nodes[t].rect.minX >= rc.maxX + minimum
                        && nodes[t].rect.minX - rc.maxX <= 3 * rc.height
                }
                return words.min(by: { nodes[$0].rect.minX < nodes[$1].rect.minX }).map { (c, $0) }
            }
            if let (l, r) = pairs.first(where: { name($0.0) == "Button" && name($0.1) == "Button" }) ?? pairs.first
                ?? beside.first {
                let a = nodes[l].rect, b = nodes[r].rect
                let y = ((max(a.minY, b.minY) + min(a.maxY, b.maxY)) / 2).rounded()
                spacing.append(RedlineMark(role: .gap, what: "Gap", start: CGPoint(x: a.maxX, y: y),
                                           end: CGPoint(x: b.minX, y: y), axis: .horizontal))
            }

            // A button's padding: its edge to its own words.
            // On a second button of the kind when there is one: the first
            // already carries its size's brackets.
            let buttons = kinds.prefix(mostSizes).first { $0.name == "Button" }?.members ?? []
            if let button = buttons.dropFirst().first ?? buttons.first,
               let words = kids(button).first(where: { nodes[$0].kind == .text }) {
                let b = nodes[button].rect, w = nodes[words].rect
                // Centred words in a wide button have no inset to specify.
                if w.minX - b.minX >= minimum, w.minX - b.minX <= 1.5 * b.height {
                    // Drawn in the padding under the words, so its readout
                    // can leave the button without crossing them.
                    let y = ((w.maxY + b.maxY) / 2).rounded()
                    spacing.append(RedlineMark(role: .inset, what: "Label inset", start: CGPoint(x: b.minX, y: y),
                                               end: CGPoint(x: w.minX, y: y), axis: .horizontal))
                }
            }

            return Array((sizes + spacing).prefix(mostMarks))
        }

        func rowHeight(_ containers: [Int], controls: [Int], obstacles: [CGRect]) -> RedlineMark? {
            // Dividers in a card, or straight on the page (a plain list).
            for card in containers.map(Optional.some) + [nil] {
                let rules = kids(card).filter { nodes[$0].kind == .rule && nodes[$0].rect.width > nodes[$0].rect.height }
                    .sorted { nodes[$0].rect.minY < nodes[$1].rect.minY }
                guard rules.count >= 2 else { continue }
                let a = nodes[rules[0]].rect, b = nodes[rules[1]].rect
                guard b.minY - a.minY >= 8 * scale else { continue }
                let x = clearLine(across: a.midY...b.midY, along: max(a.minX, b.minX)...min(a.maxX, b.maxX),
                                  vertical: true, obstacles: obstacles)
                return RedlineMark(role: .rhythm, what: "Row height", start: CGPoint(x: x, y: a.minY),
                                   end: CGPoint(x: x, y: b.minY), axis: .vertical, repeats: rules.count + 1)
            }
            // No dividers: two like controls one above the other, top to top.
            for (i, a) in controls.enumerated() {
                for b in controls[(i + 1)...] {
                    let ra = nodes[a].rect, rb = nodes[b].rect
                    guard nodes[a].parent == nodes[b].parent, name(a) == name(b), near(ra.minX, rb.minX),
                      near(ra.width, rb.width), near(ra.height, rb.height), rb.minY > ra.maxY else { continue }
                    let x = (ra.maxX + 8 * scale).rounded()
                    return RedlineMark(role: .rhythm, what: "Row height", start: CGPoint(x: x, y: ra.minY),
                                       end: CGPoint(x: x, y: rb.minY), axis: .vertical)
                }
            }
            return nil
        }
    }
}

/// A redline drawn: each mark's calipers, placed so no readout sits on
/// another readout, on another measurement's line, or on any word or control
/// in the picture, and no two leader lines cross.
public struct RedlineDrawn: Sendable {
    public var mark: RedlineMark
    /// In document space, with the readout's placement applied. A size has
    /// its width and its height; spacing has one.
    public var calipers: [MeasureContent]
}

public enum RedlineLayout {

    /// Lays out `marks` in order. `size` and `spacing` are the Measure tool's
    /// styles for the two roles; `obstacles` is what readouts stay off
    /// (`RedlinePlan.obstacles`); `placed` is readouts already on the canvas.
    public static func lay(_ marks: [RedlineMark], obstacles: [CGRect], canvas: CGSize,
                           size: MeasureContent, spacing: MeasureContent,
                           placed: [CGRect] = []) -> [RedlineDrawn] {
        var kept = marks
        // A mark with no clean spot for a readout is left out rather than
        // stacked; the rest are laid again without its lines in the way.
        for _ in 0..<4 {
            let (drawn, failed) = attempt(kept, obstacles: obstacles, canvas: canvas, size: size,
                                          spacing: spacing, placed: placed)
            if failed.isEmpty { return drawn }
            kept = kept.enumerated().filter { !failed.contains($0.offset) }.map(\.element)
        }
        return attempt(kept, obstacles: obstacles, canvas: canvas, size: size, spacing: spacing,
                       placed: placed).drawn
    }

    static func attempt(_ marks: [RedlineMark], obstacles: [CGRect], canvas: CGSize,
                        size: MeasureContent, spacing: MeasureContent,
                        placed: [CGRect]) -> (drawn: [RedlineDrawn], failed: Set<Int>) {
        var state = State(obstacles: obstacles, canvas: canvas, readouts: placed)
        // Every line first, so a readout placed early never lands where a
        // later measurement draws its line.
        var drawn: [RedlineDrawn] = marks.map { mark in
            guard let box = mark.box else {
                var c = spacing
                c.mode = mark.axis
                c.start = mark.start
                c.end = mark.end
                c.headOffset = 0
                return RedlineDrawn(mark: mark, calipers: [c])
            }
            return RedlineDrawn(mark: mark, calipers: [true, false].map { horizontal in
                var c = size
                c.mode = horizontal ? .horizontal : .vertical
                let feet = state.side(of: box, horizontal: horizontal, template: c)
                c.start = feet.start
                c.end = feet.end
                c.headOffset = feet.head
                return c
            })
        }
        state.lines = drawn.flatMap { $0.calipers.map(\.subjectRects) }
        var failed = Set<Int>()
        for i in drawn.indices {
            let subjects = drawn[i].mark.box.map { [$0] } ?? []
            let saved = state
            for j in drawn[i].calipers.indices {
                guard let c = state.place(drawn[i].calipers[j], describing: subjects) else {
                    failed.insert(i)
                    state = saved
                    break
                }
                drawn[i].calipers[j] = c
            }
        }
        return (drawn.enumerated().filter { !failed.contains($0.offset) }.map(\.element), failed)
    }

    /// The leader the canvas draws from a caliper to a readout that has
    /// stepped off its line (`MeasurePlan.make`: from the nearest point of the
    /// caliper's own strokes to where that run meets the pill), or nil when
    /// none is drawn.
    public static func leader(of c: MeasureContent) -> (CGPoint, CGPoint)? {
        let plan = MeasurePlan.make(c, geometry: c.caliperGeometry(), chipSize: c.estimatedLabelSize)
        return plan.leader.map { ($0.from, $0.to) }
    }

    /// The boxes a leader from `start` may run across: only one it starts
    /// strictly inside (a button whose label inset it measures). A box the
    /// leader merely starts on the edge of is still in its way.
    public static func inWay(of start: CGPoint, among rects: [CGRect]) -> [CGRect] {
        rects.filter { !$0.insetBy(dx: 1, dy: 1).contains(start) }
    }

    /// Whether two straight runs cross (touching at an end does not count).
    public static func cross(_ a: (CGPoint, CGPoint), _ b: (CGPoint, CGPoint)) -> Bool {
        func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        let d1 = side(b.0, b.1, a.0), d2 = side(b.0, b.1, a.1)
        let d3 = side(a.0, a.1, b.0), d4 = side(a.0, a.1, b.1)
        return d1 * d2 < 0 && d3 * d4 < 0
    }

    struct State {
        let obstacles: [CGRect]
        let canvas: CGSize
        var readouts: [CGRect]
        /// Every caliper's line, one entry per caliper.
        var lines: [[CGRect]] = []
        var leaders: [(CGPoint, CGPoint)] = []

        init(obstacles: [CGRect], canvas: CGSize, readouts: [CGRect]) {
            self.obstacles = obstacles
            self.canvas = canvas
            self.readouts = readouts
        }

        var bounds: CGRect { CGRect(origin: .zero, size: canvas) }

        /// Which side of `box` a size caliper goes on: the side with the more
        /// open room before the next word or control, below or right on a tie.
        /// The head stands off by exactly the air a readout keeps from what
        /// it measures, so the dimension line hugs the box.
        func side(of box: CGRect, horizontal: Bool,
                  template: MeasureContent) -> (start: CGPoint, end: CGPoint, head: CGFloat) {
            func room(_ positive: Bool) -> CGFloat {
                var limit: CGFloat
                if horizontal {
                    limit = positive ? canvas.height - box.maxY : box.minY
                } else {
                    limit = positive ? canvas.width - box.maxX : box.minX
                }
                for o in obstacles + readouts where o != box {
                    if horizontal {
                        guard o.maxX > box.minX, o.minX < box.maxX else { continue }
                        if positive, o.minY >= box.maxY { limit = min(limit, o.minY - box.maxY) }
                        if !positive, o.maxY <= box.minY { limit = min(limit, box.minY - o.maxY) }
                    } else {
                        guard o.maxY > box.minY, o.minY < box.maxY else { continue }
                        if positive, o.minX >= box.maxX { limit = min(limit, o.minX - box.maxX) }
                        if !positive, o.maxX <= box.minX { limit = min(limit, box.minX - o.maxX) }
                    }
                }
                return limit
            }
            var probe = template
            probe.start = box.origin
            probe.end = CGPoint(x: box.maxX, y: box.maxY)
            let clearing = MeasureBuilder.clearingHeadOffset(content: probe, from: probe.start, to: probe.end)
            // The side that holds the head and a readout beside it, below or
            // right when both do; failing that, the roomier one.
            let chip = probe.estimatedLabelSize
            let needed = clearing + (horizontal ? chip.height : chip.width) / 2 + MeasureBuilder.canvasEdgeGap
            let below = room(true), above = room(false)
            let positive = below >= needed || (above < needed && below >= above)
            // Where neither side holds it, the head stops short of whatever
            // is next (the picture's edge included) rather than run past it.
            let room = positive ? below : above
            let reach = min(clearing, max(room - MeasureBuilder.canvasEdgeGap, MeasureBuilder.minimumClearingReach))
            if horizontal {
                let y = positive ? box.maxY : box.minY
                return (CGPoint(x: box.minX, y: y), CGPoint(x: box.maxX, y: y), positive ? reach : -reach)
            }
            let x = positive ? box.maxX : box.minX
            return (CGPoint(x: x, y: box.minY), CGPoint(x: x, y: box.maxY), positive ? reach : -reach)
        }

        /// Places one caliper's readout: on its line when that is clear, else
        /// the nearest spot, along the line or stepped off it on a leader,
        /// that touches no word, control, readout or measuring line, and whose
        /// leader crosses no other. When nowhere is clear it falls back to
        /// the Measure tool's own placer, which tolerates the least overlap.
        mutating func place(_ content: MeasureContent, describing subjects: [CGRect]) -> MeasureContent? {
            var c = content
            let chip = c.estimatedLabelSize
            let step = c.chipAxisHalfExtent(chipSize: chip) + MeasureContent.chipLineGap
            let crossStep = (c.mode == .horizontal ? chip.height : chip.width) / 2
            let ownLines = c.subjectRects
            let otherLines = lines.filter { $0 != ownLines }.flatMap { $0 }
            let blocked = obstacles.filter { o in !subjects.contains(o) } + readouts + otherLines
            let mine = subjects.map { $0.insetBy(dx: -1, dy: -1) }
            let outward: MeasureLabelPlacement = c.headOffset < 0 ? .clearNegative : .clearPositive
            let inward: MeasureLabelPlacement = outward == .clearPositive ? .clearNegative : .clearPositive

            func candidates(leash: CGFloat, along: Int, leadersMayCross: Bool) -> [LabelCandidate<MeasureLabelPlanner.Plan>] {
                var found: [LabelCandidate<MeasureLabelPlanner.Plan>] = []
                func consider(_ placement: MeasureLabelPlacement, nudge: CGFloat, reach: CGFloat, cost: CGFloat) {
                    var probe = c
                    probe.labelPlacement = placement
                    probe.labelNudge = nudge
                    probe.labelCrossReach = reach
                    // Past the end, a chip hanging off the picture slides
                    // back across the line by the overhang, as the Measure
                    // tool's own placer lets it.
                    if placement == .afterEnd || placement == .beforeStart,
                       let slide = probe.edgeSlide(for: probe.labelRect(chipSize: chip), within: bounds) {
                        probe.labelCrossReach = slide
                    }
                    let rect = probe.labelRect(chipSize: chip)
                    guard bounds.contains(rect) else { return }
                    var extra = cost
                    // A leader runs over nothing: no word, control, readout
                    // or other line (save what it starts inside), and never
                    // across another leader.
                    if let run = RedlineLayout.leader(of: probe) {
                        if leaders.contains(where: { RedlineLayout.cross($0, run) }) { return }
                        let over = RedlineLayout.inWay(of: run.0, among: blocked + subjects)
                        if LabelPlacer.segment(from: run.0, to: run.1, crosses: over) {
                            guard leadersMayCross else { return }
                            extra += LabelPlacer.crossingCost
                        }
                        extra += hypot(run.1.x - run.0.x, run.1.y - run.0.y) * LabelPlacer.travelCost
                    }
                    found.append(LabelCandidate(rect: rect, payload: (placement, nudge, probe.labelCrossReach), cost: extra))
                }
                let nudges: [CGFloat] = [0] + (1...along).flatMap { [CGFloat($0), -CGFloat($0)] }
                for m in nudges {
                    consider(.onLine, nudge: step * m, reach: 0, cost: abs(m) * LabelPlacer.nudgeCost)
                }
                for (rank, placement) in [outward, inward].enumerated() {
                    var reach: CGFloat = 0
                    while reach <= leash {
                        for m in nudges {
                            consider(placement, nudge: step * m, reach: reach,
                                     cost: CGFloat(rank + 1) * LabelPlacer.rankCost + abs(m) * LabelPlacer.nudgeCost
                                        + reach / max(crossStep, 1) * LabelPlacer.nudgeCost)
                        }
                        reach += crossStep
                    }
                }
                for (rank, placement) in [MeasureLabelPlacement.afterEnd, .beforeStart].enumerated() {
                    for m in [0, 1, -1] as [CGFloat] {
                        consider(placement, nudge: step * m, reach: 0,
                                 cost: CGFloat(rank + 3) * LabelPlacer.rankCost + abs(m) * LabelPlacer.nudgeCost)
                    }
                }
                return found
            }

            // Near first, at the Measure tool's own leash; then twice as far.
            // Never a readout on top of anything or a leader across it: with
            // no clean spot the mark is left out.
            let leash = MeasureLabelPlanner.maxCrossReach(for: c, chip: chip)
            let strict = [LabelAvoidance(rects: blocked + mine, weight: .forbidden)]
            let tiers = [(leash, 4, false), (leash * 2, 8, false)]
            var chosen: MeasureLabelPlanner.Plan?
            for tier in tiers where chosen == nil {
                chosen = LabelPlacer.best(among: candidates(leash: tier.0, along: tier.1, leadersMayCross: tier.2),
                                          avoiding: strict, within: bounds, anchoredAt: c.labelAnchor)
            }
            guard let plan = chosen else { return nil }
            c.apply(plan)
            readouts.append(c.labelRect(chipSize: chip))
            if let run = RedlineLayout.leader(of: c) { leaders.append(run) }
            return c
        }
    }
}
