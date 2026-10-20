import CoreGraphics
import Foundation

// Animated charts you can drop into a video (task
// `animated-charts-you-can-drop-into-a-video`).
//
// The user, 2026-10-17, naming what a video's catalog holds: "title page, name
// plates, animated charts". Good explainer and product videos show data the way
// Keynote builds a chart: bars growing in one after another, a line drawing
// itself, a donut sweeping round, a big number counting up to its value.
//
// **A chart is a title.** It lands as one group of ordinary layers on the
// timeline (bars are boxes, the line and the wedges are paths, the numbers are
// words) moved by a design (`TitleDesign.swift`), so every title knob restyles
// it: theme, font pair, energy, intensity, background, the per-part rows on the
// timeline. What it adds is its data, kept in the title's recipe
// (`TitleRecipe.chart`): every restyle lays the pieces out again from the data
// in the new colours and faces, so typing a new number moves its bar. Words
// typed on the canvas are read back into the data first, so a label renamed
// in place stays renamed.
//
// Sizes are points of a 1080 line frame, scaled to the frame it lands on.

// MARK: - The kinds

/// A kind of chart, which is also its preset on the shelf.
public enum ChartKind: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case bar, horizontalBar, line, donut, bigNumber, comparison

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .bar: "Bar Chart"
        case .horizontalBar: "Horizontal Bars"
        case .line: "Line Chart"
        case .donut: "Donut"
        case .bigNumber: "Big Number"
        case .comparison: "Comparison"
        }
    }

    /// How many rows it can draw: a big number is one, a comparison two or
    /// three cards, the rest up to a dozen.
    public var rowLimit: ClosedRange<Int> {
        switch self {
        case .bigNumber: 1...1
        case .comparison: 1...3
        case .line: 2...ChartSpec.maxRows
        default: 1...ChartSpec.maxRows
        }
    }
}

// MARK: - The data

/// One row of a chart: a bar, a point, a wedge or a card.
public struct ChartRow: Hashable, Codable, Sendable {
    public var label: String
    public var value: Double
    /// Its own colour, whatever the theme; nil wears the theme's.
    public var colorHex: String?

    public init(label: String, value: Double, colorHex: String? = nil) {
        self.label = label
        self.value = value
        self.colorHex = colorHex
    }
}

/// How a chart writes its numbers: a unit before or after, and decimals.
public struct ChartNumberFormat: Hashable, Codable, Sendable {
    public var prefix: String
    public var suffix: String
    public var decimals: Int

    public static let decimalRange: ClosedRange<Int> = 0...3

    public init(prefix: String = "", suffix: String = "", decimals: Int = 0) {
        self.prefix = prefix
        self.suffix = suffix
        self.decimals = min(max(decimals, Self.decimalRange.lowerBound), Self.decimalRange.upperBound)
    }

    /// The units the panel offers, each a prefix or a suffix.
    public enum Unit: String, CaseIterable, Identifiable, Hashable, Sendable {
        case none, dollars, euros, pounds, percent, thousands, millions, billions, times

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .none: "None"
            case .dollars: "$ Dollars"
            case .euros: "€ Euros"
            case .pounds: "£ Pounds"
            case .percent: "% Percent"
            case .thousands: "K Thousands"
            case .millions: "M Millions"
            case .billions: "B Billions"
            case .times: "x Times"
            }
        }

        var prefix: String {
            switch self {
            case .dollars: "$"
            case .euros: "€"
            case .pounds: "£"
            default: ""
            }
        }

        var suffix: String {
            switch self {
            case .percent: "%"
            case .thousands: "K"
            case .millions: "M"
            case .billions: "B"
            case .times: "x"
            default: ""
            }
        }
    }

    public init(unit: Unit, decimals: Int = 0) {
        self.init(prefix: unit.prefix, suffix: unit.suffix, decimals: decimals)
    }

    /// The unit this format is, nil for a prefix or suffix of somebody's own.
    public var unit: Unit? {
        Unit.allCases.first { $0.prefix == prefix && $0.suffix == suffix }
    }

    /// A value written out: "$1,234.5".
    public func string(_ value: Double) -> String {
        let digits = Self.digits(abs(value), decimals: decimals, groups: true)
        let negative = value < 0 && digits.contains { $0.isNumber && $0 != "0" }
        return (negative ? "-" : "") + prefix + digits + suffix
    }

    /// A number's digits: thousands grouped where asked, `decimals` after the
    /// point, rounded half away from nought (so 9.25 to one place is 9.3).
    public static func digits(_ value: Double, decimals: Int, groups: Bool) -> String {
        let places = min(max(decimals, 0), 6)
        guard value.isFinite else { return "0" }
        let scale = pow(10, Double(places))
        let scaled = (abs(value) * scale).rounded(.toNearestOrAwayFromZero)
        guard scaled < 1e17 else { return String(format: "%.\(places)f", value) }
        let whole = Int64(scaled / scale)
        let fraction = Int64(scaled) - whole * Int64(scale)
        var integer = String(whole)
        if groups, integer.count > 3 {
            var grouped = ""
            for (index, character) in integer.enumerated() {
                if index > 0, (integer.count - index) % 3 == 0 { grouped.append(",") }
                grouped.append(character)
            }
            integer = grouped
        }
        var out = integer
        if places > 0 {
            let tail = String(fraction)
            out += "." + String(repeating: "0", count: max(0, places - tail.count)) + tail
        }
        return value < 0 && scaled > 0 ? "-" + out : out
    }
}

