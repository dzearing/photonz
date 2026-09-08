import CoreGraphics
import Foundation

/// A container that is too small for what is inside it, and the size that
/// would hold everything.
///
/// `BringIntoView` is the one move back for a layer that has its own position.
/// Inside a stack or a grid it has none: the container works one out on every
/// pass, so sliding the layer back would only shuffle the running order and
/// push a different layer out the same edge. What is wrong there is the
/// container's own size, and this is that number — the one the container would
/// have if it were as big as its contents.
///
/// `change` is the words the offer is made in, because the number has to be on
/// screen BEFORE it is pressed: growing a card undoes a height somebody typed
/// on purpose, and a press that quietly rewrites a typed number is a press
/// nobody would trust twice.
public struct ContainerFit: Hashable, Sendable {
    /// The container that would grow.
    public let container: UUID
    /// Its name, the way its own row is named.
    public let name: String
    /// How wide it would be able to reach, or nil where it is already wide
    /// enough. Not always its Width: where a ceiling is what held the box in,
    /// the ceiling is the number that moves and the box goes on being the size
    /// of its contents.
    public let width: CGFloat?
    /// The same, down the page.
    public let height: CGFloat?
    /// The whole layout as it would be, worked out once here so taking the
    /// offer does not measure everything a second time.
    public let fitted: GroupLayout

    public init(container: UUID, name: String, width: CGFloat?, height: CGFloat?,
                fitted: GroupLayout) {
        self.container = container
        self.name = name
        self.width = width
        self.height = height
        self.fitted = fitted
    }

    /// What taking the offer would do, in the words the row says it in:
    /// "taller (120)". Named so it can be dropped into a sentence about the
    /// container — "make Card taller (120) so everything fits".
    public var change: String {
        switch (width, height) {
        case let (across?, down?): "bigger (\(Self.number(across)) × \(Self.number(down)))"
        case let (across?, nil): "wider (\(Self.number(across)))"
        case let (nil, down?): "taller (\(Self.number(down)))"
        case (nil, nil): "bigger"
        }
    }

    private static func number(_ value: CGFloat) -> String { String(Int(value.rounded())) }
}

extension PhotonzDocument {

    /// The container to grow so this layer is back in view, or nil where that
    /// is not the fix.
    ///
    /// Only where the layer has no move of its own to make: a layer that can
    /// simply slide back over the edge does that instead, because moving one
    /// layer is a smaller change than resizing the box around it. And only
    /// where growing actually works — the whole layout is worked out, flowed
    /// and asked the same question the mark asks, so the offer can never
    /// promise a fix that leaves the layer exactly where it was.
    public func containerFit(bringingIntoView id: UUID) -> ContainerFit? {
        guard let layer = layer(id: id), !canPlace(id) else { return nil }
        let box = layer.localBounds
        guard let cutting = OutOfView.cutting(box, under: clipScopes(around: id)),
              let container = self.layer(id: cutting.id), let group = container.group,
              let layout = group.layout, layout.arranges, layout.hasSizeOfItsOwn,
              // A screen's box is the box somebody drew to build on, not a
              // number the flow worked out, so it is not resized from a row in
              // the layers list. A locked container is locked, and a copy's
              // size belongs to its original.
              !group.isFrame, !container.isLocked, ownsContentRules(id: cutting.id)
        else { return nil }
        guard let fit = fitting(container, layout, keeping: id,
                                went: OutOfView.outside(box, of: cutting.rect)) else { return nil }
        return ContainerFit(container: cutting.id, name: container.name,
                            width: fit.width, height: fit.height, fitted: fit.layout)
    }

    /// Whether this layer's row should offer to grow the container around it.
    public func canMakeRoomForLayer(id: UUID) -> Bool {
        containerFit(bringingIntoView: id) != nil
    }

