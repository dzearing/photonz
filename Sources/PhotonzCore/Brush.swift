import CoreGraphics
import Foundation

// The Brush's model (`docs/design/brushes.md`): what a painted stroke IS, kept
// as data rather than pixels so undo stays a small snapshot and the agent's
// stroke and a person's are the same value. Marking (turning dabs into paint)
// lives in PhotonzRender; this file decides where the dabs go.

// MARK: - Media and their settings

/// One of the brush's seven media. Each declares the settings it has, so the
/// tool options, the panel, MCP and the tests all read one list (decision 7).
public enum BrushMedium: String, CaseIterable, Codable, Hashable, Sendable {
    case charcoal
    case chalk
    case crayon
    case marker
    case airbrush
    case oil
    case watercolour

    /// What the medium is called on screen.
    public var title: String {
        switch self {
        case .charcoal: "Charcoal"
        case .chalk: "Chalk"
        case .crayon: "Crayon"
        case .marker: "Marker"
        case .airbrush: "Airbrush"
        case .oil: "Oil Paint"
        case .watercolour: "Watercolour"
        }
    }

    /// The size a fresh brush of this medium starts at, in points.
    var defaultSize: Double {
        switch self {
        case .charcoal: 16
        case .chalk: 20
        case .crayon: 10
        case .marker: 14
        case .airbrush: 40
        case .oil: 24
        case .watercolour: 30
        }
    }

    /// Every setting this medium has, in the order they are shown: Size and
    /// Opacity first, then the medium's own two (the design doc's table).
    public var settings: [BrushSettingSpec] {
        let shared = [
            BrushSettingSpec(id: "size", name: "Size", range: 1...500, defaultValue: defaultSize),
            BrushSettingSpec(id: "opacity", name: "Opacity", range: 1...100, defaultValue: 100),
        ]
        let own: [BrushSettingSpec]
        switch self {
        case .charcoal:
            own = [.percent("grain", "Grain", 60), .percent("smudge", "Smudge", 20)]
        case .chalk:
            own = [.percent("grain", "Grain", 80), .percent("smudge", "Smudge", 15)]
        case .crayon:
            own = [.percent("grain", "Grain", 70), .percent("wax", "Wax", 50)]
        case .marker:
            own = [BrushSettingSpec(id: "tip", name: "Tip", range: 0...1, defaultValue: 0,
                                    options: ["Round", "Chisel"]),
                   .percent("flow", "Flow", 60)]
        case .airbrush:
            own = [.percent("flow", "Flow", 30), .percent("softness", "Softness", 80)]
        case .oil:
            own = [.percent("load", "Load", 70), .percent("smear", "Smear", 40)]
        case .watercolour:
            own = [.percent("wetness", "Wetness", 60), .percent("bleed", "Bleed", 40)]
        }
        return shared + own
    }

    func spec(_ id: String) -> BrushSettingSpec? { settings.first { $0.id == id } }
}

/// One setting a medium declares: its id (what MCP and the store say), its
/// plain name, the values it may take and where it starts.
public struct BrushSettingSpec: Hashable, Sendable {
    public var id: String
    public var name: String
    public var range: ClosedRange<Double>
    public var defaultValue: Double
    /// For a setting that is a choice rather than a number: the choices, in
    /// order, whose index is the value (a marker's Round or Chisel tip).
    public var options: [String]?

    public init(id: String, name: String, range: ClosedRange<Double>, defaultValue: Double,
                options: [String]? = nil) {
        self.id = id
        self.name = name
        self.range = range
        self.defaultValue = defaultValue
        self.options = options
    }

    static func percent(_ id: String, _ name: String, _ value: Double) -> BrushSettingSpec {
        BrushSettingSpec(id: id, name: name, range: 0...100, defaultValue: value)
    }

    func clamp(_ value: Double) -> Double {
        let bounded = min(max(value, range.lowerBound), range.upperBound)
        return options == nil ? bounded : bounded.rounded()
    }
}

/// A brush: a medium and a value for each of its settings, always inside the
/// medium's ranges. Copied into every stroke, so changing the armed brush later
/// never repaints what was already painted.
public struct BrushSettings: Hashable, Codable, Sendable {
    public var medium: BrushMedium
    public private(set) var values: [String: Double]