/// Everything a chart draws: its kind, its title, its rows, how it writes
/// numbers, and for a big number the change beside it ("+18%").
public struct ChartSpec: Hashable, Codable, Sendable {
    public var kind: ChartKind
    public var title: String
    public var rows: [ChartRow]
    public var format: ChartNumberFormat
    public var delta: String?
    /// Its later sets of numbers along its clip, nil for a chart of one set
    /// (`ChartData.swift`). Nil on every chart written before there were any.
    public var steps: [ChartStep]?
    /// The axis a chart drawn at a moment keeps, which is the whole chart's
    /// rather than that moment's (`shown(atMS:)`). Nil on every chart saved.
    var axis: ClosedRange<Double>?

    public static let maxRows = 12

    public init(kind: ChartKind, title: String, rows: [ChartRow], format: ChartNumberFormat = ChartNumberFormat(),
                delta: String? = nil, steps: [ChartStep]? = nil) {
        self.kind = kind
        self.title = title
        self.rows = rows
        self.format = format
        self.delta = delta
        self.steps = steps
    }

    /// What a chart says when it lands, before anybody types their own.
    public static func sample(_ kind: ChartKind) -> ChartSpec {
        func rows(_ pairs: [(String, Double)]) -> [ChartRow] { pairs.map { ChartRow(label: $0.0, value: $0.1) } }
        switch kind {
        case .bar:
            return ChartSpec(kind: kind, title: "Signups by Quarter",
                             rows: rows([("Q1", 1240), ("Q2", 1860), ("Q3", 2310), ("Q4", 3180)]))
        case .horizontalBar:
            return ChartSpec(kind: kind, title: "Time Saved per Task",
                             rows: rows([("Export", 42), ("Captions", 35), ("Cuts", 28), ("Titles", 18)]),
                             format: ChartNumberFormat(unit: .percent))
        case .line:
            return ChartSpec(kind: kind, title: "Monthly Visitors",
                             rows: rows([("Jan", 12), ("Feb", 15), ("Mar", 14), ("Apr", 19), ("May", 24),
                                         ("Jun", 31)]),
                             format: ChartNumberFormat(unit: .thousands))
        case .donut:
            return ChartSpec(kind: kind, title: "Where the Time Goes",
                             rows: rows([("Editing", 45), ("Review", 25), ("Export", 15), ("Other", 15)]),
                             format: ChartNumberFormat(unit: .percent))
        case .bigNumber:
            return ChartSpec(kind: kind, title: "Hours Saved",
                             rows: rows([("Hours saved every week", 12.5)]),
                             format: ChartNumberFormat(decimals: 1), delta: "+18%")
        case .comparison:
            return ChartSpec(kind: kind, title: "Error Rate",
                             rows: rows([("Before", 48), ("After", 12)]),
                             format: ChartNumberFormat(unit: .percent))
        }
    }

    /// This spec within what its kind can draw: rows cut to its limit (a
    /// line needs two points, so one is doubled), decimals in range.
    public var tidied: ChartSpec {
        var spec = self
        let limit = kind.rowLimit
        if spec.rows.count > limit.upperBound { spec.rows = Array(spec.rows.prefix(limit.upperBound)) }
        if spec.rows.isEmpty { spec.rows = [ChartRow(label: "Item", value: 1)] }
        while spec.rows.count < limit.lowerBound, let last = spec.rows.last { spec.rows.append(last) }
        spec.format = ChartNumberFormat(prefix: format.prefix, suffix: format.suffix, decimals: format.decimals)
        spec.steps = spec.tidiedSteps()
        return spec
    }

    // MARK: Pasting

    /// Rows out of pasted text: a line per row, cells split by tabs (a
    /// spreadsheet's copy), or commas with quotes (a CSV), or semicolons.
    /// The first cell is the label and the first column of numbers the
    /// value; a cell like `#FF9500` is the row's colour. A header is
    /// skipped. Money, percents and thousands read as numbers
    /// (`ChartTable.reading`).
    public static func rows(pasted text: String) -> [ChartRow] {
        ChartTable.reading(text)?.rows ?? []
    }

    /// A cell as a number, where it is one: "$1,200", "42%", "-3.5", "12K",
    /// and "(25)", the way an account writes minus 25.
    public static func number(in cell: String) -> Double? {
        var cleaned = cell.trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("("), cleaned.hasSuffix(")"), cleaned.count > 2 {
            return number(in: String(cleaned.dropFirst().dropLast())).map { -abs($0) }
        }
        for mark in ["$", "€", "£", "%", ",", "\u{00A0}", " "] { cleaned = cleaned.replacingOccurrences(of: mark, with: "") }
        cleaned = cleaned.replacingOccurrences(of: "\u{2212}", with: "-")
        // A unit letter after it ("12K") is the unit, not part of the value.
        if let last = cleaned.last, "kKmMbBxX".contains(last), cleaned.count > 1 { cleaned.removeLast() }
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    // MARK: Reading the canvas back

    /// Words typed on the canvas taken back into the data: the title, each
    /// label, and each number that still reads as one.
    mutating func read(from group: Layer) {
        func words(_ path: String) -> String? { TitleDesign.find(path, in: group)?.text?.string }
        func number(_ path: String) -> Double? { words(path).flatMap(CountedNumber.init(parsing:))?.value }
        if let title = words("Title") { self.title = title }
        switch kind {
        case .bigNumber:
            if let label = words("Label"), !rows.isEmpty { rows[0].label = label }
            if let value = number("Number"), !rows.isEmpty { rows[0].value = value }
            if let delta = words("Delta") { self.delta = delta }
        case .comparison:
            for index in rows.indices {
                if let label = words("Label \(index + 1)") { rows[index].label = label }
                if let value = number("Number \(index + 1)") { rows[index].value = value }
            }
        default:
            for index in rows.indices {
                if let label = words("Label \(index + 1)") { rows[index].label = label }
                if let value = number("Value \(index + 1)") { rows[index].value = value }
            }
        }
    }
}

// MARK: - How each kind looks when it lands

extension ChartKind {
    /// The colours a chart lands in: a curated theme each, so six tiles never
    /// read as one tile six times.
    var theme: TitleTheme {
        let id = switch self {
        case .bar: "night"
        case .horizontalBar: "ink"
        case .line: "aurora"
        case .donut: "forest"
        case .bigNumber: "night"
        case .comparison: "ink"
        }
        return TitleTheme.curated.first { $0.id == id } ?? TitleTheme.curated[0]
    }

