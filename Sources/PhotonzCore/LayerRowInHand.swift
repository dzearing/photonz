import Foundation

/// The row the layers list is holding while one is being carried up or down
/// it, and the rules that decide when it stops holding it.
///
/// The list has to remember which row is in the air, because that is what the
/// drop line is drawn for and what the drop finally moves. Every obvious way a
/// drag ends reports itself and puts the row down. The ones that matter are the
/// ones that do not: escape cancels a drag, it can be let go over the picture
/// or outside the window, and the row under it can be rebuilt out from under
/// it. Any of those used to leave the row in the list's hand for good, and the
/// next thing carried over a row — a colour off a swatch, a saved colour off
/// the Library shelf, words out of a field — was read as that row coming back
/// and drew a reorder line for something that is not a row at all.
///
/// So the row is held only while the drag keeps saying so: once nothing is in
/// the air and nobody has spoken for `idleGrace`, it is put down on its own,
/// whatever path the drag took out. It is the same shape as `PanelDropMarking`,
/// which settles the mark the panel wears for exactly the same reason, and the
/// one watch in the app settles both.
public struct LayerRowInHand: Equatable, Sendable {
    /// How long a row stays held after the last word about it, once nothing is
    /// in the air. The same grace the panel's mark gets, and for the same
    /// reasons: a real drag holds the mouse button down and asks its target
    /// again many times a second, so this can never be reached under one, while
    /// a scripted walk carries a drag with no button down at all and needs
    /// room to breathe between its own updates.
    public static let idleGrace: TimeInterval = PanelDropMarking.idleGrace

    /// The row being carried, nil when the list is holding nothing.
    public private(set) var rowID: UUID?

    /// Where the row under the pointer says the carried row would land, which
    /// is what the drop line draws. Nil while the pointer is somewhere nothing
    /// can land.
    public private(set) var landing: LayerDrop?

    /// When the drag last said anything, which is what the deadline counts
    /// from.
    private var spokeAt: TimeInterval = 0

    public init() {}

    public var isHolding: Bool { rowID != nil }

    /// A row was picked up. Starts over rather than carrying anything across,
    /// so the first frame of a drag never draws the line the last one left.
    public mutating func pickUp(_ id: UUID, at now: TimeInterval) {
        rowID = id
        landing = nil
        spokeAt = now
    }

    /// The row under the pointer says where the carried row would land, nil for
    /// a place it cannot. Called on every frame of a drag, so an unchanged
    /// answer only pushes the deadline out.
    ///
    /// It does nothing at all when no row is being carried: a file, a colour or
    /// words held over a row are not a row, and letting them speak here is what
    /// would put something in the list's hand that it never picked up.
    public mutating func say(landing: LayerDrop?, at now: TimeInterval) {
        guard isHolding else { return }
        spokeAt = now
        guard self.landing != landing else { return }
        self.landing = landing
    }

    /// The row was let go somewhere that reported it: a drop that landed, or
    /// one the list refused.
    public mutating func letGo() {
        rowID = nil
        landing = nil
        spokeAt = 0
    }

    /// The way out that does not depend on the drag reporting its own end.
    /// `dragInTheAir` is whether anything is being carried at all right now.
    /// Answers whether it put a row down.
    @discardableResult
    public mutating func settle(dragInTheAir: Bool, at now: TimeInterval) -> Bool {
        guard isHolding, !dragInTheAir, now - spokeAt >= Self.idleGrace else { return false }
        letGo()
        return true
    }
}
