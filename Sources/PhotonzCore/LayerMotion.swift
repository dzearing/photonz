import CoreGraphics
import Foundation

// MARK: - What can move

/// One property of a layer that can be told to change over time.
///
/// There is no list of named motions here and there never will be: the user
/// rejected "Pulse, Wiggle, Bounce, Spin" on 2026-09-15 as a closed vocabulary
/// pretending to be a model, and they were right. A preset is a COMBINATION of
/// these, and combinations are what you make, not what you pick.
///
/// So the plus on the Motion header is built out of the layer in front of you.
/// Every item names something that layer actually has and shows the value it
/// has right now, because that is what you would be animating away from.
public enum MotionProperty: String, CaseIterable, Hashable, Codable, Sendable {
    /// Where it sits, in the coordinates of whatever contains it.
    case position
    /// How big it is, as a percentage of the size it was drawn.
    case scale
    /// How far it is turned, in degrees, clockwise on screen.
    case rotation
    /// How see-through it is, as a percentage.
    case opacity
    /// What it is painted.
    case color
    /// How thick the one line round it is, in document points.
    case strokeWidth
    /// How soft the blur in its Effects list is, in document points.
    ///
    /// **An effect changing over a shot is this machinery pointed at a
    /// different property, never a second one.** A blur that comes on over a
    /// second is a motion like any other: it gets the curve list, the lane on
    /// the strip, the From and To row, undo and the export without a line
    /// written for it (`docs/design/video-transitions.md`).
    case blur
    /// How round its corners are, in document points: the mask a picture, a
    /// clip or a box is cut out with (`LayerStyle.cornerRadius`).
    case cornerRadius
    /// How soft and far its shadow spreads, in document points: the first
    /// shadow in its Effects list, which a key brings in when there is none.
    case shadow
    /// How big its type is, in document points. Words only.
    case textSize
    /// How far the first glow in its Effects list reaches, in document points:
    /// an effect's amount, keyed like any other length.
    case glow
    /// How much of a picture or a clip is cut away from each edge, as a
    /// percent of the picture: Premiere's Crop effect, whose four edges are
    /// keyed one at a time. The picture that is kept stays where it was drawn
    /// (`KeyedCrop.swift`).
    case cropLeft
    case cropTop
    case cropRight
    case cropBottom

    /// What the menu item and the row are called.
    public var title: String {
        switch self {
        case .position: "Position"
        case .scale: "Scale"
        case .rotation: "Rotation"
        case .opacity: "Opacity"
        case .color: "Color"
        case .strokeWidth: "Stroke width"
        case .blur: "Blur"
        case .cornerRadius: "Corner radius"
        case .shadow: "Shadow size"
        case .textSize: "Text size"
        case .glow: "Glow size"
        case .cropLeft: "Crop left"
        case .cropTop: "Crop top"
        case .cropRight: "Crop right"
        case .cropBottom: "Crop bottom"
        }
    }

    /// The four edges of a keyed crop.
    public static let cropEdges: [MotionProperty] = [.cropLeft, .cropTop, .cropRight, .cropBottom]

    /// One of the four edges of a keyed crop.
    public var isCrop: Bool { Self.cropEdges.contains(self) }

    /// A distance in document points, which the panel writes in the app's one
    /// word for a length (`DocumentUnit`).
    public var isLength: Bool {
        [.strokeWidth, .blur, .cornerRadius, .shadow, .glow, .textSize].contains(self)
    }

    /// The order the menu offers them in: where it is, how big, how turned,
    /// how faded, then what it is painted and what its line is. Transform
    /// first, because that is what an icon animation is nearly always made of.
    public static let menuOrder: [MotionProperty] =
        [.position, .scale, .rotation, .opacity, .color, .strokeWidth, .blur]

    /// How the properties NEST when more than one is on the same layer,
    /// outermost first: a fade over everything, then the move, then the turn,
    /// then the growth, and inside all of them what the shape is painted and
    /// how thick its line is.
    ///
    /// One list, read by both halves of the promise. An exported file wraps the
    /// layer in this order literally (`SVGMotionExport`), and the canvas works
    /// the same picture out by applying them from the INSIDE out, so a shape
    /// told to double and to thicken its line ends up with the same line in the
    /// app and in a browser. Without it the two disagree the moment a layer
    /// carries both, because growing something multiplies the line it is drawn
    /// with and setting that line afterwards throws the multiplication away.
    ///
    /// Corner, shadow and type size sit innermost with the line, for the same
    /// reason: they are lengths the growth multiplies, so they are set before
    /// it rather than after. A glow's size is one more of those lengths.
    ///
    /// The crop is innermost of all: Premiere crops the picture first and
    /// moves, turns and grows what is left, so a crop is a cut in the picture
    /// the growth then magnifies, and the growth keeps its middle where the
    /// whole picture's middle is (`applied`, the scale case).
    public static let nestingOrder: [MotionProperty] =
        [.opacity, .blur, .position, .rotation, .scale, .color, .strokeWidth,
         .cornerRadius, .shadow, .glow, .textSize,
         .cropLeft, .cropTop, .cropRight, .cropBottom]

    /// One item of the plus's menu: a property, the value the layer is wearing
    /// now, and whether this layer is already animating it.
    public struct Offer: Hashable, Sendable {
        public let property: MotionProperty
        public let current: MotionValue
        /// True when there is already a motion on this property. One property
        /// is one answer: a second rotation would be two answers to one
        /// question, so the menu says so by going quiet rather than by letting
        /// it in and then ignoring one of them.
        public let isAlreadyMoving: Bool

        public init(property: MotionProperty, current: MotionValue, isAlreadyMoving: Bool) {
            self.property = property
            self.current = current
            self.isAlreadyMoving = isAlreadyMoving
        }

        /// What the menu prints down the right hand edge.
        public var reading: String { property.format(current) }
    }

    /// What this layer can be told to change, with the numbers it is wearing.
    ///
    /// A photograph is not offered a colour it has not got, and a rectangle is
    /// not offered a stroke width now that a box's edge is a Border in the
    /// Effects list. A row that cannot change anything is a row that lies about
    /// what the layer is.
    public static func offered(for layer: Layer) -> [Offer] {
        let moving = Set((layer.motions ?? []).map(\.property))
        return menuOrder.compactMap { property in
            guard let value = property.current(of: layer) else { return nil }
            return Offer(property: property, current: value,
                         isAlreadyMoving: moving.contains(property))
        }
    }

    /// The value this layer is wearing now, or nil where the layer has no such
    /// property at all.
    public func current(of layer: Layer) -> MotionValue? {
        switch self {
        case .position:
            return .point(layer.frame.origin)
        case .scale:
            // Always a hundred percent of what was drawn. Before anything has
            // moved there is nothing else it could mean.
            return .number(100)
        case .rotation:
            return .number(Double(layer.transform.rotation) * 180 / .pi)
        case .opacity:
            return .number(layer.style.opacity * 100)
        case .color:
            return MotionProperty.paintedColorHex(of: layer).map { .color($0) }
        case .strokeWidth:
            // Only where the line IS the layer: a path's outline, a line, an
            // arrow. A box's edge lives in the Effects list and is that
            // effect's business, not the layer's.
            guard layer.drawsItsOwnOutline else { return nil }
            return .number(Double(layer.outlineWidth))
        case .blur:
            // Only where there is a blur in the Effects list to change. The
            // menu says what the layer HAS, and offering a blur to a layer
            // with none would be offering to animate a thing that is not
            // there.
            guard layer.style.effects.contains(where: { $0.kind == .blur }) else { return nil }
            return .number(Double(layer.style.blurRadius))
        case .cornerRadius:
            guard layer.hasRoundableCorners else { return nil }
            return .number(Double(layer.roundedCornerRadius))
        case .shadow:
            guard let shadow = layer.style.shadows.first else { return nil }
            return .number(Double(shadow.radius))
        case .textSize:
            return layer.text.map { .number(Double($0.fontSize)) }
        case .glow:
            return layer.style.glowEffects.first.map { .number(Double($0.size)) }
        case .cropLeft, .cropTop, .cropRight, .cropBottom:
            // Nothing cut away: a keyed crop is measured from the picture as
            // it is drawn, whatever the Crop tool already took off it.
            return layer.supportsContentCrop ? .number(0) : nil
        }
    }

