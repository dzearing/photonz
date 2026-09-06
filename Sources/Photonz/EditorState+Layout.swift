import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// Layout intents: lining layers up, grouping them, groups that arrange
// themselves, and how the pieces sit when something is resized.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    // MARK: - Whole-selection commands (Layers menu)

    /// Every layer the Layers menu's Duplicate, Delete and arrange commands
    /// act on: the multi-selection when there is one (shift-click, command-
    /// click or a marquee), else the primary selection. Empty with no layer
    /// selected, which is when those menu items grey out.
    var actionableLayerIDs: Set<UUID> {
        if !multiSelectedLayerIDs.isEmpty { return multiSelectedLayerIDs }
        return selectedLayerID.map { [$0] } ?? []
    }

    var hasLayerSelection: Bool { !actionableLayerIDs.isEmpty }

    /// Layers > Delete Layer (⌘⌫): the whole selection in one undo step.
    func deleteSelectedLayers() {
        let ids = actionableLayerIDs
        guard !ids.isEmpty else { return }
        deleteLayers(ids: Array(ids))
    }

    /// Layers > Duplicate Layer over a selection: every member gets a copy
    /// directly above it, in one undo step, and the copies become the new
    /// selection so a follow-up nudge or arrange moves the copies, not the
    /// originals.
    func duplicateSelectedLayers() {
        let ids = actionableLayerIDs
        guard !ids.isEmpty else { return }
        if ids.count == 1, let only = ids.first {
            duplicateLayer(id: only)
            return
        }
        discardDragPreview()
        var copies: [Layer] = []
        perform { copies = $0.duplicateLayers(ids: ids, offsetBy: CGPoint(x: 16, y: 16)) }
        selectLayers(Set(copies.map(\.id)))
    }

    /// The four arrange commands over a selection: the members move together,
    /// keeping their relative order and gaps, and stop at the locked Background.
    func restackSelectedLayers(_ step: PhotonzDocument.RestackStep) {
        guard let document else { return }
        let ids = actionableLayerIDs
        guard !ids.isEmpty else { return }
        // Dry-run on a copy so a pinned selection never costs an undo step.
        var preview = document
        guard preview.restackLayers(ids: ids, step) else { return }
        discardDragPreview()
        perform { $0.restackLayers(ids: ids, step) }
    }

    // MARK: - Lining layers up (Next flag `next-align-layers`)

    /// The boxes the Arrange commands act on: every selected layer that is
    /// free to move, as the box it occupies on canvas. Canvas space, so a
    /// layer inside a group lines up with one outside it — what you see is
    /// what gets lined up, whatever the layers list says about parentage.
    /// Locked layers stay out: the picture underneath must not slide when you
    /// tidy the buttons on top of it.
    private var arrangeBoxes: [LayerArrangement.Box] {
        guard Experiments.shared.alignLayersEnabled, let document else { return [] }
        let selected = actionableLayerIDs
        return selected.compactMap { id in
            guard let layer = document.layer(id: id), !layer.isLocked,
                  let bounds = document.canvasContentBounds(of: id) else { return nil }
            // A layer inside a selected group is already carried by that
            // group, so it takes no place of its own here: moving both would
            // be lining a thing up against something it is part of.
            var parent = document.parentID(of: id)
            while let up = parent {
                if selected.contains(up) { return nil }
                parent = document.parentID(of: up)
            }
            // Lined up by the box you can see, so a right-aligned label lands
            // its last letter on the edge rather than four points past it.
            return LayerArrangement.Box(id: id, frame: bounds)
        }
    }

    /// What ONE selected layer lines up inside, when something holds it.
    ///
    /// A layer picked on its own has nothing to line up with, unless something
    /// holds it. Two kinds of thing do, and the rule is `ArrangeContainer`'s:
    /// a screen hands over its own box, and a plain group hands over the box of
    /// everything ELSE inside it, which is what makes centring a word on a
    /// button mean the button's background.
    ///
    /// It is the layer's OWN parent or nothing: the search never climbs. A word
    /// inside a button inside a screen answers to the button, rather than flying
    /// to the middle of the screen and out of the button it belongs to.
    ///
    /// Nil for everything else, which keeps a multi-selection lining up with
    /// itself exactly as it did.
    private var arrangeReference: (holder: Layer, container: ArrangeContainer)? {
        guard let document else { return nil }
        let boxes = arrangeBoxes
        guard boxes.count == 1, let id = boxes.first?.id,
              let container = document.arrangeContainer(of: id),
              let holder = document.layer(id: container.id) else { return nil }
        // Each kind of holder rides its own flag: screens are `next-frames`,
        // groups are `next-layer-groups`.
        guard holder.isFrame ? Experiments.shared.framesEnabled
                             : Experiments.shared.layerGroupsEnabled else { return nil }
        return (holder, container)
    }

    /// What the Arrange row is lining things up against, in the words it shows:
    /// the screen's or the group's name when there is one, nil when the
    /// selection is its own reference. The row has to say this out loud,
    /// because six live buttons with only one layer on screen otherwise leave
    /// you guessing what moves where.
    var arrangeReferenceName: String? {
        guard let holder = arrangeReference?.holder else { return nil }
        let name = holder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty else { return name }
        return holder.isFrame ? "the screen around it" : "the group around it"
    }

    /// How many layers the Arrange row is speaking for, so it can say so.
    var arrangeableLayerCount: Int { arrangeBoxes.count }

    var canAlignSelection: Bool {
        LayerArrangement.canAlign(count: arrangeBoxes.count,
                                  hasContainer: arrangeReference != nil)
    }

    /// Whether ONE of the six align commands has anywhere to move what is
    /// picked. Inside a plain group an axis can be dead: a word as wide as the
    /// button it sits on cannot go left, centre or right, so those three dim
    /// and say why rather than pretending.
    func canAlignSelection(_ alignment: LayerAlignment) -> Bool {
        guard canAlignSelection else { return false }
        guard let container = arrangeReference?.container else { return true }
        return container.allows(alignment)
    }

    /// Why half the row is dim, in plain words, or nil when none of it is. The
    /// caption says this out loud as well as the hover tips: three grey buttons
    /// with no reason beside them are a puzzle, and the answer is one clause.
    var arrangeDeadAxisNote: String? {
        arrangeDeadAxisReason(.left) ?? arrangeDeadAxisReason(.top)
    }

    /// Why three of the buttons are dim, in plain words, or nil when they are
    /// not. Only a plain group can say this: it has no box of its own, so a
    /// piece that already spans everything else in it has nowhere to go.
    func arrangeDeadAxisReason(_ alignment: LayerAlignment) -> String? {
        guard let reference = arrangeReference,
              !reference.container.allows(alignment) else { return nil }
        // Never the holder's name: only a plain group can have a dead axis, and
        // the sentence beside it has just said which group this is.
        return alignment.isHorizontal
            ? "It is already as wide as the group, so only up and down can move it."
            : "It is already as tall as the group, so only sideways can move it."
    }

    var canDistributeSelection: Bool { LayerArrangement.canDistribute(count: arrangeBoxes.count) }

    /// Layer ▸ Align: every selected layer moves onto the selection's own
    /// edge or middle, in ONE undo step. The layer already on that edge does
    /// not move, so pressing it twice is a no-op rather than a slow drift.
    /// One layer inside a screen or a group moves onto ITS HOLDER'S edge or
    /// middle instead, so a single press centres a label inside a card or a
    /// word on a button.
    func alignSelection(_ alignment: LayerAlignment) {
        guard canAlignSelection(alignment) else { return }
        moveLayers(LayerArrangement.aligned(arrangeBoxes, to: alignment,
                                            within: arrangeReference?.container.bounds))
    }

    /// Layer ▸ Space Evenly: the outermost two hold still and everything
    /// between them slides so the gaps match, in ONE undo step.
    func distributeSelection(_ axis: LayerDistribution) {
        moveLayers(LayerArrangement.distributed(arrangeBoxes, along: axis))
    }

    /// One undo step for a whole set of moves. Each layer is placed at an
    /// origin worked out from where everything was BEFORE the command, so the
    /// order they are applied in cannot change the result.
    private func moveLayers(_ moves: [UUID: CGPoint]) {
        guard !moves.isEmpty else { return }
        discardDragPreview()
        perform { document in
            for (id, origin) in moves { document.moveLayer(id: id, toCanvasOrigin: origin) }
        }
    }

    // MARK: - Groups (Next flag `next-layer-groups`)

    /// Whether Layer ▸ Group would do anything.
    var canGroupSelection: Bool {
        guard Experiments.shared.layerGroupsEnabled, let document else { return false }
        return document.canGroup(ids: actionableLayerIDs)
    }

    /// Whether Layer ▸ Ungroup would do anything.
    var canUngroupSelection: Bool {
        guard Experiments.shared.layerGroupsEnabled, let document else { return false }
        return document.canUngroup(ids: actionableLayerIDs)
    }

    /// Layer ▸ Group (⌘G): wraps the selection in a new group, in one undo
    /// step, and selects the group — so the very next drag moves the whole
    /// thing, which is the reason you pressed it.
    func groupSelection() {
        guard canGroupSelection else { return }
        let ids = actionableLayerIDs
        discardDragPreview()
        var madeID: UUID?
        perform { document in
            madeID = document.groupLayers(ids: ids, name: document.freshGroupName())?.id
        }
        groupContextID = madeID.flatMap { document?.parentID(of: $0) }
        selectedLayerID = madeID
        // The rubber band that picked the members no longer describes anything.
        setSelection(nil, captureLayers: false)
    }

    /// Layer ▸ Ungroup (⇧⌘G): takes the selected groups apart in one undo
    /// step, leaving the pieces exactly where they were and selected, so you
    /// can carry straight on with them.
    func ungroupSelection() {
        guard canUngroupSelection else { return }
        let ids = actionableLayerIDs
        discardDragPreview()
        // Anything selected that was not a group stays selected alongside the
        // pieces that just came out.
        let kept = ids.filter { document?.layer(id: $0)?.isGroup != true }
        var freed: [UUID] = []
        perform { freed = $0.ungroupLayers(ids: ids) }
        if groupContextID.map({ document?.layer(id: $0) == nil }) ?? false { groupContextID = nil }
        setSelection(nil, captureLayers: false)
        selectLayers(Set(freed).union(kept))
    }

    // MARK: - Groups that arrange themselves (Next flag `next-auto-layout`)

    /// The group whose Arrangement the Layout section is editing: the one group
    /// picked, and nothing when the selection is anything else.
    var arrangingGroupID: UUID? {
        guard Experiments.shared.autoLayoutEnabled, let document,
              document.canSetGroupLayout(ids: actionableLayerIDs) else { return nil }
        return actionableLayerIDs.first
    }

    /// How the picked group arranges its contents right now, or nil for a group
    /// that holds things wherever you put them.
    var arrangement: GroupLayout? {
        arrangingGroupID.flatMap { document?.layer(id: $0)?.group?.layout }
    }

    /// The same, including what a group nobody has touched is already working
    /// to: it arranges nothing and closes around what is inside it.
    var workingArrangement: GroupLayout? {
        arrangingGroupID.flatMap { document?.layer(id: $0)?.workingLayout }
    }

    /// Whether Layer ▸ Stack Selection would do anything: one group to convert,
    /// or several layers to wrap up and arrange.
    var canStackSelection: Bool {
        guard Experiments.shared.autoLayoutEnabled, let document else { return false }
        let ids = actionableLayerIDs
        return document.canSetGroupLayout(ids: ids) || document.canGroup(ids: ids)
    }

    /// The Layout section's Arrangement row: this group becomes a stack, a
    /// grid, or goes back to holding things wherever they were put. Nothing
    /// moves at the moment it lands — the layout is read off where the contents
    /// already are.
    func setArrangement(id: UUID, kind: GroupLayoutKind?) {
        // A copy arranges its contents the way its original does, so there is
        // nothing to discard a drag preview for either.
        guard document?.ownsContentRules(id: id) == true else { return }
        discardDragPreview()
        perform { $0.setGroupLayout(id: id, kind: kind) }
    }

    /// One typed number on a group's arrangement: the gap, the columns, the
    /// padding. Lands as one undo step, like every other typed number.
    func updateArrangement(id: UUID, _ change: @escaping (inout GroupLayout) -> Void) {
        // A group that has never been given a layout gets one on the first
        // number typed into it, keeping the room its contents already have, so
        // nothing moves at the moment the section starts meaning something.
        guard document?.ownsContentRules(id: id) == true else { return }
        perform { $0.updateGroupLayout(id: id, change) }
    }

    /// Layer ▸ Stack Selection (⇧⌘S) / Grid Selection: several layers become
    /// one group that arranges them, and a group already picked simply starts
    /// arranging itself. The group is left selected, so the very next thing you
    /// type is its gap.
    func stackSelection(_ kind: GroupLayoutKind) {
        guard canStackSelection else { return }
        let ids = actionableLayerIDs
        discardDragPreview()
        var madeID: UUID?
        perform { madeID = $0.stackSelection(ids: ids, kind: kind) }
        guard let madeID else { return }
        groupContextID = document?.parentID(of: madeID)
        selectedLayerID = madeID
        setSelection(nil, captureLayers: false)
    }

    // MARK: - Where the pieces sit when something is resized

    /// What the Layout section shows for what is picked: the layers it places,
    /// the one thing holding them, and what each row reads across them. One
    /// layer or five, this is the same reading, which is what lets one pick
    /// stretch four buttons instead of stretching them one at a time.
    var placementSelection: PlacementSelection {
        guard let document else { return .none }
        return document.placementSelection(layerIDs: orderedSelectedLayerIDs)
    }

    /// The group the picked layers sit in, or nil when they sit loose on the
    /// canvas or in more than one thing. What the Layout section asks before it
    /// offers a row about "the container", since without one there is nothing
    /// to line up against.
    var containerOfSelection: Layer? {
        placementSelection.containerID.flatMap { document?.layer(id: $0) }
    }

    /// What the Contents rows show for what is picked: the groups they speak
    /// for and what each row reads across them. One group or three, this is the
    /// same reading, which is what lets one typed gap reach three cards instead
    /// of being typed into each in turn.
    var contentsSelection: ContentsSelection {
        guard let document else { return .none }
        return document.contentsSelection(layerIDs: orderedSelectedLayerIDs,
                                          arranging: Experiments.shared.autoLayoutEnabled)
    }

    /// What a group tells everything inside it to do when it is resized.
    func setContentPlacement(id: UUID, horizontal: HorizontalPlacement?) {
        guard document?.layer(id: id)?.isGroup == true else { return }
        perform { $0.setContentPlacement(id: id, horizontal: horizontal) }
    }

    func setContentPlacement(id: UUID, vertical: VerticalPlacement?) {
        guard document?.layer(id: id)?.isGroup == true else { return }
        perform { $0.setContentPlacement(id: id, vertical: vertical) }
    }

    /// What ONE piece does, overriding the group it sits in. Nil hands the
    /// axis back to the group.
    func setPlacement(id: UUID, horizontal: HorizontalPlacement?) {
        guard document?.layer(id: id) != nil else { return }
        perform { $0.setPlacement(id: id, horizontal: horizontal) }
    }

    func setPlacement(id: UUID, vertical: VerticalPlacement?) {
        guard document?.layer(id: id) != nil else { return }
        perform { $0.setPlacement(id: id, vertical: vertical) }
    }

    /// Telling ONE piece to take the room the stack it is in has left over
    /// along the way that stack runs, or to stop and go back to the size it
    /// had before.
    func setFillsTheFlow(id: UUID, _ fills: Bool) {
        guard document?.layer(id: id) != nil else { return }
        perform { $0.setFillsTheFlow(id: id, fills) }
    }

    /// The same three edits over EVERY picked layer, in ONE undo step however
    /// many they reached. Three buttons in a bar are told to stretch once
    /// rather than three times over, and one undo puts all three back.
    func setPlacement(ids: [UUID], horizontal: HorizontalPlacement?) {
        guard !ids.isEmpty else { return }
        perform { _ = $0.setPlacement(ids: ids, horizontal: horizontal) }
    }

    func setPlacement(ids: [UUID], vertical: VerticalPlacement?) {
        guard !ids.isEmpty else { return }
        perform { _ = $0.setPlacement(ids: ids, vertical: vertical) }
    }

    func setFillsTheFlow(ids: [UUID], _ fills: Bool) {
        guard !ids.isEmpty else { return }
        perform { _ = $0.setFillsTheFlow(ids: ids, fills) }
    }

    /// The same three edits over EVERY picked group, in ONE undo step however
    /// many they reached. Two cards are told to stack their contents once
    /// rather than twice over, and one undo puts both back.
    func setContentPlacement(ids: [UUID], horizontal: HorizontalPlacement?) {
        guard !ids.isEmpty else { return }
        perform { $0.setContentPlacement(ids: ids, horizontal: horizontal) }
    }

    func setContentPlacement(ids: [UUID], vertical: VerticalPlacement?) {
        guard !ids.isEmpty else { return }
        perform { $0.setContentPlacement(ids: ids, vertical: vertical) }
    }

    func setArrangement(ids: [UUID], kind: GroupLayoutKind?) {
        guard !ids.isEmpty else { return }
        discardDragPreview()
        perform { $0.setGroupLayout(ids: ids, kind: kind) }
    }

    /// One typed number over every picked group. The change is handed each
    /// group's own layer as well, so Hug turned into Fixed holds the size each
    /// one is at rather than the first one's borrowed by the rest.
    func updateArrangement(ids: [UUID],
                           _ change: @escaping (inout GroupLayout, Layer) -> Void) {
        guard !ids.isEmpty else { return }
        perform { $0.updateGroupLayout(ids: ids, change) }
    }

    /// The same, for the numbers that are the same number on every picked
    /// group: a gap of 12 is 12 on all of them.
    func updateArrangement(ids: [UUID], _ change: @escaping (inout GroupLayout) -> Void) {
        updateArrangement(ids: ids) { layout, _ in change(&layout) }
    }

    /// A canvas click that resolved through the group walk: the layer it
    /// picked and the group it picked it inside.
    func selectLayer(_ id: UUID?, inGroup context: UUID?) {
        if groupContextID != context { groupContextID = context }
        selectedLayerID = id
        if id == nil, !multiSelectedLayerIDs.isEmpty { multiSelectedLayerIDs = [] }
    }

    /// A ⇧-click on the canvas: adds the layer to the selection, or drops it
    /// when it is already in. The canvas gesture the Layers list has always
    /// had, so picking exactly two things to group is two clicks instead of a
    /// sweep that takes in whatever else was nearby.
    ///
    /// The caller has already resolved the click at the level you are on
    /// (`PhotonzDocument.extendTarget`), so this runs the same toggle a
    /// ⌘-click on a row runs, anchor and all: carry on in the list and it
    /// picks up where the canvas left off.
    func extendSelection(toLayer id: UUID) {
        clickRow(id, .toggle, in: [])
        // Any rubber band on screen described the OLD selection. It does not
        // describe this one, so it comes down rather than lying. A pixel
        // region belongs to the region tools, not to layers: that one stays.
        if selection != nil, !selectionTargetsPixels { setSelection(nil, captureLayers: false) }
    }

    /// A ⇧-sweep on the canvas: every layer the band fully contains joins what
    /// was already picked, so a selection can be built out of two or three
    /// sweeps instead of having to be right in one. Sweeping over something
    /// already picked leaves it picked, and a sweep that catches nothing new
    /// changes nothing.
    func addSweptLayersToSelection(in region: SelectionRegion, inside context: UUID? = nil) {
        guard let document else { return }
        let was = actionableLayerIDs
        // ⇧ adds at the level you are on, the way a ⇧-click does: inside a
        // group it reaches that group's pieces, so a selection can never end
        // up made of one child and one whole layer from the top.
        let level = sweepContext(context)
        let picked = BareCanvasPress.spares
            .selection(afterSweeping: document.layerIDs(fullyInside: region.bounds, inside: level),
                       startingFrom: was)
        // Whatever the sweep caught, the band that is on screen came from an
        // EARLIER gesture and no longer describes anything: it comes down
        // before anything else, even when this sweep caught nothing new. A
        // pixel region stays put: it is the region tools' selection, not a
        // layer pick.
        if selection != nil, !selectionTargetsPixels { setSelection(nil, captureLayers: false) }
        guard picked != was else { return }
        if picked.count == 1 {
            selectedLayerID = picked.first // didSet clears any multi-selection
        } else {
            selectedLayerID = nil // didSet clears the multi-selection first
            multiSelectedLayerIDs = picked
            // A sweep has no anchor row, the same as any other marquee: the
            // next ⇧-click in the list starts over from the row it lands on.
            rowSelection = ListSelection(selected: picked)
        }
        groupContextID = level
    }

    /// Escape, one level: leaves the group you are in with that group selected.
    /// Returns false when you are already at the top, which is when Escape
    /// means what it always meant (clear the selection).
    @discardableResult
    func exitGroupContext() -> Bool {
        guard Experiments.shared.layerGroupsEnabled, let context = groupContextID,
              document?.layer(id: context) != nil else {
            groupContextID = nil
            return false
        }
        let parent = document?.parentID(of: context)
        groupContextID = parent
        selectedLayerID = context
        return true
    }

    /// Makes `ids` the selection the way a row click would: one becomes the
    /// primary selection, several the multi-selection, none clears.
    func selectLayers(_ ids: Set<UUID>) {
        // Whatever list the new selection lives in is where you now are, so a
        // duplicate made inside a group leaves you inside that group.
        groupContextID = ids.first.flatMap { document?.parentID(of: $0) }
        switch ids.count {
        case 0:
            selectLayer(nil)
        case 1:
            selectedLayerID = ids.first
        default:
            selectedLayerID = nil // didSet clears the multi-selection first
            multiSelectedLayerIDs = ids
            rowSelection = ListSelection(selected: ids)
        }
    }

    /// Layers the committed marquee fully contains — the rubber-band
    /// multi-selection. Derived from (selection, document), so there's no
    /// separate selection state to fall out of sync.
    var marqueeSelectedLayerIDs: [UUID] {
        guard let selection, let document else { return [] }
        return document.layerIDs(fullyInside: selection.bounds)
    }

    /// Batch delete (⌫ over a marquee that captured layers): all of them go in
    /// ONE undo step, then the marquee clears.
    func deleteLayers(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        discardDragPreview()
        let idSet = Set(ids)
        if let selected = selectedLayerID, idSet.contains(selected) { selectedLayerID = nil }
        perform { $0.removeLayers(ids: idSet) }
        setSelection(nil)
    }

    func duplicateLayer(id: UUID) {
        // Duplicating a member of the multi-selection (row context menu)
        // duplicates the whole selection, like Delete does.
        if multiSelectedLayerIDs.contains(id) {
            duplicateSelectedLayers()
            return
        }
        discardDragPreview()
        var copyID: UUID?
        perform { copyID = $0.duplicateLayer(id: id, offsetBy: CGPoint(x: 16, y: 16))?.id }
        selectedLayerID = copyID
    }
}
