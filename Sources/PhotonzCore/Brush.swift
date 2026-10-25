import CoreGraphics
import Foundation

// The Brush's model (`docs/design/brushes.md`): what a painted stroke IS, kept
// as data rather than pixels so undo stays a small snapshot and the agent's
// stroke and a person's are the same value. Marking (turning dabs into paint)
// lives in PhotonzRender; this file decides where the dabs go.

// MARK: - Media and their settings

/// One of the brush's eight media. Each declares the settings it has, so the
/// tool options, the panel, MCP and the tests all read one list (decision 7).
/// Listed the way they are offered: the sketching media first, Pencil leading.
public enum BrushMedium: String, CaseIterable, Codable, Hashable, Sendable {
    case pencil
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
        case .pencil: "Pencil"
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
        case .pencil: 3
        case .charcoal: 16
        case .chalk: 20
        case .crayon: 10
        case .marker: 14
        case .airbrush: 40
        case .oil: 24
        case .watercolour: 30
        }
    }

    /// How far past half its Size a stroke of this medium can mark, as a
    /// multiple: a pencil laid on its side shades a band several times as wide
    /// as its point, watercolour bleeds and blooms well past where the brush
    /// went, and a hard press or a lean widens most media past their Size
    /// (`BrushDynamics`). One for a medium whose tip never leaves its Size.
    public var reach: Double {
        let response = BrushDynamics.response(for: self)
        let pressed = response.size(pressure: 1)
        switch self {
        case .pencil: return 7
        case .watercolour: return 4.5 * pressed
        default:
            // The tip's own edge breaks past its radius a little, and the
            // side laid down reaches along the lean.
            return pressed * (1 + response.side.long) * (response.side.long > 0 ? 1.2 : 1)
        }
    }

    /// The pencil grades Hardness picks from, hard and pale to soft and dark.
    public static let pencilGrades = ["4H", "2H", "HB", "2B", "4B", "6B", "8B"]

    /// Every setting this medium has, in the order they are shown: Size and
    /// Opacity first, then the medium's own (the design doc's table).
    public var settings: [BrushSettingSpec] {
        let shared = [
            BrushSettingSpec(id: "size", name: "Size", range: BrushSize.range, defaultValue: defaultSize),
            BrushSettingSpec(id: "opacity", name: "Opacity", range: 1...100, defaultValue: 100),
        ]
        let own: [BrushSettingSpec]
        switch self {
        case .pencil:
            own = [BrushSettingSpec(id: "hardness", name: "Hardness",
                                    range: 0...Double(Self.pencilGrades.count - 1), defaultValue: 2,
                                    options: Self.pencilGrades),
                   .percent("grain", "Grain", 50), .percent("tilt", "Tilt Shading", 60)]
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
            // Flow is how hard it sprays, Spread how wide the mist reaches
            // out from the line, Droplet Size fine mist to coarse spatter,
            // Build-up how fast a held spray piles up.
            own = [.percent("flow", "Flow", 40), .percent("spread", "Spread", 55),
                   .percent("droplet", "Droplet Size", 25), .percent("buildup", "Build-up", 50)]
        case .oil:
            own = [.percent("load", "Load", 70), .percent("smear", "Smear", 40)]
        case .watercolour:
            own = [.percent("wetness", "Wetness", 60), .percent("bleed", "Bleed", 40),
                   .percent("granulation", "Granulation", 25)]
        }
        return shared + own
    }

    /// The medium's own settings, after Size and Opacity.
    public var ownSettings: [BrushSettingSpec] { Array(settings.dropFirst(2)) }

    /// The two of its own the tool options capsule over the tool bar carries
    /// beside Size and Opacity: the first two, the ones the medium is most
    /// often tuned by. The panel's Brush section carries every one.
    public var toolOptionSettings: [BrushSettingSpec] { Array(ownSettings.prefix(2)) }

    func spec(_ id: String) -> BrushSettingSpec? { settings.first { $0.id == settingID(id) } }

    /// The id a setting goes by now, for one it used to go by: the airbrush's
    /// Softness became its Spread (2026-10-25), so a stroke saved before, or a
    /// caller still saying softness, keeps its value.
    func settingID(_ id: String) -> String {
        switch (self, id) {
        case (.airbrush, "softness"): "spread"
        default: id
        }
    }
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

    /// What kind of control sets it: a number is a slider; two or three
    /// choices stay on screen side by side; more are a dropdown (UX-PATTERNS:
    /// a list of more than three exclusive options is a dropdown).
    public enum Control: Hashable, Sendable {
        case slider
        case segmented
        case dropdown
    }

    public var control: Control {
        guard let options else { return .slider }
        return options.count <= 3 ? .segmented : .dropdown
    }

    /// The setting as it reads beside its control: a choice by its word,
    /// Size in points, the rest as a percentage.
    public func reading(_ value: Double) -> String {
        let whole = Int(value.rounded())
        if let options { return options.indices.contains(whole) ? options[whole] : "" }
        return id == "size" ? "\(whole) pt" : "\(whole)%"
    }

    func clamp(_ value: Double) -> Double {
        let bounded = min(max(value, range.lowerBound), range.upperBound)
        return options == nil ? bounded : bounded.rounded()
    }
}

