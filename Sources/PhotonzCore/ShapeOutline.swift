import CoreGraphics
import Foundation

/// What a Border can go round on a layer besides its box.
///
/// A border is a line round a THING, and the thing is not always a rectangle:
/// a drawn package, an arrow, a sticker cut out of its background. Photoshop's
/// Stroke runs round whatever the layer draws, and so does a Border here
/// whenever its row says it follows the shape (`BorderFollows.swift`). The
/// user, 2026-10-20, on a package drawn as a group of paths: "It created a box
/// border, and not one that followed the outline of the shape ... borders are
/// borders, not always boxes."
public enum ShapeToFollow: String, Hashable, Sendable {
    /// Only a box: a rectangle, a highlight, a screenshot, a frame. A border
    /// goes round it and nothing asks.
    case none
    /// A label: its letters, baked into the words (`TextRasterizer`).
    case letters
    /// Anything else with a silhouette of its own: a path, an oval, an arrow,
    /// a line, a group, a picture with a see-through edge.
    case outline
}

extension Layer {

    /// What a Border on this layer can follow besides its box.
    ///
    /// `pictureHasEdge` answers for a picture, which only the pixels can: a
    /// cut-out with a see-through edge has one, an opaque screenshot does not.
    public func shapeToFollow(pictureHasEdge: (ImageRef) -> Bool = { _ in false }) -> ShapeToFollow {
        switch content {
        case .text: return .letters
        case .path(let path): return path.anchors.count >= 2 ? .outline : .none
        case .annotation(let annotation):
            switch annotation.shape {
            case .ellipse, .arrow, .line: return .outline
            case .rectangle, .highlight: return .none
            }
        case .group(let group):
            return group.isFrame || group.children.isEmpty ? .none : .outline
        case .image(let ref):
            return crop == nil && zoomWindow == nil && pictureHasEdge(ref) ? .outline : .none
        // Paint is soft-edged marks, not an outline a ring could run round.
        case .zoomCallout, .lens, .measure, .collage, .sound, .paint:
            return .none
        }
    }

    /// The outline a Border that follows the shape runs round, or nil where the
    /// box is the answer (and on an oval, which the ring draws as an oval of
    /// its own, `RingShape.swift`).
    ///
    /// Stated the way a path layer's own anchors are: in DOCUMENT POINTS, from
    /// the top-left corner of the layer's box (its frame, or a group's
    /// `localBounds`). `contentScale` is how many of the frame's units make a
    /// point, so a document the renderer has magnified still gets its outline
    /// in points and the ring baker scales it once, exactly as it scales a
    /// path's (`DocumentRenderer.ringed`).
    ///
    /// A path answers with itself, so an open line keeps its centred band. A
    /// group answers with the UNION of everything in it, one outline round the
    /// whole package rather than one ring per face. A picture answers with the
    /// edge traced out of its transparency (`PictureEdge`), handed in by
    /// whoever has the pixels: `pictureEdge` gives it in fractions of the
    /// picture, top-left, or nil where the picture has no see-through edge.
    public func followedOutline(contentScale: CGFloat = 1,
                                pictureEdge: (ImageRef) -> CGPath? = { _ in nil }) -> PathContent? {
        switch content {
        case .path(let path):
            return path.anchors.count >= 2 ? path : nil
        case .annotation(let annotation):
            guard annotation.shape == .arrow || annotation.shape == .line,
                  let area = drawnArea(contentScale: contentScale, pictureEdge: pictureEdge)
            else { return nil }
            return PathContent(area)
        case .group(let group):
            guard !group.isFrame,
                  let area = drawnArea(contentScale: contentScale, pictureEdge: pictureEdge)
            else { return nil }
            return PathContent(area)
        case .image(let ref):
            guard crop == nil, zoomWindow == nil, pictureEdge(ref) != nil,
                  let area = drawnArea(contentScale: contentScale, pictureEdge: pictureEdge)
            else { return nil }
            return PathContent(area)
        case .text, .zoomCallout, .lens, .measure, .collage, .sound, .paint:
            return nil
        }
    }

