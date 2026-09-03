import CoreGraphics
import Foundation

/// Which edge or middle a selection lines up on.
public enum LayerAlignment: String, CaseIterable, Hashable, Sendable {
    case left
    case horizontalCenter
    case right
    case top
    case verticalCenter
    case bottom

    /// The command's name, in the menu and on the button's hover tip.
    public var title: String {
        switch self {
        case .left: "Align Left"
        case .horizontalCenter: "Align Center"
        case .right: "Align Right"
        case .top: "Align Top"
        case .verticalCenter: "Align Middle"
        case .bottom: "Align Bottom"
        }
    }

    /// The same command inside an Align submenu, where the word "Align" is
    /// already overhead and repeating it in every row reads as noise.
    public var menuTitle: String {
        switch self {
        case .left: "Left"
        case .horizontalCenter: "Center"
        case .right: "Right"
        case .top: "Top"
        case .verticalCenter: "Middle"
        case .bottom: "Bottom"
        }
    }

    /// Whether this one moves layers sideways (rather than up and down).
    public var isHorizontal: Bool {
        self == .left || self == .horizontalCenter || self == .right
    }
}

/// Which way a selection gets spaced out evenly.
public enum LayerDistribution: String, CaseIterable, Hashable, Sendable {
    case horizontal
    case vertical

    public var title: String {
        switch self {
        case .horizontal: "Space Evenly Across"
        case .vertical: "Space Evenly Down"
        }
    }
}

/// Lining a selection up with itself: the maths behind Align and Space Evenly.
///
/// Everything is expressed as boxes in canvas points and comes back as new top
/// left corners, so a group, a frame and a plain rectangle are all just boxes
/// and none of them needs a special case here.
///
/// Two rules decide what these commands mean, and both are chosen so nobody has
/// to be told them:
///
/// - **Align lines the selection up with itself.** The reference is the box the
///   whole selection occupies, so Align Left means "every left edge on the
///   leftmost one" and the layer already there does not move. One layer alone
///   has nothing to line up with, so the commands are unavailable rather than
///   quietly aligning it to the picture.
/// - **Unless something holds it.** Hand these commands a container box and it
///   becomes the reference instead, which is how ONE layer can be lined up:
///   a label inside a card has the card to answer to. Centring against a
///   container is the same sum the persistent centre rule makes
///   (`LayerScaling.span`), down to the half point, so centring a label and
///   then dragging the card wider leaves it exactly where it was put.
/// - **Space evenly means equal GAPS, not equal centres.** The outermost two
///   hold still and everything between them slides so the space between
///   neighbours is the same all the way along. When boxes differ in width,
///   spacing their centres evenly leaves gaps you can see are uneven, and the
///   gap is the thing your eye is actually judging.
///
/// Only layers that actually move come back, so a command that changes nothing
/// costs no undo step.
public enum LayerArrangement {
    /// One layer as this file sees it: an id and the box it occupies on canvas.
    public struct Box: Equatable, Sendable {
        public var id: UUID
        public var frame: CGRect

        public init(id: UUID, frame: CGRect) {
            self.id = id
            self.frame = frame
        }
    }

    /// Whether Align would do anything with this many layers selected.
    /// With a container to answer to, one layer is enough; without one, a
    /// layer has only itself and the command means nothing.
    public static func canAlign(count: Int, hasContainer: Bool = false) -> Bool {
        count >= (hasContainer ? 1 : 2)
    }

    /// Whether Space Evenly would: with two, "evenly" has no meaning, since
    /// there is only one gap.
    public static func canDistribute(count: Int) -> Bool { count >= 3 }

    /// Where each layer's top left corner should land to line the selection up.
    /// Layers already in place are left out.
    ///
    /// `container` is the box everything answers to, when there is one: the
    /// frame a layer sits inside. With nothing there the selection answers to
    /// itself, which is what two or more layers picked on the canvas mean.
    public static func aligned(_ boxes: [Box], to alignment: LayerAlignment,
                               within container: CGRect? = nil) -> [UUID: CGPoint] {
        guard canAlign(count: boxes.count, hasContainer: container != nil),
              let bounds = container ?? bounds(of: boxes) else { return [:] }
        var moves: [UUID: CGPoint] = [:]
        for box in boxes {
            let origin: CGPoint
            switch alignment {
            case .left:
                origin = CGPoint(x: bounds.minX, y: box.frame.minY)
            case .horizontalCenter:
                origin = CGPoint(x: bounds.midX - box.frame.width / 2, y: box.frame.minY)
            case .right:
                origin = CGPoint(x: bounds.maxX - box.frame.width, y: box.frame.minY)
            case .top:
                origin = CGPoint(x: box.frame.minX, y: bounds.minY)
            case .verticalCenter:
                origin = CGPoint(x: box.frame.minX, y: bounds.midY - box.frame.height / 2)
            case .bottom:
                origin = CGPoint(x: box.frame.minX, y: bounds.maxY - box.frame.height)
            }
            if origin != box.frame.origin { moves[box.id] = origin }
        }
        return moves
    }

    /// Where each layer's top left corner should land so the gaps between
    /// neighbours are equal. The two on the ends stay exactly where they are,
    /// which is what makes the command safe to press: it tidies the inside of a
    /// row without moving the row.
    ///
    /// Results land on whole points. A span that does not divide cleanly leaves
    /// one gap a point wider than another, which is invisible; half-point
    /// positions are not, and they are what typed geometry exists to avoid.
    public static func distributed(_ boxes: [Box], along axis: LayerDistribution) -> [UUID: CGPoint] {
        guard canDistribute(count: boxes.count) else { return [:] }
        let horizontal = axis == .horizontal
        // Sorted the way they read on screen, not the order they were picked
        // in: shift-clicking a row backwards must give the same answer.
        let ordered = boxes.enumerated().sorted { lhs, rhs in
            let a = horizontal ? lhs.element.frame.minX : lhs.element.frame.minY
            let b = horizontal ? rhs.element.frame.minX : rhs.element.frame.minY
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)

        let sides = ordered.map { horizontal ? $0.frame.width : $0.frame.height }
        let start = horizontal ? (ordered.first?.frame.minX ?? 0) : (ordered.first?.frame.minY ?? 0)
        let end = horizontal ? (ordered.last?.frame.maxX ?? 0) : (ordered.last?.frame.maxY ?? 0)
        let gap = (end - start - sides.reduce(0, +)) / CGFloat(ordered.count - 1)

        var moves: [UUID: CGPoint] = [:]
        var cursor = start
        for (index, box) in ordered.enumerated() {
            // The ends are held exactly, so rounding can never nudge the row's
            // outer edges off where the person put them.
            let value = index == 0 ? start
                : (index == ordered.count - 1 ? end - sides[index] : cursor.rounded())
            let origin = horizontal
                ? CGPoint(x: value, y: box.frame.minY)
                : CGPoint(x: box.frame.minX, y: value)
            if origin != box.frame.origin { moves[box.id] = origin }
            cursor = value + sides[index] + gap
        }
        return moves
    }

    /// The box the whole selection occupies.
    public static func bounds(of boxes: [Box]) -> CGRect? {
        guard var union = boxes.first?.frame else { return nil }
        for box in boxes.dropFirst() { union = union.union(box.frame) }
        return union
    }
}