    var fonts: TitleFontPair {
        TitleFontPair.curated.first { $0.id == "clean" } ?? TitleFontPair.curated[0]
    }

    /// The moving look behind it: quiet ones, so the data is the subject.
    var look: LiveLook {
        switch self {
        case .bar: .particles
        case .horizontalBar: .gridHorizon
        case .line: .aurora
        case .donut: .liquidGradient
        case .bigNumber: .lightRays
        case .comparison: .particles
        }
    }
}

// MARK: - Drawing a chart

/// Lays a chart's pieces out on a frame, in a theme and a font pair.
struct ChartPen {
    let canvas: CGSize
    let theme: TitleTheme
    let fonts: TitleFontPair
    /// True when nothing of the title is behind its words, so they throw the
    /// shade a title over footage throws.
    let overFootage: Bool

    var pen: TitlePen { TitlePen(canvas: canvas) }
    private func u(_ points: CGFloat) -> CGFloat { pen.u(points) }
    private var left: CGFloat { u(160) }
    private var right: CGFloat { canvas.width - u(160) }

    /// The whole chart as it lands: a background and every piece, grouped.
    func group(_ spec: ChartSpec, look: LiveLook) -> Layer {
        let background = pen.fullFrame(Paint(hex: theme.ground, kind: .live, stops: theme.liveStops,
                                             live: LiveBackdrop(look: look, speed: 70, strength: 70)))
        return TitlePen.grouped([background] + pieces(spec), name: spec.kind.name)
    }

