import CoreGraphics
import Foundation

// Clicking a key opens a small popover to type that key's value (task
// `clicking-a-key-opens-the-same-overlay-to-set-tha`,
// `docs/design/mocks/pages/video-animate.html`, THE KEY OVERLAY; the placement
// contract's "Named exception: the transform values", the key overlay).
//
// One code path for every value a key can hold: the picked keys read back as
// one row per keyed value, in its own units, Mixed where they differ; a value
// typed lands on every picked key of that value and on nothing else; Reset
// puts them at the value an untouched layer has. No row per property, no
// panel per property.

/// What one row of the key popover shows.
public enum KeyValueReading: Hashable, Sendable {
    /// One number every picked key of this value agrees on.
    case number(Double)
    /// A point: each axis is nil where the picked keys differ on it.
    case point(x: Double?, y: Double?)
    /// One colour, `#RRGGBB` or `#RRGGBBAA`.
    case color(String)
    /// The picked keys of this value differ.
    case mixed
}

/// One keyed value among the picked keys: a row of the popover.
public struct KeyValueRow: Hashable, Sendable {
    public let motionID: UUID
    public let property: MotionProperty
    /// The lane's own name ("Opacity", "Shadow 2 distance").
    public let title: String
    /// What the picked keys of this value hold.
    public let value: KeyValueReading
    /// The unit after the number, nil for a length or a point.
    public var unit: String? { property.keyValueUnit }

    public init(motionID: UUID, property: MotionProperty, title: String, value: KeyValueReading) {
        self.motionID = motionID
        self.property = property
        self.title = title
        self.value = value
    }
}

/// A value typed into a row.
public enum KeyValueEdit: Hashable, Sendable {
    case number(Double)
    /// One axis of a point; the other stays as each key has it.
    case x(Double)
    case y(Double)
    /// A colour as typed: `#` or not, six or eight hex digits.
    case color(String)
}

extension MotionProperty {
    /// The unit the popover writes after the number: percent and degrees,
    /// and nothing for a length, the transform values' way.
    public var keyValueUnit: String? {
        switch self {
        case .opacity, .scale, .shadowOpacity, .glowOpacity, .cropLeft, .cropTop, .cropRight, .cropBottom,
             .trimStart, .trimEnd, .backgroundZoom, .gradeSaturation:
            "%"
        case .rotation, .rotationX, .rotationY, .shadowDirection, .cameraPerspective:
            "°"
        default:
            nil
        }
    }

    /// What Reset puts a key back to: the value a layer nobody has touched
    /// has. Nil where there is no one such value (a place, a colour, a size
    /// of type), and Reset then has nothing to do.
    public var keyValueDefault: MotionValue? {
        switch self {
        case .opacity, .scale, .shadowOpacity, .glowOpacity, .trimEnd, .backgroundZoom, .gradeSaturation:
            .number(100)
        case .rotation, .rotationX, .rotationY, .depth, .pivotDepth, .blur, .backgroundBlur,
             .cropLeft, .cropTop, .cropRight, .cropBottom, .trimStart,
             .gradeTemperature, .gradeTint, .gradeExposure, .gradeContrast:
            .number(0)
        default:
            nil
        }
    }
}

extension PhotonzDocument {

    /// The picked keys of a layer, one row per keyed value, in the lanes'
    /// order.
    public func keyValueRows(layerID: UUID, _ refs: Set<KeyRef>) -> [KeyValueRow] {
        guard let layer = layer(id: layerID) else { return [] }
        return picked(refs, on: layer).map { motion, indices in
            let values = indices.map { laneReading(of: layer, motion, motion.keyframes[$0]) }
            return KeyValueRow(motionID: motion.id, property: motion.property,
                               title: KeyedProperty.motion(motion.property, effect: motion.effectOrdinal)
                                   .title(on: layer),
                               value: Self.reading(values))
        }
    }

    private static func reading(_ values: [MotionValue]) -> KeyValueReading {
        func agreed(_ numbers: [Double]) -> Double? {
            guard let first = numbers.first, numbers.allSatisfy({ abs($0 - first) < 1e-6 }) else { return nil }
            return first
        }
        let numbers = values.compactMap { value -> Double? in
            if case let .number(number) = value { return number }
            return nil
        }
        if numbers.count == values.count { return agreed(numbers).map { .number($0) } ?? .mixed }
        let points = values.compactMap { value -> CGPoint? in
            if case let .point(point) = value { return point }
            return nil
        }
        if points.count == values.count {
            return .point(x: agreed(points.map { Double($0.x) }), y: agreed(points.map { Double($0.y) }))
        }
        let colors = values.compactMap { value -> String? in
            if case let .color(hex) = value { return hex.uppercased() }
            return nil
        }
        if colors.count == values.count, let first = colors.first, colors.allSatisfy({ $0 == first }) {
            return .color(first)
        }
        return .mixed
    }