/// What a stroke does: lays down the medium, or drags what is already painted
/// along with the tip like a finger (decision 7: smudge is a mode of the brush,
/// using the picked medium's tip, so "switch to charcoal and smudge" is one
/// step).
public enum BrushMode: String, CaseIterable, Codable, Hashable, Sendable {
    case paint
    case smudge

    /// What the mode is called on screen.
    public var title: String {
        switch self {
        case .paint: "Paint"
        case .smudge: "Smudge"
        }
    }
}

/// A brush: a medium and a value for each of its settings, always inside the
/// medium's ranges. Copied into every stroke, so changing the armed brush later
/// never repaints what was already painted.
public struct BrushSettings: Hashable, Codable, Sendable {
    public var medium: BrushMedium
    public private(set) var values: [String: Double]
    /// Whether a stroke paints or smudges.
    public var mode: BrushMode

    public init(medium: BrushMedium, values: [String: Double] = [:], mode: BrushMode = .paint) {
        self.medium = medium
        var given: [String: Double] = [:]
        // A value under a setting's former id counts, unless its new id is given too.
        for (id, value) in values where medium.settingID(id) != id { given[medium.settingID(id)] = value }
        given.merge(values) { $1 }
        var filled: [String: Double] = [:]
        for spec in medium.settings {
            filled[spec.id] = spec.clamp(given[spec.id] ?? spec.defaultValue)
        }
        self.values = filled
        self.mode = mode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Re-clamped on the way in, so a hand-edited file or one written by a
        // later version with a wider range still renders inside today's. A
        // stroke from before the mode existed painted.
        self.init(medium: try c.decode(BrushMedium.self, forKey: .medium),
                  values: try c.decodeIfPresent([String: Double].self, forKey: .values) ?? [:],
                  mode: try c.decodeIfPresent(BrushMode.self, forKey: .mode) ?? .paint)
    }

    /// The value of one setting, or its default if somehow missing; zero for
    /// an id the medium does not have.
    public func value(_ id: String) -> Double {
        values[medium.settingID(id)] ?? medium.spec(id)?.defaultValue ?? 0
    }

    /// Sets one setting, clamped to its range. An id the medium does not have
    /// is ignored rather than stored.
    public mutating func set(_ id: String, to value: Double) {
        guard let spec = medium.spec(id), value.isFinite else { return }
        values[spec.id] = spec.clamp(value)
    }

    /// The same brush in another medium: Size, Opacity and the mode carry
    /// over, the new medium's own settings start at its defaults.
    public func switched(to medium: BrushMedium) -> BrushSettings {
        BrushSettings(medium: medium, values: ["size": size, "opacity": opacity], mode: mode)
    }

    /// The tip's diameter, in points.
    public var size: Double { value("size") }
    /// How opaque a stroke is, 1 to 100.
    public var opacity: Double { value("opacity") }
}

/// How [ and ] step the brush's size: Photoshop's steps, finer for a small
/// tip and coarser for a big one, so a few presses reach any size and each
/// press at a small size is still a visible change.
public enum BrushSize {
    /// Where the step size changes, and the step below each.
    private static let bands: [(below: Double, step: Double)] = [
        (10, 1), (50, 5), (100, 10), (200, 25), (300, 50), (.infinity, 100),
    ]

