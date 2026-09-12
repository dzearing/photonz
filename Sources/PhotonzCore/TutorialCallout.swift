import CoreGraphics
import Foundation

// Where a tutorial callout goes. Pure geometry, so the rule that matters can be
// tested rather than eyeballed: UX-PATTERNS D14, a callout never covers what it
// is talking about. The alignment chip that drew itself on top of the very
// label it was accusing is the reason that rule is written down, and a
// walkthrough that covers the button it is telling you to press is the same
// mistake with worse timing.
//
// Everything here is in a TOP LEFT ORIGIN space, y growing downward, like the
// document model. Screen rectangles come from AppKit bottom up, so the caller
// flips them once on the way in and once on the way out (`TutorialGeometry.flip`,
// which is its own inverse).

/// Where a callout ended up, and where its pointer goes.
public struct TutorialCalloutPlacement: Hashable, Sendable {
    /// The card, in the same space the anchor and container were given in.
    public let frame: CGRect
    /// Which side of the anchor the card ended up on. Never `automatic`.
    public let side: TutorialSide
    /// How far along the card's pointing edge the beak's tip sits, measured
    /// from the card's leading edge for a card above or below, and from its top
    /// edge for one beside. Nil when the anchor is not within the card's span
    /// at all, in which case there is nothing honest for a beak to point at and
    /// the card is drawn without one.
    public let beakOffset: CGFloat?

    public init(frame: CGRect, side: TutorialSide, beakOffset: CGFloat?) {
        self.frame = frame
        self.side = side
        self.beakOffset = beakOffset
    }
}

public enum TutorialCalloutLayout {
    /// Clear space between the anchor and the card, the beak included. Wide
    /// enough to clear the ring the cue draws round the control as well as the
    /// control itself, or the beak lands on top of the ring.
    public static let gap: CGFloat = 24
    /// Closest the card comes to the edge of the window.
    public static let edge: CGFloat = 12
    /// How close the beak may get to a corner of the card.
    public static let beakInset: CGFloat = 22

    /// Places a callout of `size` against `anchor` inside `container`.
    ///
    /// The order it tries: the side the step asked for first, then the rest in
    /// the order a person's eye goes. A side is taken when the card fits inside
    /// the container there AND lands clear of the anchor. If no side does, the
    /// side with the most room wins and the card is pushed fully off the
    /// anchor, because covering the control is the one outcome that is never
    /// allowed.
    public static func place(anchor: CGRect, size: CGSize, container: CGRect,
                             preferred: TutorialSide = .automatic,
                             gap: CGFloat = gap,
                             edge: CGFloat = edge) -> TutorialCalloutPlacement {
        let order = sideOrder(preferred: preferred, anchor: anchor, container: container)
        for side in order {
            let rect = clamped(candidate(anchor: anchor, size: size, side: side, gap: gap),
                               in: container, edge: edge)
            guard fits(rect, in: container, edge: edge), !rect.intersects(anchor) else { continue }
            return TutorialCalloutPlacement(frame: rect, side: side,
                                            beakOffset: beak(for: rect, anchor: anchor, side: side))
        }
        // Nothing fits cleanly. Take the roomiest side and shove the card off
        // the anchor even if that means hanging past the window's inset: a
        // callout half off the edge is readable, a callout on top of the button
        // it names is not.
        let side = order[0]
        var rect = clamped(candidate(anchor: anchor, size: size, side: side, gap: gap),
                           in: container, edge: edge)
        rect = pushedClear(rect, of: anchor, side: side, gap: gap)
        return TutorialCalloutPlacement(frame: rect, side: side,
                                        beakOffset: beak(for: rect, anchor: anchor, side: side))
    }

    // MARK: - Pieces

    /// How much room there is on one side of the anchor.
    public static func room(_ side: TutorialSide, anchor: CGRect, container: CGRect) -> CGFloat {
        switch side {
        case .above: max(0, anchor.minY - container.minY)
        case .below: max(0, container.maxY - anchor.maxY)
        case .leading: max(0, anchor.minX - container.minX)
        case .trailing: max(0, container.maxX - anchor.maxX)
        case .automatic: 0
        }
    }