    /// The one flat colour this layer reads as, or nil where it paints nothing
    /// of its own. Mirrors what the paint bucket means by "make this that
    /// colour" (`Fill.filled`), so the property the menu offers and the thing
    /// the motion changes can never be two different colours.
    static func paintedColorHex(of layer: Layer) -> String? {
        switch layer.content {
        // Sound paints nothing, so there is no colour of its own to change.
        case .sound: return nil
        case let .annotation(annotation):
            switch annotation.shape {
            case .rectangle, .ellipse: return annotation.fillColorHex ?? annotation.colorHex
            case .line, .arrow, .highlight: return annotation.colorHex
            }
        case let .text(text): return text.colorHex
        case let .path(path): return path.fill?.hex ?? path.paint.hex
        case let .collage(collage): return collage.backdropColorHex
        case .image, .measure, .zoomCallout, .lens, .group: return nil
        }
    }

    /// The value written the way a person reads it.
    public func format(_ value: MotionValue) -> String {
        switch (self, value) {
        case let (.rotation, .number(degrees)): return "\(MotionNumber.text(degrees))°"
        case let (.scale, .number(percent)): return "\(MotionNumber.text(percent))%"
        case let (.opacity, .number(percent)): return "\(MotionNumber.text(percent))%"
        case let (.cropLeft, .number(percent)), let (.cropTop, .number(percent)),
             let (.cropRight, .number(percent)), let (.cropBottom, .number(percent)):
            return "\(MotionNumber.text(percent))%"
        case let (.strokeWidth, .number(points)): return "\(MotionNumber.text(points)) pt"
        case let (.blur, .number(points)), let (.cornerRadius, .number(points)),
             let (.shadow, .number(points)), let (.textSize, .number(points)),
             let (.glow, .number(points)):
            return "\(MotionNumber.text(points)) pt"
        case let (.position, .point(point)):
            return "\(MotionNumber.text(Double(point.x))), \(MotionNumber.text(Double(point.y)))"
        case let (.color, .color(hex)): return hex
        case let (_, .number(number)): return MotionNumber.text(number)
        case let (_, .point(point)):
            return "\(MotionNumber.text(Double(point.x))), \(MotionNumber.text(Double(point.y)))"
        case let (_, .color(hex)): return hex
        }
    }
}

/// Numbers in a summary, written the way somebody would say them: no trailing
/// zeroes, and never enough decimals to turn a row into a wall of digits.
enum MotionNumber {
    static func text(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%g", rounded)
    }
}

// MARK: - What a property's value IS

/// The From and the To of a motion: a number, a place, or a colour.
///
/// One type rather than one motion kind per property, because everything above
/// this — the row, the summary, the blend, the timeline bar in the slice after
/// this one — is the same for all of them, and only the last step of applying
/// it cares which property it was.
public enum MotionValue: Hashable, Codable, Sendable {
    case number(Double)
    case point(CGPoint)
    /// `#RRGGBB` or `#RRGGBBAA`, the same strings the document stores.
    case color(String)

    /// Where this sits `progress` of the way to `other`, or nil where the two
    /// are not the same kind of thing at all. Overshoot is allowed through on
    /// purpose: a back or an elastic curve goes past one and comes home, and
    /// clamping here would quietly turn both of them into ease out.
    public func blended(to other: MotionValue, progress: Double) -> MotionValue? {
        switch (self, other) {
        case let (.number(from), .number(to)):
            return .number(from + (to - from) * progress)
        case let (.point(from), .point(to)):
            return .point(CGPoint(x: from.x + (to.x - from.x) * progress,
                                  y: from.y + (to.y - from.y) * progress))
        case let (.color(from), .color(to)):
            guard let a = RGBA(hex: from), let b = RGBA(hex: to) else { return nil }
            let mix = RGBA(r: a.r + (b.r - a.r) * progress,
                           g: a.g + (b.g - a.g) * progress,
                           b: a.b + (b.b - a.b) * progress,
                           a: a.a + (b.a - a.a) * progress)
            return .color(MotionValue.hex(mix))
        default:
            return nil
        }
    }

    /// `#RRGGBB`, or `#RRGGBBAA` where there is any transparency to keep.
    static func hex(_ color: RGBA) -> String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        if byte(color.a) == 255 { return color.hexString }
        return color.hexString + String(format: "%02X", byte(color.a))
    }
}

// MARK: - Curves

/// The one list of curves, named the same way everywhere.
///
/// Settled on the icon pages of the design study: each name is drawn beside its
/// shape, because nobody can tell ease out back from ease out quint by reading,
/// and a curve you draw yourself sits at the end. Video inherits this list
/// rather than keeping one of its own
/// (task `one-set-of-easing-curves-named-the-same-way-ever`).
///
/// The three the design language already had in `tokens.css` are in here under
/// the names people use: `--ease-standard` is Ease in out, `--ease-decel` is
/// Ease out, and `--ease-spring` is what Ease out back is doing.
public enum EasingCurve: Hashable, Codable, Sendable {
    case linear
    case easeInOut
    case easeIn
    case easeOut
    case easeInOutSine
    case easeOutBack
    case easeOutElastic
    /// Jumps rather than slides, in this many equal steps.
    case steps(Int)
    /// One you drew: the two control points of `cubic-bezier(x1,y1,x2,y2)`.
    case custom(x1: Double, y1: Double, x2: Double, y2: Double)

    /// The menu, in order. `custom` is not in here: it arrives from the curve
    /// editor at the bottom of the same menu, under "Draw a curve".
    public static let named: [EasingCurve] = [
        .linear, .easeInOut, .easeIn, .easeOut,
        .easeInOutSine, .easeOutBack, .easeOutElastic, .steps(4),
    ]

    public var title: String {
        switch self {
        case .linear: "Linear"
        case .easeInOut: "Ease in out"
        case .easeIn: "Ease in"
        case .easeOut: "Ease out"
        case .easeInOutSine: "Ease in out sine"
        case .easeOutBack: "Ease out back"
        case .easeOutElastic: "Ease out elastic"
        case let .steps(count): "Steps, \(count)"
        case let .custom(x1, y1, x2, y2):
            "cubic-bezier(\(MotionNumber.text(x1)), \(MotionNumber.text(y1)), "
                + "\(MotionNumber.text(x2)), \(MotionNumber.text(y2)))"
        }
    }

    /// True for the one you drew, so a row can draw its real shape rather than
    /// print four numbers.
    public var isDrawn: Bool {
        if case .custom = self { return true }
        return false
    }

