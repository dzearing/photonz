import CoreGraphics
import Foundation

// An illustration drawn the way a graphic artist works (`docs/design/ask.md`,
// "Drawing an illustration"), in eight passes, each with an output that can be
// checked before the next:
//
//  1. Brief: subject, style, time of day (`IllustrationBrief`).
//  2. Composition: the frame, a focal point off centre, the horizon off the
//     middle, the big shapes blocked in as overlapping planes.
//  3. Values: three to five planes in grey, nearest darkest.
//  4. Shape: lopsided peaks, broken ridgelines, one pine repeated.
//  5. Light: one light; every form split into a lit side and a shadow side.
//  6. Colour: one palette for the time of day; distance lighter and bluer.
//  7. Detail and finish: snow, birds, reflections, windows; line weights;
//     everything cut to the frame.
//  8. Critique: values, light, the frame, the thumbnail and the silhouette
//     checked; what fails is revised and drawn again.
//
// Pure: CoreGraphics types, no drawing. The scene becomes layers through
// `SVGArtwork` and an SVG through `IllustrationScene.svg()`.

/// One check a pass makes on its own output.
public struct IllustrationCheck: Hashable, Sendable {
    public let name: String
    public let passed: Bool
    public let detail: String
}

/// One pass: what the picture looks like after it, and what it checked.
public struct IllustrationPass: Hashable, Sendable {
    public let number: Int
    public let title: String
    public let scene: IllustrationScene
    public let checks: [IllustrationCheck]
}

public enum Illustrator {

    public static let passTitles = ["Brief", "Composition", "Values", "Shape", "Light", "Colour",
                                    "Detail and finish", "Critique"]

    /// The finished picture.
    public static func draw(_ brief: IllustrationBrief) -> IllustrationScene {
        passes(brief).last?.scene ?? IllustrationScene(size: CGSize(width: 1200, height: 800), nodes: [])
    }

    /// Every pass in order, the last one the finished picture after the
    /// critique's revisions.
    public static func passes(_ brief: IllustrationBrief) -> [IllustrationPass] {
        var tuning = IllustrationTuning()
        var work = IllustrationWork(brief: brief, tuning: tuning)
        for _ in 0..<2 {
            let failed = work.critique().filter { !$0.passed }.map(\.name)
            guard !failed.isEmpty else { break }
            tuning.revise(for: failed)
            work = IllustrationWork(brief: brief, tuning: tuning)
        }
        return work.passes()
    }
}

/// What the critique turns when something fails.
struct IllustrationTuning {
    /// How far apart the value planes are spread.
    var contrast: CGFloat = 1
    /// Seed offset, for a silhouette that did not read.
    var reroll: UInt64 = 0
    var revisions: [String] = []

    mutating func revise(for failed: [String]) {
        if failed.contains("values") || failed.contains("squint") { contrast *= 1.25 }
        if failed.contains("silhouette") || failed.contains("thumbnail") { reroll += 1 }
        revisions.append(contentsOf: failed)
    }
}

/// A plane of the picture, back to front.
struct IllustrationPlane {
    enum Kind { case range, band, hills, treeline, water, cliff, city }
    var kind: Kind
    var name: String
    var block: CGRect
    /// 0 at the back, 1 at the front.
    var depth: CGFloat
    var peaks = 3
    var roughness: CGFloat = 0.16
    var focusX: CGFloat?
    /// Planned in the values pass.
    var value: CGFloat = 0.5
}

/// What a plane became in the shape pass, and its light.
struct IllustrationForm {
    var plane: IllustrationPlane
    var outline: [IllustrationPath] = []
    var ridge: IllustrationPieces.Ridge?
    var shadows: [(peak: CGPoint, away: CGFloat, face: [CGPoint])] = []
    var highlights: [[CGPoint]] = []
    var snow: [[CGPoint]] = []
    var skyline: IllustrationPieces.Skyline?
    /// Where the form meets the water, for a reflection.
    var reflects = false
}

struct IllustrationWork {
    let brief: IllustrationBrief
    let tuning: IllustrationTuning
    let palette: IllustrationPalette
    let size: CGSize
    let frame: IllustrationFrame
    let horizon: CGFloat
    let light: CGPoint
    let lightRadius: CGFloat
    let focal: CGPoint
    var planes: [IllustrationPlane] = []
    var forms: [IllustrationForm] = []
    var props: [IllustrationPieces.Part] = []
    var castShadows: [[CGPoint]] = []
    var waterline: CGFloat?
    let scene: Scene

