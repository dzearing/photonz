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
/// the spacing that defines the layout in a redline's order: a card's padding, the row height, the gap between sections, the gap between
/// neighbouring buttons, a button's label inset. Never a whole row or a whole
/// card. A repeat that differs from its kind is left to "find the
/// misalignments", not measured again.
public enum RedlinePlan {
    /// At most this many sizes, so a busy screen still reads as a redline.
    public static let mostSizes = 4
    /// At most this many marks in all.
    public static let mostMarks = 10

    public static func marks(luma: LumaField, pixelScale: CGFloat, region: CGRect? = nil) -> [RedlineMark] {
        let nodes = LayoutRead.read(luma, pixelScale: pixelScale)
        let canvas = CGRect(x: 0, y: 0, width: luma.width, height: luma.height)
        return marks(in: nodes, canvas: canvas, pixelScale: pixelScale, focus: region)
    }

    /// `focus` is the part of the picture a person named (one card, the
    /// sidebar): the picture is still read whole, so the card is a card, and
    /// only the marks in and round that part are kept, that part's own
    /// padding and stacking first.
    public static func marks(in nodes: [LayoutNode], canvas: CGRect, pixelScale: CGFloat,
                             focus: CGRect? = nil) -> [RedlineMark] {
        var scan = Scan(nodes: nodes, canvas: canvas, scale: max(pixelScale, 1))
        scan.focus = focus
        return scan.run()
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

    /// What a readout should keep off when it has the choice but may sit
    /// on when it has none: the border of every card and every divider, so a
    /// readout sits inside a card or outside it rather than across its edge.
    public static func edges(in nodes: [LayoutNode], canvas: CGRect, pixelScale: CGFloat) -> [CGRect] {
        let scan = Scan(nodes: nodes, canvas: canvas, scale: max(pixelScale, 1))
        let t = max(pixelScale, 1)
        return nodes.indices.flatMap { i -> [CGRect] in
            let r = nodes[i].rect
            if nodes[i].kind == .rule { return [r] }
            guard scan.isContainer(i) else { return [] }
            return [CGRect(x: r.minX, y: r.minY, width: r.width, height: t),
                    CGRect(x: r.minX, y: r.maxY - t, width: r.width, height: t),
                    CGRect(x: r.minX, y: r.minY, width: t, height: r.height),
                    CGRect(x: r.maxX - t, y: r.minY, width: t, height: r.height)]
        }
    }

    /// The cards and panels a readout belongs inside or outside of: a
    /// number about something in a card stays in that card, and a number
    /// about the space between two cards stays out of both.
    public static func regions(in nodes: [LayoutNode], canvas: CGRect, pixelScale: CGFloat) -> [CGRect] {
        let scan = Scan(nodes: nodes, canvas: canvas, scale: max(pixelScale, 1))
        return nodes.indices.filter(scan.isContainer).map { nodes[$0].rect }
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
        var answer: [String: AgentJSON] = [
            "marks": .array(list),
            "count": .number(Double(list.count)),
            "unit": .string(pixelScale > 1 ? "points (the picture is \(Misalignment.number(pixelScale))x)" : "points"),
        ]
        if list.isEmpty {
            answer["say"] = .string("No controls or cards to measure were read here. Use find_elements, then add_measurement on what was asked.")
        }
        return .object(answer)
    }

    struct Scan {
        let nodes: [LayoutNode]
        let canvas: CGRect
        let scale: CGFloat
        let children: [Int?: [Int]]
        var focus: CGRect?

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
            // Under 10 points across is a chevron or a caret beside words,
            // not something a developer is handed a size for.
            return lo >= 4 && hi >= 10 && hi <= 64 && hi / max(lo, 0.1) <= 2
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
            // Controls before icons: the button is what gets built, the
            // glyph beside a row is detail.
            let found = kinds(controls)
            func rank(_ k: Kind) -> Int { nodes[k.members[0]].kind == .mark ? 2 : k.name == "Icon" ? 1 : 0 }
            let kinds = (0...2).flatMap { r in found.filter { rank($0) == r } }
            var representatives: [Int] = []
            for kind in kinds.prefix(mostSizes) {
                let pick = representative(of: kind.members, obstacles: obstacles)
                representatives.append(pick)
                sizes.append(.size(kind.name, nodes[pick].rect, repeats: kind.members.count))
            }

            var spacing: [RedlineMark] = []
            var containers = nodes.indices.filter(isContainer).sorted(by: readingOrder)
            let minimum = 2 * scale
            // The card a person named comes first: its padding is the one measured.
            let focused = focus.flatMap { f in
                containers.max { overlap($0, f) < overlap($1, f) }.flatMap { overlap($0, f) >= 0.5 ? $0 : nil }
            }
            if let focused { containers = [focused] + containers.filter { $0 != focused } }

            // No margin from the picture's edge: a screenshot's edge is where
            // somebody cropped it, not a measurement of the design.

            // A card's padding: its edge to the nearest thing inside it, left
            // and, when it differs, right.
            if let card = containers.first {
                let r = nodes[card].rect
                let inside = kids(card).filter { nodes[$0].kind != .rule }
                if let left = inside.min(by: { nodes[$0].rect.minX < nodes[$1].rect.minX }) {
                    let l = nodes[left].rect
                    let padL = l.minX - r.minX
                    if padL >= minimum {
                        // Along a divider that starts at the same inset, the
                        // line says the same number and touches no word.
                        let divider = kids(card).first { k in
                            nodes[k].kind == .rule && abs(nodes[k].rect.minX - l.minX) <= 1.5 * scale
                        }
                        let y = (divider.map { nodes[$0].rect.midY } ?? l.midY).rounded()
                        let x = divider.map { nodes[$0].rect.minX } ?? l.minX
                        spacing.append(RedlineMark(role: .padding, what: "Padding", start: CGPoint(x: r.minX, y: y),
                                                   end: CGPoint(x: x, y: y), axis: .horizontal))
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

            // In the card a person named: its top padding when it is not
            // the same as its left, and how far apart what is stacked in it
            // sits (a photo over its title, a title over its date).
            if let card = focused {
                let r = nodes[card].rect
                let inside = kids(card).filter { nodes[$0].kind != .rule }
                if let first = inside.min(by: { nodes[$0].rect.minY < nodes[$1].rect.minY }),
                   let left = inside.map({ nodes[$0].rect.minX - r.minX }).min() {
                    let f = nodes[first].rect
                    let top = f.minY - r.minY
                    if top >= minimum, abs(top - left) > 2 * scale {
                        let x = f.midX.rounded()
                        spacing.append(RedlineMark(role: .padding, what: "Top padding", start: CGPoint(x: x, y: r.minY),
                                                   end: CGPoint(x: x, y: f.minY), axis: .vertical))
                    }
                }
                let stack = inside.sorted { nodes[$0].rect.minY < nodes[$1].rect.minY }
                for (a, b) in zip(stack, stack.dropFirst()).prefix(3) {
                    let ra = nodes[a].rect, rb = nodes[b].rect
                    let shared = min(ra.maxX, rb.maxX) - max(ra.minX, rb.minX)
                    guard rb.minY - ra.maxY >= minimum, shared > 0 else { continue }
                    let x = (max(ra.minX, rb.minX) + shared / 2).rounded()
                    spacing.append(RedlineMark(role: .gap, what: "Gap", start: CGPoint(x: x, y: ra.maxY),
                                               end: CGPoint(x: x, y: rb.minY), axis: .vertical))
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

            // With no cards stacked: how far a control on the page sits
            // under what is above it (a button under its paragraph).
            if !spacing.contains(where: { $0.role == .sectionGap }),
               let (above, control) = representatives.lazy.compactMap({ c -> (Int, Int)? in
                   let rc = nodes[c].rect
                   guard nodes[c].kind == .box, nodes[c].parent == nil else { return nil }
                   let over = nodes.indices.filter { o in
                       let ro = nodes[o].rect
                       return o != c && nodes[o].kind != .rule && ro.maxY <= rc.minY - minimum
                           && min(ro.maxX, rc.maxX) - max(ro.minX, rc.minX) > min(ro.width, rc.width) / 4
                           && rc.minY - ro.maxY <= 4 * rc.height
                   }
                   return over.max(by: { nodes[$0].rect.maxY < nodes[$1].rect.maxY }).map { ($0, c) }
               }).first {
                let a = nodes[above].rect, b = nodes[control].rect
                let x = ((max(a.minX, b.minX) + min(a.maxX, b.maxX)) / 2).rounded()
                spacing.append(RedlineMark(role: .gap, what: "Space above", start: CGPoint(x: x, y: a.maxY),
                                           end: CGPoint(x: x, y: b.minY), axis: .vertical))
            }

            // The gap between neighbouring controls in a row, buttons first.
            let pairs = controls.enumerated().flatMap { i, a in
                controls[(i + 1)...].compactMap { b -> (Int, Int)? in
                    let ra = nodes[a].rect, rb = nodes[b].rect
                    guard nodes[a].parent == nodes[b].parent, sameRow(ra, rb) else { return nil }
                    let (l, r) = ra.minX < rb.minX ? (a, b) : (b, a)
                    let space = nodes[r].rect.minX - nodes[l].rect.maxX
                    guard space >= minimum else { return nil }
                    // Neighbours sit close: two things at either side of a
                    // panel are not a gap anybody specifies.
                    guard space <= 3 * max(ra.height, rb.height) else { return nil }
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
            if let button = buttons.first(where: { !representatives.contains($0) }) ?? buttons.first,
               kids(button).contains(where: { nodes[$0].kind == .text }),
               // To the first thing inside: an icon before the words counts.
               let words = kids(button).min(by: { nodes[$0].rect.minX < nodes[$1].rect.minX }) {
                let b = nodes[button].rect, w = nodes[words].rect
                // Centred words have no inset to specify: the button's width
                // says it, and a bracket under them read as a stray mark.
                let last = kids(button).max(by: { nodes[$0].rect.maxX < nodes[$1].rect.maxX }).map { nodes[$0].rect } ?? w
                let centred = abs((w.minX - b.minX) - (b.maxX - last.maxX)) <= 2 * scale
                if !centred, w.minX - b.minX >= minimum, w.minX - b.minX <= 1.5 * b.height {
                    // Drawn in the padding under the words, so its readout
                    // can leave the button without crossing them.
                    let y = ((w.maxY + b.maxY) / 2).rounded()
                    spacing.append(RedlineMark(role: .inset, what: "Label inset", start: CGPoint(x: b.minX, y: y),
                                               end: CGPoint(x: w.minX, y: y), axis: .horizontal))
                }
            }

            guard let focus else { return Array((sizes + spacing).prefix(mostMarks)) }
            // Only what is in and round the part named; its spacing before
            // the sizes of the controls in it.
            let room = focus.insetBy(dx: -24 * scale, dy: -24 * scale)
            func within(_ m: RedlineMark) -> Bool {
                room.contains(m.box ?? CGRect(x: min(m.start.x, m.end.x), y: min(m.start.y, m.end.y),
                                              width: abs(m.end.x - m.start.x), height: abs(m.end.y - m.start.y)))
            }
            return Array((spacing.filter(within) + sizes.filter(within)).prefix(mostMarks))
        }

        /// How nearly node `i` is `r`: what they share over what either covers.
        func overlap(_ i: Int, _ r: CGRect) -> CGFloat {
            let a = nodes[i].rect, both = a.intersection(r)
            guard !both.isNull else { return 0 }
            let shared = both.width * both.height
            return shared / max(1, a.width * a.height + r.width * r.height - shared)
        }

        /// Which of a kind gets the size: the first, unless another has far
        /// more open room to its right and below for the brackets and their
        /// readouts (the primary button at the end of a row, not the one
        /// hemmed in beside it).
        func representative(of members: [Int], obstacles: [CGRect]) -> Int {
            func room(_ i: Int) -> CGFloat {
                let r = nodes[i].rect
                var right = canvas.maxX - r.maxX, below = canvas.maxY - r.maxY
                for o in obstacles where o != r {
                    if o.maxY > r.minY, o.minY < r.maxY, o.minX >= r.maxX { right = min(right, o.minX - r.maxX) }
                    if o.maxX > r.minX, o.minX < r.maxX, o.minY >= r.maxY { below = min(below, o.minY - r.maxY) }
                }
                return min(right, 200 * scale) + min(below, 200 * scale)
            }
            let first = members[0]
            guard let roomiest = members.max(by: { room($0) < room($1) }),
                  room(roomiest) > 2 * room(first) else { return first }
            return roomiest
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
                    guard nodes[a].kind == .box, nodes[a].parent == nodes[b].parent, name(a) == name(b), near(ra.minX, rb.minX),
                      near(ra.width, rb.width), near(ra.height, rb.height), rb.minY > ra.maxY else { continue }
                    let x = (ra.maxX + 8 * scale).rounded()
                    return RedlineMark(role: .rhythm, what: "Row height", start: CGPoint(x: x, y: ra.minY),
                                       end: CGPoint(x: x, y: rb.minY), axis: .vertical)
                }
            }
            // Nor those: a form or an inspector of labelled rows, three or
            // more labels down one left edge, read baseline to baseline.
            let labels = nodes.indices.filter { nodes[$0].kind == .text && nodes[$0].baseline != nil }
                .sorted { nodes[$0].rect.minY < nodes[$1].rect.minY }
            for a in labels {
                let ra = nodes[a].rect
                let column = labels.filter { b in
                    nodes[b].parent == nodes[a].parent && near(nodes[b].rect.minX, ra.minX)
                        && abs(nodes[b].rect.height - ra.height) <= ra.height / 4
                }
                guard column.count >= 3, let i = column.firstIndex(of: a), i + 1 < column.count else { continue }
                let b = column[i + 1], rb = nodes[b].rect
                guard let top = nodes[a].baseline, let bottom = nodes[b].baseline,
                      bottom - top >= 1.2 * ra.height, bottom - top <= 5 * ra.height else { continue }
                let x = (ra.minX - 6 * scale).rounded()
                guard x > canvas.minX else { continue }
                return RedlineMark(role: .rhythm, what: "Row height", start: CGPoint(x: x, y: top),
                                   end: CGPoint(x: x, y: bottom), axis: .vertical, repeats: column.count)
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
    /// `regions` are the cards (`RedlinePlan.regions`): a readout keeps to
    /// the one its line is in, or to the page between them, wherever it can.
    public static func lay(_ marks: [RedlineMark], obstacles: [CGRect], edges: [CGRect] = [],
                           regions: [CGRect] = [], canvas: CGSize,
                           size: MeasureContent, spacing: MeasureContent,
                           placed: [CGRect] = []) -> [RedlineDrawn] {
        // A mark with no clean spot for a readout is left out rather than
        // stacked; the rest are laid again without its lines in the way.
        func rounds(tidySpacing: Bool) -> (drawn: [RedlineDrawn], left: [RedlineMark]) {
            var kept = marks
            var left: [RedlineMark] = []
            var drawn: [RedlineDrawn] = []
            for round in 0..<5 {
                let result = attempt(kept, obstacles: obstacles, edges: edges, regions: regions, canvas: canvas,
                                     size: size, spacing: spacing, placed: placed, tidySpacing: tidySpacing)
                drawn = result.drawn
                if result.failed.isEmpty || round == 4 { break }
                left += kept.enumerated().filter { result.failed.contains($0.offset) }.map(\.element)
                kept = kept.enumerated().filter { !result.failed.contains($0.offset) }.map(\.element)
            }
            return (drawn, left)
        }
        // Spacing whose number has no tidy spot is left out, unless that
        // would leave too little of a redline: then it may sit on an edge.
        var (drawn, left) = rounds(tidySpacing: true)
        if drawn.count < min(3, marks.count) {
            let looser = rounds(tidySpacing: false)
            if looser.drawn.count > drawn.count { (drawn, left) = looser }
        }
        // But a redline is never thrown away for it: with fewer than three
        // clean marks, the ones left out land as the Measure tool itself
        // would place them, overlap and all.
        // Only one that lands clean, though: its number on nothing and its
        // lines touching no other mark's. A number dropped into a text field
        // or a line run into another mark's tick is worse than one mark
        // fewer (the login screen, 2026-11-11). Only a redline that would
        // otherwise be empty takes the first left-out mark as it falls.
        let floor = min(3, marks.count)
        guard drawn.count < floor, !left.isEmpty else { return drawn }
        var readouts = placed + drawn.flatMap { $0.calipers.map { $0.labelRect(chipSize: $0.estimatedLabelSize) } }
        func piece(for mark: RedlineMark) -> RedlineDrawn {
            var piece = attempt([mark], obstacles: [], edges: [], regions: [], canvas: canvas, size: size, spacing: spacing,
                                placed: [], tidySpacing: false).unplaced[0]
            var chips = readouts
            for j in piece.calipers.indices {
                let c = piece.calipers[j]
                piece.calipers[j].apply(MeasureLabelPlanner.plan(for: c, canvas: canvas, avoiding: chips + obstacles,
                                                                 describing: mark.box.map { [$0] } ?? []))
                chips.append(piece.calipers[j].labelRect(chipSize: c.estimatedLabelSize))
            }
            return piece
        }
        func clean(_ p: RedlineDrawn) -> Bool {
            let subjects = p.mark.box.map { [$0] } ?? []
            let lines = drawn.flatMap(\.calipers).flatMap(inked)
            for c in p.calipers {
                let chip = c.labelRect(chipSize: c.estimatedLabelSize)
                if (obstacles.filter { !subjects.contains($0) } + subjects + readouts + lines).contains(where: chip.intersects) {
                    return false
                }
            }
            return !drawn.contains { touches($0.calipers, p.calipers) }
        }
        for mark in left where drawn.count < floor {
            let p = piece(for: mark)
            guard clean(p) else { continue }
            readouts += p.calipers.map { $0.labelRect(chipSize: $0.estimatedLabelSize) }
            drawn.append(p)
        }
        if drawn.isEmpty, let first = left.first { drawn.append(piece(for: first)) }
        return drawn
    }

    static func attempt(_ marks: [RedlineMark], obstacles: [CGRect], edges: [CGRect], regions: [CGRect], canvas: CGSize,
                        size: MeasureContent, spacing: MeasureContent,
                        placed: [CGRect], tidySpacing: Bool) -> (drawn: [RedlineDrawn], failed: Set<Int>, unplaced: [RedlineDrawn]) {
        var state = State(obstacles: obstacles, canvas: canvas, readouts: placed)
        state.tidySpacing = tidySpacing
        state.edges = edges
        state.regions = regions
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
        state.lines = drawn.flatMap { $0.calipers.map(RedlineLayout.inked) }
        let unplaced = drawn
        var failed = Set<Int>()
        for i in drawn.indices {
            let subjects = drawn[i].mark.box.map { [$0] } ?? []
            let saved = state
            for j in drawn[i].calipers.indices {
                // A size bracket with no clean spot for its number on the
                // side it chose tries the box's other side before giving up.
                let first = drawn[i].calipers[j]
                let tries = [first] + (subjects.isEmpty || first.headOffset == 0 ? [] : [Self.mirrored(first, across: subjects[0])])
                var placed: MeasureContent?
                for t in tries where placed == nil {
                    if t != first { state.swapLine(first, for: t) }
                    placed = state.place(t, describing: subjects)
                    if placed == nil, t != first { state.swapLine(t, for: first) }
                }
                guard let c = placed else {
                    failed.insert(i)
                    state = saved
                    break
                }
                drawn[i].calipers[j] = c
            }
            // Two marks whose lines meet read as one shape (a padding line
            // running into a row height's tick): the later one is left out.
            if !failed.contains(i), drawn[..<i].indices.contains(where: { k in
                !failed.contains(k) && touches(drawn[k].calipers, drawn[i].calipers)
            }) {
                failed.insert(i)
                state = saved
            }
        }
        return (drawn.enumerated().filter { !failed.contains($0.offset) }.map(\.element), failed, unplaced)
    }

    /// The strokes a caliper draws, each as a thin rect: a bracket's two
    /// legs and its head, or a flat line and the ticks at its ends.
    static func strokes(_ c: MeasureContent) -> [CGRect] {
        let g = c.caliperGeometry()
        let runs = abs(c.headOffset) < MeasureBuilder.endTickHalf
            ? [(g.headA, g.headB)] + c.endTicks
            : [(g.footA, g.headA), (g.headA, g.headB), (g.headB, g.footB)]
        let half = c.strokeWidth / 2 + 1
        return runs.map { a, b in
            CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                .insetBy(dx: -half, dy: -half)
        }
    }

    /// Whether any stroke of `a` meets any stroke of `b`.
    static func touches(_ a: [MeasureContent], _ b: [MeasureContent]) -> Bool {
        let theirs = b.flatMap(strokes)
        return a.flatMap(strokes).contains { s in theirs.contains { s.intersects($0) } }
    }

    /// `c`, a bracket on one side of `box`, moved to the opposite side.
    static func mirrored(_ c: MeasureContent, across box: CGRect) -> MeasureContent {
        var m = c
        if c.mode == .horizontal {
            let y = c.start.y >= box.midY ? box.minY : box.maxY
            m.start.y = y
            m.end.y = y
        } else {
            let x = c.start.x >= box.midX ? box.minX : box.maxX
            m.start.x = x
            m.end.x = x
        }
        m.headOffset = -c.headOffset
        return m
    }

    /// The leader the canvas draws from a caliper to a readout that has
    /// stepped off its line (`MeasurePlan.make`: from the nearest point of the
    /// caliper's own strokes to where that run meets the pill), or nil when
    /// none is drawn.
    public static func leader(of c: MeasureContent) -> (CGPoint, CGPoint)? {
        let plan = MeasurePlan.make(c, geometry: c.caliperGeometry(), chipSize: c.estimatedLabelSize)
        return plan.leader.map { ($0.from, $0.to) }
    }

    /// Everything a caliper draws, as thin rects a readout must stay off: its
    /// measuring line and, for a bracket, its legs and its head. Only the
    /// measuring line used to count, so a readout could sit on another
    /// bracket's head (the 30 point number on the 124 point line).
    static func inked(_ c: MeasureContent) -> [CGRect] {
        let g = c.caliperGeometry()
        let half = c.strokeWidth / 2 + 1
        let strokes = abs(c.headOffset) < MeasureBuilder.endTickHalf
            ? [] : [(g.footA, g.headA), (g.headA, g.headB), (g.headB, g.footB)]
        return c.subjectRects + strokes.map { a, b in
            CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                .insetBy(dx: -half, dy: -half)
        }
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
        var edges: [CGRect] = []
        var regions: [CGRect] = []
        /// Whether spacing must find a tidy spot or be left out.
        var tidySpacing = true
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
        /// The head stands just off the box (`minimumClearingReach`), so the
        /// dimension line hugs it and its number sits beside the line.
        func side(of box: CGRect, horizontal: Bool,
                  template: MeasureContent) -> (start: CGPoint, end: CGPoint, head: CGFloat) {
            // The card the box is in: a bracket that fits inside it stays
            // inside it, rather than crossing its edge into the page.
            let mid = CGPoint(x: box.midX, y: box.midY)
            let home = regions.filter { $0.contains(mid) && $0 != box }
                .min { $0.width * $0.height < $1.width * $1.height }
            func room(_ positive: Bool, inHome: Bool = false) -> CGFloat {
                var limit: CGFloat
                let frame = inHome ? (home ?? bounds) : bounds
                if horizontal {
                    limit = positive ? frame.maxY - box.maxY : box.minY - frame.minY
                } else {
                    limit = positive ? frame.maxX - box.maxX : box.minX - frame.minX
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
            // The side that holds the head and a readout beside it, below or
            // right when both do; failing that, the roomier one.
            let chip = probe.estimatedLabelSize
            let across = horizontal ? chip.height : chip.width
            // Every bracket hugs its box, its number just past the head. A
            // short span's number on its head hid the line (the judge on the
            // 26 and 30 point brackets), and a long span's head standing a
            // readout's height off the box, number riding it, read as a line
            // floating off its object (the user on the 124 and 220 point
            // brackets, 2026-11-11).
            let span = horizontal ? box.width : box.height
            let alongHalf = (horizontal ? chip.width : chip.height) / 2
            let standoff = MeasureBuilder.minimumClearingReach
            let needed = standoff + MeasureContent.chipLineGap + across + MeasureBuilder.canvasEdgeGap
            let homeBelow = room(true, inHome: true), homeAbove = room(false, inHome: true)
            let below = room(true), above = room(false)
            // An empty box (a text field, a well) with no room for the number
            // on either side inside its card carries its dimension line
            // across its own middle, ticks on its edges and the number on
            // the line. Hung outside, the line crossed into the next card and
            // its leg ran into the box's other bracket (the 220 point field).
            let thick = horizontal ? box.height : box.width
            // Only a line long enough to show a good arm either side of its
            // number: a field's height carried inside it is all number.
            if homeBelow < needed, homeAbove < needed, span >= 4 * alongHalf, thick >= across + 2,
               isEmpty(box) {
                if horizontal {
                    return (CGPoint(x: box.minX, y: box.midY), CGPoint(x: box.maxX, y: box.midY), 0)
                }
                return (CGPoint(x: box.midX, y: box.minY), CGPoint(x: box.midX, y: box.maxY), 0)
            }
            let positive: Bool
            if homeBelow >= needed || homeAbove >= needed {
                positive = homeBelow >= needed
            } else {
                positive = below >= needed || (above < needed && below >= above)
            }
            // Where neither side holds it, the head stops short of whatever
            // is next (the picture's edge included) rather than run past it.
            let room = positive ? below : above
            let reach = min(standoff, max(room - MeasureBuilder.canvasEdgeGap, MeasureBuilder.minimumClearingReach))
            if horizontal {
                let y = positive ? box.maxY : box.minY
                return (CGPoint(x: box.minX, y: y), CGPoint(x: box.maxX, y: y), positive ? reach : -reach)
            }
            let x = positive ? box.maxX : box.minX
            return (CGPoint(x: x, y: box.minY), CGPoint(x: x, y: box.maxY), positive ? reach : -reach)
        }

        /// Puts `new` where `old` was among the lines readouts stay off.
        mutating func swapLine(_ old: MeasureContent, for new: MeasureContent) {
            let was = RedlineLayout.inked(old)
            if let k = lines.firstIndex(of: was) { lines[k] = RedlineLayout.inked(new) }
        }

        /// Whether `box` holds nothing: no word, mark or control inside it.
        func isEmpty(_ box: CGRect) -> Bool {
            !regions.contains(box) && !obstacles.contains { o in
                o != box && !o.contains(box) && o.intersects(box.insetBy(dx: 2, dy: 2))
            }
        }

        /// The smallest card the middle of `c`'s line is in, or nil for the
        /// page.
        func homeRegion(of c: MeasureContent) -> CGRect? {
            let g = c.caliperGeometry()
            let mid = CGPoint(x: (g.headA.x + g.headB.x) / 2, y: (g.headA.y + g.headB.y) / 2)
            return regions.filter { $0.contains(mid) }.min { $0.width * $0.height < $1.width * $1.height }
        }

        /// Everything round `box`, so a readout kept off it stays inside it.
        static func outside(_ box: CGRect) -> [CGRect] {
            let big: CGFloat = 1_000_000
            return [CGRect(x: -big, y: -big, width: 2 * big, height: box.minY + big),
                    CGRect(x: -big, y: box.maxY, width: 2 * big, height: big),
                    CGRect(x: -big, y: box.minY, width: box.minX + big, height: box.height),
                    CGRect(x: box.maxX, y: box.minY, width: big, height: box.height)]
        }

        /// What a readout keeps off to stay in `home`: every card that is
        /// neither `home` nor round it, and everything outside `home`.
        func foreign(to home: CGRect?) -> [CGRect] {
            let others = regions.filter { r in home.map { !r.contains($0) } ?? true }
            guard let h = home else { return others }
            let big: CGFloat = 1_000_000
            return others + [CGRect(x: -big, y: -big, width: 2 * big, height: h.minY + big),
                             CGRect(x: -big, y: h.maxY, width: 2 * big, height: big),
                             CGRect(x: -big, y: h.minY, width: h.minX + big, height: h.height),
                             CGRect(x: h.maxX, y: h.minY, width: big, height: h.height)]
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
            let ownLines = RedlineLayout.inked(c)
            let otherLines = lines.filter { $0 != ownLines }.flatMap { $0 }
            let blocked = obstacles.filter { o in !subjects.contains(o) } + readouts + otherLines
            // A line across the middle of an empty box (`side(of:)`) carries
            // its number inside that box and nowhere else; any other keeps
            // its number off the box it measures.
            let g = c.caliperGeometry()
            let middle = CGPoint(x: (g.headA.x + g.headB.x) / 2, y: (g.headA.y + g.headB.y) / 2)
            let within = c.headOffset == 0 ? subjects.first { $0.insetBy(dx: 1, dy: 1).contains(middle) } : nil
            let mine = within.map(Self.outside) ?? subjects.map { $0.insetBy(dx: -1, dy: -1) }
            // A number stepped off its line stays within its own pill's
            // length of it: further, and nobody ties the two together (the
            // 12 point gap's number, 2026-11-11).
            let longestLeader = max(chip.width, chip.height)
            let outward: MeasureLabelPlacement = c.headOffset < 0 ? .clearNegative : .clearPositive
            let inward: MeasureLabelPlacement = outward == .clearPositive ? .clearNegative : .clearPositive

            func candidates(leash: CGFloat, along: Int, leadersMayCross: Bool,
                            straight: Bool = false) -> [LabelCandidate<MeasureLabelPlanner.Plan>] {
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
                    // A number over the whole span it is about says nothing
                    // about what it spans: it steps off the line instead.
                    guard !probe.labelHidesItsLine(chipSize: chip) else { return }
                    let rect = probe.labelRect(chipSize: chip)
                    guard bounds.contains(rect) else { return }
                    var extra = cost
                    // A leader runs over nothing: no word, control, readout
                    // or other line (save what it starts inside), and never
                    // across another leader.
                    if let run = RedlineLayout.leader(of: probe) {
                        // A slanted leader reads as a stray line, not as a
                        // note tied to its mark.
                        if straight, abs(run.1.x - run.0.x) > 1, abs(run.1.y - run.0.y) > 1 { return }
                        if leaders.contains(where: { RedlineLayout.cross($0, run) }) { return }
                        if hypot(run.1.x - run.0.x, run.1.y - run.0.y) > longestLeader { return }
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
                    // Stepping off on the outside, the first spot is just
                    // past the head: the readout sits against the bracket it
                    // belongs to, with no leader to draw.
                    let pastHead = placement == outward && abs(c.headOffset) > c.subjectCrossReach
                        ? [abs(c.headOffset)] : []
                    var reaches = pastHead
                    var reach: CGFloat = 0
                    while reach <= leash {
                        reaches.append(reach)
                        reach += crossStep
                    }
                    for reach in reaches {
                        for m in nudges {
                            // Just past the head is as good a spot as the
                            // head itself: it is where a redline puts the
                            // number of a span too short to carry it.
                            let ranked = pastHead.contains(reach) ? 0 : CGFloat(rank + 1) * LabelPlacer.rankCost
                                + reach / max(crossStep, 1) * LabelPlacer.nudgeCost
                            consider(placement, nudge: step * m, reach: reach,
                                     cost: ranked + abs(m) * LabelPlacer.nudgeCost)
                        }
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
            // First, a spot that keeps to the line's own region and off
            // every edge: the number about a row stays in its card, the
            // number about the space between two cards sits between them.
            // A readout on a divider, or across the gap into the next card,
            // read as clutter (the judge, 2026-11-11).
            let home = homeRegion(of: c)
            let tidy = [LabelAvoidance(rects: blocked + mine + edges + foreign(to: home), weight: .forbidden)]
            let strict = [LabelAvoidance(rects: blocked + mine, weight: .forbidden),
                          // A tie-breaker, not a wall: a readout steps off a
                          // card's edge when a near spot is as good, never
                          // onto a far leader to dodge it.
                          LabelAvoidance(rects: edges, weight: .flat(LabelPlacer.rankCost * 1.5))]
            // A size falls back to the looser spots below: the size of a
            // control is what a redline is for. Spacing with no tidy spot is
            // left out rather than laid on a divider or a card's edge.
            let loose = !subjects.isEmpty || !tidySpacing
            let tiers = [(leash, 4, tidy, true), (leash * 2, 8, tidy, true)]
                + (loose ? [(leash, 4, strict, false), (leash * 2, 8, strict, false)] : [])
            var chosen: MeasureLabelPlanner.Plan?
            for tier in tiers where chosen == nil {
                chosen = LabelPlacer.best(among: candidates(leash: tier.0, along: tier.1, leadersMayCross: false,
                                                            straight: tier.3),
                                          avoiding: tier.2, within: bounds, anchoredAt: c.labelAnchor)
            }
            guard let plan = chosen else { return nil }
            c.apply(plan)
            readouts.append(c.labelRect(chipSize: chip))
            if let run = RedlineLayout.leader(of: c) { leaders.append(run) }
            return c
        }
    }
}
