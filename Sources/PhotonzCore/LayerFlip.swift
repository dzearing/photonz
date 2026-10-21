import CoreGraphics
import Foundation

/// Flip Horizontal and Flip Vertical: what is picked, mirrored where it
/// stands, the pair Photoshop keeps under Edit ▸ Transform (with no keys, so
/// none here either: UX-PATTERNS §7).
///
/// One layer flips about its own middle and stays where it is. Several flip
/// about the middle of all of them, so a row read left to right reads right
/// to left, the way a selection flips in Photoshop and Figma.
///
/// A flip mirrors what is SEEN: a layer turned 20° clockwise is turned 20°
/// anticlockwise once mirrored, and one turning over time turns the other way
/// at every moment. Where the layer's own numbers can say the mirror image (a
/// path point for point, a line's two ends, a box's corners) they do;
/// everything else (a picture, words, a component copy) wears the flip on its
/// transform, which draws the same reflection. Words read backwards, which is
/// what flipping words means.
public enum FlipAxis: String, CaseIterable, Hashable, Codable, Sendable {
    /// Left to right, about an upright line.
    case horizontal
    /// Top to bottom, about a level line.
    case vertical

    /// The command's name in every menu that offers it, Photoshop's own.
    public var title: String {
        switch self {
        case .horizontal: "Flip Horizontal"
        case .vertical: "Flip Vertical"
        }
    }

    /// The coordinate this axis reflects.
    func along(_ point: CGPoint) -> CGFloat { self == .horizontal ? point.x : point.y }
    func min(_ rect: CGRect) -> CGFloat { self == .horizontal ? rect.minX : rect.minY }
    func max(_ rect: CGRect) -> CGFloat { self == .horizontal ? rect.maxX : rect.maxY }
    func mid(_ rect: CGRect) -> CGFloat { self == .horizontal ? rect.midX : rect.midY }
    func length(_ size: CGSize) -> CGFloat { self == .horizontal ? size.width : size.height }

    func moved(_ point: CGPoint, by delta: CGFloat) -> CGPoint {
        self == .horizontal ? CGPoint(x: point.x + delta, y: point.y)
                            : CGPoint(x: point.x, y: point.y + delta)
    }

    /// `point` reflected inside a box of `size` whose corner is the origin.
    func reflected(_ point: CGPoint, in size: CGSize) -> CGPoint {
        self == .horizontal ? CGPoint(x: size.width - point.x, y: point.y)
                            : CGPoint(x: point.x, y: size.height - point.y)
    }

    /// `rect` reflected inside a box of `size` whose corner is the origin.
    func reflected(_ rect: CGRect, in size: CGSize) -> CGRect {
        self == .horizontal
            ? CGRect(x: size.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
            : CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
    }
}

extension LayerTransform {
    /// Whether the transform wears a flip on `axis`.
    public func isFlipped(_ axis: FlipAxis) -> Bool {
        axis == .horizontal ? flipHorizontal : flipVertical
    }

    mutating func toggleFlip(_ axis: FlipAxis) {
        if axis == .horizontal { flipHorizontal.toggle() } else { flipVertical.toggle() }
    }
}

extension Layer {

    /// This layer reflected across the line `axis` = `line` (an upright line
    /// for `.horizontal`, a level one for `.vertical`), with `line` stated in
    /// the same space as `frame` (the parent's). Same identity.
    ///
    /// A turn turns the other way, because a reflection runs every angle
    /// backwards. The look is left as it is: a shadow cast down and to the
    /// right stays down and to the right, as Photoshop's layer styles do.
    public func reflected(across axis: FlipAxis, at line: CGFloat) -> Layer {
        var reflected = self
        reflected.transform.rotation = -transform.rotation
        reflected.transform.skewX = -transform.skewX
        reflected.transform.skewY = -transform.skewY
        if let group, isGroup {
            if group.isFrame || group.layout != nil || isComponentInstance {
                // A box that is not just its contents: the box moves, and what
                // is inside it is reflected about its own middle, or, where
                // something else places the contents (a stack, the original
                // of a copy), the whole of it is flipped.
                let box = localBounds
                reflected.frame.origin = axis.moved(frame.origin,
                                                    by: (2 * line - axis.max(box)) - axis.min(box))
                if group.isFrame {
                    let middle = axis.length(frame.standardized.size) / 2
                    reflected.children = children.map { $0.reflected(across: axis, at: middle) }
                } else {
                    reflected.transform.toggleFlip(axis)
                }
            } else {
                // A plain group's box is wherever its contents are, so the
                // contents move and its anchor stays put.
                let local = line - axis.along(frame.origin)
                reflected.children = children.map { $0.reflected(across: axis, at: local) }
            }
            return reflected
        }
        let box = frame.standardized
        reflected.frame.origin = axis.moved(frame.origin, by: (2 * line - axis.max(box)) - axis.min(box))
        if let content = content.reflected(axis, in: box.size) {
            reflected.content = content
            reflected.crop = crop.map { axis.reflected($0, in: box.size) }
        } else {
            reflected.transform.toggleFlip(axis)
        }
        return reflected
    }