    /// How far along the change is, `t` of the way through the time.
    ///
    /// Leaves 0 at 0 and lands on 1 at 1 for every curve on the list, which is
    /// what keeps a curve from quietly moving the From and To somebody typed.
    /// In between it is free to overshoot, and two of them do.
    public func value(at t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear:
            return t
        case .easeInOut:
            return EasingCurve.bezier(t, 0.4, 0, 0.2, 1)
        case .easeIn:
            return EasingCurve.bezier(t, 0.4, 0, 1, 1)
        case .easeOut:
            return EasingCurve.bezier(t, 0, 0, 0.2, 1)
        case .easeInOutSine:
            return -(cos(.pi * t) - 1) / 2
        case .easeOutBack:
            let c1 = 1.70158
            let c3 = c1 + 1
            let p = t - 1
            return 1 + c3 * p * p * p + c1 * p * p
        case .easeOutElastic:
            if t == 0 || t == 1 { return t }
            let c4 = (2 * Double.pi) / 3
            return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
        case let .steps(count):
            let steps = max(1, count)
            if t >= 1 { return 1 }
            return (Double(steps) * t).rounded(.down) / Double(steps)
        case let .custom(x1, y1, x2, y2):
            return EasingCurve.bezier(t, x1, y1, x2, y2)
        }
    }

    /// `cubic-bezier(x1,y1,x2,y2)` evaluated the way a browser does it: find
    /// the parameter whose x is the time you asked for, then read its y.
    ///
    /// Newton first because it converges in a handful of steps on the curves
    /// anybody actually draws, bisection after it because Newton stalls where
    /// the curve is flat and a stalled solver would silently return the wrong
    /// shape rather than fail.
    static func bezier(_ t: Double, _ x1: Double, _ y1: Double,
                       _ x2: Double, _ y2: Double) -> Double {
        func curve(_ a: Double, _ b: Double, _ u: Double) -> Double {
            let v = 1 - u
            return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
        }
        func slope(_ a: Double, _ b: Double, _ u: Double) -> Double {
            let v = 1 - u
            return 3 * v * v * a + 6 * v * u * (b - a) + 3 * u * u * (1 - b)
        }
        // A curve with its control points on the diagonal in x is already
        // parameterised by time, which is what linear is.
        if x1 == y1 && x2 == y2 { return t }
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }

        var u = t
        for _ in 0..<8 {
            let x = curve(x1, x2, u) - t
            if abs(x) < 1e-7 { return curve(y1, y2, u) }
            let d = slope(x1, x2, u)
            if abs(d) < 1e-7 { break }
            u -= x / d
        }
        var low = 0.0
        var high = 1.0
        u = t
        for _ in 0..<32 {
            let x = curve(x1, x2, u)
            if abs(x - t) < 1e-7 { break }
            if x > t { high = u } else { low = u }
            u = (low + high) / 2
        }
        return curve(y1, y2, u)
    }
}

// MARK: - What a turn turns AROUND

/// The point a rotation turns the layer about.
///
/// A bell that swings hangs from its MOUNT, not from its middle. Put the pivot
/// in the middle and the top of the bell swings one way while the bottom
/// swings the other, which reads as a bobblehead: nothing about the two angles
/// is wrong, the pivot is. So a rotation carries one of these from the moment
/// it exists, and it is a handle on the picture rather than a field somebody
/// has to know to go looking for.
///
/// It is kept as a FRACTION of the layer's own box rather than as a place on
/// the canvas, and that is the whole design:
///
/// - move the bell and its mount comes with it, instead of the swing tearing
///   loose from the drawing;
/// - resize it and the mount stays where it was on the shape;
/// - the named spots are ordinary values rather than a second kind of thing —
///   the middle IS `(0.5, 0.5)`, the top edge IS `(0.5, 0)`.
///
/// Nothing clamps it into `0...1`. A mount is very often ABOVE the shape that
/// swings, which is a negative y, and that is the case the feature exists for.
public struct MotionPivot: Hashable, Codable, Sendable {

    /// Where the point sits across the layer's box, as a fraction of it.
    /// `(0, 0)` is the box's top-left corner, because the document model is
    /// top-left origin, and `(0.5, 0.5)` is its middle.
    public var unit: CGPoint

    public init(unit: CGPoint) { self.unit = unit }

    /// The pivot that puts this place on the canvas at that fraction of
    /// `box` — what a drag on the handle and a number typed into the row both
    /// hand in.
    ///
    /// A box with no width or no height cannot say where along itself a point
    /// is, so that axis answers the middle: the alternative is a NaN, and a
    /// NaN in the pivot goes straight into the render transform and takes the
    /// layer off the canvas.
    public init(at point: CGPoint, in box: CGRect) {
        let standard = box.standardized
        self.unit = CGPoint(
            x: standard.width > 0 ? (point.x - standard.minX) / standard.width : 0.5,
            y: standard.height > 0 ? (point.y - standard.minY) / standard.height : 0.5)
    }

    /// Where this lands on a layer whose box is `box`, in the space that box
    /// is stated in.
    public func point(in box: CGRect) -> CGPoint {
        let standard = box.standardized
        return CGPoint(x: standard.minX + standard.width * unit.x,
                       y: standard.minY + standard.height * unit.y)
    }

    /// The three spots worth a name.
    ///
    /// Deliberately short. Everything else is a drag or two typed numbers, and
    /// a menu of nine corners and edges is a menu nobody reads: what a person
    /// wants by NAME is the middle they started at, the top a thing hangs
    /// from, and the bottom a thing stands on.
    public enum Named: String, CaseIterable, Hashable, Codable, Sendable {
        case centre
        case topCentre
        case bottomCentre

        public var title: String {
            switch self {
            case .centre: "Its centre"
            case .topCentre: "Top centre"
            case .bottomCentre: "Bottom centre"
            }
        }

        public var pivot: MotionPivot {
            switch self {
            case .centre: MotionPivot(unit: CGPoint(x: 0.5, y: 0.5))
            case .topCentre: MotionPivot(unit: CGPoint(x: 0.5, y: 0))
            case .bottomCentre: MotionPivot(unit: CGPoint(x: 0.5, y: 1))
            }
        }
    }

    public static let centre = Named.centre.pivot
    public static let topCentre = Named.topCentre.pivot
    public static let bottomCentre = Named.bottomCentre.pivot

    /// The spot this is sitting on, or nil where it is somewhere of its own.
    /// It is asked after every drag, so a drag that happens to land on the top
    /// edge reads back as "Top centre" rather than as a pair of numbers that
    /// happen to mean it.
    public var named: Named? {
        Named.allCases.first { spot in
            let other = spot.pivot.unit
            return abs(other.x - unit.x) < 0.0005 && abs(other.y - unit.y) < 0.0005
        }
    }

    /// What the Around row reads when it is not showing numbers.
    public var title: String { named?.title ?? "Custom" }
}

// MARK: - When, and how long

/// The two numbers that say WHEN a motion happens: how long after the top of
/// the cycle it starts, and how long it takes.
///
/// One type, because the timing strip in the slice after this one draws a bar
/// whose left edge is the start and whose width is the duration: they are the
/// same two numbers and moving either has to move both.
public struct MotionTiming: Hashable, Codable, Sendable {
    public private(set) var startMS: Int
    public private(set) var durationMS: Int

    /// A start is never before the top of the cycle and a duration is never
    /// nought, whatever gets typed into either box: nought would be a division
    /// by nought at the one place that has to be safe, the frame loop.
    public init(startMS: Int, durationMS: Int) {
        self.startMS = max(0, startMS)
        self.durationMS = max(1, durationMS)
    }

    /// When this motion is over, measured from the top of the cycle.
    public var endMS: Int { startMS + durationMS }