    var style: IllustrationStyle { brief.style }
    /// Which way shadows fall: +1 to the right of each form, when the light
    /// is on the left of the picture.
    var lightAway: CGFloat { light.x < size.width / 2 ? 1 : -1 }

    /// Line art or a silhouette on open paper, with no badge to hold it.
    var vignette: Bool { (brief.style == .lineArt || brief.style == .silhouette) && !brief.badge }
    var ink: Bool { style == .lineArt || style == .silhouette }

    init(brief: IllustrationBrief, tuning: IllustrationTuning) {
        self.brief = brief
        self.tuning = tuning
        palette = IllustrationPalette.for(brief.time)
        let badge = brief.badge
        size = badge ? CGSize(width: 1000, height: 1000) : CGSize(width: 1200, height: 800)
        let w = size.width, h = size.height
        // An ink badge's scene sits inside its inner ring.
        frame = badge ? .circle(center: CGPoint(x: w / 2, y: h / 2),
                                radius: w * 0.47 - (brief.style == .lineArt || brief.style == .silhouette ? 22 : 0))
            : (brief.style == .lineArt || brief.style == .silhouette)
                // Open paper: the picture stops at its ground line.
                ? .box(CGRect(x: 0, y: 0, width: w, height: h * 0.9 + 2), radius: 0)
                : .box(CGRect(origin: .zero, size: size), radius: 28)
        let scene = IllustrationWork.scene(of: brief)
        self.scene = scene
        // Pass 2, composition: where the light and the focus sit.
        let night = brief.time == .night
        var lightAt: CGPoint
        switch (scene, brief.time) {
        case (.coast, _): lightAt = CGPoint(x: w * 0.26, y: h * (night ? 0.2 : 0.56))
        case (.city, _): lightAt = CGPoint(x: w * 0.76, y: h * 0.2)
        case (.fox, _): lightAt = CGPoint(x: w * 0.74, y: h * (night ? 0.2 : 0.48))
        case (.forest, _): lightAt = CGPoint(x: w * 0.62, y: h * (night ? 0.2 : 0.5))
        case (.mountains, .day): lightAt = CGPoint(x: w * 0.7, y: h * 0.22)
        case (.mountains, .night): lightAt = CGPoint(x: w * 0.72, y: h * 0.2)
        case (.mountains, _): lightAt = CGPoint(x: w * 0.63, y: h * (brief.style == .sunset ? 0.46 : 0.44))
        }
        if badge { lightAt.y = max(lightAt.y, h * 0.3) }
        light = lightAt
        lightRadius = w * (night ? 0.05 : (brief.time == .day ? 0.06 : 0.085))
        var horizonAt: CGFloat = h * 0.66
        var focusAt = CGPoint(x: w * 0.4, y: h * 0.45)
        switch scene {
        case .coast: horizonAt = h * 0.64; focusAt = CGPoint(x: w * 0.68, y: h * 0.4)
        case .city: horizonAt = h * 0.74; focusAt = CGPoint(x: w * 0.42, y: h * 0.45)
        case .fox: horizonAt = h * 0.62; focusAt = CGPoint(x: w * 0.4, y: h * 0.7)
        case .forest: horizonAt = h * 0.62; focusAt = CGPoint(x: w * 0.6, y: h * 0.55)
        case .mountains: break
        }
        horizon = horizonAt
        focal = focusAt
        planes = blockIn(scene)
        planValues()
        buildShapes(scene)
        shadeForms(scene)
    }

    enum Scene { case mountains, forest, coast, city, fox }

    static func scene(of brief: IllustrationBrief) -> Scene {
        if brief.has(.fox) { return .fox }
        if brief.has(.lighthouse) || brief.has(.cliff) || (brief.has(.sea) && !brief.has(.mountains)) { return .coast }
        if brief.has(.city) { return .city }
        if brief.has(.mountains) { return .mountains }
        if brief.has(.forest) { return .forest }
        return .mountains
    }

    func stream(_ salt: UInt64) -> IllustrationRandom {
        IllustrationRandom(seed: brief.seed &+ salt &* 7919 &+ tuning.reroll &* 104_729)
    }

    // MARK: Pass 2, composition: the planes blocked in

