import Foundation

/// What the properties panel is promising to do with the thing being held over
/// it. Two answers, drawn so they are told apart at a glance rather than read.
public enum PanelDropOffer: Equatable, Sendable {
    /// The panel will take it, and the picture will land here. The landing is
    /// nil only when there is no stack to land in, where the file opens a
    /// window of its own instead.
    case accepts(LayerDrop?)
    /// The panel cannot use what is being held over it.
    case refuses
}

/// The mark the properties panel wears while something is held over it, and the
/// rules that decide when it stops wearing it.
///
/// Three targets answer for the same surface — a section, a layer row, and the
/// panel itself — so they speak through one mark rather than each drawing its
/// own, and the last one to speak owns it. A goodbye from a target that no
/// longer owns the mark is the stale half of a pointer crossing a boundary
/// (the new target is entered BEFORE the old one is left) and is ignored,
/// otherwise the mark blinks off at every row edge.
///
/// The important part is the deadline. Every other way out of this mark is a
/// target reporting that the drag left it, and a drag does not always report
/// anything: escape cancels it, it can be let go outside the window, and the
/// row under it can be rebuilt out from under it. Any of those used to leave
/// the mark on the panel for good. So the mark also stands only while it is
/// being refreshed: once nothing is in the air and nobody has spoken for
/// `idleGrace`, it goes on its own, whatever path the drag took out.
public struct PanelDropMarking: Equatable, Sendable {
    /// How long a mark stands after the last word about it, once nothing is in
    /// the air. Long enough that it is never reached during a drag — a drag
    /// holds the mouse button down, which is what "in the air" means, and asks
    /// its target again many times a second — and short enough that a mark
    /// stranded by an unpredicted ending is gone before anyone reads it as
    /// permanent.
    public static let idleGrace: TimeInterval = 1

    /// What the panel is saying right now, nil when it is saying nothing.
    public private(set) var offer: PanelDropOffer?

    /// Which target spoke last. Only that one can take the mark back.
    private var owner: String?

    /// When it last spoke, which is what the deadline counts from.
    private var spokeAt: TimeInterval = 0

    public init() {}

    /// The landing the mark is promising, which is what the drop line in the
    /// layers list draws. Only an accepting mark has one.
    public var landing: LayerDrop? {
        guard case .accepts(let drop) = offer else { return nil }
        return drop
    }

    /// A target says what it is about to do with what it is holding. Called on
    /// every frame of a drag, so an unchanged answer only pushes the deadline
    /// out.
    public mutating func say(_ offer: PanelDropOffer, from owner: String, at now: TimeInterval) {
        self.owner = owner
        spokeAt = now
        guard self.offer != offer else { return }
        self.offer = offer
    }

    /// The thing in the air has left this target, or landed on it.
    public mutating func end(from owner: String) {
        guard self.owner == owner else { return }
        clear()
    }

    /// The way out that does not depend on the drag reporting its own end.
    /// `dragInTheAir` is whether anything is being carried at all right now.
    /// Answers whether it cleared anything.
    @discardableResult
    public mutating func settle(dragInTheAir: Bool, at now: TimeInterval) -> Bool {
        guard offer != nil, !dragInTheAir, now - spokeAt >= Self.idleGrace else { return false }
        clear()
        return true
    }

    public mutating func clear() {
        owner = nil
        offer = nil
        spokeAt = 0
    }
}
