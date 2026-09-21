import CoreGraphics
import Foundation

// MARK: - What the file does about the motions

extension SVGExport {

    /// Whether an exported file carries the document's motions.
    public enum Animation: Hashable, Sendable {
        /// A still picture of the drawing: what Export has always written.
        case still
        /// One lap of the loop, written into the file so it plays itself.
        case moving(cycleMS: Int)

        /// The lap in milliseconds, or nil where the file stands still.
        var cycleMS: Int? {
            guard case let .moving(ms) = self else { return nil }
            return max(1, ms)
        }

        /// Whether the file carries the motion at all.
        public var isMoving: Bool { cycleMS != nil }
    }
}

// MARK: - One layer's motions, as SMIL

/// Turns the motions on a layer into the animation elements an SVG plays by
/// itself.
///
/// **Milliseconds on screen, fractions in the file.** Every motion in a
/// document shares ONE lap — the same lap the canvas and the timing strip use
/// — and each one is written as a list of moments inside that lap, stated as
/// fractions of it. That is what keeps a ninety millisecond lag between two
/// parts of one drawing exactly ninety milliseconds after the trip: two
/// animations with two different durations would drift apart on the first
/// repeat (`MotionStrip.swift`).
///
/// SMIL rather than CSS keyframes, because a turn has to say the point it
/// turns ABOUT and `<animateTransform type="rotate">` says it in plain user
/// units, right there in the value. The CSS answer is `transform-origin`,
/// whose meaning inside an SVG depends on `transform-box` and on whether the
/// transform arrived as an attribute or as a property, and a bell that hangs
/// from the wrong point is the one mistake this feature exists to avoid
/// (`MotionPivot`).
///
/// Everything a host that strips the animation would be left with is stated
/// as an ordinary attribute too, so a file whose motion is thrown away still
/// draws the icon the way it was drawn rather than as a black square.
enum MotionSVG {

    /// The four control numbers of a `cubic-bezier`, the only easing SMIL can
    /// state rather than be shown.
    typealias Spline = (x1: Double, y1: Double, x2: Double, y2: Double)

    /// Straight through: what a hold and a sampled run both use.
    static let hold: Spline = (0, 0, 1, 1)

    // MARK: What wraps one layer

    /// The groups one animated layer is wrapped in, and what its own shapes
    /// must therefore stop saying for themselves.
    struct Wrap {
        /// The opening tags, outermost first, each already indented.
        var opens: [String] = []
        /// The closing tags, innermost first.
        var closes: [String] = []
        /// How many levels deeper the layer's own body now sits.
        var levels = 0
        /// Paint roles ("fill", "stroke") the wrapper animates, which the
        /// shape inside must leave unsaid so it inherits them.
        var omitPaint: Set<String> = []
        /// Whether the line width is animated and so inherited.
        var omitsStrokeWidth = false
        /// Whether the layer's own fade is animated, so stating it as well
        /// would fade the drawing twice over.
        var omitsOpacity = false
        /// Whether a turn owns the layer's angle outright, so the still
        /// placement must not turn it a second time.
        var ownsTheTurn = false
        /// Parts of the motion the file could not carry, each with the reason
        /// in words a person can read.
        var dropped: [SVGExport.Fallback] = []

        var isEmpty: Bool { opens.isEmpty }
    }