    public init(medium: BrushMedium, values: [String: Double] = [:]) {
        self.medium = medium
        var filled: [String: Double] = [:]
        for spec in medium.settings {
            filled[spec.id] = spec.clamp(values[spec.id] ?? spec.defaultValue)
        }
        self.values = filled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Re-clamped on the way in, so a hand-edited file or one written by a
        // later version with a wider range still renders inside today's.
        self.init(medium: try c.decode(BrushMedium.self, forKey: .medium),
                  values: try c.decodeIfPresent([String: Double].self, forKey: .values) ?? [:])
    }

    /// The value of one setting, or its default if somehow missing; zero for
    /// an id the medium does not have.
    public func value(_ id: String) -> Double {
        values[id] ?? medium.spec(id)?.defaultValue ?? 0
    }

    /// Sets one setting, clamped to its range. An id the medium does not have
    /// is ignored rather than stored.
    public mutating func set(_ id: String, to value: Double) {
        guard let spec = medium.spec(id), value.isFinite else { return }
        values[id] = spec.clamp(value)
    }

    /// The same brush in another medium: Size and Opacity carry over, the new
    /// medium's own settings start at its defaults.
    public func switched(to medium: BrushMedium) -> BrushSettings {
        BrushSettings(medium: medium, values: ["size": size, "opacity": opacity])
    }

    /// The tip's diameter, in points.
    public var size: Double { value("size") }
    /// How opaque a stroke is, 1 to 100.
    public var opacity: Double { value("opacity") }
}

// MARK: - A stroke as data

/// One reading of the pointer while painting, in the layer's own top-left
/// points. Pressure and tilt are nil for a device that has none (a mouse);
/// nothing reads them yet, they are recorded so the dynamics slice only has to
/// add what they do.
public struct StrokeSample: Hashable, Codable, Sendable {
    public var point: CGPoint
    /// 0...1 from a tablet or pencil, nil for a mouse.
    public var pressure: Double?
    /// The pen's tilt, each axis -1...1, nil where the device has none.
    public var tilt: CGPoint?
    /// Milliseconds since the stroke began.
    public var ms: Double

    public init(point: CGPoint, pressure: Double? = nil, tilt: CGPoint? = nil, ms: Double) {
        self.point = point
        self.pressure = pressure
        self.tilt = tilt
        self.ms = ms
    }
}

/// One painted stroke: where the pointer went, the brush it was painted with,
/// its colour, and the seed every random choice the engine makes is drawn from,
/// so it looks the same on every render.
public struct BrushStroke: Hashable, Codable, Sendable {
    public var samples: [StrokeSample]
    public var settings: BrushSettings
    public var colorHex: String
    public var seed: UInt32

    public init(samples: [StrokeSample], settings: BrushSettings, colorHex: String, seed: UInt32) {
        self.samples = samples
        self.settings = settings
        self.colorHex = colorHex
        self.seed = seed
    }

    /// The same stroke with every sample moved, for carrying it between the
    /// canvas's space and a layer's own.
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> BrushStroke {
        var moved = self
        moved.samples = samples.map { sample in
            var sample = sample
            sample.point = CGPoint(x: sample.point.x + dx, y: sample.point.y + dy)
            return sample
        }
        return moved
    }

    /// The box the stroke can paint in: its samples, reached out by half the
    /// tip on every side. Null for a stroke with no samples.
    public var bounds: CGRect {
        guard let first = samples.first?.point else { return .null }
        var box = CGRect(origin: first, size: .zero)
        for sample in samples.dropFirst() { box = box.union(CGRect(origin: sample.point, size: .zero)) }
        let reach = settings.size / 2
        return box.insetBy(dx: -reach, dy: -reach)
    }
}

/// A painted layer's content: its strokes, oldest first, the order they paint.
public struct PaintContent: Hashable, Codable, Sendable {
    public var strokes: [BrushStroke]

    public init(strokes: [BrushStroke] = []) {
        self.strokes = strokes
    }

    /// The name a new paint layer is given.
    public static let layerName = "Paint"
}

extension Layer {
    /// The layer's paint, nil for other kinds of content.
    public var paint: PaintContent? {
        if case .paint(let paint) = content { return paint }
        return nil
    }
}

// MARK: - Where the dabs go

/// One mark of the tip along a stroke, in the stroke's own points.
public struct BrushDab: Hashable, Sendable {
    public var center: CGPoint
    public var diameter: CGFloat
    /// 0...1.
    public var opacity: Double
    /// Radians, for tips that are not round.
    public var angle: Double

