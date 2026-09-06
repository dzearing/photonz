import CoreGraphics
import Foundation

/// Which way a pinned guide runs.
public enum CanvasGuideAxis: String, Codable, Sendable, CaseIterable {
    /// A line down the picture, fixed at an x.
    case vertical
    /// A line across the picture, fixed at a y.
    case horizontal
}

/// A line the grid could give you, before anybody has pinned it: the thing the
/// canvas lights up under the pointer while the grid is being adjusted.
public struct CanvasGuideLine: Hashable, Sendable {
    public var axis: CanvasGuideAxis
    /// Document points: an x for a vertical line, a y for a horizontal one.
    public var position: CGFloat

    public init(axis: CanvasGuideAxis, position: CGFloat) {
        self.axis = axis
        self.position = position.isFinite ? position : 0
    }
}

/// A guide somebody pinned: one line, held at one place in ONE document.
///
/// It belongs to the document rather than to the app because a guide marking
/// the left margin of one screenshot means nothing in another. It is drawn by
/// the canvas rather than by the renderer, so like the grid it never reaches an
/// export or a copied picture — and unlike the grid it stays on screen when the
/// grid is switched off, because you pinned it on purpose and the grid is only
/// the ruler you pinned it with.
public struct CanvasGuide: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var axis: CanvasGuideAxis
    /// Document points: an x for a vertical guide, a y for a horizontal one.
    public var position: CGFloat

    public init(id: UUID = UUID(), axis: CanvasGuideAxis, position: CGFloat) {
        self.id = id
        self.axis = axis
        self.position = position.isFinite ? position : 0
    }

    public init(id: UUID = UUID(), line: CanvasGuideLine) {
        self.init(id: id, axis: line.axis, position: line.position)
    }

    public var line: CanvasGuideLine { CanvasGuideLine(axis: axis, position: position) }

    /// A number written by hand into a saved document cannot put a guide
    /// somewhere the canvas has no way to draw.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let position = try c.decode(CGFloat.self, forKey: .position)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  axis: try c.decode(CanvasGuideAxis.self, forKey: .axis),
                  position: position.isFinite ? position : 0)
    }
}

/// Working with a set of pinned guides: adding one, finding the one under the
/// pointer, and reading them back per axis for the snapping path.
///
/// It is free functions over an array rather than methods on the document
/// because the SAME operations run on the document's guides and on the working
/// copy held while the grid is being adjusted, and two implementations of
/// "pin a guide" would drift.
public enum CanvasGuides {

    /// Two guides closer together than this are the same guide. A hair over a
    /// tenth of a point: close enough that no click can land between them, far
    /// enough that a guide at 16 and one at 16.5 are still two.
    public static let sameLine: CGFloat = 0.125

    /// Pins a line, and hands back which guide is now under the pointer.
    ///
    /// Clicking a line that already carries a guide does NOT stack a second one
    /// on top of it; it picks up the one that is there. Otherwise a person who
    /// clicked twice would delete one guide and still see a guide, which is the
    /// most confusing thing a pinned line could do.
    public static func pinning(_ guides: [CanvasGuide],
                               _ line: CanvasGuideLine) -> (guides: [CanvasGuide], id: UUID) {
        if let existing = guides.first(where: { $0.axis == line.axis
            && abs($0.position - line.position) <= sameLine }) {
            return (guides, existing.id)
        }
        let guide = CanvasGuide(line: line)
        return (guides + [guide], guide.id)
    }

    /// Where this axis's guides sit, in the order they were pinned. What the
    /// snapping path asks for.
    public static func positions(_ guides: [CanvasGuide], axis: CanvasGuideAxis) -> [CGFloat] {
        guides.filter { $0.axis == axis }.map(\.position)
    }

    /// The guide under a point, or nil when the pointer is not on one.
    /// Distance is measured ACROSS the line, so a vertical guide is grabbable
    /// down its whole length. The nearest wins where two cross.
    public static func nearest(_ guides: [CanvasGuide], to point: CGPoint,
                               within tolerance: CGFloat) -> CanvasGuide? {
        guard point.x.isFinite, point.y.isFinite, tolerance.isFinite, tolerance >= 0 else {
            return nil
        }
        var best: (guide: CanvasGuide, distance: CGFloat)?
        for guide in guides {
            let distance = guide.axis == .vertical ? abs(point.x - guide.position)
                                                   : abs(point.y - guide.position)
            guard distance <= tolerance, distance < (best?.distance ?? .infinity) else { continue }
            best = (guide, distance)
        }
        return best?.guide
    }

    /// Everything except one guide, for a delete.
    public static func removing(_ guides: [CanvasGuide], id: UUID) -> [CanvasGuide] {
        guides.filter { $0.id != id }
    }

    /// One guide moved to a new line, keeping its identity so the thing you
    /// picked up is the thing you put down.
    public static func moving(_ guides: [CanvasGuide], id: UUID,
                              to line: CanvasGuideLine) -> [CanvasGuide] {
        guides.map { guide in
            guard guide.id == id else { return guide }
            var moved = guide
            moved.axis = line.axis
            moved.position = line.position.isFinite ? line.position : guide.position
            return moved
        }
    }
}

/// Which grid line the pointer is on, while the grid is being adjusted.
///
/// The rule is the one the task asks for — whichever line is nearest, down or
/// across — with the one thing that rule needs to survive a crossing. At a
/// crossing both lines are the same distance away, so a bare "nearest" flips
/// the highlight between them on every pixel of a hand's tremor. The axis
/// already lit therefore keeps it until the other is CLEARLY nearer, which is
/// the same promise the rest of the canvas makes: a line that is showing is the
/// line you get.
public enum CanvasGuidePick {

    /// How much nearer the other axis has to be before the highlight hands
    /// over, in SCREEN points, so the dead band feels the same at any zoom.
    public static let axisSlackOnScreen: CGFloat = 6

    public static func line(near point: CGPoint, spacing: CGFloat, origin: CGPoint,
                            axes: CanvasGridAxes,
                            holding held: CanvasGuideAxis? = nil,
                            slack: CGFloat = 0) -> CanvasGuideLine? {
        guard spacing.isFinite, spacing > 0, point.x.isFinite, point.y.isFinite,
              origin.x.isFinite, origin.y.isFinite else { return nil }
        let x = origin.x + ((point.x - origin.x) / spacing).rounded() * spacing
        let down = CanvasGuideLine(axis: .vertical, position: x)
        guard axes.drawsRows else { return down }
        let y = origin.y + ((point.y - origin.y) / spacing).rounded() * spacing
        let across = CanvasGuideLine(axis: .horizontal, position: y)

        let downDistance = abs(point.x - x)
        let acrossDistance = abs(point.y - y)
        let slack = slack.isFinite ? max(0, slack) : 0
        switch held {
        case .vertical where downDistance <= acrossDistance + slack: return down
        case .horizontal where acrossDistance <= downDistance + slack: return across
        default: break
        }
        // Ties go down the picture: a column is the line people pin most.
        return downDistance <= acrossDistance ? down : across
    }
}