    /// Everything the file needs around `layer` for its motions to play.
    static func wrap(for layer: Layer, cycleMS: Int, level: Int,
                     isPicture: Bool) -> Wrap {
        var wrap = Wrap()
        let motions = (layer.motions ?? []).filter(\.isOn)
        guard !motions.isEmpty, cycleMS > 0 else { return wrap }

        // The groups that do the animating sit OUTSIDE the one that puts the
        // layer in its place, so every point in them is stated where the layer
        // sits — the same space `turnPivot` answers in, and the same space the
        // layer's own frame is stated in.
        let box = layer.isGroup ? layer.localBounds : layer.frame
        let pivot = layer.turnPivot

        func push(_ attributes: String, _ children: [String]) {
            wrap.opens.append(indent(level + wrap.levels) + "<g\(attributes)>")
            for child in children {
                wrap.opens.append(indent(level + wrap.levels + 1) + child)
            }
            wrap.closes.insert(indent(level + wrap.levels) + "</g>", at: 0)
            wrap.levels += 1
        }

        func drop(_ property: MotionProperty, _ reason: String) {
            wrap.dropped.append(SVGExport.Fallback(
                layerName: layer.name,
                reason: "\(property.title.lowercased()) \(reason)"))
        }

        // Outermost first: a fade over everything, then the move, then the
        // turn, then the growth. That is the order the canvas composes them
        // in, where a move shifts the whole drawing and a turn swings what is
        // inside it (`LayerMotion.applied`).
        for property in MotionProperty.nestingOrder {
            guard let motion = motions.first(where: { $0.property == property }) else { continue }
            guard let track = track(for: motion, layer: layer, pivot: pivot, cycleMS: cycleMS)
            else {
                drop(property, "could not be written into the file")
                continue
            }
            switch property {
            case .opacity:
                wrap.omitsOpacity = true
                let base = track.base == "1" ? "" : " opacity=\"\(track.base)\""
                push(base, [track.element])
            case .position:
                let base = track.base == "0 0" ? "" : " transform=\"translate(\(track.base))\""
                push(base, [track.element])
            case .rotation:
                // A turn on a layer that is also flipped or skewed cannot be
                // lifted out of the matrix that says the rest, so it stays
                // still rather than turning about the wrong thing.
                if layer.transform.skewX != 0 || layer.transform.skewY != 0
                    || layer.transform.flipHorizontal || layer.transform.flipVertical {
                    drop(property, "cannot be separated from the flip or skew on the same layer")
                    continue
                }
                wrap.ownsTheTurn = true
                push(" transform=\"rotate(\(track.base))\"", [track.element])
            case .scale:
                // Growing happens about the middle of the layer, so the file
                // steps out to the middle, grows, and steps back.
                let middle = "\(SVGExport.num(box.midX)) \(SVGExport.num(box.midY))"
                let back = "\(SVGExport.num(-box.midX)) \(SVGExport.num(-box.midY))"
                push(" transform=\"translate(\(middle))\"", [])
                let base = track.base == "1 1" ? "" : " transform=\"scale(\(track.base))\""
                push(base, [track.element])
                push(" transform=\"translate(\(back))\"", [])
            case .color:
                guard !isPicture, let role = paintRole(of: layer) else {
                    drop(property, isPicture
                        ? "belongs to a layer that goes out as a picture"
                        : "has no flat colour in the file to change")
                    continue
                }
                wrap.omitPaint.insert(role)
                push(" \(role)=\"\(track.base)\"", [track.element])
            case .blur:
                // An animated SVG has no way to say this yet: a blur in the
                // file is a filter, and animating its softness means writing a
                // filter and animating the number inside it. Said out loud in
                // the fallback list rather than quietly left out, which is the
                // rule for everything this exporter cannot carry.
                drop(property, "is not written into an animated SVG yet")
                continue
            case .strokeWidth:
                guard !isPicture, canInheritStrokeWidth(layer) else {
                    drop(property, widthReason(for: layer, isPicture: isPicture))
                    continue
                }
                wrap.omitsStrokeWidth = true
                push(" stroke-width=\"\(track.base)\"", [track.element])
            }
        }
        return wrap
    }

    // MARK: What the shape inside must stop saying

    /// Which paint a colour change lands on, exactly where the paint bucket
    /// puts it (`MotionProperty.paintedColorHex`), or nil where the layer has
    /// no flat colour an inherited one could replace.
    ///
    /// A ramp is never it: a shape pointing at a gradient goes on pointing at
    /// it whatever the group around it says, so a colour written on the group
    /// would simply be ignored.
    static func paintRole(of layer: Layer) -> String? {
        switch layer.content {
        case let .path(path):
            if path.paintsAnInside, let fill = path.fill {
                return fill.isGradient ? nil : "fill"
            }
            return path.paint.isGradient ? nil : "stroke"
        case let .annotation(annotation):
            switch annotation.shape {
            case .rectangle, .ellipse:
                if let fill = annotation.fill { return fill.isGradient ? nil : "fill" }
                return annotation.paint.isGradient ? nil : "stroke"
            case .line:
                return annotation.paint.isGradient ? nil : "stroke"
            case .arrow, .highlight:
                return nil
            }
        case .text:
            return "fill"
        default:
            return nil
        }
    }