    public init(center: CGPoint, diameter: CGFloat, opacity: Double, angle: Double = 0) {
        self.center = center
        self.diameter = diameter
        self.opacity = opacity
        self.angle = angle
    }
}

/// Works out where a stroke's dabs go: along a smooth curve through its
/// samples, evenly spaced at a fraction of the tip, each with its size and
/// opacity and any jitter, drawn from the stroke's seed (decision 4).
public enum BrushPlacement {

    /// The distance between dabs for a tip, in points: a tenth of the tip, so
    /// a soft round reads as one smooth line, and never less than a quarter
    /// point however small the tip.
    public static func spacing(forDiameter diameter: CGFloat) -> CGFloat {
        max(0.25, diameter * 0.1)
    }

    /// Every dab of a finished stroke. `jitter` moves each dab off the line by
    /// up to that fraction of its radius.
    public static func dabs(for stroke: BrushStroke, jitter: CGFloat = 0) -> [BrushDab] {
        var walker = Walker(settings: stroke.settings, seed: stroke.seed, jitter: jitter)
        var dabs: [BrushDab] = []
        for sample in stroke.samples { dabs += walker.add(sample) }
        dabs += walker.finish()
        return dabs
    }

    /// The same placement, one sample at a time, for the live stroke: what it
    /// hands back as the pointer moves, plus `finish()`, is exactly
    /// `dabs(for:)` of the finished stroke, so what lands is what was seen.
    ///
    /// It runs one sample behind: the curve through a sample bends according
    /// to the sample after it, so a span is only placed once the next sample
    /// has arrived (one mouse event, a few milliseconds).
    public struct Walker: Sendable {
        let diameter: CGFloat
        let opacity: Double
        let gap: CGFloat
        let jitter: CGFloat
        private var random: SeededRandom
        private var points: [CGPoint] = []
        /// How far along the path the next dab is due, from the last one.
        private var untilNext: CGFloat = 0

        public init(settings: BrushSettings, seed: UInt32, jitter: CGFloat = 0) {
            diameter = CGFloat(settings.size)
            opacity = settings.opacity / 100
            gap = BrushPlacement.spacing(forDiameter: diameter)
            self.jitter = max(0, jitter)
            random = SeededRandom(seed: seed, salt: 0xB2C5)
        }

        /// Takes the next sample and hands back the dabs it settled.
        public mutating func add(_ sample: StrokeSample) -> [BrushDab] {
            let point = sample.point
            // A sample on top of the last one adds nothing to the curve.
            if let last = points.last, last == point { return [] }
            points.append(point)
            var dabs: [BrushDab] = []
            if points.count == 1 {
                dabs.append(dab(at: point))
                untilNext = gap
                return dabs
            }
            // Place the span ending at the sample BEFORE this one, now that
            // the curve's direction through it is known.
            if points.count >= 3 { walkSpan(from: points.count - 3, into: &dabs) }
            if points.count > 4 { points.removeFirst() }
            return dabs
        }

        /// The stroke is over: places the last span, which has no sample after
        /// it to bend toward, and a last dab on the very end so the stroke
        /// reaches where the pointer let go rather than stopping short of it.
        public mutating func finish() -> [BrushDab] {
            var dabs: [BrushDab] = []
            guard points.count >= 2, let end = points.last else { return dabs }
            walkSpan(from: points.count - 2, into: &dabs)
            if untilNext < gap { dabs.append(dab(at: end)) }
            return dabs
        }

        /// Walks the curve from `points[k]` to `points[k + 1]` (Catmull-Rom
        /// through its neighbours, an end standing in for a missing one),
        /// dropping a dab every `gap` along it.
        private mutating func walkSpan(from k: Int, into dabs: inout [BrushDab]) {
            let p1 = points[k], p2 = points[k + 1]
            let p0 = k > 0 ? points[k - 1] : p1
            let p3 = k + 2 < points.count ? points[k + 2] : p2
            let length = hypot(p2.x - p1.x, p2.y - p1.y)
            guard length > 0 else { return }
            // Enough pieces that each is well under a dab apart.
            let pieces = max(1, Int((length / max(gap * 0.5, 0.5)).rounded(.up)))
            var previous = p1
            for step in 1...pieces {
                let t = CGFloat(step) / CGFloat(pieces)
                let next = step == pieces ? p2 : catmullRom(p0, p1, p2, p3, t)
                var segment = hypot(next.x - previous.x, next.y - previous.y)
                var from = previous
                while segment >= untilNext {
                    let f = untilNext / segment
                    let at = CGPoint(x: from.x + (next.x - from.x) * f,
                                     y: from.y + (next.y - from.y) * f)
                    dabs.append(dab(at: at))
                    segment -= untilNext
                    from = at
                    untilNext = gap
                }
                untilNext -= segment
                previous = next
            }
        }

