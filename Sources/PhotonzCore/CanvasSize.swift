import CoreGraphics
import Foundation

/// Where existing content pins when the canvas size changes: the 3×3 grid of
/// the canvas-size dialog's anchor picker.
public enum CanvasAnchor: String, CaseIterable, Hashable, Codable, Sendable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight

    /// Offset multipliers: the content shifts by `(Δwidth · unit.x, Δheight · unit.y)`.
    public var unit: CGPoint {
        let x: CGFloat = switch self {
        case .topLeft, .left, .bottomLeft: 0
        case .top, .center, .bottom: 0.5
        case .topRight, .right, .bottomRight: 1
        }
        let y: CGFloat = switch self {
        case .topLeft, .top, .topRight: 0
        case .left, .center, .right: 0.5
        case .bottomLeft, .bottom, .bottomRight: 1
        }
        return CGPoint(x: x, y: y)
    }
}

extension PhotonzDocument {
    /// Changes the canvas size without scaling content: every layer keeps its
    /// size and shifts per the anchor (the corner/edge of the old canvas that
    /// stays pinned to the same corner/edge of the new one). Layers falling
    /// outside a shrunk canvas are kept — they clip visually but survive,
    /// unlike `crop(to:)`.
    public mutating func setCanvasSize(_ newSize: CGSize, anchor: CanvasAnchor) {
        let size = CGSize(width: max(1, newSize.width), height: max(1, newSize.height))
        let dx = (size.width - canvasSize.width) * anchor.unit.x
        let dy = (size.height - canvasSize.height) * anchor.unit.y
        canvasSize = size
        for i in layers.indices {
            layers[i].frame.origin.x += dx
            layers[i].frame.origin.y += dy
        }
    }
}