    /// Why a width written on the group would not reach the line this layer
    /// draws, in words a person can read on the Export sheet.
    static func widthReason(for layer: Layer, isPicture: Bool) -> String {
        if isPicture { return "belongs to a layer that goes out as a picture" }
        switch layer.content {
        case .annotation(let annotation)
            where annotation.shape == .arrow || annotation.shape == .highlight:
            return "belongs to a mark the file draws in several pieces"
        case .measure:
            return "belongs to a mark the file draws in several pieces"
        default:
            return "belongs to a line the file draws in two halves"
        }
    }

    /// Whether a width written on the group reaches the line this layer
    /// draws. An inside or an outside line is drawn at double width and cut
    /// in half, so a width handed down from above would come out half the
    /// size it says (`SVGExport` writes that pair).
    static func canInheritStrokeWidth(_ layer: Layer) -> Bool {
        switch layer.content {
        case let .path(path):
            return path.strokeWidth > 0 && path.effectiveStrokePosition == .center
        case let .annotation(annotation):
            switch annotation.shape {
            case .rectangle, .ellipse, .line: return annotation.strokeWidth > 0
            case .arrow, .highlight: return false
            }
        default:
            return false
        }
    }

    // MARK: One motion, as one element

    struct Track {
        /// The whole `<animate…/>` element.
        var element: String
        /// What the value is at the top of the lap, for a host that throws
        /// the animation away and shows the attribute underneath instead.
        var base: String
    }

    static func track(for motion: LayerMotion, layer: Layer, pivot: CGPoint,
                      cycleMS: Int) -> Track? {
        let stops = stops(for: motion, cycleMS: cycleMS)
        guard stops.count >= 2 else { return nil }
        let texts = stops.compactMap {
            text(of: $0.value, property: motion.property, layer: layer, pivot: pivot)
        }
        guard texts.count == stops.count else { return nil }

        let cycle = Double(max(1, cycleMS))
        let keyTimes = stops.map { SVGExport.num(CGFloat(min(max($0.ms / cycle, 0), 1))) }
        let splines = stops.dropLast().map(\.spline)
        let stepping: Bool = if case .steps = motion.curve { true } else { false }

        // A transform animation REPLACES the transform attribute beside it
        // while it plays, which is exactly what is wanted: that attribute is
        // the still pose, kept for a host that strips the animation out.
        let element: String
        let attributes: String
        switch motion.property {
        case .position:
            element = "animateTransform"
            attributes = "attributeName=\"transform\" type=\"translate\""
        case .rotation:
            element = "animateTransform"
            attributes = "attributeName=\"transform\" type=\"rotate\""
        case .scale:
            element = "animateTransform"
            attributes = "attributeName=\"transform\" type=\"scale\""
        case .opacity:
            element = "animate"
            attributes = "attributeName=\"opacity\""
        case .color:
            element = "animate"
            attributes = "attributeName=\"\(paintRole(of: layer) ?? "fill")\""
        case .strokeWidth:
            element = "animate"
            attributes = "attributeName=\"stroke-width\""
        case .blur:
            // Never reached: a blur is dropped before a track is asked for.
            return nil
        }

        var parts = ["<\(element) \(attributes)"]
        parts.append("dur=\"\(max(1, cycleMS))ms\"")
        parts.append("repeatCount=\"\(repeatCount(motion.repeats))\"")
        if motion.repeats.cycles != nil { parts.append("fill=\"freeze\"") }
        if stepping {
            parts.append("calcMode=\"discrete\"")
        } else if splines.contains(where: { !isHold($0) }) {
            parts.append("calcMode=\"spline\"")
            parts.append("keySplines=\"" + splines.map(text(of:)).joined(separator: ";") + "\"")
        } else {
            parts.append("calcMode=\"linear\"")
        }
        parts.append("keyTimes=\"" + keyTimes.joined(separator: ";") + "\"")
        parts.append("values=\"" + texts.joined(separator: ";") + "\"/>")
        return Track(element: parts.joined(separator: " "), base: texts[0])
    }

