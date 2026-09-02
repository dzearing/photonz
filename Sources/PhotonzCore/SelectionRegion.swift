import CoreGraphics
import Foundation

/// A path-based selected REGION of the canvas (Photoshop-style), in document
/// coordinates. Distinct from layer selection: while a region exists, ops like
/// fill/delete/copy target it instead of the selected layer.
///
/// This is editor state, not document state — it is never persisted, so it
/// wraps a `CGPath` directly (fine for PhotonzCore: CoreGraphics only).
/// Interior is defined by the even-odd rule everywhere (containment, ants,
/// fill clipping), which is what the CGPath boolean ops emit.
public struct SelectionRegion: Equatable, @unchecked Sendable {
    // @unchecked, and why it cannot be plain Sendable: the macOS 26 SDK does not
    // mark `CGPath` Sendable (its subclass `CGMutablePath` is mutable), so a
    // struct holding one fails strict-concurrency checking outright. The only
    // alternative would be to store the path as value-typed elements and rebuild
    // a CGPath on every `contains`/`bounds` call, which the marching ants and
    // fill clipping hit constantly. Instead this type guarantees the invariant
    // the compiler cannot see: `path` is always an immutable `CGPath` copy made
    // by `init` (a `CGMutablePath` source is never retained; if the copy fails
    // the init fails), and nothing here ever hands it out for mutation.

    /// The region outline. Immutable; may contain multiple subpaths (disjoint
    /// blobs) and holes (even-odd).
    public let path: CGPath

    /// How a new shape combines with the existing selection.
    public enum Mode: Equatable, Sendable {
        case replace, add, subtract, intersect

        /// Photoshop-style gesture modifiers: ⇧ add, ⌥ subtract, ⇧⌥ intersect.
        public init(shift: Bool, option: Bool) {
            switch (shift, option) {
            case (false, false): self = .replace
            case (true, false): self = .add
            case (false, true): self = .subtract
            case (true, true): self = .intersect
            }
        }
    }

    /// `nil` when the path encloses no area — callers hold `SelectionRegion?`
    /// and `nil` uniformly means "no selection".
    public init?(path: CGPath) {
        let box = path.boundingBoxOfPath
        guard !path.isEmpty, !box.isNull, box.width > 0, box.height > 0,
              let copy = path.copy() else { return nil }
        self.path = copy
    }

    public static func rect(_ rect: CGRect) -> SelectionRegion? {
        let r = rect.standardized
        guard !r.isEmpty else { return nil }
        return SelectionRegion(path: CGPath(rect: r, transform: nil))
    }

    public static func ellipse(in rect: CGRect) -> SelectionRegion? {
        let r = rect.standardized
        guard !r.isEmpty else { return nil }
        return SelectionRegion(path: CGPath(ellipseIn: r, transform: nil))
    }

    /// Tight bounding box of the region (what rect-based consumers use).
    public var bounds: CGRect { path.boundingBoxOfPath }

    public func contains(_ point: CGPoint) -> Bool {
        path.contains(point, using: .evenOdd)
    }

    /// This region combined with `shape`. `nil` when the result encloses no
    /// area (e.g. subtracting everything), collapsing the selection.
    public func combining(_ shape: SelectionRegion, mode: Mode) -> SelectionRegion? {
        switch mode {
        case .replace: return shape
        case .add: return SelectionRegion(path: path.union(shape.path, using: .evenOdd))
        case .subtract: return SelectionRegion(path: path.subtracting(shape.path, using: .evenOdd))
        case .intersect: return SelectionRegion(path: path.intersection(shape.path, using: .evenOdd))
        }
    }

    /// The region shifted by `delta` — moving the outline, or following
    /// content that moved. (A translation can't empty a region, but the
    /// optional keeps the `SelectionRegion?` call sites uniform.)
    public func translated(by delta: CGVector) -> SelectionRegion? {
        guard delta != .zero else { return self }
        var transform = CGAffineTransform(translationX: delta.dx, y: delta.dy)
        return path.copy(using: &transform).flatMap(SelectionRegion.init)
    }

    /// Combines against an optional existing selection: with no base, replace
    /// and add start from the shape; subtract and intersect select nothing.
    public static func combine(_ base: SelectionRegion?, with shape: SelectionRegion, mode: Mode) -> SelectionRegion? {
        guard let base else {
            switch mode {
            case .replace, .add: return shape
            case .subtract, .intersect: return nil
            }
        }
        return base.combining(shape, mode: mode)
    }

    public static func == (lhs: SelectionRegion, rhs: SelectionRegion) -> Bool {
        lhs.path == rhs.path
    }
}