    /// The same stretch, moved along the clock. What turns a motion's own
    /// timing into where it happens on the DOCUMENT's timeline
    /// (`Layer.motionShiftMS`).
    public func shifted(byMS ms: Int) -> MotionTiming {
        MotionTiming(startMS: startMS + ms, durationMS: durationMS)
    }

    public mutating func setStart(_ ms: Int) { startMS = max(0, ms) }
    public mutating func setDuration(_ ms: Int) { durationMS = max(1, ms) }
}

/// What happens after a motion has played once.
///
/// The mock's panel offered Once, 3 times and Forever, and its own bell swung
/// out and back inside one cycle, which none of those three can say. Rather
/// than a seventh field, the answer lives here, because "what happens after it
/// plays" is one question: a one way repeat snaps back to the start every
/// cycle, which is a jump cut, and there and back is what an icon nearly always
/// wants.
public enum MotionRepeat: Hashable, Codable, Sendable {
    case once
    case times(Int)
    case forever
    case foreverThereAndBack

    /// What the Repeat menu offers, in order.
    public static let choices: [MotionRepeat] = [.once, .times(3), .forever, .foreverThereAndBack]

    public var title: String {
        switch self {
        case .once: "Once"
        case let .times(count): "\(count) times"
        case .forever: "Forever"
        case .foreverThereAndBack: "Forever, there and back"
        }
    }

    /// True where the motion goes out and comes home inside one cycle.
    public var reverses: Bool { self == .foreverThereAndBack }

    /// How many cycles it plays, or nil for ever.
    public var cycles: Int? {
        switch self {
        case .once: 1
        case let .times(count): max(1, count)
        case .forever, .foreverThereAndBack: nil
        }
    }
}

// MARK: - A value nailed down part way through

/// One value a property is nailed to part way through a motion.
///
/// **This is what a punch-in forced, and it is general.** A move that goes out
/// and comes back is not two motions on one property — one property is still
/// one answer — it is one motion with more than two keys on it. From and To are
/// the first and the last of them; these are the ones in between, and a gap
/// between two stops holding the same value is a HOLD, which is what a camera
/// does when it has arrived somewhere and stays.
///
/// Measured in the same clock as `MotionTiming`, and always inside it: a stop
/// outside the span is a key on a lane the bar does not cover, which is a
/// number nothing can draw.
public struct MotionStop: Hashable, Codable, Sendable {
    public var atMS: Int
    public var value: MotionValue
    /// How the value arrives at this key and leaves it, where somebody has
    /// said (`KeyEase`). Nil follows the motion's own curve, which is every
    /// key written before keys could be eased, so those read back unchanged.
    public var ease: KeyEase?
    /// Where this key's Bezier handles are, once somebody has drawn them
    /// (`KeyHandles`). Nil on every key nobody has, so those encode nothing new.
    public var handles: KeyHandles?

    public init(atMS: Int, value: MotionValue, ease: KeyEase? = nil, handles: KeyHandles? = nil) {
        self.atMS = atMS
        self.value = value
        self.ease = ease
        self.handles = handles
    }

    /// The control point of the stretch LEAVING this key, in that stretch's
    /// unit square: `x1, y1` of its cubic Bezier.
    func leavingHandle(_ fallback: KeyEase) -> CGPoint {
        let ease = self.ease ?? fallback
        if ease == .bezier, let handles { return handles.leaving }
        return KeyHandles.implied(by: ease == .bezier ? .easeInAndOut : ease).leaving
    }

    /// The control point of the stretch ARRIVING at this key, in that
    /// stretch's unit square: `x2, y2` of its cubic Bezier.
    func arrivingHandle(_ fallback: KeyEase) -> CGPoint {
        let ease = self.ease ?? fallback
        if ease == .bezier, let handles { return handles.arriving }
        return KeyHandles.implied(by: ease == .bezier ? .easeInAndOut : ease).arriving
    }
}

/// A key's two Bezier handles (task `a-layer-s-track-opens-into-one-lane-per-
/// keyed-va`): the curve view's handles, one either side of the key.
///
/// Each is stated in the unit square of the stretch it shapes, the way CSS
/// states `cubic-bezier`: `leaving` is `x1, y1` of the stretch that leaves this
/// key, `arriving` is `x2, y2` of the stretch that arrives at it. So a handle
/// stays the same shape when its keys are dragged further apart or given new
/// values, and time never runs backwards: `x` is kept between 0 and 1.
public struct KeyHandles: Hashable, Codable, Sendable {
    public var arriving: CGPoint
    public var leaving: CGPoint

    public init(arriving: CGPoint, leaving: CGPoint) {
        self.arriving = CGPoint(x: min(max(arriving.x, 0), 1), y: arriving.y)
        self.leaving = CGPoint(x: min(max(leaving.x, 0), 1), y: leaving.y)
    }

    /// Where the handles of a key eased any other way sit: exactly the curves
    /// `EasingCurve` already plays for those eases, so turning a key into a
    /// Bezier one changes nothing until a handle is dragged.
    public static func implied(by ease: KeyEase) -> KeyHandles {
        KeyHandles(arriving: ease.easesIn ? CGPoint(x: 0.2, y: 1) : CGPoint(x: 1, y: 1),
                   leaving: ease.easesOut ? CGPoint(x: 0.4, y: 0) : CGPoint(x: 0, y: 0))
    }
}

/// Which of a key's two handles.
public enum KeyHandleSide: String, Hashable, Sendable {
    case arriving, leaving
}

/// How a value moves through one key: a key's right-click in Premiere
/// (Temporal Interpolation), under Premiere's names and with Premiere's
/// meaning. **Ease In is how it ARRIVES at the key, Ease Out is how it LEAVES**,
/// so a move that should settle into place gets Ease In on the key it lands on.
///
/// Each stretch between two keys is shaped by both of them: it leaves slowly
/// where the left key eases out, and arrives slowly where the right key eases
/// in. That is what makes the choice per key rather than per stretch, and it
/// is why the last key can be eased at all.
public enum KeyEase: String, Hashable, Codable, Sendable, CaseIterable {
    case linear
    case easeIn
    case easeOut
    case easeInAndOut
    /// The value stays where this key puts it until the next key, and then
    /// jumps: Premiere's Hold.
    case hold
    /// Shaped by the key's own handles in the curve view (`KeyHandles`).
    case bezier

    public var title: String {
        switch self {
        case .linear: "Linear"
        case .easeIn: "Ease In"
        case .easeOut: "Ease Out"
        case .easeInAndOut: "Ease In and Out"
        case .hold: "Hold"
        case .bezier: "Bezier"
        }
    }

    /// Slows as it arrives at the key.
    public var easesIn: Bool { self == .easeIn || self == .easeInAndOut }
    /// Slows as it leaves the key.
    public var easesOut: Bool { self == .easeOut || self == .easeInAndOut }

    public init(easesIn: Bool, easesOut: Bool) {
        switch (easesIn, easesOut) {
        case (true, true): self = .easeInAndOut
        case (true, false): self = .easeIn
        case (false, true): self = .easeOut
        case (false, false): self = .linear
        }
    }

    /// What a key nobody has eased does under a motion's curve: the curve's
    /// slow start is the left key easing out, its slow end the right key
    /// easing in. A curve with no such reading (a bounce, steps) counts as
    /// easing both ways, the nearest of the four.
    public init(following curve: EasingCurve) {
        // (`hold` and `bezier` are only ever chosen, never read off a curve.)
        switch curve {
        case .linear, .steps: self = .linear
        case .easeIn: self = .easeOut
        case .easeOut: self = .easeIn
        default: self = .easeInAndOut
        }
    }

