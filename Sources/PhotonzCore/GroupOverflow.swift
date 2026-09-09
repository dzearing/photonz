import CoreGraphics
import Foundation

/// A group whose contents run past its own edge, and the one line that says so.
///
/// Give a row a width too small for what is in it and the pieces simply hang
/// out over the edge. If the group also clips, they disappear instead. Neither
/// of those says anything anywhere: the canvas shows a shape somebody has to
/// notice is wrong, and the Layout section, where every fix for it lives, goes
/// on printing nothing. So the section says it once, in the section's own
/// voice, with the number that would hold everything already worked out.
///
/// It is MEASURED, never guessed. The group is flowed exactly the way the
/// canvas flows it and the pieces are held against the box that came out, so
/// the line and the picture cannot drift apart, and a row that wraps goes
/// quiet the moment the wrapping makes everything fit.
public struct GroupOverflow: Hashable, Sendable {
    /// How far the furthest piece reaches past the box's right edge, and zero
    /// where nothing does.
    public let across: CGFloat
    /// The same, past the bottom edge.
    public let down: CGFloat
    /// How wide the box would have to be to hold everything, and nil where its
    /// width was never the problem.
    ///
    /// Not always its Width: where a largest width was what held the box in,
    /// this is the number that largest has to become, because a box that hugs
    /// under a ceiling goes on hugging once the ceiling is raised.
    public let width: CGFloat?
    /// The same, down the page.
    public let height: CGFloat?
    /// Whether ticking Wrap onto more lines fixes it on its own.
    ///
    /// Asked of the wrapped row on BOTH axes, because a row that wraps inside
    /// a height somebody gave it pushes its new lines out of the bottom, and
    /// an offer that only moves the problem to the other edge is worse than no
    /// offer at all.
    public let wrapWouldFit: Bool

    public init(across: CGFloat, down: CGFloat, width: CGFloat?, height: CGFloat?,
                wrapWouldFit: Bool) {
        self.across = across
        self.down = down
        self.width = width
        self.height = height
        self.wrapWouldFit = wrapWouldFit
    }

    /// The one line the Layout section prints.
    ///
    /// Which edge, then what to do about it, and at most two things to do:
    /// wrap the row, or make the box the size that holds everything. Clipping
    /// is a third fix and is deliberately not offered, because it hides the
    /// pieces rather than fitting them, and its switch is already on this
    /// section for anybody who wants it.
    ///
    /// The fix names a NUMBER and never a field. The field that holds a box in
    /// is Width on one group, Largest on the next, and both on a third, so
    /// "make it 320 wide" is the one phrasing that is true of every one of
    /// them and the short one as well.
    public var sentence: String {
        "The pieces run past the \(edges). \(fix)"
    }

    private var edges: String {
        switch (across > 0, down > 0) {
        case (true, true): "right and bottom edges"
        case (false, true): "bottom edge"
        default: "right edge"
        }
    }

    private var fix: String {
        guard let size else { return "Wrap them onto more lines." }
        return wrapWouldFit
            ? "Wrap them onto more lines, or make it \(size)."
            : "Make it \(size)."
    }

    /// The size that would hold everything, in the words the offer is made in:
    /// "320 wide", "40 tall", "320 × 40". Nil where no number is known, which
    /// leaves wrapping as the only thing to say.
    private var size: String? {
        switch (width, height) {
        case let (across?, down?): "\(Self.number(across)) × \(Self.number(down))"
        case let (across?, nil): "\(Self.number(across)) wide"
        case let (nil, down?): "\(Self.number(down)) tall"
        case (nil, nil): nil
        }
    }

    private static func number(_ value: CGFloat) -> String { String(Int(value.rounded())) }
}

extension Layer {

