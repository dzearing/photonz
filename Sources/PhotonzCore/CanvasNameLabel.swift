import CoreGraphics
import Foundation

/// One name as it sits on the canvas above the box it belongs to: which layer
/// it names, the box that layer draws in (view space, top-left origin), how
/// wide the name itself measured out, and how far in from the box's left edge
/// the letters start.
///
/// The width matters because the label BOX is generous — up to 240 points, so a
/// long name has room — while the name inside it may be four letters. Only the
/// name answers a click; the empty space beside it is still bare canvas.
///
/// The inset matters because a component's name is drawn behind its four-diamond
/// mark, so its letters start a little further right than a screen's do. The
/// mark rides along with the name as one chip, and the chip is the handle either
/// way.
public struct CanvasNameLabel: Hashable, Sendable, Identifiable {
    public let id: UUID
    /// Where the layer draws, in view points.
    public let frameRect: CGRect
    /// How wide the name draws, in view points.
    public let textWidth: CGFloat
    /// How far right of the box's left edge the letters begin, leaving room for
    /// a mark drawn in front of them. Zero for a plain screen name.
    public let leadingInset: CGFloat

    public init(id: UUID, frameRect: CGRect, textWidth: CGFloat, leadingInset: CGFloat = 0) {
        self.id = id
        self.frameRect = frameRect
        self.textWidth = textWidth
        self.leadingInset = leadingInset
    }
}

/// Where a name draws above its box on the canvas, and what a click on it means.
///
/// The name hangs above a box's top left corner and is the same size at every
/// zoom, so all of this is view-space geometry rather than document geometry.
/// It lives here, away from AppKit, because the interesting part is a rule
/// rather than a drawing call: **the name is the target, the box it draws in
/// is not.**
/// A screen called "Home" prints thirty points of text in a box that may be two
/// hundred wide, and a click on the empty part of that box has to keep meaning
/// what it always meant on bare canvas.
///
/// One set of rules covers a screen's name and a component's name, because on
/// the canvas they are the same thing wearing different paint: click to pick
/// the box, double click to rename it where it sits.
public enum CanvasNameLabels {

    /// The distance from a box's top edge up to the strip its name sits in.
    /// Close enough to belong to the box, clear enough not to touch it.
    public static let gap: CGFloat = 4
    /// The height of that strip.
    public static let height: CGFloat = 14
    /// The widest a name box gets, however long the name is.
    public static let maximumWidth: CGFloat = 240
    /// The narrowest, so a small box's name still has somewhere to print.
    public static let minimumWidth: CGFloat = 40
    /// The narrowest a name's clickable area gets, so a screen called "A" is
    /// still something a person can hit.
    public static let minimumHitWidth: CGFloat = 24
    /// How far past the letters a click still counts, to the sides and above.
    public static let slop: CGFloat = 3

    /// Where the name draws for a box drawn at `frameRect`, with `leadingInset`
    /// points reserved at the left for a mark in front of the letters.
    public static func box(forFrameRect frameRect: CGRect, leadingInset: CGFloat = 0) -> CGRect {
        let strip = CGRect(x: frameRect.minX,
                           y: frameRect.minY - height - gap,
                           width: max(min(frameRect.width, maximumWidth), minimumWidth),
                           height: height)
        guard leadingInset > 0 else { return strip }
        // The mark eats into the strip rather than pushing the name past the
        // box's right edge, but a narrow box still keeps somewhere to print.
        return CGRect(x: strip.minX + leadingInset,
                      y: strip.minY,
                      width: max(strip.width - leadingInset, minimumWidth),
                      height: strip.height)
    }

    /// Where the name draws for `label`.
    public static func box(for label: CanvasNameLabel) -> CGRect {
        box(forFrameRect: label.frameRect, leadingInset: label.leadingInset)
    }

    /// The area a click on that name lands in: the letters plus a little slop,
    /// never wider than the box that drew them (past its right edge the name is
    /// truncated, so there is nothing there to click), and never reaching down
    /// onto the box's own top edge, which belongs to the box.
    ///
    /// A mark in front of the letters is part of the target, not a hole in it.
    /// The mark and the name read as one small chip, and a click that lands on
    /// the chip and does nothing is the kind of miss nobody forgives.
    public static func hitBox(forFrameRect frameRect: CGRect, textWidth: CGFloat,
                             leadingInset: CGFloat = 0) -> CGRect {
        let box = box(forFrameRect: frameRect, leadingInset: leadingInset)
        let letters = min(max(textWidth, minimumHitWidth), box.width)
        return CGRect(x: box.minX - slop - leadingInset,
                      y: box.minY - slop,
                      width: letters + slop * 2 + leadingInset,
                      // The bottom stops one point short of the box, so the
                      // gap never swallows a click meant for the picture.
                      height: box.height + slop + (gap - 1))
    }

