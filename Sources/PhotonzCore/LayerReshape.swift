import CoreGraphics
import Foundation

// MARK: - Skew & distort: the picture itself, reshaped
//
// The chip by a picked layer's knob has three modes, in the order they apply:
// Size, Skew & distort, 3D (the user's approved prototype
// `docs/design/mocks/pages/selection-transform.html`, 2026-11-01). Skew &
// distort reshapes the picture ITSELF: an edge pill slides its edge along its
// own line (skew), a corner moves freely (distort), and Shift on a corner
// keystones, the corner across the same edge mirroring it.
//
// The reshape is stored as each corner's offset, as a share of the width and
// height, in the layer's own unturned plane. So a resize keeps the shape, and
// the flat turn, the flip and 3D all act on top of the reshaped picture. The
// renderer warps the finished layer onto the four reshaped corners before it
// turns it (`DocumentRenderer`), and nothing is ever baked into pixels.

/// How a layer's picture is reshaped: each corner's offset, top left, top
/// right, bottom right, bottom left, as a share of the box's width (x) and
/// height (y), y down, in the layer's own plane before any turn.
public struct LayerReshape: Hashable, Sendable {
    public var offsets: [CGPoint]

    public init(offsets: [CGPoint] = [.zero, .zero, .zero, .zero]) {
        self.offsets = offsets.count == 4 ? offsets : [.zero, .zero, .zero, .zero]
    }

    /// Nothing moved: the picture is its box.
    public var isNone: Bool {
        offsets.allSatisfy { abs($0.x) < 1e-9 && abs($0.y) < 1e-9 }
    }

    /// The four reshaped corners of `box`, clockwise from top left.
    public func corners(of box: CGRect) -> [CGPoint] {
        let plain = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                     CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        return zip(plain, offsets).map {
            CGPoint(x: $0.x + $1.x * box.width, y: $0.y + $1.y * box.height)
        }
    }

    /// Where each reshaped corner sits as a share of the box, its own corner
    /// included: the top right with no offset is (1, 0).
    private var shares: [CGPoint] {
        let base = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        return zip(base, offsets).map { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
    }

    /// The flat rectangle round the reshaped picture, in the same plane: what
    /// Size and 3D put their grips on, so a reshaped picture is handled like a
    /// new original.
    public func outerBox(of box: CGRect) -> CGRect {
        let s = shares
        let x0 = s.map(\.x).min() ?? 0, x1 = s.map(\.x).max() ?? 1
        let y0 = s.map(\.y).min() ?? 0, y1 = s.map(\.y).max() ?? 1
        return CGRect(x: box.minX + x0 * box.width, y: box.minY + y0 * box.height,
                      width: (x1 - x0) * box.width, height: (y1 - y0) * box.height)
    }

    /// The box whose reshaped picture has `outer` round it: how a resize made
    /// on the flat rectangle round a reshaped picture becomes the layer's own
    /// frame. A shape squashed to a line across or down keeps the frame's size
    /// that way.
    public func frame(forOuterBox outer: CGRect) -> CGRect {
        let s = shares
        let x0 = s.map(\.x).min() ?? 0, x1 = s.map(\.x).max() ?? 1
        let y0 = s.map(\.y).min() ?? 0, y1 = s.map(\.y).max() ?? 1
        let w = x1 - x0 > 1e-9 ? outer.width / (x1 - x0) : outer.width
        let h = y1 - y0 > 1e-9 ? outer.height / (y1 - y0) : outer.height
        return CGRect(x: outer.minX - x0 * w, y: outer.minY - y0 * h, width: w, height: h)
    }

    /// The plane map that sends `box` onto its reshaped corners. Nil where
    /// the shape has folded flat.
    public func map(of box: CGRect) -> Homography? {
        Homography(box: box, to: corners(of: box))
    }
}

extension LayerReshape: Codable {
    /// Eight numbers, two per corner, top left first. Anything else reads as
    /// no reshape rather than failing the whole document.
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var numbers: [Double] = []
        while !c.isAtEnd { numbers.append(try c.decode(Double.self)) }
        guard numbers.count == 8, numbers.allSatisfy(\.isFinite) else { self.init(); return }
        self.init(offsets: stride(from: 0, to: 8, by: 2).map { CGPoint(x: numbers[$0], y: numbers[$0 + 1]) })
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        for p in offsets {
            try c.encode(Double(p.x))
            try c.encode(Double(p.y))
        }
    }
}

extension Layer {
    /// Whether Skew & distort is offered on this layer: one drawn picture,
    /// shape or piece of text. A group, a magnifier, a line, an arrow and a
    /// measurement are not: a group draws its contents its own way, a
    /// magnifier's leader lines meet its box, and the rest move by their ends.
    public var canBeReshaped: Bool {
        !isGroup && zoomCallout == nil && !hasEndpointHandles && measure == nil
    }