    /// The curve a stretch runs on, from how its two keys say to move.
    static func curve(leaving left: KeyEase, arriving right: KeyEase) -> EasingCurve {
        switch (left.easesOut, right.easesIn) {
        case (true, true): .easeInOut
        case (true, false): .easeIn
        case (false, true): .easeOut
        case (false, false): .linear
        }
    }
}

// MARK: - One motion

/// One property of one layer, changing over time.
///
/// Read exactly the way an entry in the Effects list is read: a switch, a name,
/// a small drawing and a summary you can say out loud. The difference is only
/// what a row MEANS. An Effects row is something the layer paints; this is
/// something about the layer that changes.
public struct LayerMotion: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var property: MotionProperty
    public var from: MotionValue
    public var to: MotionValue
    public var timing: MotionTiming
    /// The keys BETWEEN From and To, where there are any.
    ///
    /// Nil on everything that simply goes from one value to another, which is
    /// nearly everything, so a document written before a move could hold in the
    /// middle reads back byte for byte the same (`MotionStop`).
    public var stops: [MotionStop]?
    public var curve: EasingCurve
    /// How the value moves through From and To, where somebody has eased
    /// those keys (`KeyEase`). The keys in between carry their own.
    public var fromEase: KeyEase?
    public var toEase: KeyEase?
    /// The Bezier handles of From and To, where somebody has drawn them
    /// (`KeyHandles`). The keys in between carry their own.
    public var fromHandles: KeyHandles?
    public var toHandles: KeyHandles?
    public var repeats: MotionRepeat
    /// What a TURN turns around, and nil on everything else: a fade and a
    /// slide have no axis, and a pivot sitting unused on one would be a number
    /// the row cannot explain. Optional so that a motion written before pivots
    /// existed reads back untouched, and nil means the middle, which is what
    /// it drew then (`turnsAbout`).
    public var pivot: MotionPivot?
    /// The switch on the row. Off keeps every number on it and stops it
    /// moving, which is the same bargain the eye on an effect strikes:
    /// with-and-without is the thing you do constantly, so it is the gesture
    /// that keeps your work.
    public var isOn: Bool

    public init(id: UUID = UUID(), property: MotionProperty,
                from: MotionValue, to: MotionValue,
                timing: MotionTiming, curve: EasingCurve = .linear,
                repeats: MotionRepeat = .foreverThereAndBack, isOn: Bool = true,
                pivot: MotionPivot? = nil, stops: [MotionStop]? = nil,
                fromEase: KeyEase? = nil, toEase: KeyEase? = nil,
                fromHandles: KeyHandles? = nil, toHandles: KeyHandles? = nil) {
        self.id = id
        self.fromEase = fromEase
        self.toEase = toEase
        self.fromHandles = fromHandles
        self.toHandles = toHandles
        self.property = property
        self.from = from
        self.to = to
        self.timing = timing
        self.stops = stops.flatMap { $0.isEmpty ? nil : $0 }
        self.curve = curve
        self.repeats = repeats
        self.isOn = isOn
        self.pivot = pivot
    }

    /// This motion re-timed, with everything nailed down inside it carried
    /// along.
    ///
    /// Dragging a bar on the timing strip moves and stretches the span, and a
    /// stop is stated in the same clock the span is, so leaving the stops where
    /// they were would slide a hold out of the move that owns it — or right off
    /// the end of it. They travel in proportion instead, which is what dragging
    /// the bar looks like it is doing: the whole move, later or slower.
    public func retimed(to timing: MotionTiming) -> LayerMotion {
        var moved = self
        moved.timing = timing
        guard let stops, !stops.isEmpty, self.timing.durationMS > 0 else { return moved }
        let stretch = Double(timing.durationMS) / Double(self.timing.durationMS)
        moved.stops = stops.map {
            let along = Double($0.atMS - self.timing.startMS) * stretch
            var stop = $0
            stop.atMS = timing.startMS + Int(along.rounded())
            return stop
        }
        return moved
    }

    /// The point this turn turns about, with the middle standing in wherever
    /// nothing has been said. One place asks the question so nothing can read
    /// nil as "do not pivot at all".
    public var turnsAbout: MotionPivot { pivot ?? .centre }

    // MARK: What it is at a given millisecond

    /// The value this property has `ms` into the preview, with the whole
    /// picture's cycle being `cycleMS` long.
    ///
    /// The clock is one cycle in milliseconds and it wraps, which is what an
    /// icon is: it repeats. A video finishes, and that is why the study is
    /// explicit that the two cannot share a ruler.
    public func value(atMS ms: Int, cycleMS: Int) -> MotionValue {
        guard isOn else { return from }
        let cycle = max(1, cycleMS)
        let elapsed = max(0, ms)
        let iteration = elapsed / cycle
        if let cycles = repeats.cycles, iteration >= cycles {
            // It has played the number of times it was asked to and stays
            // where it landed. There and back always lands home, so this is
            // only ever reached by Once and N times.
            return repeats.reverses ? from : to
        }
        let local = elapsed % cycle
        if local <= timing.startMS { return from }
        if local >= timing.endMS { return repeats.reverses ? from : to }

        var progress = Double(local - timing.startMS) / Double(timing.durationMS)
        if repeats.reverses {
            // Out to To at the half way mark and home by the end, so the next
            // cycle starts exactly where the last one ended and there is no
            // seam to see.
            progress = progress < 0.5 ? progress * 2 : (1 - progress) * 2
        }
        return value(atProgress: progress)
    }

    /// Every key on this motion, first to last: From at the start, whatever was
    /// nailed down in between, To at the end.
    ///
    /// Stops outside the span are dropped rather than clamped, because a key
    /// dragged past the end of the bar means the bar should have been longer,
    /// and silently piling several onto the last millisecond would draw one key
    /// where there were three.
    public var keys: [MotionStop] {
        var list = [MotionStop(atMS: timing.startMS, value: from, ease: fromEase, handles: fromHandles)]
        for stop in (stops ?? []).sorted(by: { $0.atMS < $1.atMS })
        where stop.atMS > timing.startMS && stop.atMS < timing.endMS {
            list.append(stop)
        }
        list.append(MotionStop(atMS: timing.endMS, value: to, ease: toEase, handles: toHandles))
        return list
    }

    /// This motion with the key at `index` among the ones BETWEEN its ends
    /// moved to `ms`, and every other number on it left alone.
    ///
    /// What dragging a mark on the timing strip writes down. It is about WHEN
    /// and never about what: the key keeps its value, the two ends keep theirs,
    /// and the span is untouched, which is exactly what a bar drag does not do.
    ///
    /// The moment is kept inside the span, and the stops come back in order, so
    /// a key carried past its neighbour settles beside it rather than swapping
    /// the two over and drawing a different move.
    public func movingKey(_ index: Int, toMS ms: Int) -> LayerMotion {
        var middle = Array(keys.dropFirst().dropLast())
        guard middle.indices.contains(index) else { return self }
        middle[index].atMS = min(max(ms, timing.startMS + 1), timing.endMS - 1)
        // Anything already outside the span is left where it is rather than
        // quietly dropped: it is not drawn and it does not play, but losing it
        // on an unrelated drag would be an edit nobody asked for.
        let outside = (stops ?? []).filter { $0.atMS <= timing.startMS || $0.atMS >= timing.endMS }
        var moved = self
        moved.stops = (middle + outside).sorted { $0.atMS < $1.atMS }
        return moved
    }

    /// The value this motion has a fraction of the way along its span.
    ///
    /// One segment between each pair of keys, each eased by the motion's own
    /// curve, so a two-key motion is exactly what it always was and a longer
    /// one leans in and settles at every key rather than only at the ends. Two
    /// keys holding the same value make a segment that does not move, which is
    /// the HOLD, and it costs nothing to draw.
    func value(atProgress progress: Double) -> MotionValue {
        let list = keys
        guard list.count > 2 else {
            let shaped = segmentCurve(leaving: list[0], arriving: list[list.count - 1])
            return from.blended(to: to, progress: shaped.value(at: progress)) ?? from
        }
        let at = Double(timing.startMS) + progress * Double(timing.durationMS)
        for index in 0..<(list.count - 1) {
            let left = list[index]
            let right = list[index + 1]
            guard at < Double(right.atMS) || index == list.count - 2 else { continue }
            let span = Double(right.atMS - left.atMS)
            guard span > 0 else { return right.value }
            let local = min(max((at - Double(left.atMS)) / span, 0), 1)
            let shaped = segmentCurve(leaving: left, arriving: right)
            return left.value.blended(to: right.value, progress: shaped.value(at: local)) ?? left.value
        }
        return to
    }

    /// The curve the stretch between two keys runs on: the motion's own where
    /// neither key has been eased, which is every motion made before keys
    /// could be, and otherwise what the two keys say (`KeyEase`).
    func segmentCurve(leaving left: MotionStop, arriving right: MotionStop) -> EasingCurve {
        if left.ease == nil, right.ease == nil { return curve }
        let fallback = KeyEase(following: curve)
        let leaving = left.ease ?? fallback
        let arriving = right.ease ?? fallback
        // A held key keeps its value for the whole stretch and the next key's
        // value arrives on the next key's own frame.
        if leaving == .hold { return .steps(1) }
        if leaving == .bezier || arriving == .bezier {
            let a = left.leavingHandle(fallback)
            let b = right.arrivingHandle(fallback)
            return .custom(x1: Double(a.x), y1: Double(a.y), x2: Double(b.x), y2: Double(b.y))
        }
        return KeyEase.curve(leaving: leaving, arriving: arriving)
    }

    /// True once this motion has stopped moving for good, so the preview can
    /// stop drawing frames rather than burning them on a finished icon.
    public func hasSettled(atMS ms: Int, cycleMS: Int) -> Bool {
        guard isOn else { return true }
        guard let cycles = repeats.cycles else { return false }
        return max(0, ms) >= cycles * max(1, cycleMS)
    }

    // MARK: What the row says

    /// The row, read back as a sentence about the drawing: what it goes from,
    /// what it goes to, how long that takes, and how late it starts when it
    /// does not start at the top.
    public var summary: String {
        let seconds = MotionNumber.text(Double(timing.durationMS) / 1000)
        var text: String
        if let middle = stops?.sorted(by: { $0.atMS < $1.atMS }), !middle.isEmpty {
            // A move with keys in the middle is read as the journey it is
            // rather than as its two ends, which on a punch-in that comes back
            // out would otherwise read "100% → 100%" and look like nothing.
            let steps = ([from] + middle.map(\.value) + [to]).map { property.format($0) }
            text = steps.joined(separator: " → ") + " over \(seconds)s"
        } else {
            text = "\(property.format(from)) → \(property.format(to)) over \(seconds)s"
        }
        if timing.startMS > 0 {
            text += ", after \(MotionNumber.text(Double(timing.startMS) / 1000))s"
        }
        return text
    }

    // MARK: What a fresh one starts as

    /// A motion just added to this layer.
    ///
    /// It ALREADY MOVES. The mock seeds From and To at the value the layer has
    /// now, so its own row reads "0° → 0°": add a motion and nothing whatsoever
    /// happens, which is a feature that looks broken on the first press. These
    /// start at something worth watching and get tuned from there.
    public static func starting(_ property: MotionProperty, on layer: Layer) -> LayerMotion {
        let current = property.current(of: layer)
        // **A document finishes; an icon repeats.** A motion added to something
        // that occupies a stretch of a timeline plays ONCE and stays where it
        // landed, because a blur that came on over a second and then quietly
        // took itself back off again is not what anybody meant by a blur coming
        // on. Everything without a stretch keeps the icon's own answer, which
        // is there and back for ever, because that is what an icon is.
        let plays: MotionRepeat = layer.occupiesTime ? .once : .foreverThereAndBack
        switch property {
        case .rotation:
            // The swing: out one way, through where it was drawn, and back.
            // Measured from the angle the layer is ALREADY at, so a shape
            // somebody turned on purpose does not jerk upright the moment it
            // is told to move.
            let angle = if case let .number(number) = current ?? .number(0) { number } else { 0.0 }
            // The pivot arrives WITH it, on the middle of the layer, and the
            // handle for it is on the picture the same instant. That is
            // deliberately the wrong answer for a bell — it rocks like a
            // bobblehead — and the one drag that repairs it is the argument
            // for the whole feature.
            return LayerMotion(property: .rotation,
                               from: .number(angle - 12), to: .number(angle + 12),
                               timing: MotionTiming(startMS: 0, durationMS: 900),
                               curve: .easeInOutSine, repeats: plays, pivot: .centre)
        case .scale:
            return LayerMotion(property: .scale, from: .number(100), to: .number(120),
                               timing: MotionTiming(startMS: 0, durationMS: 600),
                               curve: .easeInOut, repeats: plays)
        case .opacity:
            // Fades out from wherever it is now, and a layer that is already
            // invisible fades IN instead: either way something happens.
            let now = if case let .number(number) = current ?? .number(100) { number } else { 100.0 }
            return LayerMotion(property: .opacity, from: .number(now),
                               to: .number(now > 1 ? 0 : 100),
                               timing: MotionTiming(startMS: 0, durationMS: 600),
                               curve: .easeInOut, repeats: plays)
        case .position:
            let origin = layer.frame.origin
            // Up and back by a handful of points: enough to see at icon size,
            // small enough not to leave the artboard.
            return LayerMotion(property: .position,
                               from: .point(origin),
                               to: .point(CGPoint(x: origin.x, y: origin.y - 8)),
                               timing: MotionTiming(startMS: 0, durationMS: 600),
                               curve: .easeInOut, repeats: plays)
        case .strokeWidth:
            let width = if case let .number(number) = current ?? .number(1) { number } else { 1.0 }
            return LayerMotion(property: .strokeWidth, from: .number(width),
                               to: .number((width * 2 * 10).rounded() / 10),
                               timing: MotionTiming(startMS: 0, durationMS: 600),
                               curve: .easeInOut, repeats: plays)
        case .blur:
            // Comes ON, from clear to the softness the layer is already
            // wearing: that is the shot going out of focus, which is what
            // somebody asking for a blur over time nearly always means. The
            // other direction is one swap of two numbers away.
            let radius = if case let .number(number) = current ?? .number(8) { number } else { 8.0 }
            return LayerMotion(property: .blur, from: .number(0),
                               to: .number(radius > 0 ? radius : 8),
                               timing: MotionTiming(startMS: 0, durationMS: 1000),
                               curve: .easeInOut, repeats: plays)
        case .color:
            // The one property whose second value nobody can guess, so it
            // starts where the layer is and waits for the colour you mean.
            let hex = if case let .color(hex) = current ?? .color("#000000") { hex } else { "#000000" }
            return LayerMotion(property: .color, from: .color(hex), to: .color(hex),
                               timing: MotionTiming(startMS: 0, durationMS: 600),
                               curve: .easeInOut, repeats: plays)
        case .cornerRadius, .shadow, .textSize:
            // Reached through a key diamond rather than the plus, but a motion
            // of any property can be asked for, so these start from what the
            // layer has and grow by half: something to see, tuned from there.
            let now = if case let .number(number) = current ?? .number(0) { number } else { 0.0 }
            let to = now > 0 ? (now * 1.5 * 10).rounded() / 10 : 12
            return LayerMotion(property: property, from: .number(now), to: .number(to),
                               timing: MotionTiming(startMS: 0, durationMS: 600),
                               curve: .easeInOut, repeats: plays)
        case .glow:
            // Grows the glow it has by half, the same as the lengths above.
            let now = if case let .number(number) = current ?? .number(0) { number } else { 0.0 }
            let to = now > 0 ? (now * 1.5 * 10).rounded() / 10 : Double(GlowEffect.startingSize)
            return LayerMotion(property: .glow, from: .number(now), to: .number(to),
                               timing: MotionTiming(startMS: 0, durationMS: 600),
                               curve: .easeInOut, repeats: plays)
        case .cropLeft, .cropTop, .cropRight, .cropBottom:
            // A wipe in from that edge: nothing cut away, then a quarter.
            return LayerMotion(property: property, from: .number(0), to: .number(25),
                               timing: MotionTiming(startMS: 0, durationMS: 600),
                               curve: .easeInOut, repeats: plays)
        }
    }
}