    static func repeatCount(_ repeats: MotionRepeat) -> String {
        guard let cycles = repeats.cycles else { return "indefinite" }
        return String(cycles)
    }

    static func isHold(_ spline: Spline) -> Bool {
        spline.x1 == 0 && spline.y1 == 0 && spline.x2 == 1 && spline.y2 == 1
    }

    static func text(of spline: Spline) -> String {
        [spline.x1, spline.y1, spline.x2, spline.y2]
            .map { SVGExport.num(CGFloat($0)) }.joined(separator: " ")
    }

    // MARK: The moments inside one lap

    struct Stop {
        var ms: Double
        var value: MotionValue
        /// How the value travels from here to the next moment.
        var spline: Spline
    }

    /// Every moment of one lap this motion has to state, in milliseconds.
    ///
    /// The value at each moment is asked of the motion ITSELF rather than
    /// worked out again here, so the file and the canvas can never disagree
    /// about what a curve, a delay or a there-and-back means.
    static func stops(for motion: LayerMotion, cycleMS: Int) -> [Stop] {
        let cycle = max(1, cycleMS)
        let lap = Double(cycle)
        let startMS = min(Double(motion.timing.startMS), lap)
        let exact = spline(for: motion.curve)

        // What the lap is made of: the run out, and for a there-and-back the
        // run home, each clipped to the lap. A bar is allowed to overrun the
        // lap, which is what a lag in something that repeats IS, and the part
        // past the edge is simply never seen.
        struct Run {
            var from: Double
            var to: Double
            /// Where the run LANDS, said outright rather than sampled: at the
            /// very end of a run the clock has already moved on to whatever
            /// comes next, and asking then would answer for the next lap.
            var lands: MotionValue
            var spline: Spline?
            var truncated: Bool
        }
        var runs: [Run] = []
        let out = Double(motion.timing.startMS)
        let home = Double(motion.timing.endMS)
        if motion.repeats.reverses {
            let middle = out + Double(motion.timing.durationMS) / 2
            runs.append(Run(from: out, to: middle, lands: motion.to,
                            spline: exact, truncated: false))
            runs.append(Run(from: middle, to: home, lands: motion.from,
                            spline: exact.map(reversed), truncated: false))
        } else {
            runs.append(Run(from: out, to: home, lands: motion.to,
                            spline: exact, truncated: false))
        }
        runs = runs.compactMap { run in
            guard run.from < lap, run.to > run.from else { return nil }
            var run = run
            if run.to > lap {
                run.to = lap
                run.truncated = true
            }
            return run
        }
        guard !runs.isEmpty else { return [] }

        // The value the motion itself says it has at that moment. The very
        // end of the lap is never asked for: there the clock has wrapped and
        // the answer is the top of the NEXT lap, which is the first value in
        // this list already.
        func value(at ms: Double) -> MotionValue {
            let asked = min(max(ms, 0), lap - 0.5)
            return motion.value(atMS: Int(asked.rounded()), cycleMS: cycle)
        }

        var stops: [Stop] = []
        func add(_ ms: Double, _ value: MotionValue, _ spline: Spline) {
            if let last = stops.last, abs(last.ms - ms) < 0.5 {
                stops[stops.count - 1].spline = spline
                return
            }
            stops.append(Stop(ms: ms, value: value, spline: spline))
        }

        // It holds where it was drawn until its turn comes.
        if startMS > 0 { add(0, motion.from, hold) }

        for (index, run) in runs.enumerated() {
            let samples = run.truncated || run.spline == nil
                ? sampleCount(for: motion.curve) : 0
            if samples <= 0, let spline = run.spline {
                add(run.from, index == 0 ? motion.from : runs[index - 1].lands, spline)
                continue
            }
            // A curve SVG cannot state — one that overshoots, or one cut off
            // by the edge of the lap — is drawn point by point instead.
            let step = (run.to - run.from) / Double(max(1, samples))
            for step_index in 0..<max(1, samples) {
                let ms = run.from + step * Double(step_index)
                let value = step_index == 0 && index == 0 && !motion.repeats.reverses
                    ? motion.from : value(at: ms)
                add(ms, value, hold)
            }
        }

        // Where the last run lands, and what it sits at for the rest of the
        // lap. A run cut off by the edge of the lap lands wherever it had got
        // to, which is the one case that has to be asked for.
        guard let last = runs.last else { return [] }
        let landed = last.truncated ? value(at: last.to - 1) : last.lands
        add(last.to, landed, hold)
        if last.to < lap - 0.5 { add(lap, landed, hold) }
        return stops
    }

