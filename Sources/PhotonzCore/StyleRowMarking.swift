import Foundation

/// Something saved being held over one row in the layers list: which row, what
/// letting go there would do, and which layers it would reach.
///
/// Either kind of tile, because a row answers for both and the list draws one
/// mark: a saved text style sets the words, a saved colour paints the layer's
/// main colour. What the row draws is the same either way — a ring and one
/// sentence — so the mark carries the ANSWER in the two terms the list uses
/// rather than which kind of thing is in the air, and neither `TextStyleDrop`
/// nor `ColorDrop` has to know the other exists.
public struct StyleRowDrop: Equatable, Sendable {
    public var rowID: UUID
    /// Whether the row lights up, which is also whether letting go there does
    /// anything at all.
    public var lands: Bool
    /// The one line the list says: what letting go would do, or why it would do
    /// nothing. Written either way round, so a row that stays dark is never a
    /// mystery.
    public var note: String
    public var layerIDs: [UUID]

    public init(rowID: UUID, lands: Bool, note: String, layerIDs: [UUID]) {
        self.rowID = rowID
        self.lands = lands
        self.note = note
        self.layerIDs = layerIDs
    }

    /// A saved text style over the row.
    public init(rowID: UUID, answer: TextStyleDrop.Answer, layerIDs: [UUID]) {
        self.init(rowID: rowID, lands: answer.lands, note: answer.note, layerIDs: layerIDs)
    }

    /// A colour over the row.
    public init(rowID: UUID, answer: ColorDrop.Answer, layerIDs: [UUID]) {
        self.init(rowID: rowID, lands: answer.lightsUp, note: answer.note, layerIDs: layerIDs)
    }
}

/// The mark ONE row wears while a style is held over it, and the rules that
/// decide when it stops wearing it.
///
/// It is the layer-row twin of `PanelDropMarking`, and it exists for the same
/// reason that one does: a drag does not always report its own end. Escape
/// cancels it, it can be let go outside the window, and the row under it can be
/// rebuilt out from under it — and any of those would otherwise leave one row
/// in the list ringed in accent for the rest of the session. So the mark stands
/// only while it is being refreshed: once nothing is in the air and nobody has
/// spoken for `PanelDropMarking.idleGrace`, it goes on its own.
///
/// It is separate from `PanelDropMarking` rather than folded into it because
/// the two draw different things. A file lights up the WHOLE panel, because a
/// file has no row of its own to land on; a style lights up the one row it is
/// aimed at, and a panel-wide ring would promise that anywhere would do.
public struct StyleRowMarking: Equatable, Sendable {

    /// What the list is saying right now, nil when it is saying nothing.
    public private(set) var drop: StyleRowDrop?

    /// When it last spoke, which is what the deadline counts from.
    private var spokeAt: TimeInterval = 0

    public init() {}

    /// The row under the pointer says what letting go on it would do. Called on
    /// every frame of a drag, so an unchanged answer only pushes the deadline
    /// out.
    public mutating func say(_ drop: StyleRowDrop, at now: TimeInterval) {
        spokeAt = now
        guard self.drop != drop else { return }
        self.drop = drop
    }

    /// The style has left this row, or landed on it. A goodbye from a row that
    /// no longer owns the mark is the stale half of a pointer crossing a row
    /// edge — the new row is entered BEFORE the old one is left — and is
    /// ignored, otherwise the mark blinks off at every boundary.
    public mutating func end(from rowID: UUID) {
        guard drop?.rowID == rowID else { return }
        clear()
    }

    /// The way out that does not depend on the drag reporting its own end.
    /// `dragInTheAir` is whether anything is being carried at all right now.
    /// Answers whether it cleared anything.
    @discardableResult
    public mutating func settle(dragInTheAir: Bool, at now: TimeInterval) -> Bool {
        guard drop != nil, !dragInTheAir,
              now - spokeAt >= PanelDropMarking.idleGrace else { return false }
        clear()
        return true
    }

    public mutating func clear() {
        drop = nil
        spokeAt = 0
    }
}
