import CoreGraphics
import Foundation

/// Turning what is selected into a choice, in one act
/// (`docs/design/ui-building.md`, the C6 follow-up).
///
/// A choice knob reaches a GROUP and picks which one of its children is drawn,
/// so before this the only way to offer one was to already know the shape of
/// the answer: group the alternatives by hand, then find that group again in
/// the original's Add menu. Two shapes drawn side by side are the thing a
/// person actually has when they want a choice, and nothing joined those two
/// facts up.
///
/// So: the selected layers become a group of alternatives, the original settles
/// on one of them, and the knob that picks between them exists — one mutation,
/// which means one undo.
extension PhotonzDocument {

    /// The name the group of alternatives takes, because that group IS the
    /// place the choice is made. Its knob is named for what it SETS ("Shape"),
    /// so a copy's panel never reads "Choice" beside a chip saying "choice".
    public static let choiceNameBase = "Choice"

    /// What making a choice produced: the group holding the alternatives, the
    /// knob that picks between them, and how many there are to pick from.
    public struct MadeChoice: Hashable, Sendable {
        public var group: UUID
        public var property: UUID
        public var options: Int

        public init(group: UUID, property: UUID, options: Int) {
            self.group = group
            self.property = property
            self.options = options
        }
    }

    /// Whether Layer ▸ Make Alternatives would do anything.
    public func canMakeChoice(ids: Set<UUID>) -> Bool { choicePlan(ids: ids) != nil }

    /// Turns the selection into a set of alternatives with a knob that picks
    /// between them, and returns what it made.
    ///
    /// Everything happens on a draft that is only kept if every part of it
    /// worked, so a selection that turns out not to be exposable does not leave
    /// a stray group behind for somebody to undo.
    @discardableResult
    public mutating func makeChoice(ids: Set<UUID>) -> MadeChoice? {
        guard let plan = choicePlan(ids: ids) else { return nil }
        var draft = self
        let group: UUID
        switch plan {
        case .expose(let id):
            group = id
        case .groupThenExpose(let members):
            guard let made = draft.groupLayers(ids: Set(members),
                                               name: draft.freshGroupName(base: Self.choiceNameBase))
            else { return nil }
            group = made.id
        }
        guard let parent = draft.parentID(of: group),
              let home = draft.componentHome(of: parent) else { return nil }
        // A group the command just minted is called "Choice", and a knob named
        // after it would say the chip beside it twice. One this person named
        // themselves is worth borrowing, so only the minted name is replaced.
        let knobName = plan.isFresh
            ? draft.freshPropertyName(base: ComponentPropertyKind.variant.defaultName,
                                      taken: draft.componentProperties(of: home).map(\.name))
            : nil
        guard let property = draft.addComponentProperty(componentID: home, target: group,
                                                        kind: .variant, name: knobName)
        else { return nil }
        let options = draft.layer(id: group)?.children.count ?? 0
        self = draft
        return MadeChoice(group: group, property: property, options: options)
    }

    /// The two ways a selection can become a choice.
    private enum ChoicePlan {
        /// One group that already holds alternatives: expose it where it
        /// stands rather than wrapping a group in a group.
        case expose(UUID)
        /// Two or more layers of one list: group them, then expose that.
        case groupThenExpose([UUID])

        /// Whether the group is one this command is about to mint.
        var isFresh: Bool {
            if case .groupThenExpose = self { return true }
            return false
        }
    }

    /// What the selection would do, or nil when it cannot become a choice —
    /// which is the same question the menu row asks, so the row and the command
    /// can never disagree.
    private func choicePlan(ids: Set<UUID>) -> ChoicePlan? {
        if ids.count == 1, let id = ids.first, let layer = layer(id: id),
           layer.canBeVariant, !layer.isLocked, let parent = parentID(of: id),
           let home = componentHome(of: parent),
           canAddComponentProperty(componentID: home, target: id, kind: .variant) {
            return .expose(id)
        }
        // The same members ⌘G would wrap up, so a person who has just pressed
        // ⌘G somewhere else is not learning a second rule about selections.
        let members = groupableMembers(ids: ids)
        guard members.count >= 2, let anchor = members.first,
              let parent = parentID(of: anchor),
              componentHome(of: parent) != nil,
              componentDepth(of: parent) <= Self.componentPropertyDepthLimit else { return nil }
        return .groupThenExpose(members)
    }

    /// The original whose insides hold this layer, counting the layer itself.
    ///
    /// Nil when it is not inside an original at all, and nil when a copy sits
    /// between: a copy's contents belong to ITS original and are rewritten on
    /// the next sync, so a knob reaching into one would not survive.
    public func componentHome(of id: UUID) -> UUID? { componentWalk(from: id)?.componentID }

    /// How many groups sit between this layer and the original above it, so a
    /// knob is not made somewhere the Add menu could never list it again.
    private func componentDepth(of id: UUID) -> Int { componentWalk(from: id)?.depth ?? .max }

    private func componentWalk(from id: UUID) -> (componentID: UUID, depth: Int)? {
        var current: UUID? = id
        var depth = 0
        while let layerID = current, let layer = layer(id: layerID) {
            if layer.isComponentInstance { return nil }
            if let componentID = layer.componentID { return (componentID, depth) }
            depth += 1
            current = parentID(of: layerID)
        }
        return nil
    }
}
