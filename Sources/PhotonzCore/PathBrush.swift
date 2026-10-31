import CoreGraphics
import Foundation

// A path's line painted with a brush (`docs/design/brushes.md`, decision 9;
// PRODUCT-MODEL.md, "Vector strokes are brushes"). The path keeps its exact
// anchors; only the LINE changes: instead of a plain stroke it is walked into
// brush strokes, the same `BrushStroke` value a person's pointer makes, and
// painted by the same engine. Move an anchor and the walk is taken again, so
// the brushed line follows the new curve. Nothing here draws: PathRasterizer
// hands these strokes to PaintRasterizer.

/// The brush a path's line is painted with: a medium and its settings, and the
/// seed its grain and bristles are drawn from, so the line looks the same on
/// every render.
///
/// The line's width is the path's own Thickness (`PathContent.strokeWidth`),
/// never a second number kept here, and its colour is the line's colour: so
/// the Thickness slider and the colour well go on meaning what they mean, and
/// the brush only decides what the line is made of.
public struct PathBrush: Hashable, Codable, Sendable {
    public var settings: BrushSettings
    public var seed: UInt32

    public init(settings: BrushSettings, seed: UInt32 = PathBrush.defaultSeed) {
        var settings = settings
        // A line is painted, never smudged: there is nothing under a path's
        // own line for a finger to drag.
        settings.mode = .paint
        self.settings = settings
        self.seed = seed
    }

    /// One fixed seed, so a path brushed by hand and the same path brushed by
    /// the agent are the same picture.
    public static let defaultSeed: UInt32 = 7

    public var medium: BrushMedium { settings.medium }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(settings: try c.decode(BrushSettings.self, forKey: .settings),
                  seed: try c.decodeIfPresent(UInt32.self, forKey: .seed) ?? PathBrush.defaultSeed)
    }

    private enum CodingKeys: String, CodingKey { case settings, seed }
}

extension PathContent {

    /// How far apart the points a brushed line is walked through are, in
    /// points: close enough that the brush's own curve through them is the
    /// path's curve, never so close a long line costs more than its dabs.
    static func brushStep(width: CGFloat) -> CGFloat { min(4, max(1, width / 4)) }

    /// The line as brush strokes, in the layer's own top-left points: one a
    /// figure of the line as drawn (each ring, or each dash of a dashed line,
    /// after any trim), empty when the path has no brush or no line.
    ///
    /// An open figure is walked the way a steady mouse would paint it, with no
    /// pressure, so the engine tapers both of its ends (decision 6). A closed
    /// figure has no ends: it is walked at the steady press all the way round
    /// and its last point meets its first, so no taper shows a seam.
    public var brushStrokes: [BrushStroke] {
        guard let brush, strokeWidth > 0, anchors.count >= 2 else { return [] }
        var settings = brush.settings
        settings.set("size", to: Double(strokeWidth))
        settings.mode = .paint
        var line = cgPath
        if let trim, !trim.isWhole { line = trim.applied(to: line) }
        if let dash = dashPattern { line = line.copy(dashingWithPhase: 0, lengths: dash) }
        let step = Self.brushStep(width: strokeWidth)
        return Self.figures(of: line, step: step).enumerated().compactMap { index, figure in
            guard figure.points.count >= 2 else { return nil }
            var samples: [StrokeSample] = []
            var ms = 0.0
            for point in figure.points {
                if let last = samples.last?.point {
                    ms += Double(hypot(point.x - last.x, point.y - last.y)) / AgentPaint.handSpeed
                }
                samples.append(StrokeSample(point: point,
                                            pressure: figure.closed ? BrushDynamics.steadyPress : nil,
                                            ms: ms))
            }
            return BrushStroke(samples: samples, settings: settings, colorHex: paint.hex,
                               seed: brush.seed &+ UInt32(index))
        }
    }

    /// How far a brushed line marks past the outline, in points: half its
    /// width stretched by how far the medium reaches past its Size (a hard
    /// press, a lean, a bleeding wash). Zero without a brush.
    var brushOutset: CGFloat {
        guard let brush, strokeWidth > 0 else { return 0 }
        return strokeWidth / 2 * CGFloat(brush.medium.reach)
    }

    /// One figure of a path walked as points no further apart than `step`:
    /// the anchors' runs cut finely along their length, and whether the
    /// figure closes back on its start.
    struct Figure: Hashable {
        var points: [CGPoint]
        var closed: Bool
    }