    public static let range: ClosedRange<Double> = 1...500

    /// The next size up (]) or down ([) from `size`, landing on a whole step
    /// and held inside `range`.
    public static func stepped(_ size: Double, larger: Bool) -> Double {
        guard size.isFinite else { return range.lowerBound }
        let next: Double
        if larger {
            let step = bands.first { size < $0.below }?.step ?? 100
            next = (size / step + 1e-9).rounded(.down) * step + step
        } else {
            let step = bands.first { size <= $0.below }?.step ?? 100
            next = (size / step - 1e-9).rounded(.up) * step - step
        }
        return min(max(next, range.lowerBound), range.upperBound)
    }
}

// MARK: - A stroke as data

/// One reading of the pointer while painting, in the layer's own top-left
/// points. Pressure and tilt are nil for a device that has none (a mouse):
/// placement then simulates a press and a taper (`BrushDynamics`). Every
/// medium reads them its own way (`BrushDynamics.response(for:)`).
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
/// its colour, the seed every random choice the engine makes is drawn from, so
/// it looks the same on every render, and when it was painted.
public struct BrushStroke: Hashable, Codable, Sendable {
    public var samples: [StrokeSample]
    public var settings: BrushSettings
    public var colorHex: String
    public var seed: UInt32
    /// When the stroke began, in seconds on the wall clock (any fixed epoch;
    /// the canvas uses the reference date). Watercolour reads it to know which
    /// earlier strokes are still wet (`wetness(when:)`), and because it is
    /// stored, a replay blooms exactly where the first render did. Nil for a
    /// stroke painted before strokes had a time: it reads as long dry.
    public var startedAt: Double?

    public init(samples: [StrokeSample], settings: BrushSettings, colorHex: String, seed: UInt32,
                startedAt: Double? = nil) {
        self.samples = samples
        self.settings = settings
        self.colorHex = colorHex
        self.seed = seed
        self.startedAt = startedAt
    }

    /// When the pointer came up, in the same seconds as `startedAt`.
    public var endedAt: Double? {
        startedAt.map { $0 + (samples.last?.ms ?? 0) / 1000 }
    }