    private static func sideOrder(preferred: TutorialSide, anchor: CGRect,
                                  container: CGRect) -> [TutorialSide] {
        let real: [TutorialSide] = [.above, .below, .leading, .trailing]
        // Roomiest first, and stable when two sides tie so the callout does not
        // flip sides on a one pixel resize.
        let byRoom = real.sorted { a, b in
            let ra = room(a, anchor: anchor, container: container)
            let rb = room(b, anchor: anchor, container: container)
            if ra == rb { return (real.firstIndex(of: a) ?? 0) < (real.firstIndex(of: b) ?? 0) }
            return ra > rb
        }
        guard preferred != .automatic else { return byRoom }
        return [preferred] + byRoom.filter { $0 != preferred }
    }

    private static func candidate(anchor: CGRect, size: CGSize, side: TutorialSide,
                                  gap: CGFloat) -> CGRect {
        switch side {
        case .above:
            CGRect(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height,
                   width: size.width, height: size.height)
        case .below:
            CGRect(x: anchor.midX - size.width / 2, y: anchor.maxY + gap,
                   width: size.width, height: size.height)
        case .leading:
            CGRect(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2,
                   width: size.width, height: size.height)
        case .trailing, .automatic:
            CGRect(x: anchor.maxX + gap, y: anchor.midY - size.height / 2,
                   width: size.width, height: size.height)
        }
    }

    private static func clamped(_ rect: CGRect, in container: CGRect, edge: CGFloat) -> CGRect {
        var rect = rect
        let minX = container.minX + edge
        let maxX = container.maxX - edge - rect.width
        let minY = container.minY + edge
        let maxY = container.maxY - edge - rect.height
        if maxX >= minX { rect.origin.x = min(max(rect.origin.x, minX), maxX) }
        if maxY >= minY { rect.origin.y = min(max(rect.origin.y, minY), maxY) }
        return rect
    }

    private static func fits(_ rect: CGRect, in container: CGRect, edge: CGFloat) -> Bool {
        rect.minX >= container.minX + edge - 0.5
            && rect.maxX <= container.maxX - edge + 0.5
            && rect.minY >= container.minY + edge - 0.5
            && rect.maxY <= container.maxY - edge + 0.5
    }

    /// Last resort: move the card entirely off the anchor along the side's own
    /// axis, whatever that costs at the window's edge.
    private static func pushedClear(_ rect: CGRect, of anchor: CGRect, side: TutorialSide,
                                    gap: CGFloat) -> CGRect {
        guard rect.intersects(anchor) else { return rect }
        var rect = rect
        switch side {
        case .above: rect.origin.y = anchor.minY - gap - rect.height
        case .below, .automatic: rect.origin.y = anchor.maxY + gap
        case .leading: rect.origin.x = anchor.minX - gap - rect.width
        case .trailing: rect.origin.x = anchor.maxX + gap
        }
        return rect
    }

    /// Where the beak's tip sits along the card's pointing edge, or nil when
    /// the anchor's middle is not under the card at all.
    private static func beak(for rect: CGRect, anchor: CGRect, side: TutorialSide) -> CGFloat? {
        switch side {
        case .above, .below:
            let target = anchor.midX
            guard target >= rect.minX, target <= rect.maxX else { return nil }
            let low = min(beakInset, rect.width / 2)
            return min(max(target - rect.minX, low), rect.width - low)
        case .leading, .trailing, .automatic:
            let target = anchor.midY
            guard target >= rect.minY, target <= rect.maxY else { return nil }
            let low = min(beakInset, rect.height / 2)
            return min(max(target - rect.minY, low), rect.height - low)
        }
    }
}

/// The one flip between AppKit's bottom up screen space and the top left space
/// the placement math is written in. Its own inverse, so the same call goes
/// both ways and there is no second formula to get wrong.
public enum TutorialGeometry {
    public static func flip(_ rect: CGRect, in container: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: container.minY + container.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }
}
