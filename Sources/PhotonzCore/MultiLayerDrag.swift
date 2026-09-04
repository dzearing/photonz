import CoreGraphics
import Foundation

/// Dragging a multi-selection on the canvas. Press on any one of the picked
/// layers and the whole selection travels with the pointer, as one object.
///
/// The object that moves is the BOX the selection makes, not whichever piece
/// happens to sit under the pointer. That is what makes a multi-selection feel
/// like one thing: its outer edges are what line up with the picture and with
/// the layers that stayed behind, and everything inside keeps the spacing it
/// had, because every member is offset by exactly the same amount.
public struct MultiLayerDrag: Equatable, Sendable {
    /// One layer the drag carries, as the box it occupies on canvas.
    public struct Member: Equatable, Sendable {
        public let id: UUID
        public let bounds: CGRect

        public init(id: UUID, bounds: CGRect) {
            self.id = id
            self.bounds = bounds
        }
    }

    /// Draw order, so a drag lands the same way twice running.
    public let members: [Member]
    /// The canvas-space box the selection filled when the drag began.
    public let bounds: CGRect

    /// Nil when nothing in the selection is free to move, which is when a
    /// press has nothing to drag and should behave as it always did.
    public init?(members: [Member]) {
        guard let first = members.first else { return nil }
        self.members = members
        self.bounds = members.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
    }

    /// Where every member lands when the whole selection travels `delta`, in
    /// canvas coordinates. This is the arrow keys' half of the same move: a
    /// nudge is a distance rather than a destination, so nothing has to work
    /// out where the selection's box would end up first.
    public func origins(offsetBy delta: CGVector) -> [UUID: CGPoint] {
        origins(movingBoundsTo: CGPoint(x: bounds.origin.x + delta.dx,
                                        y: bounds.origin.y + delta.dy))
    }

    /// Where every member lands when the selection's box moves to `origin`,
    /// in canvas coordinates. Worked out from where each one started, so the
    /// order they are applied in cannot change the result.
    public func origins(movingBoundsTo origin: CGPoint) -> [UUID: CGPoint] {
        let dx = origin.x - bounds.origin.x
        let dy = origin.y - bounds.origin.y
        return members.reduce(into: [:]) { moves, member in
            moves[member.id] = CGPoint(x: member.bounds.origin.x + dx,
                                       y: member.bounds.origin.y + dy)
        }
    }
}

public extension PhotonzDocument {
    /// The drag a press on one of `ids` starts: every picked layer that is
    /// free to move, as the box it occupies on canvas.
    ///
    /// Two kinds of layer are left out, each for a reason you would see:
    ///
    /// - locked layers, so tidying the buttons on top never slides the
    ///   picture underneath;
    /// - a layer inside a picked group, which the group already carries —
    ///   moving both would offset it twice.
    func multiLayerDrag(moving ids: Set<UUID>) -> MultiLayerDrag? {
        guard !ids.isEmpty else { return nil }
        let members = allLayers.compactMap { layer -> MultiLayerDrag.Member? in
            guard ids.contains(layer.id), !layer.isLocked,
                  let bounds = canvasContentBounds(of: layer.id) else { return nil }
            var parent = parentID(of: layer.id)
            while let up = parent {
                if ids.contains(up) { return nil }
                parent = parentID(of: up)
            }
            return MultiLayerDrag.Member(id: layer.id, bounds: bounds)
        }
        return MultiLayerDrag(members: members)
    }
}

/// What a press that lands on a layer already in a multi-selection means.
///
/// The press itself never changes what is picked: the whole selection has to
/// survive it so the group can travel with the pointer as one object. Letting
/// go is what decides. A press that travelled was a move, and everything that
/// moved stays picked. A press that never travelled was a plain click on one
/// of several things, and clicking one of several things narrows to it
/// everywhere else on the Mac — so it narrows here too, instead of asking you
/// to click bare canvas first and then click the layer.
///
/// ⇧ never reaches this: a ⇧-click on a picked layer drops it from the
/// selection, which is its own rule, decided on the press.
public enum PickedMemberPress: Equatable, Sendable {
    /// The pointer travelled past the click tolerance: this was a move.
    case moved
    /// The pointer never travelled: this was a click on one of several.
    case click

    public init(moved: Bool) { self = moved ? .moved : .click }

    /// Whether letting go narrows the selection to the layer that was pressed.
    public var narrowsSelection: Bool { self == .click }

    /// What is picked once the press lets go: just the layer it landed on for
    /// a click, everything that travelled for a move.
    public func selection(afterPressing id: UUID,
                          startingFrom existing: Set<UUID>) -> Set<UUID> {
        narrowsSelection ? [id] : existing
    }
}