// MARK: - The picture at a moment

extension Layer {

    /// Whether anything about this layer is moving.
    public var hasMotion: Bool { !(motions ?? []).isEmpty }

    /// Whether this layer or anything inside it moves.
    ///
    /// An icon frame almost never moves itself: what swings is the shapes drawn
    /// in it. So the question "does this frame have anything to play" has to
    /// reach all the way down, and `hasMotion` on the frame alone would answer
    /// no for every icon anybody makes.
    public var hasMotionInside: Bool {
        hasMotion || (group?.children.contains { $0.hasMotionInside } ?? false)
    }

    /// The longest any motion on this layer runs, measured from the top of the
    /// cycle. Nought when nothing on it moves.
    var motionEndMS: Int {
        (motions ?? []).filter(\.isOn).map(\.timing.endMS).max() ?? 0
    }

    /// This layer as it looks `ms` into the preview.
    ///
    /// Never stored. The document keeps the layer you drew, and this is what
    /// the canvas is handed to draw instead — the same bargain the rest of the
    /// styling strikes, where nothing is ever baked into pixels.
    ///
    /// `magnification` is how much bigger than drawn everything ABOVE this
    /// layer is at this moment. It matters because the lengths a motion states
    /// in points — how far to slide, how thick a line to draw — are stated in
    /// the size the layer was drawn at, and an exported file writes them
    /// inside the growth, where a browser multiplies them without being asked
    /// (`MotionProperty.nestingOrder`). One is passed in rather than read off
    /// the layer because a layer cannot see what contains it.
    public func moved(toMotionTimeMS ms: Int, cycleMS: Int,
                      magnification: CGFloat = 1) -> Layer {
        var moved = self
        // From the INSIDE out, so the picture does not depend on which order
        // somebody happened to add the rows in and matches the way an exported
        // file nests them (`MotionProperty.nestingOrder`).
        for motion in (motions ?? []).filter(\.isOn).sorted(by: { left, right in
            let order = MotionProperty.nestingOrder
            let l = order.firstIndex(of: left.property) ?? 0
            let r = order.firstIndex(of: right.property) ?? 0
            return l > r
        }) {
            moved = motion.property.applied(motion.value(atMS: ms, cycleMS: cycleMS),
                                            to: moved, authored: self,
                                            magnification: magnification)
        }
        return moved
    }
}