    /// How wet this stroke's paint still is when `later` begins: 1 while it is
    /// being painted or just finished, falling to 0 by its drying time
    /// (`WatercolourDrying`). Zero for anything but watercolour paint, and
    /// for either stroke without a time.
    public func wetness(when later: BrushStroke) -> Double {
        guard settings.medium == .watercolour, settings.mode == .paint,
              let ended = endedAt, let begins = later.startedAt else { return 0 }
        let drying = WatercolourDrying.seconds(wetness: settings.value("wetness"))
        return min(1, max(0, 1 - (begins - ended) / drying))
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
        let reach = settings.size / 2 * settings.medium.reach
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

/// How long a watercolour stroke stays wet after the brush lifts: a few
/// seconds, longer the wetter the brush (Wetness 0...100). Long enough to drop
/// a second colour into a wash, the way a watercolourist works wet into wet,
/// and short enough that a stroke laid a little later glazes over a dry one.
public enum WatercolourDrying {
    public static func seconds(wetness: Double) -> Double {
        1.5 + 6.5 * min(1, max(0, wetness / 100))
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
    /// How hard the tip pressed here, 0...1: the pen's own reading, eased
    /// between its samples, or a mouse's simulated press.
    public var pressure: Double
    /// The pen's lean here, each axis -1...1; zero standing upright, which is
    /// how a mouse always paints.
    public var tilt: CGPoint
    /// The share of its paint the dab lays, 0...1: an airbrush sprays by
    /// time, so a dab on a fast pass, over in a moment, lays less than one on
    /// a slow pass or held still. 1 for every other medium.
    public var spray: Double
    /// How heavily the dab marks against the medium's own weight: the press
    /// and the taper of a stroke's ends, around 1 (a pen pressed hard can go
    /// a little past it). The diameter already carries the press's width.
    public var weight: Double
    /// How far along the stroke's path the dab is, in points from where it
    /// touched down: what the taper of its ends is read from.
    public var along: Double

    public init(center: CGPoint, diameter: CGFloat, opacity: Double, angle: Double = 0,
                pressure: Double = 1, tilt: CGPoint = .zero, spray: Double = 1, weight: Double = 1,
                along: Double = 0) {
        self.center = center
        self.diameter = diameter
        self.opacity = opacity
        self.angle = angle
        self.pressure = pressure
        self.tilt = tilt
        self.spray = spray
        self.weight = weight
        self.along = along
    }
}

/// How the hand shapes a stroke (decision 6): a pen's press, its lean and its
/// speed, and for a pointer with no pressure of its own (a mouse) a simulated
/// press and a taper at both ends.
///
/// A mouse stroke touches down lightly and settles to a steady middle press
/// over its first few points, presses lighter the faster it moves, swells in
/// from a narrow point and, once the pointer lifts, thins out again over its
/// last stretch. The live stroke cannot know where it ends, so the taper out
/// is laid when the stroke lands (`BrushPlacement.taperedOut`): the end of the
/// line visibly draws in as it lands, the way a finger's taper does in other
/// paint apps.
public enum BrushDynamics {

    /// The press a mouse settles to, and the press every medium's response is
    /// measured from: pressed like this, a stroke is exactly its Size and its
    /// medium's own weight, so what a mouse paints is what the Size says.
    public static let steadyPress = 0.64

    /// The press of a mouse moving `speed` points a millisecond, `travelled`
    /// points into a stroke whose tip is `diameter` points across. 0...1.
    public static func mousePressure(speed: Double, travelled: Double, diameter: Double) -> Double {
        let settle = smooth(0, max(6, diameter * 3), travelled)
        let press = 0.38 + (steadyPress - 0.38) * settle
        let thinned = press * (1 - 0.4 * smooth(0.4, 3, speed))
        return min(1, max(0.1, thinned))
    }

    /// How a medium answers the hand, the design doc's table: what a press
    /// does to its width and its weight, how much a fast pen thins it, how
    /// far a mouse stroke's ends taper, and what a lean lays down.
    public struct Response: Hashable, Sendable {
        /// The width at no press at all, as a share of the width at a full
        /// press; 1 when the press does not change the width.
        public var sizeFloor: Double
        /// The same for the weight: how dark or dense it lays.
        public var weightFloor: Double
        /// How much a pen moving fast narrows the line, 0...1 at a quick
        /// 4 points a millisecond.
        public var speedThinning: Double
        /// How far a mouse stroke's ends narrow: 0.7 starts and ends the line
        /// at three tenths of its width.
        public var taperDepth: Double
        /// What leaning the pen does.
        public var side: Side

        /// The width a press gives, as a multiple of the Size: exactly 1 at
        /// the steady press.
        public func size(pressure: Double) -> Double {
            Self.factor(sizeFloor, pressure)
        }

        /// The weight a press gives, as a multiple of the medium's own: 1 at
        /// the steady press.
        public func weight(pressure: Double) -> Double {
            Self.factor(weightFloor, pressure)
        }

        private static func factor(_ floor: Double, _ pressure: Double) -> Double {
            let p = min(1, max(0, pressure))
            return (floor + (1 - floor) * p) / (floor + (1 - floor) * steadyPress)
        }
    }

    /// What a lean lays down: a stick on its side marks a patch `long` radii
    /// further along the lean and `short` further across it, at `pale` less
    /// weight (a press spread over more paper). A round marker nib leaned
    /// broadens the same way; a chisel nib also turns to the lean
    /// (`turnsNib`). All zero for a medium a lean does not change.
    public struct Side: Hashable, Sendable {
        public var long: Double
        public var short: Double
        public var pale: Double
        public var turnsNib: Bool

        public static let none = Side(long: 0, short: 0, pale: 0, turnsNib: false)
    }

    /// Each medium's response. The pencil's press and lean are its own
    /// (`DryLook`, its grades and Tilt Shading), so its width and weight read
    /// flat here and only the taper and a fast pen shape it. The airbrush
    /// already sprays by the press and the pass's speed, and its spray has no
    /// blunt end to taper. Oil's press is its load and watercolour's is the
    /// belly of a round brush spreading.
    public static func response(for medium: BrushMedium) -> Response {
        switch medium {
        case .pencil:
            Response(sizeFloor: 1, weightFloor: 1, speedThinning: 0.25, taperDepth: 0.55, side: .none)
        case .charcoal:
            Response(sizeFloor: 0.4, weightFloor: 0.3, speedThinning: 0.3, taperDepth: 0.75,
                     side: Side(long: 1.6, short: 0.5, pale: 0.3, turnsNib: false))
        case .chalk:
            Response(sizeFloor: 0.5, weightFloor: 0.4, speedThinning: 0.3, taperDepth: 0.65,
                     side: Side(long: 1.7, short: 0.5, pale: 0.15, turnsNib: false))
        case .crayon:
            Response(sizeFloor: 0.75, weightFloor: 0.3, speedThinning: 0.2, taperDepth: 0.5, side: .none)
        case .marker:
            Response(sizeFloor: 0.8, weightFloor: 1, speedThinning: 0.1, taperDepth: 0.35,
                     side: Side(long: 0.6, short: 0, pale: 0, turnsNib: true))
        case .airbrush:
            Response(sizeFloor: 1, weightFloor: 1, speedThinning: 0, taperDepth: 0, side: .none)
        case .oil:
            Response(sizeFloor: 0.7, weightFloor: 1, speedThinning: 0.15, taperDepth: 0.3, side: .none)
        case .watercolour:
            Response(sizeFloor: 0.3, weightFloor: 1, speedThinning: 0.3, taperDepth: 0.8, side: .none)
        }
    }

    /// The response a brush paints with: its medium's, except that a smudge
    /// is a finger, the same width end to end however it is pressed.
    public static func response(for settings: BrushSettings) -> Response {
        guard settings.mode == .paint else {
            return Response(sizeFloor: 1, weightFloor: 1, speedThinning: 0, taperDepth: 0, side: .none)
        }
        return response(for: settings.medium)
    }

    /// How much a pen moving `speed` points a millisecond narrows a line
    /// that thins by `thinning`: not at all slow, the whole of it by a quick
    /// 4. A mouse's press already carries its speed.
    public static func penThinning(speed: Double, thinning: Double) -> Double {
        1 - thinning * smooth(0.5, 4, speed)
    }

    /// How far a lean of `tilt` (each axis -1...1) lays the side down, 0...1,
    /// and which way: upright and a slight lean are 0, a lean of 0.8 or more
    /// is all of it.
    public static func lean(_ tilt: CGPoint) -> (amount: Double, axis: CGVector) {
        let leaning = Double(hypot(tilt.x, tilt.y))
        let amount = smooth(0.12, 0.8, leaning)
        guard amount > 0.01, leaning > 0 else { return (0, CGVector(dx: 1, dy: 0)) }
        return (amount, CGVector(dx: tilt.x / CGFloat(leaning), dy: tilt.y / CGFloat(leaning)))
    }

    /// How long a mouse stroke's taper runs, in points, for a tip `diameter`
    /// across: a few tip widths, never so short a thin line has none.
    public static func taperLength(diameter: Double) -> Double {
        min(60, max(10, diameter * 2))
    }

    /// The width a mouse stroke has `distance` points from one of its ends,
    /// as a share of its full width: `1 - depth` at the end, swelling to all
    /// of it a taper's length in.
    public static func taper(distance: Double, diameter: Double, depth: Double) -> Double {
        1 - depth * (1 - smooth(0, taperLength(diameter: diameter), distance))
    }

    /// What a taper of `width` (a share of the full width) does to the weight:
    /// the ends lighten as well as narrow, the way a hand lifts off.
    public static func taperWeight(_ width: Double) -> Double {
        (1 + width) / 2
    }

    /// How quickly the speed a press is read from follows the pointer: a
    /// share of each new reading, so one jittery event does not flicker it.
    static let speedEase = 0.3

    private static func smooth(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
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

    /// How often an airbrush held still lays another dab, in milliseconds,
    /// at the default Build-up: the spray keeps coming while the trigger is
    /// down, so paint builds up over one spot the longer the pointer stays
    /// there (decision 4).
    public static let dwellInterval: Double = 40

    /// How often a held airbrush lays another dab at a Build-up of 0...100:
    /// twice as often at 100 as at the default 50, and never at 0, where the
    /// spray lays only what a pass does.
    public static func dwellInterval(buildUp: Double) -> Double? {
        let b = min(100, max(0, buildUp))
        return b < 1 ? nil : dwellInterval * 50 / b
    }

    /// The share of its paint an airbrush dab lays on a pass at `speed`
    /// points a millisecond: all of it slow, about half at a brisk 2, never
    /// under a quarter however fast, so a fast pass is a light veil and never
    /// a broken line.
    public static func spray(speed: Double) -> Double {
        max(0.25, 1 / (1 + 0.5 * max(0, speed)))
    }

    /// Every dab of a finished stroke. `jitter` moves each dab off the line by
    /// up to that fraction of its radius.
    public static func dabs(for stroke: BrushStroke, jitter: CGFloat = 0) -> [BrushDab] {
        var walker = Walker(settings: stroke.settings, seed: stroke.seed, jitter: jitter)
        var dabs: [BrushDab] = []
        for sample in stroke.samples { dabs += walker.add(sample) }
        dabs += walker.finish()
        return taperedOut(dabs, for: stroke)
    }

    /// A mouse stroke's dabs with the end of it thinned out (decision 6), now
    /// that it is known where it ends: each dab narrows to the lesser of the
    /// taper from where it touched down, which it already has, and the taper
    /// from where it lifted. A pen's stroke is handed back as it is, since its
    /// own press lifts off.
    public static func taperedOut(_ dabs: [BrushDab], for stroke: BrushStroke) -> [BrushDab] {
        let depth = BrushDynamics.response(for: stroke.settings).taperDepth
        guard stroke.samples.first?.pressure == nil, depth > 0, let end = dabs.last?.along else { return dabs }
        let size = stroke.settings.size
        return dabs.map { dab in
            let fromStart = BrushDynamics.taper(distance: dab.along, diameter: size, depth: depth)
            let fromEnd = BrushDynamics.taper(distance: end - dab.along, diameter: size, depth: depth)
            guard fromEnd < fromStart else { return dab }
            var dab = dab
            dab.diameter *= CGFloat(fromEnd / fromStart)
            dab.weight *= BrushDynamics.taperWeight(fromEnd) / BrushDynamics.taperWeight(fromStart)
            return dab
        }
    }

    /// The same placement, one sample at a time, for the live stroke: what it
    /// hands back as the pointer moves, plus `finish()`, is `dabs(for:)` of
    /// the finished stroke before a mouse stroke's end is thinned
    /// (`taperedOut`), so what lands is what was seen up to the last stretch.
    ///
    /// It runs one sample behind: the curve through a sample bends according
    /// to the sample after it, so a span is only placed once the next sample
    /// has arrived (one mouse event, a few milliseconds).
    public struct Walker: Sendable {
        let diameter: CGFloat
        let opacity: Double
        let gap: CGFloat
        let jitter: CGFloat
        /// How the medium answers the press, the lean and the speed.
        let response: BrushDynamics.Response
        private var random: SeededRandom
        private var points: [CGPoint] = []
        /// Each point's press and lean, and how much a pen's speed thins it
        /// there, kept beside it.
        private var pressures: [Double] = []
        private var tilts: [CGPoint] = []
        private var thins: [Double] = []
        /// Whether the press is simulated (a mouse: its first sample had no
        /// pressure), which is what swells its start in.
        private var simulated: Bool?
        /// How far along the path the next spaced dab is.
        private var along: Double = 0
        /// What a mouse's press is read from: how fast it has been moving
        /// (eased), how far it has come, and when its last sample was.
        private var speed: Double = 0
        private var travelled: Double = 0
        private var lastMs: Double?
        /// How far along the path the next dab is due, from the last one.
        private var untilNext: CGFloat = 0
        /// Whether this brush keeps laying dabs while the pointer holds still
        /// (the airbrush), and, for one that does: where the pointer has been
        /// staying, when it was last read there, and the time owed toward the
        /// next dab.
        let dwells: Bool
        /// How often a held spray lays a dab, nil for one that does not.
        let interval: Double?
        private var stay: CGPoint?
        private var stayMs: Double = 0
        private var dwellOwed: Double = 0

        public init(settings: BrushSettings, seed: UInt32, jitter: CGFloat = 0) {
            diameter = CGFloat(settings.size)
            opacity = settings.opacity / 100
            gap = BrushPlacement.spacing(forDiameter: diameter)
            dwells = settings.medium == .airbrush
            response = BrushDynamics.response(for: settings)
            interval = dwells ? BrushPlacement.dwellInterval(buildUp: settings.value("buildup")) : nil
            self.jitter = max(0, jitter)
            random = SeededRandom(seed: seed, salt: 0xB2C5)
        }

        /// Takes the next sample and hands back the dabs it settled.
        public mutating func add(_ sample: StrokeSample) -> [BrushDab] {
            let point = sample.point
            var dabs = dwells ? held(sample) : []
            // A sample on top of the last one adds nothing to the curve.
            if let last = points.last, last == point { return dabs }
            if let last = points.last {
                let distance = Double(hypot(point.x - last.x, point.y - last.y))
                travelled += distance
                if let lastMs, sample.ms > lastMs {
                    speed += BrushDynamics.speedEase * (distance / (sample.ms - lastMs) - speed)
                }
            }
            lastMs = sample.ms
            if simulated == nil { simulated = sample.pressure == nil }
            points.append(point)
            pressures.append(sample.pressure.map { min(1, max(0, $0)) }
                             ?? BrushDynamics.mousePressure(speed: speed, travelled: travelled,
                                                            diameter: Double(diameter)))
            tilts.append(sample.tilt.map { CGPoint(x: min(1, max(-1, $0.x)), y: min(1, max(-1, $0.y))) }
                         ?? .zero)
            thins.append(sample.pressure == nil ? 1
                         : BrushDynamics.penThinning(speed: speed, thinning: response.speedThinning))
            if points.count == 1 {
                dabs.append(dab(at: point, pressure: pressures[0], tilt: tilts[0], thin: thins[0]))
                untilNext = gap
                return dabs
            }
            // Place the span ending at the sample BEFORE this one, now that
            // the curve's direction through it is known.
            if points.count >= 3 { walkSpan(from: points.count - 3, into: &dabs) }
            if points.count > 4 {
                points.removeFirst()
                pressures.removeFirst()
                tilts.removeFirst()
                thins.removeFirst()
            }
            return dabs
        }

        /// The dabs a brush that dwells lays while the pointer stays within a
        /// dab's spacing of where it settled: one every `dwellInterval` of the
        /// time it has stayed, at the pointer. Moving further away starts a
        /// new stay, so a steady pass lays only its spaced dabs and a slow one
        /// a few more, the way an airbrush deposits by time.
        private mutating func held(_ sample: StrokeSample) -> [BrushDab] {
            guard let anchor = stay,
                  hypot(sample.point.x - anchor.x, sample.point.y - anchor.y) < gap else {
                stay = sample.point
                stayMs = sample.ms
                dwellOwed = 0
                return []
            }
            dwellOwed += max(0, sample.ms - stayMs)
            stayMs = sample.ms
            var dabs: [BrushDab] = []
            let press = sample.pressure.map { min(1, max(0, $0)) } ?? pressures.last ?? 0.5
            let lean = sample.tilt.map { CGPoint(x: min(1, max(-1, $0.x)), y: min(1, max(-1, $0.y))) }
                ?? tilts.last ?? .zero
            guard let interval else { return dabs }
            while dwellOwed >= interval {
                dwellOwed -= interval
                dabs.append(dab(at: sample.point, pressure: press, tilt: lean, thin: 1, held: true))
            }
            return dabs
        }

        /// The stroke is over: places the last span, which has no sample after
        /// it to bend toward, and a last dab on the very end so the stroke
        /// reaches where the pointer let go rather than stopping short of it.
        public mutating func finish() -> [BrushDab] {
            var dabs: [BrushDab] = []
            guard points.count >= 2, let end = points.last, let press = pressures.last,
                  let lean = tilts.last, let thin = thins.last else { return dabs }
            walkSpan(from: points.count - 2, into: &dabs)
            if untilNext < gap {
                // The very end is short of a whole spacing past the last dab.
                along += Double(gap - untilNext) - Double(gap)
                dabs.append(dab(at: end, pressure: press, tilt: lean, thin: thin))
            }
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
            // The press and lean ease from one sample's to the next's.
            let press1 = pressures[k], press2 = pressures[k + 1]
            let lean1 = tilts[k], lean2 = tilts[k + 1]
            let thin1 = thins[k], thin2 = thins[k + 1]
            // Enough pieces that each is well under a dab apart.
            let pieces = max(1, Int((length / max(gap * 0.5, 0.5)).rounded(.up)))
            var previous = p1
            for step in 1...pieces {
                let t0 = CGFloat(step - 1) / CGFloat(pieces)
                let t = CGFloat(step) / CGFloat(pieces)
                let next = step == pieces ? p2 : catmullRom(p0, p1, p2, p3, t)
                let whole = hypot(next.x - previous.x, next.y - previous.y)
                var segment = whole
                var from = previous
                while segment >= untilNext {
                    let f = untilNext / segment
                    let at = CGPoint(x: from.x + (next.x - from.x) * f,
                                     y: from.y + (next.y - from.y) * f)
                    // How far along the whole span this dab is.
                    let u = Double(t0 + (t - t0) * (whole - segment + untilNext) / whole)
                    dabs.append(dab(at: at, pressure: press1 + (press2 - press1) * u,
                                    tilt: CGPoint(x: lean1.x + (lean2.x - lean1.x) * u,
                                                  y: lean1.y + (lean2.y - lean1.y) * u),
                                    thin: thin1 + (thin2 - thin1) * u))
                    segment -= untilNext
                    from = at
                    untilNext = gap
                }
                untilNext -= segment
                previous = next
            }
        }

        /// One dab, shaped by the hand: its width and weight from the press
        /// (`response`), narrowed by a fast pen (`thin`) and, for a mouse,
        /// swelled in from the touch-down. A spaced dab moves `along` on by a
        /// spacing; one held in place stays where the pointer is.
        private mutating func dab(at point: CGPoint, pressure: Double, tilt: CGPoint, thin: Double,
                                  held: Bool = false) -> BrushDab {
            var center = point
            if jitter > 0 {
                let radius = diameter / 2 * jitter * random.unit().squareRoot()
                let angle = random.range(0, 2 * .pi)
                center.x += cos(angle) * radius
                center.y += sin(angle) * radius
            }
            let at = along
            if !held { along += Double(gap) }
            var width = response.size(pressure: pressure) * thin
            var weight = response.weight(pressure: pressure)
            if simulated == true {
                let taper = BrushDynamics.taper(distance: at, diameter: Double(diameter),
                                                depth: response.taperDepth)
                width *= taper
                weight *= BrushDynamics.taperWeight(taper)
            }
            return BrushDab(center: center, diameter: diameter * CGFloat(width), opacity: opacity,
                            pressure: pressure, tilt: tilt,
                            spray: dwells && !held ? BrushPlacement.spray(speed: speed) : 1,
                            weight: weight, along: at)
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

    /// Adds a smudge `stroke` (in canvas points) to the paint it drags, and
    /// returns that layer, or nil when there is no paint to smudge.
    ///
    /// A smudge only ever moves paint that is already there: it never makes a
    /// layer and never writes into a picture (the house's non-destructive
    /// rule), so with a screenshot picked it finds the paint under the pointer
    /// instead (`smudgeTarget`).
    @discardableResult
    public mutating func smudgeStroke(_ stroke: BrushStroke, onto pickedID: UUID?) -> UUID? {
        guard let start = stroke.samples.first?.point,
              let target = smudgeTarget(at: start, picked: pickedID),
              let origin = canvasBounds(of: target)?.origin else { return nil }
        let local = stroke.offsetBy(dx: -origin.x, dy: -origin.y)
        updateLayer(id: target) { layer in
            guard case .paint(var paint) = layer.content else { return }
            paint.strokes.append(local)
            layer.content = .paint(paint)
        }
        return target
    }

    /// The paint layer a smudge starting at `point` drags: the picked one when
    /// it is an unlocked paint layer, otherwise the topmost shown, unlocked
    /// paint layer whose box holds the point. Nil when there is none.
    public func smudgeTarget(at point: CGPoint, picked pickedID: UUID?) -> UUID? {
        if let pickedID, let picked = layer(id: pickedID), picked.paint != nil {
            return picked.isLocked ? nil : pickedID
        }
        for leaf in flattenedLayers.reversed() where leaf.paint != nil {
            guard leaf.isVisible, !leaf.isLocked,
                  let box = canvasBounds(of: leaf.id), box.contains(point) else { continue }
            return leaf.id
        }
        return nil
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