    func blockIn(_ scene: Scene) -> [IllustrationPlane] {
        let w = size.width, h = size.height
        func box(_ top: CGFloat, _ bottom: CGFloat, _ left: CGFloat = 0, _ right: CGFloat = 1) -> CGRect {
            CGRect(x: w * left, y: h * top, width: w * (right - left), height: h * (bottom - top))
        }
        switch scene {
        case .mountains:
            if style == .sunset {
                let tops: [CGFloat] = [0.38, 0.47, 0.57, 0.67, 0.79]
                return tops.enumerated().map { index, top in
                    var plane = IllustrationPlane(kind: .band, name: ["Far ridge", "Second ridge", "Middle ridge", "Fourth ridge", "Near ridge"][index],
                                                  block: box(top, min(1.02, top + 0.32)), depth: CGFloat(index) / CGFloat(tops.count - 1))
                    plane.peaks = [5, 4, 3, 3, 2][index]
                    plane.roughness = 0.09
                    plane.focusX = index == 1 ? w * 0.4 : nil
                    return plane
                }
            }
            var planes = [
                IllustrationPlane(kind: .range, name: "Far range", block: box(0.3, 0.74), depth: 0, peaks: 5, roughness: 0.13),
                IllustrationPlane(kind: .range, name: "Middle range", block: box(0.36, 0.82), depth: 0.4, peaks: 3, roughness: 0.16, focusX: w * 0.4),
                IllustrationPlane(kind: .range, name: "Near range", block: box(0.58, 0.92), depth: 0.72, peaks: 2, roughness: 0.18),
            ]
            if brief.has(.lake) || (style == .silhouette && brief.has(.forest)) {
                // A silhouette's pines stand against the paper of a lake, never against black rock.
                planes.append(IllustrationPlane(kind: .water, name: "Lake", block: box(0.8, 1.02), depth: 0.85))
                planes.append(IllustrationPlane(kind: .treeline, name: brief.has(.lake) ? "Shore pines" : "Pines",
                                                block: box(0.86, 1.02), depth: 1))
            } else if brief.has(.forest) {
                planes.append(IllustrationPlane(kind: .treeline, name: "Pines", block: box(0.74, 1.02), depth: 1))
            } else if !(brief.style == .lineArt || brief.style == .silhouette) || brief.badge {
                planes.append(IllustrationPlane(kind: .hills, name: "Foothills", block: box(0.82, 1.02), depth: 1))
            }
            return planes
        case .forest:
            // A still lake in front of the trees holds the dusk sky and doubles the treeline.
            return [
                IllustrationPlane(kind: .hills, name: "Far hills", block: box(0.44, 0.7), depth: 0),
                IllustrationPlane(kind: .treeline, name: "Back pines", block: box(0.5, 0.64), depth: 0.33),
                IllustrationPlane(kind: .treeline, name: "Middle pines", block: box(0.5, 0.72), depth: 0.66),
                IllustrationPlane(kind: .water, name: "Lake", block: box(0.72, 1.02), depth: 0.8),
                IllustrationPlane(kind: .treeline, name: "Front pines", block: box(0.5, 1.02), depth: 1),
            ]
        case .coast:
            return [
                IllustrationPlane(kind: .range, name: "Far headland", block: box(0.5, 0.66, 0, 0.5), depth: 0, peaks: 2, roughness: 0.08),
                IllustrationPlane(kind: .range, name: "Headland", block: box(0.56, 0.66, -0.05, 0.3), depth: 0.25, peaks: 1, roughness: 0.1),
                IllustrationPlane(kind: .water, name: "Sea", block: box(0.64, 1.02), depth: 0.4),
                IllustrationPlane(kind: .cliff, name: "Cliff", block: box(0.56, 1.02, 0.44, 1.02), depth: 1),
            ]
        case .city:
            return [
                IllustrationPlane(kind: .city, name: "Far towers", block: box(0.3, 0.74), depth: 0),
                IllustrationPlane(kind: .city, name: "Middle towers", block: box(0.4, 0.74), depth: 0.5),
                IllustrationPlane(kind: .city, name: "Front towers", block: box(0.5, 0.76), depth: 0.8),
                IllustrationPlane(kind: .water, name: "River", block: box(0.76, 1.02), depth: 1),
            ]
        case .fox:
            return [
                IllustrationPlane(kind: .hills, name: "Far hills", block: box(0.36, 0.62), depth: 0),
                IllustrationPlane(kind: .treeline, name: "Far pines", block: box(0.48, 0.68), depth: 0.35),
                IllustrationPlane(kind: .hills, name: "Meadow", block: box(0.52, 1.02), depth: 1),
            ]
        }
    }