    /// A value typed into a row: every picked key of `motionID` takes it,
    /// kept to what the property can be. One change. False where nothing
    /// changed: no picked key there, or a value of the wrong kind.
    @discardableResult
    public mutating func setKeyValues(layerID: UUID, _ refs: Set<KeyRef>, motionID: UUID,
                                      _ edit: KeyValueEdit) -> Bool {
        guard let layer = layer(id: layerID),
              let (motion, indices) = picked(refs, on: layer).first(where: { $0.0.id == motionID }) else {
            return false
        }
        var list = motion.keyframes
        var changed = false
        for index in indices {
            guard let value = edited(list[index].value, edit, motion: motion, key: list[index], on: layer)
            else { return false }
            if value != list[index].value {
                list[index].value = value
                changed = true
            }
        }
        guard changed else { return false }
        replaceMotions(layerID: layerID, [motion.id: motion.rebuilt(from: list)])
        return true
    }

    /// What a key holds once `edit` lands on it, or nil where the edit is
    /// not the kind of thing the key holds.
    private func edited(_ value: MotionValue, _ edit: KeyValueEdit, motion: LayerMotion, key: MotionStop,
                        on layer: Layer) -> MotionValue? {
        switch (value, edit) {
        case let (.number, .number(number)):
            return .number(motion.property.graphBounded(number))
        case (.point, .x), (.point, .y):
            // A recording that reads its place as its middle is typed in its
            // middle, and stored as the corner that puts it there.
            guard case let .point(shown) = laneReading(of: layer, motion, key) else { return nil }
            var point = shown
            if case let .x(x) = edit { point.x = CGFloat(x) }
            if case let .y(y) = edit { point.y = CGFloat(y) }
            return .point(storedPoint(point, of: layer, motion, key))
        case let (.color, .color(typed)):
            let digits = typed.trimmingCharacters(in: .whitespaces)
            guard let rgba = RGBA(hex: digits) else { return nil }
            let bare = digits.hasPrefix("#") ? String(digits.dropFirst()) : digits
            return .color(bare.count == 8 ? "#" + bare.uppercased() : rgba.hexString)
        default:
            return nil
        }
    }

    /// The corner stored for a place read as `shown`: the inverse of
    /// `laneReading`.
    private func storedPoint(_ shown: CGPoint, of layer: Layer, _ motion: LayerMotion, _ key: MotionStop) -> CGPoint {
        guard motion.property == .position, motion.effectOrdinal == 0, layer.positionReadsAsCentre else {
            return shown
        }
        var percent: Double = 100
        let cycle = layer.motionCycleMS(documentCycleMS: max(1, documentDurationMS))
        if let scale = layer.keyedMotion(.scale),
           case let .number(number) = scale.value(atMS: key.atMS, cycleMS: cycle), number > 0 {
            percent = number
        }
        return ClipReframe.origin(centring: shown, in: layer.frame, atScalePercent: percent)
    }

    /// What Reset puts one key at: its value's default, and for a place the
    /// middle of the canvas (the mock's Position default).
    private func resetValue(_ motion: LayerMotion, _ key: MotionStop, on layer: Layer) -> MotionValue? {
        if let value = motion.property.keyValueDefault { return value }
        guard motion.property == .position, motion.effectOrdinal == 0 else { return nil }
        let middle: CGPoint
        if layer.positionReadsAsCentre {
            middle = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        } else {
            middle = CGPoint(x: (canvasSize.width - layer.frame.width) / 2,
                             y: (canvasSize.height - layer.frame.height) / 2)
        }
        return .point(storedPoint(middle, of: layer, motion, key))
    }

    /// Whether Reset would change anything: a picked key of a value with a
    /// default that is not at it.
    public func canResetKeyValues(layerID: UUID, _ refs: Set<KeyRef>) -> Bool {
        guard let layer = layer(id: layerID) else { return false }
        return picked(refs, on: layer).contains { motion, indices in
            indices.contains { index in
                let key = motion.keyframes[index]
                guard let value = resetValue(motion, key, on: layer) else { return false }
                return key.value != value
            }
        }
    }

    /// Reset: every picked key of a value with a default goes to it. One
    /// change. False where nothing changed.
    @discardableResult
    public mutating func resetKeyValues(layerID: UUID, _ refs: Set<KeyRef>) -> Bool {
        guard let layer = layer(id: layerID) else { return false }
        var made: [UUID: LayerMotion?] = [:]
        for (motion, indices) in picked(refs, on: layer) {
            var list = motion.keyframes
            var changed = false
            for index in indices {
                guard let value = resetValue(motion, list[index], on: layer), list[index].value != value else { continue }
                list[index].value = value
                changed = true
            }
            if changed { made[motion.id] = motion.rebuilt(from: list) }
        }
        guard !made.isEmpty else { return false }
        replaceMotions(layerID: layerID, made)
        return true
    }
}

