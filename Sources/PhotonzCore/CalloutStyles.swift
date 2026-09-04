import Foundation

/// The zoom callout tool's own memory, exactly like `AnnotationStyles` is the
/// per-shape memory and `MeasureStyles` the measure tool's: what the NEXT
/// callout you draw looks like.
///
/// Only the silhouette lives here. Magnification comes out of the drag and out
/// of every corner pull afterwards, so remembering it would mean the tool
/// quietly picked up whatever the last resize left behind; there is nothing to
/// remember that the drag does not already say.
public struct CalloutStyles: Equatable, Codable, Sendable {
    /// Box or circle for the next callout, and for the source outline that
    /// goes with it.
    public var shape: ZoomCalloutShape

    public init(shape: ZoomCalloutShape = .rectangle) {
        self.shape = shape
    }

    /// Tolerant, like the other style memories: a blob written before the tool
    /// remembered anything reads as the shipped default rather than throwing
    /// the whole memory away.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shape = try container.decodeIfPresent(ZoomCalloutShape.self, forKey: .shape) ?? .rectangle
    }
}
