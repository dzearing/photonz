import CoreGraphics
import Foundation

/// What a color slot actually holds.
///
/// Every color in the document used to be one flat hex string, which is why a
/// box could only ever be one color. A `Paint` is that same flat color plus,
/// when you ask for one, a ramp: a straight gradient, one spreading out from a
/// point, or one sweeping around it.
///
/// Two things about it are deliberate.
///
/// **The flat color never goes away.** `hex` is what a solid paints, AND it is
/// the color everything that can only draw one thing uses: an arrow's caption
/// pill, a swatch in a list, a contrast reading. So turning a fill into a
/// gradient and back gives you the color you started with, and nothing that
/// only understands hexes has to be taught about gradients first.
///
/// **A flat paint writes the plain string it always wrote.** `#FF3B30` on disk
/// stays `#FF3B30` on disk, so a document saved before gradients existed opens
/// unchanged and a document with no gradient in it is byte-identical to the one
/// the old build would have written. Only a gradient costs an object.
public struct Paint: Hashable, Sendable {

    /// The four shapes a paint can take. `solid` is one color; the other three
    /// read the ramp.
    public enum Kind: String, CaseIterable, Hashable, Codable, Sendable {
        /// One flat color.
        case solid
        /// A straight run across the shape, aimed by `angle`.
        case linear
        /// Spreading out from `center` to the furthest corner.
        case radial
        /// Sweeping around `center`, starting at `angle`.
        case angular

        public var title: String {
            switch self {
            case .solid: return "Solid"
            case .linear: return "Linear"
            case .radial: return "Radial"
            case .angular: return "Angular"
            }
        }
    }

    /// Which shape this paint takes.
    public var kind: Kind
    /// The flat color: what `solid` paints, and the stand-in everywhere one
    /// color is all that can be drawn.
    public var hex: String
    /// The ramp, in no particular order — read `orderedStops`. Kept even while
    /// the paint is solid, so flipping the type back and forth is free.
    public var stops: [GradientStop]
    /// Degrees, the way CSS says them: 0 runs toward the top of the shape and
    /// they increase clockwise, so 90 runs to the right. `linear` aims its run
    /// with this; `angular` starts its sweep here; `radial` ignores it.
    public var angle: Double
    /// Where a `radial` or `angular` paint is centred, in the shape's own box:
    /// 0,0 is its top-left corner and 1,1 its bottom-right.
    public var center: CGPoint

    public init(hex: String,
                kind: Kind = .solid,
                stops: [GradientStop] = [],
                angle: Double = 135,
                center: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        self.kind = kind
        self.hex = hex
        self.stops = stops
        self.angle = angle
        self.center = center
    }

    /// A flat paint of this color, which is what every existing color in the
    /// app already is.
    public static func solid(_ hex: String) -> Paint { Paint(hex: hex) }

    // MARK: - Reading it

    /// Whether this actually draws a ramp. A type on its own is not enough:
    /// two stops are the fewest a gradient can be made of, so a paint marked
    /// `linear` with nothing in its ramp still draws flat rather than drawing
    /// nothing.
    public var isGradient: Bool { kind != .solid && stops.count >= 2 }

    /// The ramp read left to right, which is the only order that means
    /// anything. Stops are stored in the order they were made so that adding
    /// one does not renumber the one you are editing.
    public var orderedStops: [GradientStop] {
        stops.sorted { $0.position < $1.position }
    }

    /// The color this paint is at `t` along its ramp (0 to 1), or the flat
    /// color when it has no ramp. Past either end it holds the end color,
    /// which is what every gradient everywhere does.
    public func color(at t: Double) -> RGBA? {
        guard isGradient else { return RGBA(hex: hex) }
        let ramp = orderedStops.compactMap { stop -> (Double, RGBA)? in
            guard let rgba = RGBA(hex: stop.hex) else { return nil }
            return (stop.position, rgba)
        }
        guard let first = ramp.first, let last = ramp.last else { return RGBA(hex: hex) }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for (lower, upper) in zip(ramp, ramp.dropFirst()) where t >= lower.0 && t <= upper.0 {
            let span = upper.0 - lower.0
            let f = span > 0 ? (t - lower.0) / span : 0
            return RGBA(r: lower.1.r + (upper.1.r - lower.1.r) * f,
                        g: lower.1.g + (upper.1.g - lower.1.g) * f,
                        b: lower.1.b + (upper.1.b - lower.1.b) * f,
                        a: lower.1.a + (upper.1.a - lower.1.a) * f)
        }
        return last.1
    }

    // MARK: - Changing it

    /// Switches this paint to a type, seeding the ramp the first time a
    /// gradient is asked for so the first thing you see is YOUR color running
    /// somewhere rather than a stock preset.
    public mutating func becoming(_ kind: Kind) {
        self.kind = kind
        if kind != .solid, stops.count < 2 { stops = Paint.seededStops(from: hex) }
    }