    /// Grows the container until everything inside it fits. False where there
    /// was nothing to do, so a caller can leave the document, and the undo
    /// stack, untouched.
    ///
    /// One number on one container changes, so one undo puts back exactly the
    /// number that was typed.
    @discardableResult
    public mutating func makeRoomForLayer(id: UUID) -> Bool {
        guard let fit = containerFit(bringingIntoView: id) else { return false }
        updateGroupLayout(id: fit.container) { $0 = fit.fitted }
        return true
    }

    /// The layout this container would have if it were big enough, and which of
    /// its two sides moved. Nil where it already fits, or where growing it
    /// would still leave `wanted` cut off by something further out.
    ///
    /// `went` is which way the layer left, and only those sides grow. A card
    /// whose last row fell out of the bottom is made taller, full stop: its
    /// width is what its words are wrapping to, so freeing that as well would
    /// widen the card to the length of the longest unwrapped line — a change
    /// nobody asked for, on the axis nothing was lost on.
    private func fitting(_ container: Layer, _ layout: GroupLayout, keeping wanted: UUID,
                         went: (horizontal: Bool, vertical: Bool))
        -> (layout: GroupLayout, width: CGFloat?, height: CGFloat?)? {
        var next = layout
        // Across first, because how wide the box is decides where the words
        // inside it break, and where the words break decides how tall it has
        // to be. Down the page second, measured at the width that fits.
        let across = went.horizontal ? grown(container, &next, horizontal: true) : nil
        let down = went.vertical ? grown(container, &next, horizontal: false) : nil
        guard across != nil || down != nil else { return nil }
        guard !cutsOff(wanted, in: container, with: next) else { return nil }
        return (next, across, down)
    }

    /// Grows one side of `layout` to the size its contents need, and says what
    /// that size is, or nil where that side was already big enough.
    ///
    /// The number moves wherever the box was being held: a given Width is
    /// rewritten, and a ceiling that was holding the box in is raised so the
    /// box can go on being the size of its contents. A floor is left alone —
    /// it only ever makes the box bigger, so nothing was ever hanging out
    /// because of one.
    private func grown(_ container: Layer, _ layout: inout GroupLayout,
                       horizontal: Bool) -> CGFloat? {
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
        let natural = flowedSize(of: container, with: free)
        let held = flowedSize(of: container, with: layout)
        // Whole points, rounded up: the inspector types in whole points, and
        // rounding down by a fraction is a box that still cuts off a hairline
        // of what it was grown to hold.
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

    /// How big this container comes out with a layout it does not have yet,
    /// with everything inside it flowed for that layout: the same sum the
    /// canvas does, on a copy nobody can see.
    private func flowedSize(of container: Layer, with layout: GroupLayout) -> CGSize {
        var probe = container
        probe.setGroupLayout(layout)
        return GroupFlow.flowing(probe).localBounds.size
    }

    /// Whether `wanted` is STILL cut off once the container has grown — asked
    /// the same way the mark asks it, on the same flow, so the offer and the
    /// mark can never disagree about whether the fix worked.
    ///
    /// It is asked of everything still in force outside the container as well,
    /// because a card grown until its own contents fit can still be a card
    /// sitting off the edge of the screen it is on.
    private func cutsOff(_ wanted: UUID, in container: Layer, with layout: GroupLayout) -> Bool {
        var probe = container
        probe.setGroupLayout(layout)
        let flowed = GroupFlow.flowing(probe)
        let outer = clipScopes(around: container.id)
        func walk(_ list: [Layer], _ clips: [ClipScope]) -> Bool? {
            for child in list {
                let box = child.localBounds
                if child.id == wanted { return OutOfView.cutter(of: box, under: clips) != nil }
                guard child.isOpenableGroup else { continue }
                if let found = walk(child.children,
                                    OutOfView.scopes(inside: child, box: box, under: clips)) {
                    return found
                }
            }
            return nil
        }
        let inside = OutOfView.scopes(inside: flowed, box: flowed.localBounds, under: outer)
        // A layer the flow cannot find at all is not one this fix can promise
        // anything about, so the offer is not made.
        return walk(flowed.children, inside) ?? true
    }
}