    // MARK: Pass 3, values

    mutating func planValues() {
        let far = palette.farValue
        // A creature or a building in front needs ground it stands out on.
        var near = palette.nearValue
        if scene == .coast { near = max(near, 0.28) }
        if scene == .fox { near = max(near, 0.4) }
        if style == .flat { near = max(near, 0.26) }
        let middle = (far + near) / 2
        let half = (far - near) / 2 * min(tuning.contrast, 1.4)
        for index in planes.indices {
            let t = pow(planes[index].depth, 0.85)
            let spread = middle + half - 2 * half * t
            planes[index].value = min(max(spread, 0.02), 0.95)
            if planes[index].kind == .water {
                // Water carries the sky's light: it is read, not planned.
                planes[index].value = IllustrationColor.value(palette.water.first?.hex ?? "#808080")
            }
        }
    }

    // MARK: Pass 4, shape

    mutating func buildShapes(_ scene: Scene) {
        let bottom = size.height + 20
        for (index, plane) in planes.enumerated() {
            var form = IllustrationForm(plane: plane)
            var random = stream(UInt64(index + 1))
            switch plane.kind {
            case .range, .band:
                var ridge = IllustrationPieces.ridge(in: plane.block, peaks: plane.peaks, roughness: plane.roughness,
                                                     focusX: plane.focusX, random: &random)
                if plane.kind == .band {
                    // Sunset bands roll: the ridge is eased into a gentler line.
                    ridge.points = Self.eased(ridge.points)
                }
                if vignette {
                    // Ink on open paper: the ranges come down to the ground
                    // inside the picture rather than being cut by its edge.
                    let ground = size.height * 0.9
                    ridge.points = ridge.points.map { point in
                        let inside = min(point.x - size.width * 0.03, size.width * 0.97 - point.x) / (size.width * 0.14)
                        let eased = max(0, min(1, inside))
                        return CGPoint(x: point.x, y: ground + (point.y - ground) * eased)
                    }
                }
                form.ridge = ridge
                form.outline = [IllustrationPath(IllustrationPieces.silhouette(ridge, bottom: bottom))]
                form.reflects = index == planes.lastIndex(where: { $0.kind == .range || $0.kind == .band })
                    && planes.contains { $0.kind == .water }
            case .hills:
                let crest = IllustrationPieces.hills(in: plane.block, swells: plane.name == "Meadow" ? 1 : 2, random: &random)
                let left = crest.first?.x ?? 0, right = crest.last?.x ?? size.width
                form.outline = [IllustrationPath(crest + [CGPoint(x: right, y: bottom), CGPoint(x: left, y: bottom)],
                                                 smooth: true, corners: [crest.count, crest.count + 1])]
                form.ridge = IllustrationPieces.Ridge(points: crest, peaks: [], valleys: [])
            case .treeline:
                let base = plane.block.maxY - (plane.name == "Front pines" ? 0.03 * size.height : plane.block.height * 0.2)
                let height: CGFloat
                switch plane.name {
                case "Front pines": height = size.height * 0.36
                case "Pines": height = size.height * (style == .silhouette ? 0.15 : 0.2)
                case "Shore pines": height = size.height * 0.1
                case "Far pines": height = size.height * 0.15
                default: height = plane.block.height * 0.8
                }
                let baseline: (CGFloat) -> CGFloat = { x in base + sin(x / 140) * 6 }
                let front = plane.name == "Front pines"
                var left = front ? -size.width * 0.04 : -size.width * 0.02
                var right = size.width * 1.02
                if case .circle(let c, let r) = frame {
                    // In a badge the row spans the circle where the trees stand, not the square.
                    let dy = min(r, abs(plane.block.minY - c.y))
                    let half = (r * r - dy * dy).squareRoot()
                    left = c.x - half + height * 0.2
                    right = c.x + half - height * 0.2
                }
                var trees = IllustrationPieces.treeline(from: left, to: right, baseline: baseline, height: height, bottom: bottom,
                                                        spacing: height * (front ? 0.42 : (style == .silhouette ? 0.5 : 0.3)),
                                                        edgeLift: front ? 0.9 : (style == .silhouette ? 0.6 : 0.3),
                                                        groundDepth: .infinity,
                                                        random: &random)
                if front {
                    // The front row frames the picture: trees only toward the edges.
                    let clearLeft = size.width * 0.3, clearRight = size.width * 0.78
                    trees = trees.enumerated().filter { offset, tree in
                        offset == 0 || !(tree.bounds.midX > clearLeft && tree.bounds.midX < clearRight)
                    }.map(\.element)
                }
                form.outline = trees
                // The row nearest the water is the one it mirrors.
                if let water = planes.firstIndex(where: { $0.kind == .water }), water == index + 1 { form.reflects = true }
            case .water:
                waterline = plane.block.minY
                form.outline = [IllustrationPath([CGPoint(x: -20, y: plane.block.minY), CGPoint(x: size.width + 20, y: plane.block.minY),
                                                  CGPoint(x: size.width + 20, y: bottom), CGPoint(x: -20, y: bottom)])]
            case .cliff:
                form.outline = [IllustrationPath(Self.cliff(plane.block, bottom: bottom, random: &random), smooth: true,
                                                 corners: [0, 1, 6, 7, 8, 9, 10, 11, 12])]
                form.ridge = IllustrationPieces.Ridge(points: Self.cliffTop(plane.block), peaks: [], valleys: [])
            case .city:
                let ground = plane.block.maxY
                let tallest = ground - plane.block.minY
                let skyline = IllustrationPieces.skyline(
                    from: -10, to: size.width + 10, ground: ground + 4, tallest: tallest, shortest: tallest * 0.3,
                    focusX: focal.x + CGFloat(index) * size.width * 0.07, lightSide: light.x > size.width / 2 ? 1 : -1,
                    windows: plane.depth > 0.3, random: &random)
                form.skyline = skyline
                form.outline = skyline.bodies + skyline.spires
            }
            forms.append(form)
        }
        switch scene {
        case .coast:
            if let cliff = forms.first(where: { $0.plane.kind == .cliff }), let top = cliff.ridge {
                let x = size.width * 0.68
                let base = CGPoint(x: x, y: top.y(at: x) + 4)
                props = IllustrationPieces.lighthouse(base: base, height: size.height * 0.44)
                let cottageX = size.width * 0.84
                props += IllustrationPieces.cottage(base: CGPoint(x: cottageX, y: top.y(at: cottageX) + 6), width: size.width * 0.09)
            }
        case .fox:
            let x = size.width * 0.4
            let meadow = forms.last(where: { $0.plane.kind == .hills })?.ridge
            let ground = (meadow?.y(at: x) ?? size.height * 0.75) + size.height * 0.2
            props = IllustrationPieces.fox(base: CGPoint(x: x, y: min(ground, size.height * 0.94)), height: size.height * 0.5,
                                           facingRight: light.x > x)
        default: break
        }
    }