        private mutating func dab(at point: CGPoint) -> BrushDab {
            var center = point
            if jitter > 0 {
                let radius = diameter / 2 * jitter * random.unit().squareRoot()
                let angle = random.range(0, 2 * .pi)
                center.x += cos(angle) * radius
                center.y += sin(angle) * radius
            }
            return BrushDab(center: center, diameter: diameter, opacity: opacity)
        }

        private func catmullRom(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint,
                                _ t: CGFloat) -> CGPoint {
            let t2 = t * t, t3 = t2 * t
            func axis(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2
                       + (-a + 3 * b - 3 * c + d) * t3)
            }
            return CGPoint(x: axis(p0.x, p1.x, p2.x, p3.x), y: axis(p0.y, p1.y, p2.y, p3.y))
        }
    }
}

// MARK: - Where a stroke lands

extension PhotonzDocument {

    /// Paints `stroke` (in canvas points) into the document and returns the
    /// layer it went onto (decision 2).
    ///
    /// With an unlocked paint layer picked, the stroke is added to it. Anything
    /// else picked, the stroke makes a new layer named Paint just above it;
    /// nothing picked, on top. A new Paint layer is the size of the frame the
    /// stroke starts on, or of the canvas, and joins that frame. Never into a
    /// picture's own pixels: the picture underneath is left exactly as it was.
    @discardableResult
    public mutating func paintStroke(_ stroke: BrushStroke, onto pickedID: UUID?) -> UUID {
        if let pickedID, let picked = layer(id: pickedID), picked.paint != nil, !picked.isLocked,
           let origin = canvasBounds(of: pickedID)?.origin {
            let local = stroke.offsetBy(dx: -origin.x, dy: -origin.y)
            updateLayer(id: pickedID) { layer in
                guard case .paint(var paint) = layer.content else { return }
                paint.strokes.append(local)
                layer.content = .paint(paint)
            }
            return pickedID
        }
        let start = stroke.samples.first?.point ?? .zero
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let box = frameID(under: start).flatMap { canvasBounds(of: $0) } ?? canvas
        let local = stroke.offsetBy(dx: -box.minX, dy: -box.minY)
        let layer = Layer(name: PaintContent.layerName,
                          content: .paint(PaintContent(strokes: [local])), frame: box)
        if let pickedID, self.layer(id: pickedID) != nil, insertLayer(layer, .above(pickedID)) {
            return layer.id
        }
        addLayerDrawnOnFrame(layer)
        return layer.id
    }
}

// MARK: - Paint moved, reflected and restated

extension PaintContent {

    /// Every stroke's samples carried through `transform` (a reflection, a
    /// magnification). The tips stay the size they were.
    public func transformed(by transform: CGAffineTransform) -> PaintContent {
        PaintContent(strokes: strokes.map { stroke in
            var stroke = stroke
            stroke.samples = stroke.samples.map { sample in
                var sample = sample
                sample.point = sample.point.applying(transform)
                return sample
            }
            return stroke
        })
    }

    /// The paint with every tip `factor` times the size, leaving where the
    /// strokes run alone.
    public func tipsScaled(by factor: CGFloat) -> PaintContent {
        PaintContent(strokes: strokes.map { stroke in
            var stroke = stroke
            stroke.settings.set("size", to: stroke.settings.size * Double(factor))
            return stroke
        })
    }

    /// The paint restated for a picture `scale` times the size: where the
    /// strokes run and how big their tips are.
    public func rescaled(by scale: CGFloat) -> PaintContent {
        transformed(by: CGAffineTransform(scaleX: scale, y: scale)).tipsScaled(by: scale)
    }

    /// Every stroke repainted in one colour, which is what the paint bucket
    /// pointed at a paint layer means.
    public func recoloured(_ hex: String) -> PaintContent {
        PaintContent(strokes: strokes.map { stroke in
            var stroke = stroke
            stroke.colorHex = hex
            return stroke
        })
    }
}
