import Foundation

/// What the Layout section shows when several layers are picked at once
/// (`docs/design/mocks/shared/UX-PATTERNS.md` §4, "What a control DOES for
/// several picked things").
///
/// Picking a second layer used to take the whole section off the panel, so
/// saying "Stretch" over three buttons in a bar meant saying it three times.
/// The rule says disappearing is only ever the answer for "none of the picked
/// things has this property at all": every layer inside a container has a place
/// in it, the panel reaches all of them, so the section stays and speaks for
/// them.
///
/// It is deliberately the same shape as `ComponentKnobSelection`: one value
/// holds who it reaches and what each row reads, and one layer picked reads
/// exactly the way five do, so the panel has one path rather than two that can
/// drift.

/// What one Layout row reads across the layers it speaks for.
public struct PlacementReading<Value: Hashable & Sendable>: Hashable, Sendable {
    /// The answer they all give. Nil when they do not agree on one, and when
    /// the row reaches nothing.
    public let value: Value?
    /// Whether they disagree, which is what puts `Mixed` in the control.
    public let isMixed: Bool
    /// Whether every layer it reaches takes this answer from the thing holding
    /// it rather than saying it for itself. One layer with a rule of its own is
    /// enough to make this false, even where that rule lands on the same
    /// answer: it stops matching the moment the container changes.
    public let follows: Bool

    public init(value: Value?, isMixed: Bool, follows: Bool) {
        self.value = value
        self.isMixed = isMixed
        self.follows = follows
    }

    /// The row that reaches nothing.
    public static var empty: Self { Self(value: nil, isMixed: false, follows: false) }

    /// The reading over one answer per layer, each paired with whether the
    /// container gave it.
    public static func over(_ answers: [(value: Value, follows: Bool)]) -> Self {
        guard let first = answers.first else { return .empty }
        let agreed = answers.allSatisfy { $0.value == first.value }
        return Self(value: agreed ? first.value : nil,
                    isMixed: !agreed,
                    follows: answers.allSatisfy(\.follows))
    }
}

/// The layers one Layout section speaks for, and what each of its rows reads
/// across them.
public struct PlacementSelection: Hashable, Sendable {

    /// The picked layers this section places, in draw order. Empty when the
    /// picked layers are not all in one container.
    public let layers: [UUID]
    /// How many layers are picked altogether, so a heading can name them.
    public let selectionCount: Int
    /// The one thing holding every picked layer: the group or screen they are
    /// all in. Nil when they sit loose on the canvas, and when they are in
    /// different containers.
    public let containerID: UUID?
    /// Whether the picked layers sit in more than one container. Then there is
    /// no place they share, and the section says so rather than going blank.
    public let hasDifferentContainers: Bool
    /// Where they sit across, once each layer's own rule and the container's
    /// default are put together.
    public let horizontal: PlacementReading<HorizontalPlacement>
    /// The same down the box.
    public let vertical: PlacementReading<VerticalPlacement>
    /// Whether they take the room their stack has left over.
    public let fills: PlacementReading<Bool>

    public init(layers: [UUID], selectionCount: Int, containerID: UUID?,
                hasDifferentContainers: Bool,
                horizontal: PlacementReading<HorizontalPlacement>,
                vertical: PlacementReading<VerticalPlacement>,
                fills: PlacementReading<Bool>) {
        self.layers = layers
        self.selectionCount = selectionCount
        self.containerID = containerID
        self.hasDifferentContainers = hasDifferentContainers
        self.horizontal = horizontal
        self.vertical = vertical
        self.fills = fills
    }

    /// The empty answer: nothing picked has a place in anything, so there is no
    /// section.
    public static let none = PlacementSelection(
        layers: [], selectionCount: 0, containerID: nil, hasDifferentContainers: false,
        horizontal: .empty, vertical: .empty, fills: .empty)

    public var count: Int { layers.count }

    public var isEmpty: Bool { layers.isEmpty }

    /// Whether the section belongs on the panel at all: the picked layers sit
    /// in something, even where they sit in more than one thing.
    public var isPresent: Bool {
        hasDifferentContainers || (containerID != nil && !layers.isEmpty)
    }

    /// What a row shows in place of a value when the layers differ. One word
    /// for the whole app, so no two controls can spell it differently.
    public static let mixedText = MixedValue.text

    /// What the section says when the picked layers are not all in the same
    /// thing. Two layers in two groups are placed by two different containers,
    /// so a row averaging them would be setting a rule against a container
    /// neither of them answers to.
    public static let differentContainersNote =
        "These layers are not all in the same group. "
        + "Pick layers from one group to place them together."
}

extension PhotonzDocument {

    /// What the Layout section shows for the layers picked: the ones it places,
    /// what holds them, and what each row reads across them.
    ///
    /// Layers loose on the canvas are held by nothing, so a selection of those
    /// brings no section at all — the same answer a single loose layer has
    /// always given. Layers in DIFFERENT containers bring the section with one
    /// sentence in it: every one of them has a place, so silently going blank
    /// would read as a fault.
    public func placementSelection(layerIDs: [UUID]) -> PlacementSelection {
        let known = layerIDs.filter { layer(id: $0) != nil }
        guard !known.isEmpty else { return .none }
        var containers: [UUID?] = []
        for id in known {
            let parent = parentID(of: id)
            if !containers.contains(parent) { containers.append(parent) }
        }
        guard containers.count == 1, let containerID = containers[0],
              let container = layer(id: containerID) else {
            guard containers.count > 1 else { return .none }
            return PlacementSelection(
                layers: [], selectionCount: known.count, containerID: nil,
                hasDifferentContainers: true,
                horizontal: .empty, vertical: .empty, fills: .empty)
        }
        // A piece inside a copy owns none of this: its place comes from the
        // original and is written back over on the next redraw, so a row that
        // set it would be taking an answer and losing it. The single-layer
        // panel already refuses (`sectionsAPieceDoesNotOwn`); this is the same
        // refusal said for several.
        let placed = known.filter { componentPiece(of: $0) == nil }
        guard !placed.isEmpty else { return .none }
        let resolved = placed.compactMap { layer(id: $0)?.resolvedPlacement(in: container) }
        return PlacementSelection(
            layers: placed,
            selectionCount: known.count,
            containerID: containerID,
            hasDifferentContainers: false,
            horizontal: .over(resolved.map { ($0.horizontal, $0.followsHorizontal) }),
            vertical: .over(resolved.map { ($0.vertical, $0.followsVertical) }),
            fills: .over(placed.compactMap { layer(id: $0) }.map { ($0.fillsTheFlow, false) }))
    }
}