/// Where the key popover sits: above the key it hangs from, centred on it,
/// below it where there is no room above, slid in to stay inside the window,
/// and never over the key (the mock's "Near the top of the timeline").
///
/// On an open graph the key is a point on a curve, and the popover keeps off
/// the curve and the handles shaping it as well, so the segment a person is
/// about to shape stays in sight: it slides along above the point, then tries
/// below it, then beside it, and where no spot is clear it takes the one that
/// covers least.
public enum KeyValuesPlacement {
    /// Between the key and the popover.
    public static let gap: CGFloat = 8
    /// Between the popover and the window's edge.
    public static let margin: CGFloat = 8
    /// How far off a line the popover keeps: a picked segment's stroke is
    /// five points wide, and air past that so the line reads as its own.
    public static let clearance: CGFloat = 8

    public static func frame(anchor: CGRect, size: CGSize, in bounds: CGRect) -> CGRect {
        let lowestX = bounds.minX + margin
        let highestX = max(lowestX, bounds.maxX - margin - size.width)
        let x = min(max(anchor.midX - size.width / 2, lowestX), highestX)
        let above = anchor.minY - gap - size.height
        let y = above >= bounds.minY + margin ? above : anchor.maxY + gap
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The same, kept off `lines`: polylines in the anchor's own space (the
    /// curve's segments and the handles drawn on it). With nothing to keep
    /// off, or nothing under the plain spot, it is the plain spot.
    public static func frame(anchor: CGRect, size: CGSize, in bounds: CGRect, clearOf lines: [[CGPoint]]) -> CGRect {
        let plain = frame(anchor: anchor, size: size, in: bounds)
        var best = plain
        var least = covered(plain, by: lines)
        guard least > 0 else { return plain }
        for spot in spots(anchor: anchor, size: size, in: bounds) where !spot.intersects(anchor) {
            let under = covered(spot, by: lines)
            if under == 0 { return spot }
            // Only a spot that covers clearly less moves it off the plain one.
            if under < least - 0.5 {
                best = spot
                least = under
            }
        }
        return best
    }

    /// How much of `lines` lies under `frame`, grown by the clearance, in
    /// points of line.
    public static func covered(_ frame: CGRect, by lines: [[CGPoint]]) -> CGFloat {
        let box = frame.insetBy(dx: -clearance, dy: -clearance)
        var length: CGFloat = 0
        for line in lines {
            if line.count == 1, let only = line.first, box.contains(only) { length += 1 }
            for (a, b) in zip(line, line.dropFirst()) {
                length += clippedLength(from: a, to: b, in: box)
            }
        }
        return length
    }

    /// The spots worth trying, nearest the plain one first: along above the
    /// key, then along below it, then beside it. Each is slid inside the
    /// window; above and below are only tried where they fit.
    private static func spots(anchor: CGRect, size: CGSize, in bounds: CGRect) -> [CGRect] {
        let lowestX = bounds.minX + margin
        let highestX = max(lowestX, bounds.maxX - margin - size.width)
        let lowestY = bounds.minY + margin
        let highestY = max(lowestY, bounds.maxY - margin - size.height)
        func slid(x: CGFloat, y: CGFloat) -> CGRect {
            CGRect(x: min(max(x, lowestX), highestX), y: min(max(y, lowestY), highestY),
                   width: size.width, height: size.height)
        }
        let centred = anchor.midX - size.width / 2
        let beside = size.width / 2 + anchor.width / 2 + gap
        let along: [CGFloat] = [0, -size.width / 4, size.width / 4, -size.width / 2, size.width / 2, -beside, beside]
        var spots: [CGRect] = []
        let above = anchor.minY - gap - size.height
        if above >= lowestY { spots += along.map { slid(x: centred + $0, y: above) } }
        let below = anchor.maxY + gap
        if below <= highestY { spots += along.map { slid(x: centred + $0, y: below) } }
        let middle = anchor.midY - size.height / 2
        spots.append(slid(x: anchor.minX - gap - size.width, y: middle))
        spots.append(slid(x: anchor.maxX + gap, y: middle))
        return spots
    }

    /// The length of the stretch from `a` to `b` inside `box` (Liang and
    /// Barsky's clip).
    private static func clippedLength(from a: CGPoint, to b: CGPoint, in box: CGRect) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        var enter: CGFloat = 0, leave: CGFloat = 1
        for (p, q) in [(-dx, a.x - box.minX), (dx, box.maxX - a.x), (-dy, a.y - box.minY), (dy, box.maxY - a.y)] {
            if p == 0 {
                if q < 0 { return 0 }
            } else {
                let t = q / p
                if p < 0 { enter = max(enter, t) } else { leave = min(leave, t) }
            }
        }
        guard enter < leave else { return 0 }
        return (leave - enter) * (dx * dx + dy * dy).squareRoot()
    }
}