    /// Flip: this layer reflected across `line`, and every value it moves
    /// through over time reflected with it, so it is the mirror image at every
    /// moment. Its turn runs the other way; the path it travels keeps its
    /// shape, carried along by however far the reflection moved its box.
    public func flipped(_ axis: FlipAxis, at line: CGFloat) -> Layer {
        var flipped = reflected(across: axis, at: line)
        guard let motions, !motions.isEmpty else { return flipped }
        let shift = axis.along(flipped.frame.origin) - axis.along(frame.origin)
        flipped.motions = motions.map { motion in
            switch motion.property {
            case .rotation:
                return motion.mappingValues { value in
                    if case let .number(degrees) = value { return .number(-degrees) }
                    return value
                }
            case .position where shift != 0:
                return motion.mappingValues { value in
                    if case let .point(point) = value { return .point(axis.moved(point, by: shift)) }
                    return value
                }
            default:
                return motion
            }
        }
        return flipped
    }

    /// The box this layer flips about, in its parent's space: its frame, or
    /// for a group the box its contents occupy.
    var flipBox: CGRect { isGroup ? localBounds : frame.standardized }

    /// This layer mirrored inside its own box: the drawing reflected, the box
    /// and the turn just as they were. What a side handle dragged past the
    /// opposite side does, as in Photoshop's Free Transform, so a turned layer
    /// stays turned and only what is on it reads the other way.
    public func mirroredInPlace(_ axes: Set<FlipAxis>) -> Layer {
        var mirrored = self
        for axis in FlipAxis.allCases where axes.contains(axis) {
            mirrored = mirrored.reflected(across: axis, at: axis.mid(mirrored.flipBox))
            mirrored.transform.rotation = transform.rotation
            mirrored.transform.skewX = transform.skewX
            mirrored.transform.skewY = transform.skewY
        }
        return mirrored
    }
}

extension LayerMotion {
    /// The same motion with every key's value passed through `change`: From,
    /// To and each key between.
    func mappingValues(_ change: (MotionValue) -> MotionValue) -> LayerMotion {
        var mapped = self
        mapped.from = change(from)
        mapped.to = change(to)
        mapped.stops = stops?.map { stop in
            var stop = stop
            stop.value = change(stop.value)
            return stop
        }
        return mapped
    }
}

extension LayerContent {

    /// The content reflected inside its own box of `size`, or nil where it
    /// cannot be stated reflected and has to be flipped instead.
    func reflected(_ axis: FlipAxis, in size: CGSize) -> LayerContent? {
        switch self {
        case .path(let path):
            let mirror = axis == .horizontal
                ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: size.width, ty: 0)
                : CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
            return .path(path.transformed(by: mirror))
        case .annotation(var mark):
            switch mark.shape {
            case .arrow, .line:
                // A line runs from one end to the other, so both ends move.
                mark.start = axis.reflected(mark.start, in: size)
                mark.end = axis.reflected(mark.end, in: size)
                // The bend is stated against the line from tail to tip, on
                // its left; reflected either way, the same bow is on its right.
                if let bend = mark.bend {
                    mark.bend = ArrowBend(along: bend.along, across: -bend.across)
                }
            case .rectangle, .ellipse, .highlight:
                // A box fills its frame whichever corner it was dragged from,
                // so only a corner rounded unlike its neighbour changes side.
                let c = mark.cornerRadii
                mark.cornerRadii = axis == .horizontal
                    ? CornerRadii(topLeft: c.topRight, topRight: c.topLeft,
                                  bottomRight: c.bottomLeft, bottomLeft: c.bottomRight)
                    : CornerRadii(topLeft: c.bottomLeft, topRight: c.bottomRight,
                                  bottomRight: c.topRight, bottomLeft: c.topLeft)
            }
            return .annotation(mark)
        case .image, .text, .collage, .zoomCallout, .lens, .measure, .group, .sound:
            return nil
        }
    }
}

extension PhotonzDocument {

    /// Whether Flip Horizontal or Flip Vertical would do anything to `ids`:
    /// the same layers Mirror Across Center takes (unlocked, of a kind a
    /// reflection means something for, not a piece of a copy, not inside
    /// another picked layer).
    public func canFlip(ids: Set<UUID>) -> Bool { !mirrorTargets(ids: ids).isEmpty }

    /// Flips every picked layer across `axis` in one mutation, so it is one
    /// undo step: one layer about its own middle, several about the middle of
    /// the box round all of them. False when there was nothing to flip.
    @discardableResult
    public mutating func flip(ids: Set<UUID>, _ axis: FlipAxis) -> Bool {
        let targets = mirrorTargets(ids: ids)
        let boxes = targets.compactMap { canvasBounds(of: $0) }
        guard let first = boxes.first else { return false }
        let line = axis.mid(boxes.dropFirst().reduce(first) { $0.union($1) })
        for id in targets {
            guard let origin = parentOrigin(of: id) else { continue }
            let local = line - axis.along(origin)
            updateLayer(id: id) { $0 = $0.flipped(axis, at: local) }
        }
        return true
    }
}