    /// Each point pulled toward its neighbours' middle: a gentler line.
    static func eased(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var out = points
        for _ in 0..<2 {
            let was = out
            for index in 1..<(was.count - 1) {
                out[index].y = (was[index - 1].y + was[index].y * 2 + was[index + 1].y) / 4
            }
        }
        return out
    }

    static func cliffTop(_ block: CGRect) -> [CGPoint] {
        [CGPoint(x: block.minX + block.width * 0.04, y: block.minY + 10), CGPoint(x: block.minX + block.width * 0.2, y: block.minY - 4),
         CGPoint(x: block.minX + block.width * 0.5, y: block.minY + 6), CGPoint(x: block.minX + block.width * 0.8, y: block.minY - 2),
         CGPoint(x: block.maxX + 20, y: block.minY + 4)]
    }

    /// A headland: a grassy top and a broken rock face dropping into the sea.
    static func cliff(_ block: CGRect, bottom: CGFloat, random: inout IllustrationRandom) -> [CGPoint] {
        let top = cliffTop(block)
        let face = block.minX
        var points: [CGPoint] = [CGPoint(x: block.maxX + 20, y: bottom), CGPoint(x: block.maxX + 20, y: top[4].y)]
        points.append(contentsOf: top.dropLast().reversed())
        // The face, stepping down and out.
        let depth = bottom - block.minY
        points.append(CGPoint(x: face + block.width * 0.015, y: block.minY + depth * 0.18))
        points.append(CGPoint(x: face - block.width * 0.02, y: block.minY + depth * 0.32))
        points.append(CGPoint(x: face + block.width * 0.005, y: block.minY + depth * 0.4))
        points.append(CGPoint(x: face - block.width * 0.05, y: block.minY + depth * 0.58))
        points.append(CGPoint(x: face - block.width * 0.04, y: block.minY + depth * 0.66))
        points.append(CGPoint(x: face - block.width * 0.1, y: bottom))
        return points
    }