    static func figures(of path: CGPath, step: CGFloat) -> [Figure] {
        var figures: [Figure] = []
        var current = Figure(points: [], closed: false)
        var at = CGPoint.zero
        func finish() {
            if current.points.count >= 2 { figures.append(current) }
            current = Figure(points: [], closed: false)
        }
        func add(_ point: CGPoint) {
            if let last = current.points.last, last == point { return }
            current.points.append(point)
        }
        func run(steps: Int, _ curve: (CGFloat) -> CGPoint) {
            for index in 1...max(1, steps) { add(curve(CGFloat(index) / CGFloat(max(1, steps)))) }
        }
        func count(_ length: CGFloat) -> Int { max(1, Int((length / step).rounded(.up))) }
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                finish()
                at = points[0]
                add(at)
            case .addLineToPoint:
                let from = at, to = points[0]
                run(steps: count(hypot(to.x - from.x, to.y - from.y))) { t in
                    CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
                }
                at = to
            case .addQuadCurveToPoint:
                let from = at, control = points[0], to = points[1]
                let length = hypot(control.x - from.x, control.y - from.y) + hypot(to.x - control.x, to.y - control.y)
                run(steps: count(length)) { t in
                    let u = 1 - t
                    return CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                                   y: u * u * from.y + 2 * u * t * control.y + t * t * to.y)
                }
                at = to
            case .addCurveToPoint:
                let from = at, c1 = points[0], c2 = points[1], to = points[2]
                // The control polygon is never shorter than the curve, so
                // cutting by it never leaves a step longer than `step`.
                let length = hypot(c1.x - from.x, c1.y - from.y) + hypot(c2.x - c1.x, c2.y - c1.y)
                    + hypot(to.x - c2.x, to.y - c2.y)
                run(steps: count(length)) { t in
                    let u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    return CGPoint(x: a * from.x + b * c1.x + c * c2.x + d * to.x,
                                   y: a * from.y + b * c1.y + c * c2.y + d * to.y)
                }
                at = to
            case .closeSubpath:
                if let first = current.points.first {
                    let from = at
                    run(steps: count(hypot(first.x - from.x, first.y - from.y))) { t in
                        CGPoint(x: from.x + (first.x - from.x) * t, y: from.y + (first.y - from.y) * t)
                    }
                    // The walk ends ON its first point, so the loop meets.
                    if current.points.last != first { current.points.append(first) }
                    at = first
                }
                current.closed = true
                finish()
            @unknown default:
                break
            }
        }
        finish()
        return figures
    }
}

// MARK: - Setting it

extension PhotonzDocument {

    /// Every path `layerIDs` reach: the paths among them, and every path
    /// inside a group among them, however deep, in the order they are listed.
    /// So picking a drawing's group and choosing a brush restyles every line
    /// in it at once.
    public func pathLayerIDs(reaching layerIDs: [UUID]) -> [UUID] {
        var found: [UUID] = []
        var seen = Set<UUID>()
        func visit(_ layer: Layer) {
            if layer.path != nil, seen.insert(layer.id).inserted { found.append(layer.id) }
            for child in layer.group?.children ?? [] { visit(child) }
        }
        for id in layerIDs {
            if let layer = layer(id: id) { visit(layer) }
        }
        return found
    }

    /// Paints the line of every path `layerIDs` reach with `brush`, or gives
    /// it back its plain line with nil. A path that had a brush in another
    /// medium takes the new one whole; one already in this medium keeps its
    /// seed. A path with no line is given one at the weight a fresh path
    /// wears, since a brush on no line would change nothing anybody can see.
    /// Returns how many changed; locked layers are left alone.
    @discardableResult
    public mutating func setPathBrush(layerIDs: [UUID], to brush: BrushSettings?) -> Int {
        var changed = 0
        for id in pathLayerIDs(reaching: layerIDs) {
            guard let layer = layer(id: id), !layer.isLocked, var path = layer.path else { continue }
            let before = path
            if let brush {
                path.brush = PathBrush(settings: brush, seed: path.brush?.seed ?? PathBrush.defaultSeed)
                if path.strokeWidth <= 0 { path.gainingALineThatReads(width: PathContent.defaultStrokeWidth) }
            } else {
                path.brush = nil
            }
            guard path != before else { continue }
            updateLayer(id: id) { $0.content = .path(path) }
            changed += 1
        }
        return changed
    }

    /// One of the brush's own settings on every brushed path `layerIDs`
    /// reach, clamped to its range. Paths painted in a medium without that
    /// setting, and plain lines, are left alone.
    @discardableResult
    public mutating func setPathBrushSetting(layerIDs: [UUID], id settingID: String, to value: Double) -> Int {
        var changed = 0
        for id in pathLayerIDs(reaching: layerIDs) {
            guard let layer = layer(id: id), !layer.isLocked, var path = layer.path,
                  var brush = path.brush, brush.medium.spec(settingID) != nil else { continue }
            brush.settings.set(settingID, to: value)
            path.brush = brush
            guard path != layer.path else { continue }
            updateLayer(id: id) { $0.content = .path(path) }
            changed += 1
        }
        return changed
    }
}