    /// Everything this layer puts ink on, as one filled area in points from
    /// the top-left of its box, overlaps merged out. Nil where it draws nothing.
    ///
    /// Anything with no silhouette of its own (a label, a screenshot, a frame)
    /// gives its box, so a group holding one still closes round it.
    func drawnArea(contentScale: CGFloat, pictureEdge: (ImageRef) -> CGPath?) -> CGPath? {
        let scale = contentScale > 0 ? contentScale : 1
        let ownBox = CGRect(origin: .zero, size: CGSize(width: localBounds.width / scale,
                                                        height: localBounds.height / scale))
        func boxArea() -> CGPath? {
            ownBox.width > 0 && ownBox.height > 0 ? CGPath(rect: ownBox, transform: nil) : nil
        }
        switch content {
        case .path(let path):
            return ShapeOutline.area(of: path)
        case .annotation(let annotation):
            return ShapeOutline.area(of: annotation)
        case .group(let group):
            if group.isFrame { return boxArea() }
            return ShapeOutline.union(of: self, group: group, contentScale: scale,
                                      pictureEdge: pictureEdge)
        case .image(let ref):
            guard crop == nil, zoomWindow == nil, let edge = pictureEdge(ref) else { return boxArea() }
            var stretch = CGAffineTransform(scaleX: ownBox.width, y: ownBox.height)
            return edge.copy(using: &stretch)
        case .sound:
            return nil
        // Paint has no silhouette worked out yet, so it stands as its box.
        case .text, .zoomCallout, .lens, .measure, .collage, .paint:
            return boxArea()
        }
    }
}

/// The arithmetic behind `Layer.followedOutline`: Core Graphics' own area
/// operations, the ones Combine Shapes and Outline Stroke already use.
enum ShapeOutline {

    /// A path's ink: inside it where it is closed and filled, and the band its
    /// own line covers.
    static func area(of path: PathContent) -> CGPath? {
        guard path.anchors.count >= 2 else { return nil }
        var pieces: [CGPath] = []
        let line = OutlineStroke.outline(of: path)?.cgPath
        if path.isClosed, path.fill != nil || line == nil {
            pieces.append(path.cgPath.normalized(using: path.fillRule == .evenOdd ? .evenOdd : .winding))
        }
        if let line { pieces.append(line) }
        return merged(pieces)
    }

    /// A mark's ink, the way `AnnotationRasterizer` lays it down: a box or an
    /// oval out to where its own line reaches, a line as the band it strokes,
    /// an arrow as its shaft and its head together.
    static func area(of annotation: AnnotationContent) -> CGPath? {
        let box = CGRect(x: min(annotation.start.x, annotation.end.x),
                         y: min(annotation.start.y, annotation.end.y),
                         width: abs(annotation.end.x - annotation.start.x),
                         height: abs(annotation.end.y - annotation.start.y))
        let width = annotation.strokeWidth
        let cap: CGLineCap = annotation.showsLineEnds ? annotation.lineEnd.lineCap : .round
        let trim = annotation.trim.flatMap { $0.isWhole ? nil : $0 }
        func swept(_ path: CGPath, cap: CGLineCap = cap) -> CGPath? {
            let drawn = trim?.applied(to: path) ?? path
            guard width > 0, !drawn.isEmpty else { return nil }
            return drawn.copy(strokingWithWidth: width, lineCap: cap, lineJoin: .round, miterLimit: 10)
        }
        switch annotation.shape {
        case .rectangle, .highlight:
            let reach = annotation.shape == .rectangle ? annotation.strokeOutset : 0
            let outer = box.insetBy(dx: -reach, dy: -reach)
            guard outer.width > 0, outer.height > 0 else { return nil }
            let radii = annotation.shape == .rectangle ? annotation.cornerRadii.grown(by: reach) : .none
            return radii.isRound ? radii.fitted(in: outer.size).path(in: outer)
                                 : CGPath(rect: outer, transform: nil)
        case .ellipse:
            let outer = box.insetBy(dx: -annotation.strokeOutset, dy: -annotation.strokeOutset)
            guard outer.width > 0, outer.height > 0 else { return nil }
            return CGPath(ellipseIn: outer, transform: nil)
        case .line:
            let line = CGMutablePath()
            line.move(to: annotation.start)
            line.addLine(to: annotation.end)
            return swept(line)
        case .arrow:
            var pieces: [CGPath] = []
            if annotation.arrowStyle.isHandMade {
                let drawn = HandMadeArrow.outlines(for: annotation)
                pieces = [drawn.shaft, drawn.head].filter { !$0.isEmpty }
                    .map { $0.normalized(using: .winding) }
            } else {
                if let shaft = swept(annotation.shaftPath) { pieces.append(shaft) }
                let headIsDrawn = trim.map { $0.end >= 0.999 && !$0.isEmpty } ?? true
                if headIsDrawn, let head = head(of: annotation) { pieces.append(head) }
            }
            return merged(pieces)
        }
    }

