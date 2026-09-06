import CoreGraphics
import Foundation

/// What the Contents rows of the Layout section show when SEVERAL groups are
/// picked at once (`docs/design/mocks/shared/UX-PATTERNS.md` §4, "What a
/// control DOES for several picked things").
///
/// Picking a second card used to take the whole Contents block off the panel,
/// and that block is not two rows: it is the arrangement, the direction, the
/// gap, the columns, the padding, the size and its limits, and then where the
/// contents sit. So making two cards stack their contents 12 apart meant doing
/// every one of those twice, once per card, with a click in between to change
/// which card the panel was talking about.
///
/// It is deliberately NOT `PlacementSelection`, and deliberately the same
/// SHAPE. That one answers "where do the picked layers sit in whatever holds
/// them"; this one answers "what do the picked groups tell their own contents
/// to do". Both hold who they reach and what each row reads, and in both, one
/// picked reads exactly the way five do, so the panel has one path rather than
/// two that can drift.
public struct ContentsSelection: Hashable, Sendable {

    /// One picked group, and everything the Contents rows read off it.
    ///
    /// Read once, here, rather than by each row reaching back into the
    /// document: a row that fetched its own layer would be a row that could
    /// disagree with the one above it about which group it was talking about.
    public struct Group: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let name: String
        /// A screen, which is a box somebody drew, rather than a group, which
        /// is the size of what is inside it. Decides the words the rows use and
        /// whether a size of its own is even a question.
        public let isFrame: Bool
        /// What this group is working to, including what a group nobody has
        /// touched is already working to, so the rows read the same either way.
        public let layout: GroupLayout
        /// The arrangement actually deciding things, or nil where nothing is
        /// arranging: a free group, or the whole feature switched off.
        public let arrangement: GroupLayout?
        /// What this group tells its contents by default, in the words the
        /// inspector shows.
        public let contents: ResolvedPlacement
        /// Whether it PLACES its contents rather than magnifying them, which
        /// is what takes the proportional Scale off the menus.
        public let placesItsContents: Bool
        /// Whether it has a box its contents can hang out of, which is what
        /// makes clipping a question at all.
        public let hasBoxOfItsOwn: Bool
        public let clipsContents: Bool
        /// The size it is right now, which is where Hug turns into Fixed. Held
        /// per group, so telling two groups to hold their size holds each one's
        /// OWN size rather than the first one's borrowed by the rest.
        public let measured: CGSize
        /// The rule it has actually WRITTEN about its contents, as opposed to
        /// what that resolves to. The one place a rule left sitting on the
        /// direction its own flow decides can still be read, and taken off.
        public let rule: LayerPlacement?
        /// Which of its contents' two directions its own flow has taken over,
        /// and the words for saying so.
        public let editing: PlacementEditing
        /// Who inside it has a rule of its own.
        public let overrides: [PlacementOverride]
    }

    /// The picked groups these rows speak for and can set, in draw order.
    public let groups: [Group]
    /// How many layers are picked altogether, so a heading can tell you
    /// something picked was left out of this block.
    public let selectionCount: Int
    /// Whether every group here is a copy of a component. A copy's contents
    /// are its original's, refilled after every edit, so the rows are shown
    /// and never asked.
    public let isFollowed: Bool

    public init(groups: [Group], selectionCount: Int, isFollowed: Bool) {
        self.groups = groups
        self.selectionCount = selectionCount
        self.isFollowed = isFollowed
    }

    /// Nothing picked has contents to arrange, so there is no block.
    public static let none = ContentsSelection(groups: [], selectionCount: 0, isFollowed: false)

    public var ids: [UUID] { groups.map(\.id) }
    public var count: Int { groups.count }
    public var isEmpty: Bool { groups.isEmpty }
    /// Whether the block belongs on the panel at all.
    public var isPresent: Bool { !groups.isEmpty }

    // MARK: - Who this is about, in words

    /// What the block is headed: one group by its name, several by how many.
    public var heading: String {
        if let one = groups.first, groups.count == 1 { return "Contents of \(one.name)" }
        return "Contents of these \(groups.count) \(plural)"
    }

    /// What to call several of these. Screens and groups are different enough
    /// that calling two screens "groups" would read as a mistake, and a pick
    /// with one of each falls back to the word that covers both.
    public var plural: String {
        if groups.allSatisfy(\.isFrame) { return "screens" }
        if groups.allSatisfy({ !$0.isFrame }) { return "groups" }
        return "layers"
    }

    /// One of these, for a sentence: "the room kept clear inside the group's
    /// edges". Several read as one kind of thing, so the sentence stays in the
    /// singular and the heading above it carries the number.
    public var noun: String {
        if groups.allSatisfy(\.isFrame) { return "screen" }
        if groups.allSatisfy({ !$0.isFrame }) { return "group" }
        return "layer"
    }

    /// Whether every picked group is a screen, which has no size of its own to
    /// set here.
    public var allFrames: Bool { !groups.isEmpty && groups.allSatisfy(\.isFrame) }

    /// Whether a size of its own is a question for the whole pick. A screen is
    /// a box somebody drew, so one screen in the pick takes the size rows away
    /// rather than showing a control that would do nothing to it.
    public var offersASizeOfItsOwn: Bool { !groups.isEmpty && groups.allSatisfy { !$0.isFrame } }

    /// Whether clipping is a question: every picked group has a box its
    /// contents could hang out of. A switch that reached only two of three
    /// picked groups would be worse than no switch.
    public var offersClipping: Bool {
        offersASizeOfItsOwn && groups.allSatisfy(\.hasBoxOfItsOwn)
    }

    /// Whether every picked stack has room left over to share out.
    public var canSpread: Bool {
        !groups.isEmpty && groups.allSatisfy { $0.isFrame || $0.layout.couldSpread }
    }

    /// The choices worth offering across the whole pick: anything one of them
    /// could not honour is off the menu, so no pick here can land on some of
    /// them and not the others.
    public var horizontalChoices: [HorizontalPlacement] {
        HorizontalPlacement.allCases.filter { choice in
            choice != .scale || groups.allSatisfy { !$0.placesItsContents }
        }
    }

    public var verticalChoices: [VerticalPlacement] {
        VerticalPlacement.allCases.filter { choice in
            choice != .scale || groups.allSatisfy { !$0.placesItsContents }
        }
    }

    // MARK: - What each row reads

    public var arrangement: PlacementReading<GroupLayoutKind?> {
        .across(groups.map(\.layout.kind))
    }

    public var direction: PlacementReading<StackDirection> {
        .across(groups.map(\.layout.direction))
    }

    public var columns: PlacementReading<Int> { .across(groups.map(\.layout.usedColumns)) }
    public var gap: PlacementReading<CGFloat> { .across(groups.map(\.layout.usedGap)) }
    public var rowGap: PlacementReading<CGFloat> { .across(groups.map(\.layout.usedRowGap)) }
    public var spreads: PlacementReading<Bool> { .across(groups.map(\.layout.spreadsGap)) }
    public var padding: PlacementReading<GroupPadding> { .across(groups.map(\.layout.usedPadding)) }
    public var hugsWidth: PlacementReading<Bool> { .across(groups.map(\.layout.hugsWidth)) }
    public var hugsHeight: PlacementReading<Bool> { .across(groups.map(\.layout.hugsHeight)) }
    public var minWidth: PlacementReading<CGFloat?> { .across(groups.map(\.layout.usedMinWidth)) }
    public var maxWidth: PlacementReading<CGFloat?> { .across(groups.map(\.layout.usedMaxWidth)) }
    public var minHeight: PlacementReading<CGFloat?> { .across(groups.map(\.layout.usedMinHeight)) }
    public var maxHeight: PlacementReading<CGFloat?> { .across(groups.map(\.layout.usedMaxHeight)) }
    public var clips: PlacementReading<Bool> { .across(groups.map(\.clipsContents)) }
    public var horizontal: PlacementReading<HorizontalPlacement> {
        .across(groups.map(\.contents.horizontal))
    }
    public var vertical: PlacementReading<VerticalPlacement> {
        .across(groups.map(\.contents.vertical))
    }

    /// Whether any picked group carries a limit, which is what opens the two
    /// limit rows before anybody asks. One group holding itself open is reason
    /// enough: a number doing that is not something to go hunting for.
    public var limitsWidth: Bool { groups.contains { $0.layout.limitsWidth } }
    public var limitsHeight: Bool { groups.contains { $0.layout.limitsHeight } }

    /// The room kept clear on ONE side, read across the picked groups.
    public func padding(_ side: GroupPadding.Side) -> PlacementReading<CGFloat> {
        .across(groups.map { $0.layout.usedPadding[side] })
    }

    /// Whether nothing picked is arranging its contents at all, which is what
    /// leaves the placement rows to say the whole story on their own.
    public var nothingArranged: Bool { groups.allSatisfy { $0.arrangement == nil } }

    /// Which of the contents' two directions the picked groups' own flows have
    /// taken over. Where they do not agree, neither direction is treated as
    /// taken: it is still a question for some of them, and a row that went dead
    /// would be answering for the ones it is not about.
    public var flow: PlacementEditing {
        guard let first = groups.first?.editing, !flowsDiffer else {
            return PlacementEditing(arrangement: nil)
        }
        return first
    }

    /// Whether the picked groups disagree about which direction their own flow
    /// decides, which is the one case a row here reaches only some of them.
    public var flowsDiffer: Bool {
        guard let first = groups.first?.editing else { return false }
        return !groups.allSatisfy { $0.editing == first }
    }

    /// The one line under the rows for that case, in the two halves the wording
    /// law asks for: what is true, and what it means for what you are about to
    /// do.
    public static let flowsDifferNote =
        "These are not all arranged the same way. A pick here reaches every one of them, "
        + "and in the ones that line their contents up, the arrangement still decides one "
        + "of the two directions."

    /// Whether any picked group's four sides disagree, which is what opens the
    /// sides before anybody asks — including the case where each group's own
    /// four sides agree but the groups disagree with each other, since the one
    /// field has no honest number for that either.
    public var paddingDiffers: Bool {
        groups.contains { !$0.layout.usedPadding.isUniform } || padding.isMixed
    }

    // MARK: - Who is not following

    /// Every layer with a rule of its own, across every picked group, each one
    /// carrying the group it is in. Two cards can both hold a layer called
    /// Title, so a flat list of names would be two rows nobody could tell
    /// apart.
    public var overrides: [ContentsOverride] {
        groups.flatMap { group in
            group.overrides.map {
                ContentsOverride(override: $0, groupID: group.id, groupName: group.name)
            }
        }
    }

    /// What that list is headed. With one group it is the sentence it has
    /// always been; with several it says how many groups it is counting, or
    /// names the one group they all turned out to come from.
    public var overridesHeading: String {
        let all = overrides
        let plural = all.count == 1 ? "One layer" : "\(all.count) layers"
        let verb = all.count == 1 ? "has a rule of its own" : "have rules of their own"
        guard groups.count > 1 else { return "\(plural) \(verb)" }
        let from = Set(all.map(\.groupID))
        if from.count == 1, let name = all.first?.groupName {
            return "\(plural) in \(name) \(verb)"
        }
        return "\(plural) across \(from.count) groups \(verb)"
    }
}

