import CoreGraphics
import Foundation

/// The zoom callout tool's own memory, exactly like `AnnotationStyles` is the
/// per-shape memory and `MeasureStyles` the measure tool's: what the NEXT
/// callout you draw looks like.
///
/// The silhouette and how much it magnifies. Both are choices you make with
/// the tool in your hand, before there is anything to pick.
///
/// The number used to be left out on the grounds that magnification comes out
/// of the drag. It does not: the drag says which region to magnify, and every
/// new callout was drawn at exactly two whatever you dragged. What the old
/// note was really guarding against is the tool absorbing whatever the last
/// corner pull left behind, and that still holds — this is written ONLY when
/// somebody moves the tool's own control, never when a placed callout is
/// resized.
public struct CalloutStyles: Equatable, Codable, Sendable {
    /// Box or circle for the next callout, and for the source outline that
    /// goes with it.
    public var shape: ZoomCalloutShape

    /// How much bigger the next callout draws the region it points at. Always
    /// inside what the slider offers, whatever is assigned.
    public var magnification: CGFloat {
        didSet { magnification = ZoomCalloutBuilder.clampedMagnification(magnification) }
    }

    public init(shape: ZoomCalloutShape = .rectangle,
                magnification: CGFloat = ZoomCalloutBuilder.defaultMagnification) {
        self.shape = shape
        self.magnification = ZoomCalloutBuilder.clampedMagnification(magnification)
    }

    /// Tolerant, like the other style memories: a blob written before the tool
    /// remembered anything reads as the shipped default rather than throwing
    /// the whole memory away.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shape = try container.decodeIfPresent(ZoomCalloutShape.self, forKey: .shape) ?? .rectangle
        magnification = ZoomCalloutBuilder.clampedMagnification(
            try container.decodeIfPresent(CGFloat.self, forKey: .magnification)
                ?? ZoomCalloutBuilder.defaultMagnification)
    }
}