    /// Where this group's contents run past its own edge, or nil where
    /// everything fits and there is nothing to say.
    ///
    /// Only a group that ARRANGES its contents. On a Free group everything is
    /// exactly where somebody put it, so a badge hanging off a corner is a
    /// drawing and not a fault, and the app second-guessing that drawing would
    /// be a line nobody could ever switch off. And not a screen: a screen's box
    /// is a frame somebody drew to build on, with its size two sections up in
    /// Position & Size rather than in Layout, and things overhanging one while
    /// you work is ordinary.
    ///
    /// Nil as well where nothing can be said about the fix. A box held in only
    /// by a smallest size can never be too small for its contents, so there is
    /// no number to move and no line to print.
    ///
    /// The panel reads this on every redraw, so the gate on the front of it is
    /// worth as much as the answer: a group holding no size and no ceiling is
    /// exactly as big as what is inside it and can never run out of room, so it
    /// is turned away before anything is flowed at all. Only a box somebody
    /// held in pays for the measuring, and only while it is still too small.
    public var contentsOverflow: GroupOverflow? {
        guard let group, !group.children.isEmpty, !group.isFrame,
              let layout = group.layout, layout.arranges, layout.hasSizeOfItsOwn
        else { return nil }
        let flowed = GroupFlow.flowing(self)
        let past = Self.pieces(past: flowed)
        guard past.across > 0 || past.down > 0 else { return nil }
        var grown = layout
        // Across first, because how wide the box is decides where the words
        // inside it break, and where they break decides how tall it comes out.
        // The size it is at now is the flow that has just been made, handed on
        // rather than measured a second time.
        let width = past.across > 0
            ? grownSide(&grown, horizontal: true, held: flowed.localBounds.size) : nil
        let height = past.down > 0 ? grownSide(&grown, horizontal: false) : nil
        let wraps = layout.couldWrap && !layout.wraps && fitsWrapped(layout)
        guard width != nil || height != nil || wraps else { return nil }
        return GroupOverflow(across: past.across, down: past.down,
                             width: width, height: height, wrapWouldFit: wraps)
    }

    /// How far the furthest piece in an ALREADY FLOWED group reaches past the
    /// box that flow came out with, one axis at a time.
    ///
    /// The box is the group's own box seen from one level in, which is the
    /// space its children's boxes are stored in — the same shift
    /// `OutOfView.scopes(inside:)` makes for the same reason.
    ///
    /// Half a point of slack, because a piece landing a hairline past an edge
    /// is float arithmetic rather than something anybody can see, and a panel
    /// that nags about a hairline is a panel people learn to ignore.
    private static func pieces(past flowed: Layer) -> (across: CGFloat, down: CGFloat) {
        let origin = flowed.frame.origin
        let box = flowed.localBounds.standardized.offsetBy(dx: -origin.x, dy: -origin.y)
        var across: CGFloat = 0
        var down: CGFloat = 0
        for child in flowed.children {
            let piece = child.localBounds.standardized
            across = max(across, piece.maxX - box.maxX)
            down = max(down, piece.maxY - box.maxY)
        }
        let slack: CGFloat = 0.5
        return (across > slack ? across : 0, down > slack ? down : 0)
    }

    /// Grows one side of `layout` to the size its contents need and says what
    /// that size is, or nil where that side was never what held them in.
    ///
    /// The number moves wherever the box was being held: a given size is
    /// rewritten, and a ceiling holding the box in is raised so the box can go
    /// on being the size of its contents. A floor is left alone, since one only
    /// ever makes the box bigger. The same walk `ContainerFit` makes for the
    /// row in the layers list, so the panel and that row can never name two
    /// different numbers for the same box.
    private func grownSide(_ layout: inout GroupLayout, horizontal: Bool,
                           held knownHeld: CGSize? = nil) -> CGFloat? {
        let side = horizontal ? layout.usedWidth : layout.usedHeight
        let ceiling = horizontal ? layout.usedMaxWidth : layout.usedMaxHeight
        guard side != nil || ceiling != nil else { return nil }
        var free = layout
        if horizontal {
            free.width = nil
            free.maxWidth = nil
        } else {
            free.height = nil
            free.maxHeight = nil
        }
        let natural = flowedSize(with: free)
        let held = knownHeld ?? flowedSize(with: layout)
        // Whole points, rounded up: the inspector types in whole points, and
        // rounding down by a fraction names a number that still cuts off a
        // hairline of what it was meant to hold.
        let fit = (horizontal ? natural.width : natural.height).rounded(.up)
        guard fit > (horizontal ? held.width : held.height) else { return nil }
        if horizontal {
            if layout.usedWidth != nil { layout.width = fit }
            if let ceiling, ceiling < fit { layout.maxWidth = fit }
        } else {
            if layout.usedHeight != nil { layout.height = fit }
            if let ceiling, ceiling < fit { layout.maxHeight = fit }
        }
        return fit
    }

    /// Whether the same row with its wrapping switched on holds everything, on
    /// both axes. The offer in the words is this answer, so it can never
    /// promise a fix that only sends the pieces out of a different edge.
    private func fitsWrapped(_ layout: GroupLayout) -> Bool {
        var wrapped = layout
        wrapped.wraps = true
        var probe = self
        probe.setGroupLayout(wrapped)
        let past = Self.pieces(past: GroupFlow.flowing(probe))
        return past.across == 0 && past.down == 0
    }

    /// How big this group comes out with a layout it does not have, everything
    /// inside it flowed for that layout: the same sum the canvas does, on a
    /// copy nobody can see.
    private func flowedSize(with layout: GroupLayout) -> CGSize {
        var probe = self
        probe.setGroupLayout(layout)
        return GroupFlow.flowing(probe).localBounds.size
    }
}