    /// The area every piece covers, overlaps and all, as one outline.
    ///
    /// A real union rather than the pieces laid in one path and normalised:
    /// a swept stroke and a filled triangle can run round in opposite
    /// directions, and under the winding rule the place they overlap would
    /// cancel to a hole, which is exactly where an arrow's shaft runs into its
    /// head. Merged in pairs, so a group of many parts costs a few deep merges
    /// rather than one ever-growing one.
    static func merged(_ pieces: [CGPath]) -> CGPath? {
        var level = pieces.filter { !$0.isEmpty }
        guard !level.isEmpty else { return nil }
        if level.count == 1 { return level[0].normalized(using: .winding) }
        while level.count > 1 {
            var next: [CGPath] = []
            next.reserveCapacity((level.count + 1) / 2)
            var index = 0
            while index < level.count {
                if index + 1 < level.count {
                    next.append(level[index].union(level[index + 1], using: .winding))
                } else {
                    next.append(level[index])
                }
                index += 2
            }
            level = next
        }
        return level[0].isEmpty ? nil : level[0]
    }

    /// An arrow's head, as ink: a dot or a ring, a solid triangle, or the two
    /// strokes of an open one.
    private static func head(of annotation: AnnotationContent) -> CGPath? {
        let width = annotation.strokeWidth
        let style = annotation.arrowheadStyle
        if let circle = Geometry.arrowheadCircle(at: annotation.end, strokeWidth: width,
                                                 scale: annotation.arrowheadScale, style: style) {
            // A hollow ring is drawn with a line of the arrow's own width, so
            // its ink reaches half of that past the circle it rides.
            let reach = circle.radius + (style == .dot ? 0 : width / 2)
            return CGPath(ellipseIn: CGRect(x: circle.center.x - reach, y: circle.center.y - reach,
                                            width: 2 * reach, height: 2 * reach), transform: nil)
        }
        let head = Geometry.arrowhead(start: annotation.headAim, end: annotation.end,
                                      strokeWidth: width, scale: annotation.arrowheadScale,
                                      style: style)
        guard head.count == 3 else { return nil }
        let tip = CGMutablePath()
        if style == .open {
            tip.move(to: head[1])
            tip.addLine(to: head[0])
            tip.addLine(to: head[2])
            return tip.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        }
        tip.addLines(between: head)
        tip.closeSubpath()
        return tip
    }

    /// Everything a group draws, merged into one area: each visible child's
    /// ink, put where the child sits and turned the way it is turned, and the
    /// overlaps taken out, so a ring round it is ONE ring round the whole.
    static func union(of layer: Layer, group: GroupContent, contentScale scale: CGFloat,
                      pictureEdge: (ImageRef) -> CGPath?) -> CGPath? {
        let box = layer.localBounds
        var pieces: [CGPath] = []
        for child in group.children where child.isVisible {
            guard var area = child.drawnArea(contentScale: scale, pictureEdge: pictureEdge) else { continue }
            // A child's own outside ring is part of what it draws, so the
            // group's ring goes round that too, as Photoshop's does.
            let reach = child.style.borderEffectOutset(aroundOpenLine: child.ringsAnOpenLine)
            if reach > 0 {
                area = area.union(area.copy(strokingWithWidth: reach * 2, lineCap: .round,
                                            lineJoin: .miter, miterLimit: pathMiterLimit),
                                  using: .winding)
            }
            // From the child's box to the group's, in points.
            let childBox = child.localBounds
            let origin = CGPoint(x: (childBox.minX + layer.frame.minX - box.minX) / scale,
                                 y: (childBox.minY + layer.frame.minY - box.minY) / scale)
            var place = CGAffineTransform(translationX: origin.x, y: origin.y)
            if !child.transform.isIdentity {
                let centre = CGPoint(x: origin.x + childBox.width / scale / 2,
                                     y: origin.y + childBox.height / scale / 2)
                place = place.concatenating(child.transform.affineTransform(around: centre))
            }
            guard let placed = area.copy(using: &place) else { continue }
            pieces.append(placed)
        }
        return merged(pieces)
    }
}
