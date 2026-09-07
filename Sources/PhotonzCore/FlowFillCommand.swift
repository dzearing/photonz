import CoreGraphics
import Foundation

/// One menu row's reading of "take the room this stack has left over"
/// (`docs/design/ui-building.md`, "A group can arrange its own contents").
///
/// The Layout section has offered this since the flow landed, two rows down a
/// panel that has to be open to be read. It is the answer people reach for
/// most while building a bar — the search field between the logo and the
/// buttons is whatever is left — so it is also one row in the Layer menu with
/// a key on it, the way lining a piece up already is.
///
/// The reading lives here rather than in the menu so the row and the panel
/// cannot drift apart, and so the one question a menu row cannot answer for
/// itself — why it is dead — is a sentence somebody wrote rather than silence.
public struct FlowFillCommand: Hashable, Sendable {

    /// What the row is called where there is no stack to name, which is every
    /// selection the row is dead for. "Stack" is this app's word for a group
    /// that arranges itself at all, so a dead row wearing it reads as what it
    /// is asking for.
    public static let defaultTitle = "Fill the Stack"

    /// Why the row is dead where the picked pieces are not being arranged by a
    /// stack: loose on the canvas, in a plain group, or in a grid, which shares
    /// its room out between equal cells and has none left to hand anybody.
    public static let notInAStackReason =
        "Only a piece inside a stack can take the room left over. Pick the group it is in and "
        + "set Arrangement to Stack in the Layout section."

    /// Why it is dead for the piece that spans its group: it is painted to the
    /// group's own edges rather than given a place in the line, so the room
    /// left over is not a thing it is waiting for.
    public static let spansTheGroupReason =
        "This is painted to the group's own edges instead of being lined up with the others, so "
        + "there is no room left over for it to take. Set its Stretch back and it becomes one of "
        + "the pieces in the line again."

    /// The pieces the row would reach: every picked layer that has a place in
    /// the one container they share. Empty where there is nothing to act on.
    public let layers: [UUID]
    /// What the row reads, named after the flow it is about so it is the same
    /// words as the panel row it shortcuts.
    public let title: String
    /// Whether the tick is there: every piece it reaches is already taking the
    /// room. One piece that is not unticks it, so a mixed selection is one
    /// press away from all of them filling.
    public let isOn: Bool
    /// Whether the row is live.
    public let isEnabled: Bool
    /// Why it could not be switched ON, in plain words, or nil where it can.
    /// Carried even where the row is live, because a row that is only live so
    /// a stranded rule can be taken off still owes an explanation.
    public let reason: String?

    /// The sentence the row shows on hover: why it is dead where it is, and
    /// what pressing it does where it is not. A menu row is a name and nothing
    /// else, so this is the only place the row can explain itself, and a grey
    /// row with no reason beside it is a puzzle rather than an answer.
    public var help: String { reason ?? PlacementEditing.fillReason(noun) }

    /// The flow this row is about, in the words a sentence uses for it.
    let noun: String

    public init(layers: [UUID], title: String, isOn: Bool, isEnabled: Bool, reason: String?,
                noun: String = PlacementEditing.stackNoun) {
        self.layers = layers
        self.title = title
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.reason = reason
        self.noun = noun
    }

    /// Nothing picked: a dead row with nothing to explain, like every other row
    /// in the menu at that moment.
    public static let none = FlowFillCommand(layers: [], title: defaultTitle, isOn: false,
                                             isEnabled: false, reason: nil)
}

extension PhotonzDocument {

    /// What the Layer menu's fill row reads for the layers picked.
    ///
    /// It goes by the same reading the Layout section does, so one pick means
    /// the same thing in both places, and it reaches the whole selection: three
    /// buttons in a bar are told once, in one undo step.
    ///
    /// The row stays live whenever the pieces are ALREADY filling, even where
    /// it could not be switched on. A piece that fills and is then stretched
    /// both ways, or a stack that loses the width that gave it room, leaves a
    /// rule set and doing nothing, and the panel's own row disappears in both
    /// cases. Taking a rule off has to stay reachable or it is stuck there for
    /// good.
    public func flowFillCommand(layerIDs: [UUID]) -> FlowFillCommand {
        guard !layerIDs.isEmpty else { return .none }
        let selection = placementSelection(layerIDs: layerIDs)
        guard !selection.hasDifferentContainers else {
            return FlowFillCommand(layers: [], title: FlowFillCommand.defaultTitle,
                                   isOn: false, isEnabled: false,
                                   reason: PlacementSelection.differentContainersNote)
        }
        guard let containerID = selection.containerID, let container = layer(id: containerID),
              !selection.layers.isEmpty else {
            return FlowFillCommand(layers: [], title: FlowFillCommand.defaultTitle,
                                   isOn: false, isEnabled: false,
                                   reason: FlowFillCommand.notInAStackReason)
        }
        let isOn = selection.fills.value == true
        guard let layout = container.group?.layout, layout.kind == .stack else {
            return FlowFillCommand(layers: selection.layers,
                                   title: FlowFillCommand.defaultTitle,
                                   isOn: isOn, isEnabled: isOn,
                                   reason: FlowFillCommand.notInAStackReason)
        }
        let title = PlacementEditing.fillMenuTitle(across: layout.flowsHorizontally)
        // Two different reasons a stack cannot hand this piece anything, and
        // the piece's own comes second because it is the one the user can put
        // right without touching the group.
        let flow = PlacementEditing(arrangement: layout, onAScreen: container.isFrame)
        var reason = flow.noRoomToFill
        if reason == nil,
           !selection.layers.allSatisfy({ layer(id: $0)?.canFillTheFlow(in: container) == true }) {
            reason = FlowFillCommand.spansTheGroupReason
        }
        return FlowFillCommand(layers: selection.layers, title: title, isOn: isOn,
                               isEnabled: reason == nil || isOn, reason: reason,
                               noun: layout.flowsHorizontally ? PlacementEditing.rowNoun
                                                              : PlacementEditing.stackNoun)
    }
}