    /// The area a click on `label` lands in.
    public static func hitBox(for label: CanvasNameLabel) -> CGRect {
        hitBox(forFrameRect: label.frameRect, textWidth: label.textWidth,
               leadingInset: label.leadingInset)
    }

    // MARK: Two names that want the same spot

    /// The daylight left between one name and the one it climbed over.
    public static let verticalGap: CGFloat = 2
    /// The distance from one name's line up to the line above it, when both
    /// started on the same line.
    public static let rowStep: CGFloat = height + verticalGap
    /// How much daylight two names need beside each other before they read as
    /// two names rather than one smear.
    public static let clearance: CGFloat = 6
    /// The most lines a name will climb before it gives up and prints where it
    /// is. A name far enough above its box to belong to nothing is no better
    /// than a name on top of another name.
    public static let maximumRows = 6
    /// The furthest a name ever gets from its own box.
    public static var maximumLift: CGFloat { rowStep * CGFloat(maximumRows) }

    /// The ink a name actually puts down: its mark, then its letters. Wider
    /// than nothing and narrower than the generous box it draws in, which is
    /// the whole point — two boxes overlapping is normal, two names overlapping
    /// is a bug.
    public static func chipBox(for label: CanvasNameLabel) -> CGRect {
        let strip = box(forFrameRect: label.frameRect)
        let printed = box(for: label)
        let letters = min(label.textWidth, printed.width)
        return CGRect(x: strip.minX, y: strip.minY,
                      width: label.leadingInset + letters, height: strip.height)
    }

    /// The same names, moved up onto clear lines where they would otherwise
    /// have printed on top of each other.
    ///
    /// A button sitting in a screen's top left corner puts its name in exactly
    /// the strip the screen's name uses, and two names in one strip is two
    /// names nobody can read. So a name that lands on one already taken climbs
    /// a line, and keeps climbing until it is clear.
    ///
    /// `labels` comes in drawing order, back to front, so **the name that was
    /// there first keeps its place and the one on top of it moves.** On a
    /// screen with a component in its corner that means the screen's name stays
    /// against its own edge and the component's name sits above it, which reads
    /// as outside-in: the further from the box, the deeper inside it you are.
    ///
    /// A name only ever climbs. Sliding it sideways would take it away from the
    /// corner it names, and the corner is the only thing tying a name to its
    /// box.
    ///
    /// The result is ordinary labels with their boxes moved: every other rule
    /// here, drawing and clicking alike, applies to them unchanged.
    public static func stacked(_ labels: [CanvasNameLabel]) -> [CanvasNameLabel] {
        var taken: [CGRect] = []
        var result: [CanvasNameLabel] = []
        result.reserveCapacity(labels.count)
        for label in labels {
            let chip = chipBox(for: label)
            var lift: CGFloat = 0
            var climbing = true
            var passes = 0
            // Just far enough to clear what is in the way, rather than a fixed
            // step: two boxes whose tops are a few points apart would otherwise
            // need two steps to separate and end up twice as far from their
            // corner as they need to be. Clearing one name can land on the
            // next, so this goes round until the spot is empty.
            while climbing, passes <= taken.count {
                climbing = false
                passes += 1
                let here = chip.offsetBy(dx: 0, dy: -lift).insetBy(dx: -clearance, dy: 0)
                guard let blocking = taken.first(where: { $0.intersects(here) }) else { break }
                lift = min(lift + (here.maxY - blocking.minY) + verticalGap, maximumLift)
                climbing = true
            }
            taken.append(chip.offsetBy(dx: 0, dy: -lift))
            guard lift > 0 else {
                result.append(label)
                continue
            }
            result.append(CanvasNameLabel(id: label.id,
                                          frameRect: label.frameRect.offsetBy(dx: 0, dy: -lift),
                                          textWidth: label.textWidth,
                                          leadingInset: label.leadingInset))
        }
        return result
    }

    /// The layer whose name is under `point`, or nil for anywhere else.
    ///
    /// `labels` comes in drawing order, back to front, so where two names
    /// overlap — which happens as soon as you zoom out far enough for two
    /// screens to sit close together — the one you can actually read wins.
    public static func hit(at point: CGPoint, labels: [CanvasNameLabel]) -> UUID? {
        for label in labels.reversed() where hitBox(for: label).contains(point) {
            return label.id
        }
        return nil
    }
}