    /// The same easing, read backwards: what the run HOME does on a
    /// there-and-back, where the value travels from To to From as time goes
    /// forward.
    static func reversed(_ spline: Spline) -> Spline {
        (1 - spline.x2, 1 - spline.y2, 1 - spline.x1, 1 - spline.y1)
    }

    /// The cubic SVG can state for this curve, or nil where it has to be
    /// drawn point by point. SMIL keeps both control points inside the unit
    /// square, so every curve that overshoots or jumps is in the second camp.
    static func spline(for curve: EasingCurve) -> Spline? {
        switch curve {
        case .linear: return hold
        case .easeInOut: return (0.4, 0, 0.2, 1)
        case .easeIn: return (0.4, 0, 1, 1)
        case .easeOut: return (0, 0, 0.2, 1)
        case let .custom(x1, y1, x2, y2):
            let inside = [x1, y1, x2, y2].allSatisfy { $0 >= 0 && $0 <= 1 }
            return inside ? (x1, y1, x2, y2) : nil
        case .easeInOutSine, .easeOutBack, .easeOutElastic, .steps:
            return nil
        }
    }

    /// How many moments a curve that has to be drawn is drawn with: enough
    /// that the eye reads a curve, few enough that the file stays a file you
    /// could read.
    static func sampleCount(for curve: EasingCurve) -> Int {
        switch curve {
        case .easeInOutSine: return 10
        case .easeOutBack: return 14
        case .easeOutElastic: return 28
        case let .steps(count): return max(1, count)
        case .linear, .easeIn, .easeOut, .easeInOut, .custom: return 12
        }
    }

    // MARK: One value, as the file says it

    static func text(of value: MotionValue, property: MotionProperty,
                     layer: Layer, pivot: CGPoint) -> String? {
        switch (property, value) {
        case let (.rotation, .number(degrees)):
            return "\(number(degrees)) \(SVGExport.num(pivot.x)) \(SVGExport.num(pivot.y))"
        case let (.scale, .number(percent)):
            let factor = percent / 100
            return "\(number(factor)) \(number(factor))"
        case let (.position, .point(point)):
            return "\(SVGExport.num(point.x - layer.frame.origin.x))"
                + " \(SVGExport.num(point.y - layer.frame.origin.y))"
        case let (.opacity, .number(percent)):
            return number(min(max(percent / 100, 0), 1))
        case let (.strokeWidth, .number(points)):
            return number(max(0, points))
        case let (.color, .color(hex)):
            guard let rgba = RGBA(hex: hex) else { return nil }
            return MotionValue.hex(rgba)
        default:
            return nil
        }
    }

    static func number(_ value: Double) -> String { SVGExport.num(CGFloat(value)) }

    static func indent(_ level: Int) -> String { String(repeating: "  ", count: max(level, 0)) }
}

private extension MotionProperty {
    /// Whether this is one of the three that move the drawing about, which
    /// SVG says with one element and one attribute between them.
    var isTransform: Bool {
        switch self {
        case .position, .rotation, .scale: true
        case .opacity, .color, .strokeWidth, .blur: false
        }
    }
}
