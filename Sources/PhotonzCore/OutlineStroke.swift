import CoreGraphics
import Foundation

/// Outline Stroke: the lines round a shape become filled shapes of their own,
/// the same picture with no line left in it (`icon-draw-wt.html`,
/// `#layerMenu`).
///
/// An icon is drawn in lines because a line is quick to draw and quick to
/// change, and it ships as filled outlines because that is what an icon font, a
/// symbol set and every SVG pipeline that recolours with `fill` expect. This is
/// the step between the two, and it is why Illustrator and Figma both have it
/// under this name.
///
/// **A shape has two kinds of line**, and both are outlined. A path drawn with
/// the Pen, and a line, carry their own stroke. A box or an oval wears its line
/// as a Border in the Effects list (`OutlineRetirement.swift`), and so does
/// anything Union made out of them, because the result wears the bottom
/// shape's look. A person sees one line either way, so the command treats
/// them alike.
///
/// **The arithmetic is Core Graphics'**, as it is for Combine Shapes: a
/// `CGPath` knows how to give back the area a stroke of a given width, end and
/// corner covers, and how to merge the overlaps out of it. What is done here is
/// handing it each line exactly as the canvas draws it and walking the answer
/// back into anchors you can pull.
public enum OutlineStroke {
    /// The command's name in every menu that offers it, in the menu bar's
    /// Title Case of the mock's "Outline stroke".
    public static let title = "Outline Stroke"

    /// The area `path`'s own line covers, as a closed outline filled in the
    /// line's paint, in the same coordinates; nil where there is no line or it
    /// covers nothing.
    ///
    /// It is the line as DRAWN (`PathRasterizer.strokeEdge`): a dashed line
    /// comes back in its dashes, and a line inside or outside the shape is the
    /// double-width line clipped to that side, which is exactly what the canvas
    /// paints there.
    public static func outline(of path: PathContent) -> PathContent? {
        let width = path.strokeWidth
        guard width > 0, path.anchors.count >= 2 else { return nil }
        let shape = path.cgPath
        let dashed = path.dashPattern.map { shape.copy(dashingWithPhase: 0, lengths: $0) } ?? shape
        let position = path.effectiveStrokePosition
        var band = dashed.copy(strokingWithWidth: position == .center ? width : width * 2,
                               lineCap: path.lineEnd.lineCap,
                               lineJoin: path.lineCorner.lineJoin,
                               miterLimit: pathMiterLimit).normalized()
        if position != .center {
            band = position == .inside ? band.intersection(inside(path))
                                       : band.subtracting(inside(path))
        }
        return filled(band, in: path.paint, like: path)
    }

    /// The area a Border of `width` draws round `path` with its outer edge
    /// `outset` past the outline (negative for in), filled in `paint`; nil
    /// where it covers nothing.
    ///
    /// The ring as DRAWN (`DocumentRenderer.ringed`): everything within
    /// `outset` of the shape, less everything within `outset - width` of it,
    /// each reach swept with round ends and pointed corners, so a ring keeps a
    /// sharp corner sharp and a curve parallel.
    public static func ring(around path: PathContent, width: CGFloat, outset: CGFloat,
                            paint: Paint) -> PathContent? {
        guard width > 0, path.anchors.count >= 2,
              let outer = silhouette(of: path, reaching: outset) else { return nil }
        let band = silhouette(of: path, reaching: outset - width).map { outer.subtracting($0) } ?? outer
        return filled(band, in: paint, like: path)
    }

    /// Everything within `reach` of the shape, or inside it pulled in by
    /// `-reach`. An open line has no inside, so pulled in it is nothing.
    private static func silhouette(of path: PathContent, reaching reach: CGFloat) -> CGPath? {
        let shape = path.cgPath
        let swept = abs(reach) > 0
            ? shape.copy(strokingWithWidth: abs(reach) * 2, lineCap: .round, lineJoin: .miter,
                         miterLimit: pathMiterLimit).normalized()
            : nil
        guard path.isClosed else { return reach > 0 ? swept : nil }
        guard let swept else { return inside(path) }
        return reach > 0 ? inside(path).union(swept) : inside(path).subtracting(swept)
    }

    /// The area the outline encloses, under the rule its fill uses.
    private static func inside(_ path: PathContent) -> CGPath {
        path.cgPath.normalized(using: path.fillRule == .evenOdd ? .evenOdd : .winding)
    }