    // MARK: Pass 5, light

    mutating func shadeForms(_ scene: Scene) {
        let bottom = size.height + 20
        for index in forms.indices {
            guard let ridge = forms[index].ridge, forms[index].plane.kind == .range || forms[index].plane.kind == .band else { continue }
            var random = stream(UInt64(100 + index))
            for peak in ridge.peaks {
                let top = ridge.points[peak]
                // One light for the whole picture, the way an illustrator lights
                // a scene: every shadow falls on the side away from the sun's
                // side of the picture, never flipping from peak to peak.
                let away = lightAway
                let face = IllustrationPieces.shadowFace(ridge, peak: peak, away: away, bottom: bottom, random: &random)
                if face.count >= 3 { forms[index].shadows.append((top, away, face)) }
                if forms[index].plane.kind == .range, forms[index].plane.block.height > size.height * 0.3 {
                    forms[index].highlights += IllustrationPieces.highlights(ridge, peak: peak, toward: -away,
                                                                             bottom: forms[index].plane.block.maxY, random: &random)
                }
            }
        }
        // A cast shadow from whatever stands on the ground, away from the light.
        let away: CGFloat = light.x < size.width / 2 ? 1 : -1
        if scene == .coast, let tower = props.first(where: { $0.name.hasPrefix("Tower white") }) {
            let foot = tower.geometry
            if case .path(let paths) = foot, let quad = paths.first?.points, quad.count == 4 {
                let a = quad[0], d = quad[3]
                let length = size.width * 0.16
                castShadows.append([a, d, CGPoint(x: d.x + away * length, y: d.y + 8), CGPoint(x: a.x + away * length * 0.8, y: a.y + 14)])
            }
        }
        if scene == .fox {
            // The whole fox casts it, body and tail, away from the light.
            let box = props.reduce(CGRect.null) { $0.union($1.geometryBounds) }
            if !box.isNull {
                let y = box.maxY - 4
                let left = box.minX - size.width * 0.05, right = box.maxX + away * size.width * 0.08
                castShadows.append([CGPoint(x: min(left, right), y: y - 8), CGPoint(x: max(left, right), y: y - 10),
                                    CGPoint(x: max(left, right) + 10, y: y + 6), CGPoint(x: min(left, right) - 6, y: y + 8)])
            }
        }
    }

    // MARK: Pass 7, detail: snow

    func snowCaps() -> [(Int, [CGPoint])] {
        guard brief.has(.mountains), style != .sunset else { return [] }
        var caps: [(Int, [CGPoint])] = []
        for (index, form) in forms.enumerated() where form.plane.kind == .range && form.plane.depth < 0.6 {
            guard let ridge = form.ridge else { continue }
            var random = stream(UInt64(200 + index))
            let tallest = ridge.peaks.sorted { ridge.points[$0].y < ridge.points[$1].y }.prefix(form.plane.depth == 0 ? 2 : 1)
            for peak in tallest {
                let depth = form.plane.block.height * (form.plane.depth == 0 ? 0.14 : 0.17)
                if let cap = IllustrationPieces.snowCap(ridge, peak: peak, depth: depth, random: &random) {
                    caps.append((index, cap))
                }
            }
        }
        return caps
    }

    // MARK: The planes' colours

    /// A plane's own colour, re-lit to the value planned for it.
    func colour(_ plane: IllustrationPlane) -> String {
        var hue = IllustrationColor.mix(palette.far, palette.near, plane.depth)
        if plane.kind == .hills {
            // Distant hills keep the sky's blue; near ones turn to grass.
            hue = IllustrationColor.mix(hue, scene == .fox && plane.depth > 0.5 ? "#C99A55" : palette.grass, plane.depth < 0.5 ? 0.15 : 0.5)
        }
        if plane.kind == .cliff {
            // Warm rock, lit by a low sun.
            hue = IllustrationColor.mix(palette.far, "#8C6A55", 0.6)
        }
        return IllustrationColor.relit(hue, to: plane.value)
    }
}
