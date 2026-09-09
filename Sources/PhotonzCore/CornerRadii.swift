import CoreGraphics
import Foundation

/// How round each of a box's four corners is.
///
/// One number is the common case and stays one number: pull Corner Radius to 16
/// and every corner gets 16. Plenty of real UI is not that though — a card with
/// a rounded top and a square bottom sitting on the edge of a sheet, the two
/// ends of a segmented control, a speech bubble — and all of it used to be
/// faked by laying a second shape over the first. So each corner is its own
/// number underneath, and opening the one number into four is a deliberate act.
///
/// It SAVES as a single number for as long as all four agree, which is exactly
/// what every document written before there were four corners holds. Those
/// documents open with the rounding they had and save again unchanged. This is
/// the same bargain `GroupPadding` makes with a group's four sides, on purpose:
/// one idiom for "one number that opens into four", not two.
public struct CornerRadii: Hashable, Codable, Sendable {
    public var topLeft: CGFloat
    public var topRight: CGFloat
    public var bottomRight: CGFloat
    public var bottomLeft: CGFloat

    /// Square on every corner: what a shape has until somebody rounds it, and
    /// what every document written before this existed comes back as.
    public static let none = CornerRadii(0)

    public init(topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    /// The same rounding on all four corners.
    public init(_ all: CGFloat) {
        self.init(topLeft: all, topRight: all, bottomRight: all, bottomLeft: all)
    }

    /// Which corner, in the order they are shown and typed: clockwise from the
    /// top left, the order anybody who has written a CSS `border-radius`
    /// already carries.
    public enum Corner: String, CaseIterable, Hashable, Sendable {
        case topLeft, topRight, bottomRight, bottomLeft

        /// What the inspector calls it.
        public var title: String {
            switch self {
            case .topLeft: "Top Left"
            case .topRight: "Top Right"
            case .bottomRight: "Bottom Right"
            case .bottomLeft: "Bottom Left"
            }
        }

        /// The same words in a sentence: "the top left corner".
        public var spoken: String { title.lowercased() }
    }

    public subscript(corner: Corner) -> CGFloat {
        get {
            switch corner {
            case .topLeft: topLeft
            case .topRight: topRight
            case .bottomRight: bottomRight
            case .bottomLeft: bottomLeft
            }
        }
        set {
            switch corner {
            case .topLeft: topLeft = newValue
            case .topRight: topRight = newValue
            case .bottomRight: bottomRight = newValue
            case .bottomLeft: bottomLeft = newValue
            }
        }
    }

    /// The one number all four corners are, or nil where they disagree. What
    /// the single Corner Radius readout shows, and what it goes blank for.
    public var uniform: CGFloat? {
        topLeft == topRight && topRight == bottomRight && bottomRight == bottomLeft
            ? topLeft : nil
    }

    public var isUniform: Bool { uniform != nil }

    /// The roundest corner. What the slider's knob sits at while the four
    /// disagree, so its position is a starting point rather than a claim.
    public var largest: CGFloat { Corner.allCases.map { self[$0] }.max() ?? 0 }

    /// Whether anything here rounds anything at all: the one question every
    /// ring, mask and outline asks before doing any extra work.
    public var isRound: Bool { Corner.allCases.contains { self[$0] > 0 } }

    /// The rounding actually kept. Rounding by a negative amount is not a thing
    /// anyone means, and typing over a field passes through odd values on the
    /// way to a number, so the model holds the floor rather than refusing the
    /// typing.
    public var used: CornerRadii {
        CornerRadii(topLeft: Self.usedCorner(topLeft), topRight: Self.usedCorner(topRight),
                    bottomRight: Self.usedCorner(bottomRight),
                    bottomLeft: Self.usedCorner(bottomLeft))
    }

    private static func usedCorner(_ corner: CGFloat) -> CGFloat {
        corner.isFinite ? max(0, corner) : 0
    }

    /// The four numbers, clockwise from the top left, the way a CSS shorthand
    /// writes them: `16/16/0/0`.
    ///
    /// What the single Corner Radius readout shows when the four corners are
    /// CLOSED and disagree, so a corner typed at the bottom of the opened rows
    /// is still readable once they are shut again.
    public var shorthand: String {
        Corner.allCases.map { "\(Int(self[$0].rounded()))" }.joined(separator: "/")
    }

    /// The same four numbers with their corners named: `16 top left, 16 top
    /// right, 0 bottom right, 0 bottom left`. For anywhere there is room for
    /// words, so nobody has to already carry the clockwise order.
    public var inWords: String {
        Corner.allCases.map { "\(Int(self[$0].rounded())) \($0.spoken)" }
            .joined(separator: ", ")
    }

    // MARK: - Making it fit

    /// The four numbers as they can actually be drawn in a box this size.
    ///
    /// One corner cannot round past half the box, and two corners on the same
    /// edge cannot round past the whole of it: 60 and 60 on a 100 point edge is
    /// not a shape, it is two curves crossing. So when an edge is over-subscribed
    /// every corner is scaled down by the SAME factor, which keeps the shape
    /// somebody drew rather than singling one corner out — the rule a browser
    /// uses for the identical problem.
    ///
    /// When all four agree this is exactly the `min(radius, min(w, h) / 2)` the
    /// renderer always did, so nothing uniform changes.
    public func fitted(in size: CGSize) -> CornerRadii {
        let radii = used
        guard size.width > 0, size.height > 0 else { return .none }
        guard radii.isRound else { return .none }
        var scale: CGFloat = 1
        // Each edge, and the two corners that share it.
        let edges: [(CGFloat, CGFloat)] = [
            (size.width, radii.topLeft + radii.topRight),
            (size.width, radii.bottomLeft + radii.bottomRight),
            (size.height, radii.topLeft + radii.bottomLeft),
            (size.height, radii.topRight + radii.bottomRight)
        ]
        for (length, wanted) in edges where wanted > length {
            scale = min(scale, length / wanted)
        }
        return scale >= 1 ? radii : radii.scaled(by: scale)
    }

    /// Every corner multiplied, for restating the same rounding in another
    /// unit: document points into output pixels, or a document magnified.
    public func scaled(by factor: CGFloat) -> CornerRadii {
        CornerRadii(topLeft: topLeft * factor, topRight: topRight * factor,
                    bottomRight: bottomRight * factor, bottomLeft: bottomLeft * factor)
    }

    /// Every ROUNDED corner grown by the same amount, for a ring pushed out
    /// past the box it hugs.
    ///
    /// A square corner stays square however far the ring is pushed: growing a
    /// rounded rect by d grows its radius by d, which is right for a corner
    /// that IS round and wrong for one that is not — it turned an 11pt ring
    /// round a sharp button into a lozenge (found on the probe, 2026-09-07).
    public func grown(by amount: CGFloat) -> CornerRadii {
        var grown = self
        for corner in Corner.allCases where grown[corner] > 0 {
            grown[corner] = max(0, grown[corner] + amount)
        }
        return grown
    }

    /// The same corners seen in a space whose Y runs the other way, for the
    /// compositor: what the document calls the top is the bottom of a Core
    /// Image extent.
    public var flippedVertically: CornerRadii {
        CornerRadii(topLeft: bottomLeft, topRight: bottomRight,
                    bottomRight: topRight, bottomLeft: topLeft)
    }

    // MARK: - The path everything round the box follows

    /// The outline of `box` with these four corners, in whatever space `box` is
    /// stated in: `topLeft` is the corner at the box's smallest X and smallest
    /// Y. In a flipped space, hand in `flippedVertically`.
    ///
    /// One path builder, so the shape's own fill and stroke, the mask cut out of
    /// a picture, every ring round a box and the outline round a picked layer
    /// all curve by exactly the same line.
    public func path(in box: CGRect, transform: CGAffineTransform = .identity) -> CGPath {
        var transform = transform
        let radii = fitted(in: box.size)
        guard radii.isRound else { return CGPath(rect: box, transform: &transform) }
        if let uniform = radii.uniform {
            return CGPath(roundedRect: box, cornerWidth: uniform, cornerHeight: uniform,
                          transform: &transform)
        }
        let path = CGMutablePath()
        // Clockwise from just past the top left corner, in a space where Y
        // grows downwards, which is how the document states everything.
        path.move(to: CGPoint(x: box.minX + radii.topLeft, y: box.minY), transform: transform)
        path.addLine(to: CGPoint(x: box.maxX - radii.topRight, y: box.minY), transform: transform)
        Self.addCorner(to: path, at: CGPoint(x: box.maxX, y: box.minY),
                       toward: CGPoint(x: box.maxX, y: box.maxY),
                       radius: radii.topRight, transform: transform)
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - radii.bottomRight),
                     transform: transform)
        Self.addCorner(to: path, at: CGPoint(x: box.maxX, y: box.maxY),
                       toward: CGPoint(x: box.minX, y: box.maxY),
                       radius: radii.bottomRight, transform: transform)
        path.addLine(to: CGPoint(x: box.minX + radii.bottomLeft, y: box.maxY),
                     transform: transform)
        Self.addCorner(to: path, at: CGPoint(x: box.minX, y: box.maxY),
                       toward: CGPoint(x: box.minX, y: box.minY),
                       radius: radii.bottomLeft, transform: transform)
        path.addLine(to: CGPoint(x: box.minX, y: box.minY + radii.topLeft), transform: transform)
        Self.addCorner(to: path, at: CGPoint(x: box.minX, y: box.minY),
                       toward: CGPoint(x: box.maxX, y: box.minY),
                       radius: radii.topLeft, transform: transform)
        path.closeSubpath()
        return path
    }

    /// One corner: the arc that turns the line coming into `point` into the
    /// line leaving it towards `next`. A radius of nought is the sharp corner
    /// itself, which is a straight line to it and nothing else.
    private static func addCorner(to path: CGMutablePath, at point: CGPoint,
                                  toward next: CGPoint, radius: CGFloat,
                                  transform: CGAffineTransform) {
        if radius <= 0 {
            path.addLine(to: point, transform: transform)
        } else {
            path.addArc(tangent1End: point, tangent2End: next, radius: radius,
                        transform: transform)
        }
    }

    // MARK: - On disk

    private enum CodingKeys: String, CodingKey { case topLeft, topRight, bottomRight, bottomLeft }

    /// Read either shape: the single number every older document holds, or the
    /// four corners a card with a rounded top needs.
    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(CGFloat.self) {
            self.init(single)
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(topLeft: try c.decodeIfPresent(CGFloat.self, forKey: .topLeft) ?? 0,
                      topRight: try c.decodeIfPresent(CGFloat.self, forKey: .topRight) ?? 0,
                      bottomRight: try c.decodeIfPresent(CGFloat.self, forKey: .bottomRight) ?? 0,
                      bottomLeft: try c.decodeIfPresent(CGFloat.self, forKey: .bottomLeft) ?? 0)
        }
    }

    /// Written as one number while the corners agree, so a document that never
    /// asked for an uneven corner is byte for byte the file it always was.
    public func encode(to encoder: Encoder) throws {
        if let uniform {
            var c = encoder.singleValueContainer()
            try c.encode(uniform)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(topLeft, forKey: .topLeft)
        try c.encode(topRight, forKey: .topRight)
        try c.encode(bottomRight, forKey: .bottomRight)
        try c.encode(bottomLeft, forKey: .bottomLeft)
    }
}

/// One number where four are wanted: `cornerRadii: 16` still means 16 all
/// round, so nothing that only ever wanted even corners has to say so four
/// times.
extension CornerRadii: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    public init(integerLiteral value: Int) { self.init(CGFloat(value)) }
    public init(floatLiteral value: Double) { self.init(CGFloat(value)) }
}