    /// The reshape this layer is drawn with, where it has one at all.
    public var shownReshape: LayerReshape? {
        guard let reshape, !reshape.isNone else { return nil }
        return reshape
    }

    /// The reshaped picture's four corners, through the layer's flat turn,
    /// clockwise from top left, in the same space as `transformedCorners`.
    public var reshapedCorners: [CGPoint] {
        guard let reshape = shownReshape else { return transformedCorners }
        let corners = reshape.corners(of: turnBox)
        guard !transform.isIdentity else { return corners }
        return corners.map { $0.applying(transform.affineTransform(around: turnPivot)) }
    }

    /// The flat rectangle round the reshaped picture through the flat turn:
    /// where Size and 3D put their grips. The box itself with no reshape.
    public var reshapedOuterCorners: [CGPoint] {
        guard let reshape = shownReshape else { return transformedCorners }
        let outer = reshape.outerBox(of: turnBox)
        let corners = LayerReshape().corners(of: outer)
        guard !transform.isIdentity else { return corners }
        return corners.map { $0.applying(transform.affineTransform(around: turnPivot)) }
    }

    /// A point on the reshaped picture (unturned) carried back onto the box it
    /// was reshaped from: how a click is read on a reshaped layer. The point
    /// unchanged where nothing is reshaped.
    public func unreshaped(_ point: CGPoint) -> CGPoint? {
        guard let reshape = shownReshape else { return point }
        return reshape.map(of: turnBox)?.inverted?.apply(point)
    }
}

// MARK: - What a drag in Skew & distort does

public enum ReshapeDrag {
    /// The corner across the same top or bottom edge, which keystone mirrors.
    public static func keystonePartner(of corner: Int) -> Int { [1, 0, 3, 2][corner & 3] }

    /// The two corners an edge's pill carries.
    public static func corners(of edge: ResizeHandle) -> [Int] {
        switch edge {
        case .top: [0, 1]
        case .right: [1, 2]
        case .bottom: [2, 3]
        case .left: [3, 0]
        default: []
        }
    }

    public static func cornerIndex(of handle: ResizeHandle) -> Int? {
        switch handle {
        case .topLeft: 0
        case .topRight: 1
        case .bottomRight: 2
        case .bottomLeft: 3
        default: nil
        }
    }

    /// Distort: `corner` moves by `delta` (points, in the layer's own unturned
    /// plane). Keystone: the corner across the same edge comes in or goes out
    /// by as much the other way, at the same height, so the picture stays
    /// symmetrical about its middle.
    public static func distorted(_ start: LayerReshape, corner: Int, by delta: CGPoint, size: CGSize,
                                 keystone: Bool) -> LayerReshape {
        guard (0..<4).contains(corner) else { return start }
        let d = share(delta, of: size)
        var offsets = start.offsets
        offsets[corner] = CGPoint(x: start.offsets[corner].x + d.x, y: start.offsets[corner].y + d.y)
        if keystone {
            let j = keystonePartner(of: corner)
            offsets[j] = CGPoint(x: start.offsets[j].x - d.x, y: start.offsets[j].y + d.y)
        }
        return LayerReshape(offsets: offsets)
    }

    /// Skew: the edge slides along its own line in the picture's plane, so the
    /// picture slants. A top or bottom pill moves its two corners across, a
    /// side pill moves its two up or down.
    public static func skewed(_ start: LayerReshape, edge: ResizeHandle, by delta: CGPoint,
                              size: CGSize) -> LayerReshape {
        let d = share(delta, of: size)
        let across = edge == .top || edge == .bottom
        var offsets = start.offsets
        for k in corners(of: edge) {
            offsets[k] = across ? CGPoint(x: start.offsets[k].x + d.x, y: start.offsets[k].y)
                                : CGPoint(x: start.offsets[k].x, y: start.offsets[k].y + d.y)
        }
        return LayerReshape(offsets: offsets)
    }

    /// The slant a skew drag has put on the picture's sides, in degrees.
    public static func skewDegrees(edge: ResizeHandle, by delta: CGPoint, size: CGSize) -> Double {
        let across = edge == .top || edge == .bottom
        let r = across ? atan2(Double(delta.x), Double(size.height)) : atan2(Double(delta.y), Double(size.width))
        return r * 180 / .pi
    }

    private static func share(_ delta: CGPoint, of size: CGSize) -> CGPoint {
        CGPoint(x: size.width > 0 ? delta.x / size.width : 0, y: size.height > 0 ? delta.y / size.height : 0)
    }
}