extension MotionProperty {

    /// `layer` wearing `value` for this property.
    ///
    /// `authored` is the layer as it was drawn, which is what scale is a
    /// percentage OF: reading the size off a layer another motion has already
    /// grown would compound frame by frame and run away.
    ///
    /// `magnification` is how much everything containing this layer has
    /// already grown it, which is what the two lengths stated in points get
    /// multiplied by.
    func applied(_ value: MotionValue, to layer: Layer, authored: Layer,
                 magnification: CGFloat = 1) -> Layer {
        var moved = layer
        // A growth of nought leaves nothing to draw and a growth that is not a
        // number is not one, so neither is allowed to eat the distance.
        let grown = magnification.isFinite && magnification > 0 ? magnification : 1
        switch (self, value) {
        case let (.position, .point(point)):
            // Written as a MOVE from where it was drawn rather than as an
            // origin set outright, so that animating position and scale on the
            // same layer gives the same box whichever order the two are in. An
            // origin set outright would be the top-left of whatever size scale
            // had just made it, which is a different place.
            //
            // The distance is multiplied by whatever has already magnified
            // this layer from above: a piece told to slide 20pt inside an icon
            // drawn at twice the size travels 40pt, because that is what the
            // same file does in a browser, where the translate is written
            // inside the scale.
            moved.frame.origin = CGPoint(
                x: moved.frame.origin.x + (point.x - authored.frame.origin.x) * grown,
                y: moved.frame.origin.y + (point.y - authored.frame.origin.y) * grown)
        case let (.scale, .number(percent)):
            // A real magnification about the middle of the box, so the drawing
            // grows and not just the box round it: anchors, endpoints, line
            // weight, type size, corner and shadow all multiplied together
            // (`MotionScale.swift`). Setting the frame alone left a 40pt shape
            // painted into an 80pt box, which is why Scale looked broken.
            //
            // Read off `moved` rather than `authored`, and safely: scale is the
            // only motion that changes the size of anything, and a layer is
            // offered it once, so there is nothing here to compound. Growing
            // what the other motions have already done is also what the export
            // does, where the scale wraps everything inside it.
            // The middle of what is DRAWN, which on a group is the box its
            // contents make rather than its own anchor: a group's frame is a
            // corner to measure its children from, and swelling about that
            // corner would send the drawing off across the canvas.
            //
            // A picture with a keyed crop grows about the middle of the WHOLE
            // picture, the way Premiere grows about its anchor whatever is
            // cropped: about the middle of what is left, the part kept would
            // slide across the screen as the crop moved.
            let middle = moved.group == nil
                ? (moved.hasKeyedCrop ? authored.frame.standardized : moved.frame.standardized)
                : moved.localBounds
            moved = moved.drawnLarger(by: CGFloat(percent) / 100,
                                      about: CGPoint(x: middle.midX, y: middle.midY))
        case let (.rotation, .number(degrees)):
            moved.transform.rotation = CGFloat(degrees) * .pi / 180
        case let (.opacity, .number(percent)):
            moved.style.opacity = min(max(percent / 100, 0), 1)
        case let (.color, .color(hex)):
            if let painted = Fill.filled(moved, colorHex: hex, solidRef: nil) { moved = painted }
        case let (.blur, .number(points)):
            // The same number the Effects panel's own slider sets, so a blur
            // being animated and a blur being dragged are one value with one
            // meaning. Magnified from above like the other two lengths said in
            // points: a drawing at twice the size blurs twice as softly.
            moved.style.blurRadius = CGFloat(max(0, points)) * grown
        case let (.strokeWidth, .number(points)):
            // Points again, and magnified for the same reason: the file writes
            // the width inside the growth, so 3pt of line on a drawing at
            // twice the size is drawn 6pt thick. The layer's OWN growth does
            // this already by wrapping this row (`nestingOrder`); what is
            // multiplied here is only what came from above.
            moved.setOutlineWidthForMotion(CGFloat(max(0, points)) * grown)
        case let (.cornerRadius, .number(points)):
            // Rounded the way the layer rounds: a box curves its own outline,
            // a picture or a clip is masked (`setRoundedCorners`).
            moved.setRoundedCorners(CGFloat(max(0, points)) * grown)
        case let (.shadow, .number(points)):
            // The first shadow's softness. A layer with none is given one the
            // moment the size rises above nothing, which is what keying a
            // shadow onto a title that never had one means; at nothing it is
            // left without one rather than carrying an invisible entry.
            let radius = CGFloat(max(0, points)) * grown
            var shadows = moved.style.shadows
            if shadows.isEmpty {
                if radius > 0 { moved.style.shadows = [ShadowStyle(radius: radius)] }
            } else {
                shadows[0].radius = radius
                moved.style.shadows = shadows
            }
        case let (.textSize, .number(points)):
            // The type grows and so does the box it is set in, about the box's
            // middle, so the words neither wrap nor get cut off on the way up.
            guard var text = moved.text, text.fontSize > 0 else { break }
            let size = CGFloat(max(1, points)) * grown
            let factor = size / text.fontSize
            text.fontSize = size
            moved.content = .text(text)
            let box = moved.frame.standardized
            let grownBox = CGSize(width: box.width * factor, height: box.height * factor)
            moved.frame = CGRect(x: box.midX - grownBox.width / 2, y: box.midY - grownBox.height / 2,
                                 width: grownBox.width, height: grownBox.height)
        case let (.glow, .number(points)):
            // The first glow's reach. A key never brings a glow in: the row is
            // only offered where one is already there.
            guard let index = moved.style.effects.firstIndex(where: { $0.kind == .glow }) else { break }
            moved.style.updateGlowEffect(at: index) { $0.size = CGFloat(max(0, points)) * grown }
        case let (.cropLeft, .number(percent)), let (.cropTop, .number(percent)),
             let (.cropRight, .number(percent)), let (.cropBottom, .number(percent)):
            moved = moved.croppedByKey(self, percent: percent, authored: authored)
        default:
            break
        }
        return moved
    }
}