    /// The ramp a solid turns into: the color you already had, running to a
    /// lighter, slightly warmer turn of itself.
    public static func seededStops(from hex: String) -> [GradientStop] {
        guard let rgba = RGBA(hex: hex) else {
            return [GradientStop(hex: hex, position: 0),
                    GradientStop(hex: "#FFFFFF", position: 1)]
        }
        let hsl = rgba.hsl
        let far = RGBA(hsl: HSL(hue: (hsl.hue + 40).truncatingRemainder(dividingBy: 360),
                                saturation: hsl.saturation,
                                lightness: min(0.86, hsl.lightness + 0.18)),
                       alpha: rgba.a)
        return [GradientStop(hex: hex, position: 0),
                GradientStop(hex: far.hexStringWithAlpha, position: 1)]
    }

    /// Adds a stop halfway to the next one along, or a short step past the one
    /// you are on when it is the last. Returns where the new stop landed in
    /// `stops`, which is the one to select.
    @discardableResult
    public mutating func addStop(after index: Int) -> Int {
        guard stops.indices.contains(index) else { return index }
        let from = stops[index]
        let next = stops.filter { $0.position > from.position }.min { $0.position < $1.position }
        let position = next.map { (from.position + $0.position) / 2 }
            ?? min(1, from.position + 0.2)
        stops.append(GradientStop(hex: from.hex, position: position))
        return stops.count - 1
    }

    /// Takes a stop out, unless it is one of the last two: a gradient needs
    /// two colors to be a gradient at all, and the way to a flat color is the
    /// Solid tile rather than deleting your way down to it.
    @discardableResult
    public mutating func removeStop(at index: Int) -> Bool {
        guard stops.count > 2, stops.indices.contains(index) else { return false }
        stops.remove(at: index)
        return true
    }

    /// Mirrors every stop, so what ran dark-to-light runs light-to-dark.
    public mutating func reverseStops() {
        for index in stops.indices { stops[index].position = 1 - stops[index].position }
    }
}

/// One color on a ramp, at a place along it.
public struct GradientStop: Hashable, Codable, Sendable {
    /// `#RRGGBB`, or `#RRGGBBAA` where the stop is see-through.
    public var hex: String
    /// Where it sits, 0 at the start of the ramp and 1 at its end.
    public var position: Double

    public init(hex: String, position: Double) {
        self.hex = hex
        self.position = min(max(position, 0), 1)
    }
}

// MARK: - On disk

extension Paint: Codable {

    private enum CodingKeys: String, CodingKey {
        case kind, hex, stops, angle, cx, cy
    }

    /// A flat paint writes the bare hex string the document has always held,
    /// so nothing that never used a gradient changes shape on disk.
    public func encode(to encoder: any Encoder) throws {
        guard kind != .solid else {
            var single = encoder.singleValueContainer()
            try single.encode(hex)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(hex, forKey: .hex)
        try c.encode(stops, forKey: .stops)
        try c.encode(angle, forKey: .angle)
        try c.encode(center.x, forKey: .cx)
        try c.encode(center.y, forKey: .cy)
    }

    /// A bare string is the color it always was; anything else is a gradient
    /// written by a build that knew about them.
    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let hex = try? single.decode(String.self) {
            self.init(hex: hex)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let hex = try c.decodeIfPresent(String.self, forKey: .hex) ?? "#000000"
        self.init(hex: hex,
                  kind: try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .solid,
                  stops: try c.decodeIfPresent([GradientStop].self, forKey: .stops) ?? [],
                  angle: try c.decodeIfPresent(Double.self, forKey: .angle) ?? 135,
                  center: CGPoint(x: try c.decodeIfPresent(CGFloat.self, forKey: .cx) ?? 0.5,
                                  y: try c.decodeIfPresent(CGFloat.self, forKey: .cy) ?? 0.5))
    }
}

// MARK: - Where the geometry lands

extension Paint {

    /// The two ends of a `linear` run across a box, in the box's own top-left
    /// coordinates. The line is the CSS one: it passes through the middle at
    /// `angle`, and it is long enough that the corners reach the ramp's ends.
    public func linearEnds(in box: CGRect) -> (start: CGPoint, end: CGPoint) {
        let radians = angle * .pi / 180
        // 0 degrees points at the top of the box, which is DOWN the y axis
        // here, because document space counts y from the top.
        let direction = CGPoint(x: sin(radians), y: -cos(radians))
        let length = abs(box.width * direction.x) + abs(box.height * direction.y)
        let middle = CGPoint(x: box.midX, y: box.midY)
        return (CGPoint(x: middle.x - direction.x * length / 2,
                        y: middle.y - direction.y * length / 2),
                CGPoint(x: middle.x + direction.x * length / 2,
                        y: middle.y + direction.y * length / 2))
    }

    /// Where a `radial` or `angular` paint is centred, in the box's own
    /// top-left coordinates.
    public func centerPoint(in box: CGRect) -> CGPoint {
        CGPoint(x: box.minX + box.width * center.x,
                y: box.minY + box.height * center.y)
    }

    /// How far a `radial` paint reaches: to the furthest corner, which is what
    /// keeps the ramp's far end visible however off-centre it is aimed.
    public func radialRadius(in box: CGRect) -> CGFloat {
        let middle = centerPoint(in: box)
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
        return corners.map { hypot($0.x - middle.x, $0.y - middle.y) }.max() ?? 0
    }
}