    /// `group` laid out again from `spec`: its background kept as the
    /// restyle left it, every other piece drawn afresh, each keeping the id
    /// of the piece of its name it replaces.
    func rebuilt(_ group: Layer, _ spec: ChartSpec, drawnBefore: [String: Layer] = [:]) -> Layer {
        guard let background = group.children.first(where: { $0.name == "Background" }) else { return group }
        let offset = background.frame.origin
        let was = Dictionary(group.children.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let drawn = pieces(spec).map { piece -> Layer in
            var piece = piece
            piece.frame = piece.frame.offsetBy(dx: offset.x, dy: offset.y)
            guard let old = was[piece.name] else { return piece }
            // Freshly drawn, so its name, content, frame and style are all it
            // has, but for what a hand set on it: its keys (the design's own
            // are already off it and are written again after), and an effect
            // the drawing it had did not give it.
            var style = piece.style
            if let before = drawnBefore[piece.name] {
                style.effects += old.style.effects.filter { !before.style.effects.contains($0) }
            }
            var redrawn = Layer(id: old.id, name: piece.name, content: piece.content, frame: piece.frame,
                                style: style, isVisible: piece.isVisible)
            redrawn.motions = old.motions
            return redrawn
        }
        var rebuilt = group
        rebuilt.children = [background] + drawn
        return rebuilt
    }

    /// Every piece but the background, in frame coordinates.
    func pieces(_ spec: ChartSpec) -> [Layer] {
        let spec = spec.tidied
        switch spec.kind {
        case .bar: return title(spec) + bars(spec)
        case .horizontalBar: return title(spec) + horizontalBars(spec)
        case .line: return title(spec) + line(spec)
        case .donut: return title(spec) + donut(spec)
        case .bigNumber: return bigNumber(spec)
        case .comparison: return title(spec) + comparison(spec)
        }
    }

    // MARK: Colours

    /// Row `index`'s colour: its own, or the theme's accent for a chart of
    /// one colour; a donut's wedges walk round the wheel from the accent.
    func colour(_ spec: ChartSpec, _ index: Int, distinct: Bool = false) -> String {
        if let own = spec.rows[index].colorHex { return own }
        guard distinct, index > 0, let accent = RGBA(hex: theme.accent) else { return theme.accent }
        var hsl = accent.hsl
        hsl.hue = (hsl.hue + Double(index) * 47).truncatingRemainder(dividingBy: 360)
        hsl.saturation = max(hsl.saturation, 0.45)
        hsl.lightness = min(max(hsl.lightness - Double(index % 2) * 0.08, 0.35), 0.7)
        return RGBA(hsl: hsl).hexString
    }

    // MARK: Words

    /// Words in a box `width` wide (their own width where nil), placed by
    /// their box's left, middle or right edge at `x` and their top at `top`.
    private func words(_ name: String, _ string: String, size: CGFloat, display: Bool, weight: TextWeight? = nil,
                       color: String, x: CGFloat, top: CGFloat, align: TextAlign = .left,
                       width: CGFloat? = nil) -> Layer {
        var layer = pen.words(name, string, font: display ? fonts.display : fonts.text, size: size,
                              weight: weight ?? (display ? fonts.displayWeight : fonts.textWeight), color: color,
                              origin: .zero, align: align == .left ? nil : align, width: width,
                              legibleOverVideo: overFootage)
        let w = layer.frame.width
        let originX: CGFloat = switch align {
        case .center: x - w / 2
        case .right: x - w
        default: x
        }
        layer.frame.origin = CGPoint(x: originX.rounded(), y: top.rounded())
        return layer
    }

    private func title(_ spec: ChartSpec) -> [Layer] {
        guard !spec.title.isEmpty else { return [] }
        return [words("Title", spec.title, size: 64, display: true, color: theme.primary, x: left, top: u(110))]
    }

    private func baseline(at y: CGFloat) -> Layer {
        var line = pen.line("Baseline", from: CGPoint(x: left, y: y), length: right - left, width: u(2),
                            color: theme.secondary)
        line.style.opacity = 0.45
        return line
    }

    // MARK: Bars

    /// Bars standing on a zero line: up for a value over nought, down for one
    /// under it, every one to the same scale. The scale is the biggest and
    /// the least number any set of the chart shows, so a bar that grows from
    /// one set to the next really grows.
    private func bars(_ spec: ChartSpec) -> [Layer] {
        let rows = spec.rows
        let base = canvas.height - u(200)
        let top = u(300)
        let (lo, hi) = spec.valueRange
        let span = max(hi - lo, Double.leastNonzeroMagnitude)
        // Room above for the numbers over the bars, and below for the ones
        // under bars that run down.
        let headroom = hi > 0 || lo == 0 ? u(64) : 0
        let footroom = lo < 0 ? u(64) : 0
        let room = base - top - headroom - footroom
        let zero = (top + headroom + room * CGFloat(hi / span)).rounded()
        let slot = (right - left) / CGFloat(rows.count)
        let width = min(slot * 0.58, u(200))
        var pieces: [Layer] = []
        var values: [Layer] = []
        var labels: [Layer] = []
        for (index, row) in rows.enumerated() {
            let middle = left + slot * (CGFloat(index) + 0.5)
            let height = max(u(4), (room * CGFloat(abs(row.value) / span)).rounded())
            let below = row.value < 0
            let box = CGRect(x: (middle - width / 2).rounded(), y: below ? zero : zero - height,
                             width: width.rounded(), height: height)
            pieces.append(pen.box("Bar \(index + 1)", box, fill: Paint(hex: colour(spec, index)), radius: u(10)))
            var value = words("Value \(index + 1)", spec.format.string(row.value), size: 40, display: true,
                              weight: .semibold, color: theme.primary, x: middle, top: 0, align: .center,
                              width: slot)
            value.frame.origin.y = below ? (box.maxY + u(12)).rounded()
                : (box.minY - u(12) - value.frame.height).rounded()
            values.append(value)
            labels.append(words("Label \(index + 1)", row.label, size: 30, display: false, color: theme.secondary,
                                x: middle, top: base + u(22), align: .center, width: slot))
        }
        return [baseline(at: zero)] + pieces + values + labels
    }

    private func horizontalBars(_ spec: ChartSpec) -> [Layer] {
        let rows = spec.rows
        let top = u(270)
        let bottom = canvas.height - u(130)
        let slot = (bottom - top) / CGFloat(rows.count)
        let thickness = min(slot * 0.58, u(72))
        let start = left + u(360)
        let (lo, hi) = spec.valueRange
        let span = max(hi - lo, Double.leastNonzeroMagnitude)
        // Room to the right for the numbers past the bars, and to the left of
        // nought for the ones past bars that run left.
        let rightRoom = hi > 0 || lo == 0 ? u(170) : 0
        let leftRoom = lo < 0 ? u(170) : 0
        let room = right - start - rightRoom - leftRoom
        let zero = (start + leftRoom + room * CGFloat(-lo / span)).rounded()
        var axis = pen.box("Baseline", CGRect(x: zero - u(2), y: top, width: u(2), height: bottom - top),
                           fill: Paint(hex: theme.secondary))
        axis.style.opacity = 0.45
        var pieces: [Layer] = []
        var values: [Layer] = []
        var labels: [Layer] = []
        for (index, row) in rows.enumerated() {
            let middle = top + slot * (CGFloat(index) + 0.5)
            let length = max(u(4), (room * CGFloat(abs(row.value) / span)).rounded())
            let left = row.value < 0
            let box = CGRect(x: left ? zero - length : zero, y: (middle - thickness / 2).rounded(), width: length,
                             height: thickness.rounded())
            pieces.append(pen.box("Bar \(index + 1)", box, fill: Paint(hex: colour(spec, index)), radius: u(10)))
            var value = words("Value \(index + 1)", spec.format.string(row.value), size: 38, display: true,
                              weight: .semibold, color: theme.primary,
                              x: left ? box.minX - u(18) : box.maxX + u(18), top: 0, align: left ? .right : .left,
                              width: left ? u(170) : nil)
            value.frame.origin.y = (middle - value.frame.height / 2).rounded()
            values.append(value)
            var label = words("Label \(index + 1)", row.label, size: 32, display: false, color: theme.secondary,
                              x: start - u(28), top: 0, align: .right, width: u(320))
            label.frame.origin.y = (middle - label.frame.height / 2).rounded()
            labels.append(label)
        }
        return [axis] + pieces + values + labels
    }

    // MARK: Line

    private func line(_ spec: ChartSpec) -> [Layer] {
        let rows = spec.rows
        let base = canvas.height - u(200)
        let top = u(330)
        let inset = u(60)
        let (lo, high) = spec.valueRange
        let hi = max(high, lo + 1)
        let points = rows.enumerated().map { index, row in
            CGPoint(x: (left + inset + (right - left - inset * 2) * CGFloat(index) / CGFloat(max(1, rows.count - 1))).rounded(),
                    y: (base - (base - top) * CGFloat((row.value - lo) / (hi - lo))).rounded())
        }
        // The line it sits on is nought, under the lowest point when every
        // number is over it, and between them where some are not.
        let zero = (base - (base - top) * CGFloat(-lo / (hi - lo))).rounded()
        let stroke = u(6)
        let frame = CGRect(x: left, y: top - stroke * 2, width: right - left, height: base - top + stroke * 4)
        let anchors = points.enumerated().map { index, point -> PathAnchor in
            // A curve through every point (Catmull-Rom), flat at the ends.
            let before = points[max(0, index - 1)], after = points[min(points.count - 1, index + 1)]
            let tangent = CGPoint(x: (after.x - before.x) / 6, y: (after.y - before.y) / 6)
            let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
            return PathAnchor(point: local, handleIn: CGPoint(x: -tangent.x, y: -tangent.y), handleOut: tangent,
                              kind: .smooth)
        }
        let content = PathContent(anchors: anchors, isClosed: false, paint: Paint(hex: colour(spec, 0)),
                                  strokeWidth: stroke, fill: nil, lineEnd: .round, lineCorner: .round)
        let path = Layer(name: "Line", content: .path(content), frame: frame)
        var dots: [Layer] = []
        var values: [Layer] = []
        var labels: [Layer] = []
        let slot = (right - left) / CGFloat(rows.count)
        for (index, point) in points.enumerated() {
            let size = u(20)
            dots.append(pen.oval("Dot \(index + 1)", CGRect(x: point.x - size / 2, y: point.y - size / 2,
                                                            width: size, height: size),
                                 fill: Paint(hex: colour(spec, index))))
            var value = words("Value \(index + 1)", spec.format.string(rows[index].value), size: 30, display: true,
                              weight: .semibold, color: theme.primary, x: point.x, top: 0, align: .center, width: slot)
            value.frame.origin.y = rows[index].value < 0 ? (point.y + u(24)).rounded()
                : (point.y - u(24) - value.frame.height).rounded()
            values.append(value)
            labels.append(words("Label \(index + 1)", rows[index].label, size: 30, display: false,
                                color: theme.secondary, x: point.x, top: base + u(22), align: .center, width: slot))
        }
        return [baseline(at: zero), path] + dots + values + labels
    }

    // MARK: Donut

    private func donut(_ spec: ChartSpec) -> [Layer] {
        let rows = spec.rows
        let centre = CGPoint(x: (canvas.width * 0.32).rounded(), y: (canvas.height * 0.57).rounded())
        let radius = u(230)
        let thickness = u(64)
        let total = max(rows.map { max(0, $0.value) }.reduce(0, +), Double.leastNonzeroMagnitude)
        let gap = rows.count > 1 ? 1.4 : 0
        let box = CGRect(x: centre.x - radius - thickness, y: centre.y - radius - thickness,
                         width: (radius + thickness) * 2, height: (radius + thickness) * 2)
        let local = CGPoint(x: radius + thickness, y: radius + thickness)
        var slices: [Layer] = []
        var angle = -90.0
        for (index, row) in rows.enumerated() {
            let sweep = 360 * max(0, row.value) / total
            let from = angle + gap / 2
            let to = max(from + 0.5, angle + sweep - gap / 2)
            angle += sweep
            let content = PathContent(anchors: Self.arc(centre: local, radius: radius, from: from, to: to),
                                      isClosed: false, paint: Paint(hex: colour(spec, index, distinct: true)),
                                      strokeWidth: thickness, fill: nil, lineEnd: .flat)
            slices.append(Layer(name: "Slice \(index + 1)", content: .path(content), frame: box))
        }
        let totalWords = spec.format.string(rows.map(\.value).reduce(0, +))
        var middle = words("Total", totalWords, size: 72, display: true, color: theme.primary, x: centre.x, top: 0,
                           align: .center, width: radius * 1.5)
        middle.frame.origin.y = (centre.y - middle.frame.height / 2).rounded()
        // The key, to the right: a dot, a label and the value, a row each.
        let keyLeft = (canvas.width * 0.6).rounded()
        let rowHeight = u(76)
        let firstTop = centre.y - rowHeight * CGFloat(rows.count) / 2
        var keys: [Layer] = []
        var labels: [Layer] = []
        var values: [Layer] = []
        for (index, row) in rows.enumerated() {
            let middleY = firstTop + rowHeight * (CGFloat(index) + 0.5)
            let dot = u(22)
            keys.append(pen.oval("Key \(index + 1)", CGRect(x: keyLeft, y: (middleY - dot / 2).rounded(),
                                                            width: dot, height: dot),
                                 fill: Paint(hex: colour(spec, index, distinct: true))))
            var label = words("Label \(index + 1)", row.label, size: 34, display: false, color: theme.secondary,
                              x: keyLeft + u(44), top: 0)
            label.frame.origin.y = (middleY - label.frame.height / 2).rounded()
            labels.append(label)
            var value = words("Value \(index + 1)", spec.format.string(row.value), size: 34, display: true,
                              weight: .semibold, color: theme.primary, x: right, top: 0, align: .right, width: u(200))
            value.frame.origin.y = (middleY - value.frame.height / 2).rounded()
            values.append(value)
        }
        return slices + [middle] + keys + labels + values
    }

    /// The anchors of an arc round `centre`, clockwise from `from` degrees to
    /// `to` (nought is three o'clock), a cubic for each quarter or less.
    static func arc(centre: CGPoint, radius: CGFloat, from: Double, to: Double) -> [PathAnchor] {
        let span = max(0.01, to - from)
        let pieces = max(1, Int((span / 90).rounded(.up)))
        let step = span / Double(pieces)
        let handle = 4.0 / 3.0 * tan(step * .pi / 180 / 4) * Double(radius)
        return (0...pieces).map { index in
            let radians = (from + step * Double(index)) * .pi / 180
            let point = CGPoint(x: centre.x + radius * CGFloat(cos(radians)),
                                y: centre.y + radius * CGFloat(sin(radians)))
            let tangent = CGPoint(x: -sin(radians) * handle, y: cos(radians) * handle)
            return PathAnchor(point: point,
                              handleIn: index == 0 ? nil : CGPoint(x: -tangent.x, y: -tangent.y),
                              handleOut: index == pieces ? nil : tangent,
                              kind: .smooth)
        }
    }

    // MARK: Big number

    private func bigNumber(_ spec: ChartSpec) -> [Layer] {
        let row = spec.rows[0]
        let middle = canvas.width / 2
        let width = canvas.width * 0.8
        let number = words("Number", spec.format.string(row.value), size: 220, display: true, color: theme.primary,
                           x: middle, top: canvas.height * 0.27, align: .center, width: width)
        let label = words("Label", row.label, size: 46, display: false, color: theme.secondary, x: middle,
                          top: number.frame.maxY + u(6), align: .center, width: width)
        guard let delta = spec.delta, !delta.isEmpty else { return [number, label] }
        let change = words("Delta", delta, size: 44, display: true, weight: .semibold, color: colour(spec, 0),
                           x: middle, top: label.frame.maxY + u(30), align: .center, width: width)
        return [number, label, change]
    }

    // MARK: Comparison

    private func comparison(_ spec: ChartSpec) -> [Layer] {
        let rows = spec.rows
        let gap = u(48)
        let width = min((right - left - gap * CGFloat(rows.count - 1)) / CGFloat(rows.count), u(520))
        let height = u(420)
        let total = width * CGFloat(rows.count) + gap * CGFloat(rows.count - 1)
        let start = (canvas.width - total) / 2
        let top = (canvas.height * 0.34).rounded()
        var cards: [Layer] = []
        var numbers: [Layer] = []
        var labels: [Layer] = []
        for (index, row) in rows.enumerated() {
            let x = (start + (width + gap) * CGFloat(index)).rounded()
            var card = pen.box("Card \(index + 1)", CGRect(x: x, y: top, width: width.rounded(), height: height),
                               fill: Paint(hex: theme.primary), radius: u(32))
            card.style.opacity = 0.09
            cards.append(card)
            let middle = x + width / 2
            let number = words("Number \(index + 1)", spec.format.string(row.value), size: 120, display: true,
                               color: row.colorHex ?? theme.primary, x: middle, top: top + u(110), align: .center,
                               width: width)
            labels.append(words("Label \(index + 1)", row.label, size: 36, display: false, color: theme.secondary,
                                x: middle, top: number.frame.maxY + u(10), align: .center, width: width))
            numbers.append(number)
        }
        return cards + numbers + labels
    }

    // MARK: - How it moves

    /// How a chart of this data comes in and goes off: the background, then
    /// the title, then its data one row after another, each row's number
    /// counting up as its bar grows; leaving in reverse, quicker.
    ///
    /// **Every move is a value arriving.** Bars grow to their values, the
    /// line draws through its points, the donut sweeps its shares and the
    /// numbers count. Words, dots, keys and cards only fade in: a title
    /// rising or a key bouncing was movement for its own sake, which the
    /// user turned down on 2026-10-19 ("having some elements that move on
    /// the screen is not what i expected").
    static func design(_ spec: ChartSpec) -> TitleDesign {
        typealias B = TitleBuild
        let spec = spec.tidied
        let n = spec.rows.count
        var parts = [
            TitlePart(path: "Background", role: .background,
                      in: B(.fade, delayMS: 0, lengthMS: 500, curve: .easeOutQuint),
                      out: .off(.fade, delayMS: 0, lengthMS: 400), name: "Background"),
        ]
        if spec.kind != .bigNumber, !spec.title.isEmpty {
            parts.append(TitlePart(path: "Title", role: .headline,
                                   in: B(.fade, delayMS: 150, lengthMS: 500, curve: .easeOut),
                                   out: .off(.fade, delayMS: 300, lengthMS: 300), name: "Title"))
        }
        // Rows a beat apart, the beat shrinking so a dozen still arrive in
        // the front half of the chart's time.
        let beat = n > 1 ? min(170, 1300 / (n - 1)) : 0
        func row(_ path: String, _ index: Int, role: TitlePartRole, in build: B, out: B) -> TitlePart {
            TitlePart(path: "\(path) \(index + 1)", role: role, in: build, out: out, name: "\(path) \(index + 1)")
        }
        func leaving(_ index: Int, _ kind: TitleBuildKind = .fade, direction: TitleDirection = .up) -> B {
            .off(kind, delayMS: 120 + index * 40, lengthMS: 300, direction: direction)
        }
        switch spec.kind {
        case .bar, .horizontalBar:
            let vertical = spec.kind == .bar
            parts.append(TitlePart(path: "Baseline", role: .accent,
                                   in: B(.wipe, delayMS: 300, lengthMS: 500, direction: vertical ? .right : .down,
                                         curve: .easeInOut),
                                   out: .off(.fade, delayMS: 100, lengthMS: 300), name: "Baseline"))
            for index in 0..<n {
                let start = 450 + index * beat
                parts.append(row("Bar", index, role: .accent,
                                 in: B(.wipe, delayMS: start, lengthMS: 700, direction: vertical ? .up : .right,
                                       curve: .easeOutQuint),
                                 out: leaving(index, .wipe, direction: vertical ? .down : .left)))
            }
            for index in 0..<n {
                let start = 450 + index * beat
                parts.append(row("Value", index, role: .kicker,
                                 in: B(.countUp, delayMS: start + 100, lengthMS: 800, curve: .easeOut),
                                 out: leaving(index)))
                parts.append(row("Label", index, role: .subtitle,
                                 in: B(.fade, delayMS: max(0, start - 50), lengthMS: 400, curve: .easeOut),
                                 out: leaving(index)))
            }
        case .line:
            let draw = 1400
            parts.append(TitlePart(path: "Baseline", role: .accent,
                                   in: B(.wipe, delayMS: 300, lengthMS: 500, direction: .right, curve: .easeInOut),
                                   out: .off(.fade, delayMS: 100, lengthMS: 300), name: "Baseline"))
            parts.append(TitlePart(path: "Line", role: .accent,
                                   in: B(.drawOn, delayMS: 500, lengthMS: draw, direction: .right, curve: .linear),
                                   out: .off(.drawOn, delayMS: 120, lengthMS: 400), name: "Line"))
            for index in 0..<n {
                let reached = 500 + draw * index / max(1, n - 1)
                parts.append(row("Dot", index, role: .accent,
                                 in: B(.fade, delayMS: max(0, reached - 60), lengthMS: 200, curve: .easeOut),
                                 out: leaving(index)))
                parts.append(row("Value", index, role: .kicker,
                                 in: B(.countUp, delayMS: reached, lengthMS: 500, curve: .easeOut),
                                 out: leaving(index)))
                parts.append(row("Label", index, role: .subtitle,
                                 in: B(.fade, delayMS: 400 + index * 60, lengthMS: 400, curve: .easeOut),
                                 out: leaving(index)))
            }
        case .donut:
            let sweep = 1300
            let total = max(spec.rows.map { max(0, $0.value) }.reduce(0, +), Double.leastNonzeroMagnitude)
            var done = 0.0
            for index in 0..<n {
                let share = max(0, spec.rows[index].value) / total
                let start = 400 + Int(Double(sweep) * done)
                done += share
                parts.append(row("Slice", index, role: .accent,
                                 in: B(.drawOn, delayMS: start, lengthMS: max(60, Int(Double(sweep) * share)),
                                       direction: .right, curve: .linear),
                                 out: leaving(index)))
            }
            parts.append(TitlePart(path: "Total", role: .headline,
                                   in: B(.countUp, delayMS: 400, lengthMS: sweep, curve: .easeOut),
                                   out: .off(.fade, delayMS: 100, lengthMS: 300), name: "Total"))
            for index in 0..<n {
                let start = 600 + index * min(150, beat)
                parts.append(row("Key", index, role: .accent,
                                 in: B(.fade, delayMS: start, lengthMS: 300, curve: .easeOut), out: leaving(index)))
                parts.append(row("Label", index, role: .subtitle,
                                 in: B(.fade, delayMS: start + 60, lengthMS: 400, curve: .easeOut),
                                 out: leaving(index)))
                parts.append(row("Value", index, role: .kicker,
                                 in: B(.countUp, delayMS: start + 60, lengthMS: 700, curve: .easeOut),
                                 out: leaving(index)))
            }
        case .bigNumber:
            parts.append(TitlePart(path: "Number", role: .headline,
                                   in: B(.countUp, delayMS: 200, lengthMS: 1500, curve: .easeOut),
                                   out: .off(.fade, delayMS: 150, lengthMS: 350), name: "Number"))
            parts.append(TitlePart(path: "Label", role: .subtitle,
                                   in: B(.fade, delayMS: 650, lengthMS: 500, curve: .easeOut),
                                   out: .off(.fade, delayMS: 250, lengthMS: 300), name: "Label"))
            if let delta = spec.delta, !delta.isEmpty {
                parts.append(TitlePart(path: "Delta", role: .accent,
                                       in: B(.fade, delayMS: 1500, lengthMS: 400, curve: .easeOut),
                                       out: .off(.fade, delayMS: 300, lengthMS: 250), name: "Delta"))
            }
        case .comparison:
            // Each card fades up, one after another, and its number counts.
            for index in 0..<n {
                let start = 300 + index * 500
                parts.append(row("Card", index, role: .accent,
                                 in: B(.fade, delayMS: start, lengthMS: 700, curve: .easeInOut),
                                 out: leaving(index)))
                parts.append(row("Number", index, role: .kicker,
                                 in: B(.countUp, delayMS: start + 300, lengthMS: 1100, curve: .easeOut),
                                 out: leaving(index)))
                parts.append(row("Label", index, role: .subtitle,
                                 in: B(.fade, delayMS: start + 500, lengthMS: 400, curve: .easeOut),
                                 out: leaving(index)))
            }
        }
        return TitleDesign(parts: parts)
    }

    /// `design(spec)`, keeping the in, hold and out somebody gave any part
    /// that is still there (dragged on the timeline, set in the Part section).
    static func design(_ spec: ChartSpec, keeping old: TitleDesign) -> TitleDesign {
        var fresh = design(spec)
        let before = Dictionary(old.parts.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let defaults = Dictionary(design(spec).parts.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        for index in fresh.parts.indices {
            let path = fresh.parts[index].path
            guard let was = before[path] else { continue }
            // Only what was changed from how the chart would have built it:
            // a stagger that follows the row count stays the chart's own.
            if let usual = defaults[path], was.in == usual.in, was.out == usual.out, was.hold == usual.hold {
                continue
            }
            fresh.parts[index].in = was.in
            fresh.parts[index].hold = was.hold
            fresh.parts[index].out = was.out
        }
        return fresh
    }
}

// MARK: - On the timeline

extension PhotonzDocument {

    /// Put a chart on the timeline at a moment of the document, as a title:
    /// a track of its own, the kind's length, every part on its beat. Nil on
    /// a document with no time.
    @discardableResult
    public mutating func insertTitle(chart kind: ChartKind, spec: ChartSpec? = nil, atTimeMS ms: Int,
                                     landing: ClipLanding? = nil, motionBlur: Bool = false) -> InsertedTitle? {
        guard hasTime else { return nil }
        let spec = (spec ?? .sample(kind)).tidied
        let chartPen = ChartPen(canvas: canvasSize, theme: kind.theme, fonts: kind.fonts, overFootage: false)
        let layer = chartPen.group(spec, look: kind.look)
        guard let inserted = landTitle(layer, kind: .chart, lengthMS: spec.clipLengthMS, sourceInMS: 0,
                                       atTimeMS: ms, landing: landing) else { return nil }
        let design = ChartPen.design(spec)
        applyTitleDesign(design, layerID: inserted.layerID)
        if motionBlur { addEffect(.motionBlur, layerIDs: [inserted.layerID]) }
        rememberTitleDesign(design, layerID: inserted.layerID)
        updateLayer(id: inserted.layerID) { edited in
            guard case .group(var content) = edited.content, var recipe = content.titleRecipe else { return }
            recipe.chart = spec
            // The theme and faces it was drawn in, exactly: reading them back
            // off the pieces would take a row's own colour for the accent.
            recipe.theme = kind.theme
            recipe.originalTheme = kind.theme
            recipe.fonts = kind.fonts
            recipe.originalFonts = kind.fonts
            recipe.looks = recipe.looks.filter { $0.path == "Background" }
            content.titleRecipe = recipe
            edited.content = .group(content)
        }
        return inserted
    }

    /// The data of the chart `layerID` is, nil for anything that is not one.
    public func chartSpec(layerID: UUID) -> ChartSpec? {
        titleRecipe(layerID: layerID)?.chart
    }

    /// Change a chart's data: the chart is laid out again from it, in its
    /// theme and faces, and every row comes in on its beat. A part somebody
    /// retimed keeps its timing. False when nothing changed.
    @discardableResult
    public mutating func editChart(layerID: UUID, _ change: (inout ChartSpec) -> Void) -> Bool {
        guard var recipe = titleRecipe(layerID: layerID), var spec = recipe.chart else { return false }
        let old = spec
        change(&spec)
        spec = spec.tidied
        guard spec != old else { return false }
        recipe.chart = spec
        recipe.design = ChartPen.design(spec, keeping: recipe.design)
        return restyleTitle(layerID: layerID) { $0 = recipe }
    }

    /// The chart's pieces drawn again from its data in the recipe's colours
    /// and faces, where `group` is a chart: what every restyle ends on.
    /// Whatever somebody set by hand on a piece (`from` is the recipe it was
    /// drawn from) comes along: its own keys, and any effect the old drawing
    /// did not give it.
    func chartRedrawn(_ group: Layer, recipe: TitleRecipe, from old: TitleRecipe? = nil) -> Layer {
        guard let spec = recipe.chart else { return group }
        let chartPen = ChartPen(canvas: canvasSize, theme: recipe.theme, fonts: recipe.fonts,
                                overFootage: !recipe.showsBackground)
        var drawnBefore: [String: Layer] = [:]
        if let old, let was = old.chart {
            let oldPen = ChartPen(canvas: canvasSize, theme: old.theme, fonts: old.fonts,
                                  overFootage: !old.showsBackground)
            drawnBefore = Dictionary(oldPen.pieces(was).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return chartPen.rebuilt(group, spec, drawnBefore: drawnBefore)
    }
}
