import CoreGraphics
import Foundation

// MARK: - Reset each transform mode on its own
//
// The selection chip's three modes (Size, Skew & distort, 3D) each change
// their own part of a layer, so each can be put back without losing the
// others: right-click a mode on the chip, or Edit ▸ Transform. A mode that has
// something to put back wears a small dot on its chip button. The user's
// approved prototype `docs/design/mocks/pages/selection-transform.html`,
// `changed()` and `resetStage()`.
//
// - Size: the layer's turn on the page, and for a picture its size against
//   the picture's own pixels. A shape or a piece of text has no size of its
//   own to go back to, so only its turn counts. Reset puts the picture back at
//   its own size about the same middle, upright.
// - Skew & distort: the four-corner reshape (`LayerReshape`) and the old flat
//   slant (`LayerTransform.skewX`, `skewY`), which is a skew too.
// - 3D: tip, swing and depth (`LayerTurn3D`), keyed or not. The camera's
//   perspective is every 3D layer's, not this one's, so it stays.
//
// A flip is none of these, so no reset takes it away. Keys on a mode's values
// go with the reset, the way Reset 3D Rotation always took them: a key left
// behind would put the change straight back.

/// What one reset row puts back: one mode, or all three.
public enum TransformReset: String, CaseIterable, Hashable, Sendable {
    case size
    case reshape
    case space
    case all

    public init(_ mode: TransformMode) {
        switch mode {
        case .size: self = .size
        case .reshape: self = .reshape
        case .space: self = .space
        }
    }

    /// The modes this row puts back, in the chip's order.
    public var modes: [TransformMode] {
        switch self {
        case .size: [.size]
        case .reshape: [.reshape]
        case .space: [.space]
        case .all: TransformMode.offered
        }
    }

    /// The row's words, after the chip's own names for its modes.
    public var title: String {
        switch self {
        case .size: "Reset Size"
        case .reshape: "Reset Skew & Distort"
        case .space: "Reset 3D"
        case .all: "Reset All"
        }
    }

    /// A size within this many points of the picture's own reads as its own.
    public static let sizeTolerance: CGFloat = 0.5
    /// The 3D values a reset puts back, and whose keys go with it.
    static let spaceProperties: [MotionProperty] = [.rotationX, .rotationY, .depth]
    /// The Size values whose keys go with Reset Size.
    static let sizeProperties: [MotionProperty] = [.rotation, .scale]
}

extension Layer {
    /// The size a picture has of its own: its pixels. Nil for anything drawn
    /// (a shape, text, a group), which has no size to go back to.
    public var ownSize: CGSize? {
        guard case .image(let ref) = content, ref.pixelSize.width > 0, ref.pixelSize.height > 0 else { return nil }
        return ref.pixelSize
    }

    /// Whether `mode` has anything to put back on this layer.
    public func hasTransformChange(_ mode: TransformMode) -> Bool {
        switch mode {
        case .size:
            if transform.rotation != 0 { return true }
            if TransformReset.sizeProperties.contains(where: { keyedMotion($0) != nil }) { return true }
            guard let own = ownSize else { return false }
            return abs(frame.width - own.width) > TransformReset.sizeTolerance
                || abs(frame.height - own.height) > TransformReset.sizeTolerance
        case .reshape:
            if transform.skewX != 0 || transform.skewY != 0 { return true }
            return !(reshape?.isNone ?? true)
        case .space:
            if let turn = turn3D, turn.rotationX != 0 || turn.rotationY != 0 || turn.depth != 0 { return true }
            return TransformReset.spaceProperties.contains { keyedMotion($0) != nil }
        }
    }

    /// Puts `mode` back, leaving the other modes and the flips as they are.
    public mutating func resetTransform(_ mode: TransformMode) {
        switch mode {
        case .size:
            dropMotions(TransformReset.sizeProperties)
            transform.rotation = 0
            if let own = ownSize {
                frame = CGRect(x: frame.midX - own.width / 2, y: frame.midY - own.height / 2,
                               width: own.width, height: own.height)
            }
        case .reshape:
            reshape = nil
            transform.skewX = 0
            transform.skewY = 0
        case .space:
            dropMotions(TransformReset.spaceProperties)
            guard var turn = turn3D else { return }
            turn.rotationX = 0
            turn.rotationY = 0
            turn.depth = 0
            turn3D = turn
            settleTurn3D()
        }
    }

    private mutating func dropMotions(_ properties: [MotionProperty]) {
        guard let all = motions else { return }
        let kept = all.filter { !properties.contains($0.property) }
        motions = kept.isEmpty ? nil : kept
    }
}

extension PhotonzDocument {
    /// Whether `reset` has anything to put back on the layer: what greys a row
    /// of the chip's menu and puts a dot on a chip button.
    public func hasTransformChange(_ reset: TransformReset, layerID id: UUID) -> Bool {
        guard let layer = layer(id: id) else { return false }
        return reset.modes.contains { layer.hasTransformChange($0) }
    }

    /// Puts `reset` back on each of `ids` that is not locked. One call is one
    /// undo step when made inside `History.perform`.
    public mutating func resetTransform(_ reset: TransformReset, layerIDs ids: [UUID]) {
        for id in ids {
            guard let found = layer(id: id), !found.isLocked else { continue }
            updateLayer(id: id) { layer in
                for mode in reset.modes { layer.resetTransform(mode) }
            }
        }
    }
}