    /// `area` as a filled path in `paint` with no line of its own, wearing
    /// everything else about `source`.
    private static func filled(_ area: CGPath, in paint: Paint, like source: PathContent) -> PathContent? {
        guard var made = PathContent(area) else { return nil }
        made.wear(source)
        made.paint = paint
        made.fill = paint
        made.strokeWidth = 0
        made.strokePosition = .center
        made.linePattern = .solid
        return made
    }
}

// MARK: - The lines one layer draws

/// One line a layer draws, outlined: the area, and which line it was.
struct OutlinedLine {
    /// The line as a filled outline, in the layer's parent's coordinates with
    /// any turn or flip baked in.
    var outline: PathContent
    /// Where the Border it was sits in the Effects list; nil for the shape's
    /// own stroke.
    var effectIndex: Int?
}

extension PhotonzDocument {

    /// Every line `layer` draws, outlined, in the order the canvas paints them
    /// (its own stroke, then its Borders from the foot of the list up), or
    /// empty where it draws none. A rectangle, an oval, a line or a wash is
    /// traced as the path it would become.
    func outlinedLines(of layer: Layer) -> [OutlinedLine] {
        guard !layer.isLocked else { return [] }
        let source = layer.path == nil ? layer.turnedIntoPath() : layer
        guard let source, let content = source.path else { return [] }
        var lines: [OutlinedLine] = []
        if let own = OutlineStroke.outline(of: content) {
            lines.append(OutlinedLine(outline: own, effectIndex: nil))
        }
        for index in source.style.effects.indices.reversed() {
            guard case .border(let border) = source.style.effects[index], border.paints,
                  let ring = OutlineStroke.ring(
                    around: content, width: border.width,
                    outset: border.ringOutset(aroundOpenLine: !content.isClosed),
                    paint: border.paint) else { continue }
            lines.append(OutlinedLine(outline: ring, effectIndex: index))
        }
        return lines.map { line in
            var placed = line
            placed.outline = line.outline.offsetBy(dx: source.frame.origin.x, dy: source.frame.origin.y)
            if !source.transform.isIdentity {
                let centre = CGPoint(x: source.frame.midX, y: source.frame.midY)
                placed.outline = placed.outline.transformed(by: source.transform.affineTransform(around: centre))
            }
            return placed
        }
    }

    /// The picked layers whose lines would be outlined: unlocked, drawing at
    /// least one line, not inside a copy of a component (what is in there
    /// belongs to the original).
    func outlineStrokeTargets(ids: Set<UUID>) -> Set<UUID> {
        ids.filter { id in
            guard let layer = layer(id: id), path(of: id) != nil,
                  !outlinedLines(of: layer).isEmpty else { return false }
            if let parent = parentID(of: id), isInsideCopy(parent) { return false }
            return true
        }
    }

    /// Whether Outline Stroke would do anything.
    public func canOutlineStroke(ids: Set<UUID>) -> Bool {
        !outlineStrokeTargets(ids: ids).isEmpty
    }