extension Handles {

    /// A handle drag that may cross the opposite side: the box it lands on,
    /// always upright and never inside out, and which ways the drag crossed.
    public struct FlippingResize: Equatable, Sendable {
        public var frame: CGRect
        public var flips: Set<FlipAxis>
    }

    /// The frame after dragging `handle` to `p`, where taking a side past the
    /// side opposite flips the layer and keeps going, as in Photoshop and
    /// Figma, instead of stopping at nothing.
    ///
    /// The pointer is reflected back across the side it crossed, given the
    /// plain resize, and the answer reflected forward again, so everything the
    /// plain resize knows (the smallest box, ⇧ keeping the shape) holds on
    /// both sides of the line.
    public static func resizeFlipping(_ frame: CGRect, dragging handle: ResizeHandle, to p: CGPoint,
                                      preserveAspect: Bool, minSize: CGFloat = 1) -> FlippingResize {
        let flips = crossings(of: handle, in: frame, pointer: p)
        let back = reflectedPointer(p, handle: handle, in: frame, flips: flips)
        var r = resize(frame, dragging: handle, to: back, preserveAspect: preserveAspect, minSize: minSize)
        r = reflectedFrame(r, handle: handle, in: frame, flips: flips)
        return FlippingResize(frame: r, flips: flips)
    }

    /// Which ways a pointer holding `handle` has crossed the side opposite.
    public static func crossings(of handle: ResizeHandle, in frame: CGRect,
                                 pointer p: CGPoint) -> Set<FlipAxis> {
        var flips: Set<FlipAxis> = []
        if (handle.movesMinX && p.x > frame.maxX) || (handle.movesMaxX && p.x < frame.minX) {
            flips.insert(.horizontal)
        }
        if (handle.movesMinY && p.y > frame.maxY) || (handle.movesMaxY && p.y < frame.minY) {
            flips.insert(.vertical)
        }
        return flips
    }

    /// The side a drag on `handle` holds still, on `axis`.
    static func anchorLine(_ handle: ResizeHandle, in frame: CGRect, _ axis: FlipAxis) -> CGFloat {
        switch axis {
        case .horizontal: handle.movesMinX ? frame.maxX : frame.minX
        case .vertical: handle.movesMinY ? frame.maxY : frame.minY
        }
    }

    /// `p` reflected back across every side it crossed.
    public static func reflectedPointer(_ p: CGPoint, handle: ResizeHandle, in frame: CGRect,
                                        flips: Set<FlipAxis>) -> CGPoint {
        var q = p
        if flips.contains(.horizontal) { q.x = 2 * anchorLine(handle, in: frame, .horizontal) - p.x }
        if flips.contains(.vertical) { q.y = 2 * anchorLine(handle, in: frame, .vertical) - p.y }
        return q
    }

    /// `rect` reflected across every side the drag crossed: the box on the
    /// far side of the line it was worked out on.
    public static func reflectedFrame(_ rect: CGRect, handle: ResizeHandle, in frame: CGRect,
                                      flips: Set<FlipAxis>) -> CGRect {
        var r = rect
        if flips.contains(.horizontal) {
            r.origin.x = 2 * anchorLine(handle, in: frame, .horizontal) - rect.maxX
        }
        if flips.contains(.vertical) {
            r.origin.y = 2 * anchorLine(handle, in: frame, .vertical) - rect.maxY
        }
        return r
    }

    /// `anchoredFrame` for a drag that crossed the side opposite: the side
    /// it held is now the far side of the new box on each crossed axis, so
    /// that is the point kept still on screen.
    public static func anchoredFrame(start: CGRect, proposed newFrame: CGRect, handle: ResizeHandle,
                                     transform: LayerTransform, flips: Set<FlipAxis>) -> CGRect {
        guard !flips.isEmpty else {
            return anchoredFrame(start: start, proposed: newFrame, handle: handle, transform: transform)
        }
        guard !transform.isIdentity else { return newFrame }
        let anchor = handle.opposite
        var held = point(for: anchor, in: newFrame)
        if flips.contains(.horizontal) { held.x = newFrame.minX + newFrame.maxX - held.x }
        if flips.contains(.vertical) { held.y = newFrame.minY + newFrame.maxY - held.y }
        let screenOld = point(for: anchor, in: start)
            .applying(transform.affineTransform(around: CGPoint(x: start.midX, y: start.midY)))
        let screenNew = held
            .applying(transform.affineTransform(around: CGPoint(x: newFrame.midX, y: newFrame.midY)))
        return newFrame.offsetBy(dx: screenOld.x - screenNew.x, dy: screenOld.y - screenNew.y)
    }
}