/// One layer with a rule of its own, and which of the picked groups it is in.
public struct ContentsOverride: Identifiable, Hashable, Sendable {
    public let override: PlacementOverride
    public let groupID: UUID
    public let groupName: String

    public init(override: PlacementOverride, groupID: UUID, groupName: String) {
        self.override = override
        self.groupID = groupID
        self.groupName = groupName
    }

    public var id: UUID { override.id }
    public var name: String { override.name }
    public var summary: String { override.summary }
    public var isSurface: Bool { override.isSurface }
}

extension PlacementReading {
    /// The reading over one answer per picked thing, where nothing is
    /// inherited from anywhere: a group's rules about its own contents are its
    /// own, so `follows` is never true here.
    public static func across(_ values: [Value]) -> Self {
        guard let first = values.first else { return .empty }
        let agreed = values.allSatisfy { $0 == first }
        return Self(value: agreed ? first : nil, isMixed: !agreed, follows: false)
    }
}

extension PhotonzDocument {

    /// What the Contents rows show for the layers picked: the groups they
    /// speak for, and what each row reads across them.
    ///
    /// Only layers with contents are in it. A photo has nothing to arrange, and
    /// a COPY of a component arranges its contents the way its original does —
    /// every one of its rules is refilled after each edit, so an answer typed
    /// at it would be gone by the next redraw. Copies are left out for the same
    /// reason pieces inside a copy are left out of `placementSelection`, except
    /// where they are ALL that is picked, which is the case the panel shows
    /// read-only rather than going blank.
    ///
    /// `arranging` is whether arrangements are switched on at all. With them
    /// off, no group is arranging anything, so no axis is owned by a flow and
    /// every rule counts as a rule of its own, exactly as it did before auto
    /// layout existed.
    public func contentsSelection(layerIDs: [UUID], arranging: Bool = true) -> ContentsSelection {
        let picked = layerIDs.compactMap { layer(id: $0) }
        guard !picked.isEmpty else { return .none }
        let containers = picked.filter(\.isGroup)
        guard !containers.isEmpty else { return .none }
        let own = containers.filter { ownsContentRules(id: $0.id) }
        let isFollowed = own.isEmpty
        let speaking = isFollowed ? containers : own
        return ContentsSelection(
            groups: speaking.map { group in
                let arrangement = arranging ? group.group?.layout : nil
                return ContentsSelection.Group(
                    id: group.id,
                    name: group.name,
                    isFrame: group.isFrame,
                    layout: group.workingLayout,
                    arrangement: arrangement,
                    contents: group.contentPlacementDefault,
                    placesItsContents: group.placesItsContents,
                    hasBoxOfItsOwn: group.hasBoxOfItsOwn,
                    clipsContents: group.clipsToBounds,
                    measured: group.localBounds.size,
                    rule: group.group?.contentPlacement,
                    editing: PlacementEditing(arrangement: arrangement,
                                              onAScreen: group.isFrame),
                    overrides: group.contentsWithTheirOwnPlacement(arrangement: arrangement))
            },
            selectionCount: picked.count,
            isFollowed: isFollowed)
    }
}