    /// Turns every line of every picked layer into a filled shape, in one
    /// mutation so it is one undo step. Returns the layers now holding each
    /// outline, bottom-up; the caller picks them.
    ///
    /// A shape that was ONE line and nothing else becomes its outline where it
    /// stands: same row, same id, same look, now a filled path. Anything more
    /// (a fill inside it, or a second line) stays as it was minus its lines,
    /// and each outline goes on a new layer directly above it in the order the
    /// lines were painted, because one path wears one paint inside. When that
    /// shape was see-through, blended or wore effects, the pieces go in a
    /// group that wears them instead, so they are faded or shadowed as one
    /// thing, exactly as the shape was, and never twice.
    @discardableResult
    public mutating func outlineStroke(ids: Set<UUID>) -> [UUID] {
        // Every outline worked out before anything moves.
        var lines: [UUID: [OutlinedLine]] = [:]
        for id in outlineStrokeTargets(ids: ids) {
            guard let layer = layer(id: id) else { continue }
            lines[id] = outlinedLines(of: layer)
        }
        guard !lines.isEmpty else { return [] }
        var made: [UUID] = []
        var regroup: [(pieces: [UUID], look: Layer)] = []
        var taken = Set(allLayers.map(\.name))

        func walk(_ list: inout [Layer]) {
            var result: [Layer] = []
            result.reserveCapacity(list.count)
            for var layer in list {
                if layer.isGroup { walk(&layer.children) }
                guard let outlines = lines[layer.id], !outlines.isEmpty else {
                    result.append(layer)
                    continue
                }
                let stripped = layer.withoutItsLines(outlines)
                let fills = layer.path?.paintsAnInside
                    ?? layer.turnedIntoPath()?.path?.paintsAnInside ?? false
                var pieces: [Layer] = fills ? [stripped] : []
                for line in outlines {
                    // The first outline of a shape with nothing else to it
                    // takes the shape's own row; every other one is new.
                    let inPlace = pieces.isEmpty
                    var piece = Layer.wearing(line, from: layer,
                                              as: inPlace ? stripped : stripped.duplicated())
                    if inPlace {
                        // "Ellipse" is a poor name for a ring; a name a person
                        // typed is theirs and stays.
                        if LayerNaming.isAutoName(layer.name), layer.path == nil {
                            taken.remove(layer.name)
                            piece.name = LayerNaming.firstFree(base: PathBuilder.defaultName, taken: taken)
                        }
                    } else {
                        piece.name = LayerNaming.firstFree(base: layer.name + " outline", taken: taken)
                    }
                    taken.insert(piece.name)
                    pieces.append(piece)
                    made.append(piece.id)
                }
                result += pieces
                if pieces.count > 1, !stripped.style.isPlain {
                    regroup.append((pieces.map(\.id), stripped))
                }
            }
            list = result
        }
        walk(&layers)

        for set in regroup {
            guard let group = groupLayers(ids: Set(set.pieces), name: set.look.name) else { continue }
            let effectBindings = set.look.colorStyleBindings?.filter { $0.effectIndex != nil } ?? []
            updateLayer(id: group.id) {
                $0.style = set.look.style
                if !effectBindings.isEmpty { $0.colorStyleBindings = effectBindings }
            }
            for id in set.pieces {
                updateLayer(id: id) {
                    $0.style = LayerStyle()
                    $0.colorStyleBindings = $0.colorStyleBindings?.filter { $0.effectIndex == nil }
                }
            }
        }
        return made
    }
}

extension Layer {

    /// This layer with every one of `lines` taken off it: its own stroke set to
    /// nothing, and each Border that was outlined out of its Effects list, the
    /// names on what is left following their places (`removeEffect`).
    func withoutItsLines(_ lines: [OutlinedLine]) -> Layer {
        var stripped = self
        if lines.contains(where: { $0.effectIndex == nil }) {
            switch stripped.content {
            case .path(var path):
                path.strokeWidth = 0
                stripped.content = .path(path)
            case .annotation(var mark):
                mark.strokeWidth = 0
                stripped.content = .annotation(mark)
            default:
                break
            }
            stripped.colorStyleBindings = stripped.colorStyleBindings?.filter {
                $0.effectIndex != nil || $0.slot != .stroke
            }
        }
        for index in lines.compactMap(\.effectIndex).sorted(by: >) {
            stripped.removeEffect(at: index)
        }
        return stripped
    }

    /// `base` remade as `line`'s outline: a filled path where the line was,
    /// unturned because the turn is in its points now, wearing what is left of
    /// the look. The colour style that named the line, on `original`, now
    /// names the fill.
    static func wearing(_ line: OutlinedLine, from original: Layer, as base: Layer) -> Layer {
        var shape = base.path == nil ? (base.turnedIntoPath() ?? base) : base
        shape.transform = .identity
        let local = line.outline.offsetBy(dx: -shape.frame.origin.x, dy: -shape.frame.origin.y)
        shape.content = .path(local)
        var result = PathBuilder.refit(shape, content: local)
        let named = original.colorStyleBindings?.first { binding in
            line.effectIndex.map { binding.effectIndex == $0 }
                ?? (binding.effectIndex == nil && binding.slot == .stroke)
        }
        var bindings = (base.colorStyleBindings ?? []).filter { $0.effectIndex != nil }
        if let named { bindings.append(ColorStyleBinding(slot: .fill, styleID: named.styleID)) }
        result.colorStyleBindings = bindings.isEmpty ? nil : bindings
        return result
    }
}