extension Layer {

    /// The width of the one line round this layer, set. The mirror of
    /// `outlineWidth`, and only ever reached by a stroke-width motion: every
    /// other caller sets the line through the panel that owns it.
    mutating func setOutlineWidthForMotion(_ width: CGFloat) {
        if var path {
            path.strokeWidth = width
            content = .path(path)
            return
        }
        if var annotation, drawsItsOwnOutline {
            annotation.strokeWidth = width
            content = .annotation(annotation)
            return
        }
        style.borderWidth = width
    }
}

extension PhotonzDocument {

    /// Whether anything in this document moves at all. Asked before a clock is
    /// started, so a still document costs nothing.
    public var hasMotion: Bool {
        allLayers.contains { $0.hasMotion }
    }

    /// How long one cycle of the loop is, in milliseconds: whatever has been
    /// written down for this document, and otherwise as long as the last thing
    /// to finish.
    ///
    /// ONE CYCLE, not a document timeline. An icon repeats and a video
    /// finishes, and the study is explicit that the two cannot share a ruler.
    ///
    /// The written length is what lets a bar run PAST the point the lap starts
    /// over, which is what a lag in something that loops IS: with the lap
    /// always growing to fit its longest motion, nothing could ever overrun it
    /// (`MotionStrip.swift`).
    public var motionCycleLengthMS: Int {
        if let motionCycleMS { return max(1, motionCycleMS) }
        return automaticMotionCycleLengthMS
    }

    /// How long the lap would be if nobody had written one down: as long as the
    /// last thing to finish. Nought where nothing moves.
    public var automaticMotionCycleLengthMS: Int {
        var longest = 0
        forEachLayer { longest = max(longest, $0.motionEndMS) }
        return longest
    }

    /// Whether the lap simply follows the longest motion, which is what it does
    /// until somebody says otherwise.
    public var motionCycleIsAutomatic: Bool { motionCycleMS == nil }

    /// The whole picture as it looks `ms` into the preview, groups and all.
    ///
    /// The document itself is untouched: what comes back is what the canvas is
    /// handed to draw, so the layer you can still drag is the one you drew.
    public func moved(toMotionTimeMS ms: Int) -> PhotonzDocument {
        let cycle = motionCycleLengthMS
        guard cycle > 0 else { return self }
        var moved = self
        moved.layers = layers.map { $0.movedTree(toMotionTimeMS: ms, cycleMS: cycle) }
        return moved
    }

    /// The same, for ONE layer and everything inside it.
    ///
    /// What the previews strip needs: it draws one icon frame at four small
    /// sizes, thirty times a second, and moving every layer of a document it is
    /// not showing would be a copy of the whole picture per frame for a picture
    /// of one frame. Everything outside `layerID` comes back exactly as it was
    /// drawn.
    public func moved(layerID: UUID, toMotionTimeMS ms: Int) -> PhotonzDocument {
        let cycle = motionCycleLengthMS
        guard cycle > 0 else { return self }
        var moved = self
        moved.updateLayer(id: layerID) { layer in
            layer = layer.movedTree(toMotionTimeMS: ms, cycleMS: cycle)
        }
        return moved
    }

    /// True once nothing in the document is moving any more, so the preview
    /// can stop.
    public func motionHasSettled(atMS ms: Int) -> Bool {
        let cycle = motionCycleLengthMS
        guard cycle > 0 else { return true }
        return allLayers.allSatisfy { layer in
            (layer.motions ?? []).allSatisfy { $0.hasSettled(atMS: ms, cycleMS: cycle) }
        }
    }
}

extension Layer {

    /// This layer and everything inside it, moved. A motion on a layer INSIDE
    /// a group has to be found or half an icon would animate.
    ///
    /// The growth carries DOWN. Applying this layer's own motions magnifies
    /// everything inside it, so by the time a child is asked what it does, it
    /// is already drawn bigger, and the distances its own motions state in
    /// points have to be read at that size or the app and an exported file
    /// part company on the first nested slide.
    func movedTree(toMotionTimeMS ms: Int, cycleMS: Int,
                   magnification: CGFloat = 1) -> Layer {
        var moved = moved(toMotionTimeMS: ms, cycleMS: cycleMS, magnification: magnification)
        if var group = moved.group {
            let inside = magnification * motionMagnification(atMS: ms, cycleMS: cycleMS)
            group.children = group.children.map {
                $0.movedTree(toMotionTimeMS: ms, cycleMS: cycleMS, magnification: inside)
            }
            moved.content = .group(group)
        }
        return moved
    }

    /// How much this layer's own growth magnifies what is drawn inside it at
    /// `ms`: the scale row's value as a factor, and 1 where it has no scale
    /// row or the row says something that is not a size.
    func motionMagnification(atMS ms: Int, cycleMS: Int) -> CGFloat {
        guard let growth = (motions ?? []).first(where: { $0.isOn && $0.property == .scale }),
              case let .number(percent) = growth.value(atMS: ms, cycleMS: cycleMS)
        else { return 1 }
        let factor = CGFloat(percent) / 100
        return factor.isFinite && factor > 0 ? factor : 1
    }
}
