import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// Whole-layer commands: collage, merge down, rasterize, restacking, and
// promoting a selection to a layer of its own.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    // MARK: - Collage (16.9)

    /// The layers "Arrange in Collage…" would arrange: the multi-selection's
    /// image layers when it holds at least two, else every visible, unlocked
    /// image layer (so the command works straight from the menu with nothing
    /// selected — the locked Background never participates).
    var collageLayerIDs: [UUID] {
        guard let document else { return [] }
        let eligible = document.layers.filter {
            if case .image = $0.content { return $0.isVisible && !$0.isLocked }
            return false
        }.map(\.id)
        let selected = eligible.filter { multiSelectedLayerIDs.contains($0) }
        return selected.count >= 2 ? selected : eligible
    }

    var canArrangeCollage: Bool { collageLayerIDs.count >= 2 }

    /// "Arrange in Collage": absorbs `collageLayerIDs` into ONE new collage
    /// layer (their refs become slots in reading order, frame = the union of
    /// their frames, the source layers are removed) in one undo step, then
    /// selects it. The collage is live: resize reflows, slots swap by drag,
    /// photos drop in from history/Finder/other layers.
    func arrangeSelectionAsCollage() {
        guard let document else { return }
        let ids = Set(collageLayerIDs)
        guard ids.count >= 2 else { return }
        discardDragPreview()
        let participants = document.layers.filter { ids.contains($0.id) }
        guard let collageLayer = Collage.layer(absorbing: participants),
              let topIndex = document.layers.lastIndex(where: { ids.contains($0.id) }) else { return }
        // The collage takes the TOP participant's stacking slot (indices below
        // it shift down by the number of removed participants beneath it).
        let insertIndex = topIndex - (participants.count - 1)
        selectedLayerID = nil
        perform { doc in
            doc.removeLayers(ids: ids)
            doc.addLayer(collageLayer, at: insertIndex)
        }
        selectedLayerID = collageLayer.id
    }

    /// Creates an empty 2×2 collage layer centered on the canvas.
    func newEmptyCollageLayer() {
        guard let document else { return }
        discardDragPreview()
        let canvas = document.canvasSize
        let size = CGSize(width: (canvas.width * 0.6).rounded(), height: (canvas.height * 0.6).rounded())
        let frame = CGRect(x: ((canvas.width - size.width) / 2).rounded(),
                           y: ((canvas.height - size.height) / 2).rounded(),
                           width: size.width, height: size.height)
        let layer = Collage.layer(content: CollageContent(slots: [CollageSlot(), CollageSlot(),
                                                                  CollageSlot(), CollageSlot()]),
                                  frame: frame)
        perform { $0.addLayer(layer) }
        selectedLayerID = layer.id
    }

    /// A file dropped onto a collage cell: decode and fill that slot.
    func dropImage(at url: URL, intoCollage collageID: UUID, slot: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        fillCollageSlot(collageID: collageID, slot: slot, image: image)
    }

    /// Fills a collage slot with a new image (a history/Finder drop).
    func fillCollageSlot(collageID: UUID, slot: Int, image: CGImage) {
        let ref = store.register(image)
        perform { doc in
            doc.updateLayer(id: collageID) { layer in
                if var content = layer.collage {
                    content.fill(slot: slot, with: ref)
                    layer.content = .collage(content)
                }
            }
        }
    }

    /// Drops an existing photo layer into a collage slot: the layer's ref
    /// moves into the slot and the layer disappears — one undo step.
    func absorbLayer(id: UUID, intoCollage collageID: UUID, slot: Int) {
        guard id != collageID,
              let ref = document?.layers.first(where: { $0.id == id })?.imageRef else { return }
        discardDragPreview()
        if selectedLayerID == id { selectedLayerID = nil }
        perform { doc in
            doc.removeLayers(ids: [id])
            doc.updateLayer(id: collageID) { layer in
                if var content = layer.collage {
                    content.fill(slot: slot, with: ref)
                    layer.content = .collage(content)
                }
            }
        }
        selectedLayerID = collageID
    }

    /// Swaps two slots' photos (drag between cells).
    func swapCollageSlots(collageID: UUID, _ i: Int, _ j: Int) {
        guard i != j else { return }
        perform { doc in
            doc.updateLayer(id: collageID) { layer in
                if var content = layer.collage {
                    content.swapSlots(i, j)
                    layer.content = .collage(content)
                }
            }
        }
    }

    /// Inspector mutations, each one undo step.
    func updateCollage(layerID: UUID, _ mutate: (inout CollageContent) -> Void) {
        perform { doc in
            doc.updateLayer(id: layerID) { layer in
                if var content = layer.collage {
                    mutate(&content)
                    layer.content = .collage(content)
                }
            }
        }
    }

    // MARK: - Merge down (Photoshop ⌘E)

    /// ⌘E: merge the selected layer into the one below it — or the marquee
    /// multi-selection into one — as a single rasterized image layer.
    func mergeDown() {
        guard let document else { return }
        if multiSelectedLayerIDs.count >= 2 {
            mergeLayers(ids: document.layers.filter { multiSelectedLayerIDs.contains($0.id) }.map(\.id))
        } else if let id = selectedLayerID {
            mergeDown(id: id)
        }
    }

    /// Merge one specific layer into the layer directly below it (the panel's
    /// context menu). Right clicking a MEMBER of the multi-selection merges the
    /// whole selection into one, exactly as ⌘E does, because the row menu acts
    /// on the selection whenever the row you clicked is part of it
    /// (`rowMenuTargets`). A row outside the selection merges on its own.
    func mergeDown(id: UUID) {
        guard let document else { return }
        if multiSelectedLayerIDs.contains(id), multiSelectedLayerIDs.count >= 2 {
            mergeLayers(ids: document.layers.filter { multiSelectedLayerIDs.contains($0.id) }.map(\.id))
            return
        }
        guard let idx = document.index(of: id), idx > 0 else { return }
        mergeLayers(ids: [document.layers[idx - 1].id, id])
    }

    /// Whether ⌘E has something to merge (menu enablement).
    var canMergeDown: Bool {
        guard let document else { return false }
        if multiSelectedLayerIDs.count >= 2 { return true }
        guard let id = selectedLayerID, let idx = document.index(of: id), idx > 0,
              !document.layers[idx].isLocked else { return false }
        return true
    }

    /// Composites the given layers (bottom-up order) into ONE image layer, in
    /// one undo step: their styles, blend modes, and transforms bake into the
    /// bitmap; the result takes the bottom participant's slot, name, and lock
    /// (so merging into the locked Background stays a background). All
    /// participants must be visible — a hidden layer would silently rasterize
    /// to nothing. Only the bottom layer may be locked (merge INTO it).
    private func mergeLayers(ids: [UUID]) {
        guard let document, ids.count >= 2 else { return }
        let idSet = Set(ids)
        let participants = document.layers.filter { idSet.contains($0.id) }
        guard participants.count >= 2, participants.allSatisfy(\.isVisible),
              let bottom = participants.first,
              participants.dropFirst().allSatisfy({ !$0.isLocked }) else { return }

        // The merged bitmap covers everything the participants can draw:
        // transformed bounds padded by each style's reach, clamped to canvas.
        var union = CGRect.null
        for layer in participants {
            var bounds = layer.frame
            if !layer.transform.isIdentity {
                let corners = layer.transformedCorners
                if let first = corners.first {
                    bounds = corners.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                        $0.union(CGRect(origin: $1, size: .zero))
                    }
                }
            }
            let pad = layer.reachPadding
            union = union.union(bounds.insetBy(dx: -pad, dy: -pad))
        }
        let region = Geometry.clampCrop(union, toCanvas: document.canvasSize)
        guard region.width >= 1, region.height >= 1 else { return }

        // Composite ONLY the participants (over transparency), so layers in
        // between or below don't leak into the merged bitmap.
        var temp = document
        temp.layers = participants
        guard let raster = previewRenderer.rasterize(region: region, of: temp, store: store) else { return }
        let ref = store.register(raster)
        let merged = Layer(name: bottom.name, content: .image(ref), frame: region,
                           isLocked: bottom.isLocked)
        discardDragPreview()
        perform { doc in
            guard let insertAt = doc.index(of: bottom.id) else { return }
            doc.removeLayers(ids: idSet)
            doc.addLayer(merged, at: insertAt)
        }
        selectedLayerID = merged.id
    }

    // MARK: - Turn Into Picture (a shape or a piece of text → pixels)

    /// Where the "Don't ask again" answers live: one store for every question
    /// the app can be told to stop asking, so a person can read the list back
    /// and turn any of them on again (`SilencedQuestions`). Per app bundle, so
    /// the dev and probe builds keep their own answers and neither can turn a
    /// question off for the release app.
    static let silencedQuestions = SilencedQuestions(defaults: UserDefaultsSilenceDefaults())

    /// Whether "Turn Into Picture" applies from a layer ROW's menu.
    ///
    /// It asks about everything the row menu would act on — the whole selection
    /// when the row you right clicked is part of it, else that row alone
    /// (`rowMenuTargets`) — and answers yes as soon as ONE of them is a shape
    /// or a piece of text. A picture picked alongside two rectangles does not
    /// stop the rectangles turning; it is simply left where it is.
    func canRasterizeLayer(id: UUID) -> Bool {
        canRasterizeLayers(ids: rowMenuTargets(id))
    }

    /// Whether Layer ▸ Turn Into Picture has anything to act on: the whole
    /// selection, the same targets Duplicate and Delete read.
    var canRasterizeSelection: Bool { canRasterizeLayers(ids: actionableLayerIDs) }

    /// Whether any of these layers is a shape or a piece of text. Internal
    /// rather than private because the marquee's refusal pill asks it about the
    /// ONE layer the marquee hit (`raiseRegionSliceRefusal`).
    func canRasterizeLayers(ids: Set<UUID>) -> Bool {
        guard let document else { return false }
        return !document.rasterizableLayers(ids: ids).isEmpty
    }

    /// The layer row menu's Turn Into Picture, on the whole selection when the
    /// row you right clicked is one of it.
    func rasterizeLayer(id: UUID) {
        rasterizeLayers(ids: rowMenuTargets(id))
    }

    /// Layer ▸ Turn Into Picture over the selection.
    func rasterizeSelection() {
        rasterizeLayers(ids: actionableLayerIDs)
    }

    /// Asks the question, then turns the layers into pictures if the answer is
    /// yes (`RasterizePrompt`, `RasterizeQuestion`).
    ///
    /// It asks because what the command takes away is invisible: the picture is
    /// identical the instant after, and the thing that is gone is that the shape
    /// or the words could be edited at all. The question rides the window as a
    /// sheet rather than blocking the app, and it carries "Don't ask again" so
    /// somebody cutting up half a mockup is asked once and never again.
    ///
    /// With SEVERAL layers picked the sentence has one more job, which is why
    /// the plural form exists: the singular one names the layer it is about,
    /// and over three rows that is a true sentence about one of them and
    /// silence about the other two. The plural says how many change, what each
    /// kind loses, and that one undo puts them all back.
    func rasterizeLayers(ids: Set<UUID>) {
        guard let document else { return }
        let takes = document.rasterizableLayers(ids: ids)
        guard let first = takes.first else { return }
        let targets = Set(takes.map(\.id))

        // One layer asks the question it has always asked, word for word.
        guard let question = RasterizeQuestion(layers: takes) else {
            guard let prompt = RasterizePrompt(layer: first) else { return }
            askBeforeRasterizing(title: prompt.title, message: prompt.message,
                                 confirm: prompt.confirm, cancel: prompt.cancel,
                                 ids: targets)
            return
        }
        askBeforeRasterizing(title: question.title, message: question.message,
                             confirm: question.confirm, cancel: question.cancel,
                             ids: targets)
    }

    private func askBeforeRasterizing(title: String, message: String, confirm: String,
                                      cancel: String, ids: Set<UUID>) {
        guard !Self.silencedQuestions.isSilenced(.turnIntoPicture) else {
            applyRasterize(ids: ids)
            return
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: cancel)
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = RasterizePrompt.suppression
        let answer: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if alert.suppressionButton?.state == .on {
                Self.silencedQuestions.silence(.turnIntoPicture)
            }
            guard response == .alertFirstButtonReturn else { return }
            self?.applyRasterize(ids: ids)
        }
        if let window = hostWindow {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { answer(response) }
            }
        } else {
            answer(alert.runModal())
        }
    }

    /// Bakes every shape and piece of text in `ids` into pixels in ONE undo
    /// step: each layer is rendered WITH all its style effects (blur, shadow,
    /// border, corner radius, opacity) and geometry (crop, transform) into a
    /// bitmap covering its padded on-canvas footprint, that bitmap is stored,
    /// and the layer's content becomes `.image` with its now-baked style reset.
    /// Looks pixel-identical; undo restores the editable shapes. Every layer
    /// keeps its slot/name/id, and what comes out is an ordinary picture, so a
    /// marquee can take a piece out of it (`RegionTarget.canSlice`).
    ///
    /// Three picked shapes come out as THREE pictures and never as one. Making
    /// one thing out of several is Merge Down, which is a different command
    /// under a different name; this one promises that the canvas is identical
    /// the instant after and that every row is still there, and a batch that
    /// merged would break both promises at once.
    ///
    /// The baking happens BEFORE the mutation and the mutation happens once, so
    /// no half-baked state can reach the document: a layer whose bitmap could
    /// not be rendered is left as it was and the rest still turn.
    private func applyRasterize(ids: Set<UUID>) {
        guard let document else { return }
        var baked: [(id: UUID, ref: ImageRef, region: CGRect)] = []
        for layer in document.rasterizableLayers(ids: ids) {
            // The baked bitmap covers everything the layer can draw: its
            // transformed bounds padded by the style's reach (shadow/blur),
            // clamped to canvas — exactly how merge-down sizes its result, so
            // nothing is clipped.
            var bounds = layer.frame
            if !layer.transform.isIdentity {
                let corners = layer.transformedCorners
                if let first = corners.first {
                    bounds = corners.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                        $0.union(CGRect(origin: $1, size: .zero))
                    }
                }
            }
            let pad = layer.reachPadding
            let region = Geometry.clampCrop(bounds.insetBy(dx: -pad, dy: -pad),
                                            toCanvas: document.canvasSize)
            guard region.width >= 1, region.height >= 1 else { continue }

            // Composite ONLY this layer (over transparency) so nothing below
            // leaks in, and so the layers below it in the same batch cannot
            // print themselves into its bitmap.
            var temp = document
            var only = layer
            only.isVisible = true
            temp.layers = [only]
            guard let raster = previewRenderer.rasterize(region: region, of: temp, store: store)
            else { continue }
            baked.append((layer.id, store.register(raster), region))
        }
        guard !baked.isEmpty else { return }
        discardDragPreview()
        perform { doc in
            for bake in baked {
                doc.rasterizeLayer(id: bake.id, rasterized: bake.ref, frame: bake.region)
            }
        }
        // The layers kept their ids, so what was picked is still picked and
        // nothing has to be rebuilt. A single row turned from outside the
        // selection becomes the selection, which is what it did before.
        if baked.count == 1, let only = baked.first, multiSelectedLayerIDs.isEmpty {
            selectedLayerID = only.id
        }
    }

    // MARK: - Turn Into Path (a box, an oval or a line → an outline)

    /// Whether "Turn Into Path" applies from a layer ROW's menu.
    ///
    /// It asks about everything the row menu would act on — the whole selection
    /// when the row you right clicked is part of it, else that row alone
    /// (`rowMenuTargets`) — and answers yes as soon as ONE of them has an
    /// outline to find. A picture picked alongside two lines does not stop the
    /// lines converting; it is simply left where it is.
    ///
    /// The flag is part of the answer rather than a wrapper round it, so the
    /// row and the Layer menu agree without either of them having to remember
    /// to ask twice.
    func canTurnLayerIntoPath(id: UUID) -> Bool {
        canTurnLayersIntoPath(ids: rowMenuTargets(id))
    }

    /// Whether Layer ▸ Turn Into Path has anything to act on: the whole
    /// selection, the same targets Duplicate and Delete read.
    var canTurnSelectionIntoPath: Bool {
        canTurnLayersIntoPath(ids: actionableLayerIDs)
    }

    /// Whether the command applies, from ANY of its three halves: a shape with
    /// an outline to find, two outlines already drawn that could weld, or one
    /// open outline that could be shut on its own two ends.
    ///
    /// The last two are what somebody working with the PEN gets. Runs drawn
    /// end to end are the ordinary way an icon outline gets built, and until
    /// this the menu offered them nothing at all, because the gate asked only
    /// whether something still had to be turned.
    ///
    /// It does NOT ask whether their ends actually meet, or whether closing
    /// one would enclose anything. Working either out means planning the whole
    /// thing on every menu open, and a row dimmed because two points are three
    /// apart teaches nobody what to do about it. Offered and honest beats
    /// dimmed and silent: when nothing welds the line under the canvas names
    /// the gap (`PathEditHint.nothingJoined`), and when closing would paint
    /// nothing it says that instead (`PathEditHint.nothingClosed`).
    private func canTurnLayersIntoPath(ids: Set<UUID>) -> Bool {
        pathRowAction(ids: ids) != nil
    }

    /// Which of the three things the ONE row does for what is picked right now.
    ///
    /// They are one row and not three because they are one idea — make the
    /// thing picked into an outline you can fill — and because three rows a
    /// menu apart, two of them always dimmed, is how a menu stops being
    /// readable. The order is the order of how much is taken away: turning is
    /// the only one that makes a shape stop being a shape, so it wins whenever
    /// something picked still has to be turned.
    private enum PathRowAction {
        /// A box, an oval or a line becomes an outline (and welds and closes
        /// on the way, where ends meet).
        case turn
        /// Two or more outlines already drawn weld into one where their ends
        /// meet.
        case join
        /// One outline already drawn is shut on its own two ends.
        case close
    }

    private func pathRowAction(ids: Set<UUID>) -> PathRowAction? {
        guard Experiments.shared.turnIntoPathEnabled, let document, !ids.isEmpty else { return nil }
        if ids.contains(where: { document.layer(id: $0)?.canTurnIntoPath == true }) { return .turn }
        if document.openPathsThatCouldJoin(ids: ids).count >= 2 { return .join }
        // One open outline picked on its own. Until this it offered nothing at
        // all, which left the person who drew it with the Pen and pressed
        // Return holding a run that could never be filled
        // (`PathClosing.swift`).
        if !document.openPathsThatCouldClose(ids: ids).isEmpty { return .close }
        return nil
    }

    /// What the row says from a layer ROW's menu.
    func turnIntoPathMenuItem(id: UUID) -> String {
        turnIntoPathMenuItem(ids: rowMenuTargets(id))
    }

    /// What the Layer menu's row says for what is picked right now.
    var turnSelectionIntoPathMenuItem: String {
        turnIntoPathMenuItem(ids: actionableLayerIDs)
    }

    /// One command, retitled for what is picked: "Turn Into Path" while
    /// something still has to be turned, "Join Paths" when everything that can
    /// take part is already an outline.
    ///
    /// A second menu row running the same code would put a bare Join two rows
    /// away from Combine Shapes's own Join, which adds AREAS and refuses an
    /// open path outright. One row that says what it will do to THIS selection
    /// is both shorter and truer, and with nothing picked it still reads Turn
    /// Into Path, so the row stays somewhere you can learn it exists.
    private func turnIntoPathMenuItem(ids: Set<UUID>) -> String {
        // With nothing picked the row still reads Turn Into Path, so it stays
        // somewhere you can learn it exists.
        switch pathRowAction(ids: ids) ?? .turn {
        case .turn: return TurnIntoPathPrompt.menuItem
        case .join: return PathJoin.menuItem
        case .close: return PathClose.menuItem
        }
    }

    /// The layer row menu's Turn Into Path, on the whole selection when the row
    /// you right clicked is one of it.
    func turnLayerIntoPath(id: UUID) {
        turnLayersIntoPath(ids: rowMenuTargets(id))
    }

    /// Layer ▸ Turn Into Path over the selection.
    func turnSelectionIntoPath() {
        turnLayersIntoPath(ids: actionableLayerIDs)
    }

    /// Asks the question, then turns the shapes into paths if the answer is yes.
    ///
    /// It asks for the same reason "Turn Into Picture" does: the picture is
    /// identical the instant after, and what is gone is invisible — the layer
    /// has stopped being a rectangle, so the Corner Radius control has nothing
    /// left to act on. Same sheet, same "Don't ask again", its own answer.
    ///
    /// With SEVERAL shapes picked the question has one more job, and it is the
    /// reason the plural form exists: four shapes can come out as one path or
    /// as three, they can close or stay open, and two ends can be welded across
    /// a gap of a couple of points. None of that is guessable from the canvas,
    /// so the question says which it will be BEFORE the button is pressed
    /// (`TurnIntoPathQuestion`).
    func turnLayersIntoPath(ids: Set<UUID>) {
        guard Experiments.shared.turnIntoPathEnabled, let document, !ids.isEmpty else { return }
        // One outline picked on its own is the third thing this row does, and
        // it is its own operation: it lays a straight run between that
        // outline's OWN two ends, however far apart they are, where the join
        // welds different outlines to each other and only across two points.
        if pathRowAction(ids: ids) == .close {
            closeOpenPaths(ids: ids)
            return
        }
        let plan = document.turningLayersIntoPath(ids: ids).plan
        guard !plan.isEmpty else {
            // The join was offered on two outlines and found no two ends near
            // enough. Nothing changes, and rather than going quiet the line
            // under the canvas names the gap and what to do about it: that is
            // the price of offering the command without planning it first.
            if document.openPathsThatCouldJoin(ids: ids).count >= 2 {
                turnedIntoPathNotice = PathEditHint.nothingJoined()
            }
            return
        }

        // One shape asks the question it has always asked, word for word. Only
        // a SHAPE: an outline that closed on its own also takes one layer, and
        // it has no rectangle or oval to name.
        if plan.takes == 1, plan.converted == 1 {
            guard let only = ids.first(where: { document.layer(id: $0)?.canTurnIntoPath == true }),
                  let layer = document.layer(id: only),
                  let prompt = TurnIntoPathPrompt(layer: layer) else { return }
            askBeforeTurningIntoPath(title: prompt.title, message: prompt.message,
                                     confirm: prompt.confirm, cancel: prompt.cancel,
                                     ids: [only], joinOnly: false)
            return
        }
        let question = TurnIntoPathQuestion(plan: plan)
        askBeforeTurningIntoPath(title: question.title, message: question.message,
                                 confirm: question.confirm, cancel: question.cancel,
                                 ids: ids, joinOnly: plan.isJoinOnly)
    }

    private func askBeforeTurningIntoPath(title: String, message: String, confirm: String,
                                          cancel: String, ids: Set<UUID>, joinOnly: Bool) {
        guard !Self.silencedQuestions.isSilenced(.turnIntoPath) else {
            applyTurnIntoPath(ids: ids, joinOnly: joinOnly)
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: cancel)
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = TurnIntoPathPrompt.suppression
        let answer: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if alert.suppressionButton?.state == .on {
                Self.silencedQuestions.silence(.turnIntoPath)
            }
            guard response == .alertFirstButtonReturn else { return }
            self?.applyTurnIntoPath(ids: ids, joinOnly: joinOnly)
        }
        if let window = hostWindow {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { answer(response) }
            }
        } else {
            answer(alert.runModal())
        }
    }

    /// Writes the outlines in, in ONE undo step, and leaves what survives
    /// picked so its points are on it and ready to drag (`CanvasPathEdit`).
    ///
    /// Everything that was welded into another layer is gone by now, so the
    /// selection is rebuilt from the rows that are still there rather than from
    /// the ids that went in.
    private func applyTurnIntoPath(ids: Set<UUID>, joinOnly: Bool) {
        discardDragPreview()
        perform { $0.turnLayersIntoPath(ids: ids) }
        guard let document else { return }
        let alive = ids.filter { document.layer(id: $0) != nil }
            .sorted { (document.path(of: $0)?.last ?? 0) < (document.path(of: $1)?.last ?? 0) }
        multiSelectedLayerIDs = alive.count > 1 ? Set(alive) : []
        selectedLayerID = alive.last
        // ...and the chip under the canvas says what just happened, in one
        // line, so the second time somebody uses this (with the question
        // silenced) the row does not quietly change kind with nothing said.
        turnedIntoPathNotice = joinOnly
            ? PathEditHint.justJoined(paths: alive.count)
            : PathEditHint.justTurned(paths: alive.count)
    }

    // MARK: - Close Path (an outline you already finished, shut)

    /// Asks the question, then shuts the picked outlines on their own ends.
    ///
    /// It asks for a reason the other two halves do not have: a run appears on
    /// the canvas that was not there before, and how long it is depends on
    /// where you stopped drawing. The question says the gap in points, so a
    /// run forty points long is never a surprise (`ClosePathQuestion`).
    ///
    /// An outline whose points are in a line is refused rather than asked
    /// about, because closing it would leave a layer painting no pixels. The
    /// line under the canvas says why, in the Pen's own words.
    private func closeOpenPaths(ids: Set<UUID>) {
        guard let document else { return }
        let plan = document.closingPaths(ids: ids).plan
        guard let question = ClosePathQuestion(plan: plan) else {
            turnedIntoPathNotice = PathEditHint.nothingClosed()
            return
        }
        guard !Self.silencedQuestions.isSilenced(.turnIntoPath) else {
            applyClosePaths(ids: ids)
            return
        }
        let alert = NSAlert()
        alert.messageText = question.title
        alert.informativeText = question.message
        alert.addButton(withTitle: question.confirm)
        alert.addButton(withTitle: question.cancel)
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = TurnIntoPathPrompt.suppression
        let answer: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self] response in
            // One row, one "Don't ask again": somebody who ticked it on this
            // row asked not to be asked on this row, whichever of the three it
            // is doing at the time.
            if alert.suppressionButton?.state == .on {
                Self.silencedQuestions.silence(.turnIntoPath)
            }
            guard response == .alertFirstButtonReturn else { return }
            self?.applyClosePaths(ids: ids)
        }
        if let window = hostWindow {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { answer(response) }
            }
        } else {
            answer(alert.runModal())
        }
    }

    /// Writes the closed outlines in, in ONE undo step.
    ///
    /// Nothing is swallowed and nothing is renamed, so what was picked is
    /// still picked and the selection is left exactly as it was.
    private func applyClosePaths(ids: Set<UUID>) {
        discardDragPreview()
        guard let closes = document?.closingPaths(ids: ids).plan.closes, closes > 0 else { return }
        perform { $0.closePaths(ids: ids) }
        // ...and the chip says what happened and where the inside now is,
        // because closing an outline changes the picture hardly at all: one
        // straight run appears, and the Fill row turns up on the panel.
        turnedIntoPathNotice = PathEditHint.justClosed(paths: closes)
    }

    // MARK: - Two shapes become one (join, cut out, keep or drop the overlap)

    /// Whether any of the four area operations applies from a layer ROW's menu.
    ///
    /// Like Turn Into Path, it asks about everything the row menu would act on
    /// (`rowMenuTargets`), so right clicking one of three picked circles
    /// offers the commands for all three.
    func canCombineLayers(id: UUID) -> Bool {
        canCombine(ids: rowMenuTargets(id))
    }

    /// Whether Layer ▸ Combine Shapes has anything to act on: the whole
    /// selection, the same targets Duplicate and Delete read.
    var canCombineSelection: Bool { canCombine(ids: actionableLayerIDs) }

    /// Two shapes with an inside between them is the whole test. It rides on
    /// the Pen's own flag, because the result of every one of these is a path
    /// and a path you cannot reshape is a command with no payoff.
    private func canCombine(ids: Set<UUID>) -> Bool {
        guard Experiments.shared.penEnabled, let document else { return false }
        return document.combinableLayers(ids: ids).count >= 2
    }

    /// The row menu's Join, Cut Out, Keep Overlap or Drop Overlap, on the whole
    /// selection when the row you right clicked is part of it.
    func combineLayers(id: UUID, _ operation: PathCombine.Operation) {
        combine(ids: rowMenuTargets(id), operation)
    }

    /// Layer ▸ Combine Shapes ▸ … over the selection.
    func combineSelection(_ operation: PathCombine.Operation) {
        combine(ids: actionableLayerIDs, operation)
    }

    /// Runs one of the four, in ONE undo step, and leaves the result picked so
    /// its points are on it and ready to drag (`CanvasPathEdit`).
    ///
    /// There is no question first, unlike Turn Into Path. Turning a rectangle
    /// into a path takes away something invisible — the corner radius has
    /// nothing left to act on — while this takes away two shapes you can SEE
    /// and hands back one you can see, so there is nothing to warn about that
    /// the canvas does not already say. What it does need afterwards is the
    /// one line naming which shape's look survived and whether the result has
    /// a hole in it, which is what the canvas cannot show.
    ///
    /// When the answer is nothing the document is left exactly as it was and
    /// the line says why, rather than a command quietly doing nothing.
    private func combine(ids: Set<UUID>, _ operation: PathCombine.Operation) {
        guard Experiments.shared.penEnabled, let document else { return }
        let plan = document.combiningLayers(ids: ids, operation).plan
        guard plan.takes >= 2 else { return }
        // The shape at the BOTTOM of the picked ones is the row that survives,
        // and it is named before the command runs: afterwards the rows above
        // it are gone and there is nothing left to ask.
        let keeper = document.combinableLayers(ids: ids).first
        discardDragPreview()
        if plan.didAnything {
            perform { $0.combineLayers(ids: ids, operation) }
            multiSelectedLayerIDs = []
            selectedLayerID = keeper
        }
        // The pill under the canvas rather than the path chip, because the
        // sentence that matters most is the one about a combination that came
        // to NOTHING, and in that case the shapes are still shapes and the
        // path chip is not up to say it.
        raiseCanvasNotice(.shapesCombined(plan))
    }

    // MARK: - Restacking (Photoshop ⌘] ⌘[ ⇧⌘] ⇧⌘[)

    func bringLayerForward(id: UUID) { restack(id: id, .forward) }
    func sendLayerBackward(id: UUID) { restack(id: id, .backward) }
    func bringLayerToFront(id: UUID) { restack(id: id, .toFront) }
    func sendLayerToBack(id: UUID) { restack(id: id, .toBack) }

    /// Moves a layer in the stack (row context menu). A member of the
    /// multi-selection takes the whole selection with it; on its own, locked
    /// layers stay put and nothing can be pushed underneath the locked
    /// Background at the bottom.
    private func restack(id: UUID, _ step: PhotonzDocument.RestackStep) {
        if multiSelectedLayerIDs.contains(id) {
            restackSelectedLayers(step)
            return
        }
        guard let document else { return }
        var preview = document
        guard preview.restackLayers(ids: [id], step) else { return }
        discardDragPreview()
        perform { $0.restackLayers(ids: [id], step) }
    }

    /// Drag-reorder from the layers panel (SwiftUI `onMove` indices, visual
    /// top-down order). One undo step.
    func moveLayers(visualSources: IndexSet, visualDestination: Int) {
        discardDragPreview()
        perform { $0.moveLayers(visualSources: visualSources, visualDestination: visualDestination) }
    }

    // MARK: - Promote selection

    /// ⌘J, "New Layer via Copy": **it takes the layer you picked, and a
    /// marquee crops it** — the same rule ⌘C follows (`CopyRoute`), so the
    /// same marquee gives you the same pixels whichever way you take them.
    ///
    /// With a layer picked and a marquee up, the new layer holds that layer's
    /// pixels inside the marquee and nothing from the layers around it. With a
    /// layer picked and no marquee, ⌘J duplicates it, as it always has. With
    /// nothing picked there is nothing to prefer, so the marquee's worth of
    /// every layer flattened together is promoted, also as before.
    func newLayerViaCopy() {
        // Off, the old rule stands: a marquee supersedes the layer, so ⌘J
        // promotes the flattened region and the layer you picked is baked into
        // it along with everything behind it.
        guard Experiments.shared.copyPicksYourLayerEnabled else {
            if selection != nil { promoteSelectionToLayer() } else { duplicateSelectedLayers() }
            return
        }
        switch CopyRoute.copy(picked: pickedLayerID, pixelRegion: hasPixelRegion,
                              hasDocument: document != nil) {
        case .nothing, .mergedImage: return
        case .layer: duplicateSelectedLayers()
        case .layerRegion(let id): promotePickedLayerRegion(id)
        case .mergedRegion:
            if selection != nil { promoteSelectionToLayer() } else { duplicateSelectedLayers() }
        }
    }

    /// The picked layer's pixels inside the marquee, stacked as a new layer of
    /// their own (one undo step) and left selected with the marquee cleared,
    /// exactly like the merged promote below.
    ///
    /// The piece comes from the same place ⌘C's does (`layerRegion`), so it is
    /// trimmed to what is actually drawn there: a marquee flung round a small
    /// drawing makes a layer the size of the drawing, whose handles hug it,
    /// rather than a big transparent box. A marquee that misses the layer makes
    /// NOTHING and beeps — an invisible new layer is worse than an honest
    /// refusal, and it is what ⌘C does with the same marquee.
    private func promotePickedLayerRegion(_ id: UUID) {
        guard let document, let selection, let source = document.layer(id: id) else { return }
        guard let piece = previewRenderer.layerRegion(of: id, in: document, store: store,
                                                      path: selection.path) else {
            NSSound.beep() // nothing of that layer is inside the marquee
            return
        }
        // Named the way duplicating that layer names it — an app-written name
        // takes the next number, a name a person typed gains "copy" — so the
        // panel reads "Rectangle 2" over "Rectangle" rather than filing it as
        // an anonymous "Promoted Layer".
        let name = LayerNaming.copyName(of: source.name,
                                        taken: Set(document.allLayers.map(\.name)))
        let ref = store.register(piece.image)
        var newID: UUID?
        perform { newID = $0.promoteRegionToLayer(region: piece.frame, rasterized: ref, name: name).id }
        self.selection = nil // like Photoshop's Layer via Copy, ⌘J consumes the selection
        selectedLayerID = newID
    }

    /// Every layer flattened together inside the marquee, rasterized from the
    /// current composite and stacked as a new image layer (one undo step). The
    /// new layer is selected; the marquee clears — it has done its job.
    ///
    /// This is the nothing-picked half of ⌘J (`newLayerViaCopy`).
    func promoteSelectionToLayer() {
        guard let document, let selection else { return }
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        let raster: CGImage?
        let frame: CGRect
        if selectionTargetsPixels {
            // Pixel region: the promoted bitmap is clipped to the path —
            // transparent outside a wand blob or ellipse.
            frame = selection.path.boundingBoxOfPath.integral.intersection(canvas)
            raster = previewRenderer.rasterize(region: canvas, of: document, store: store)
                .flatMap { RegionOps.extracted($0, path: selection.path) }
        } else {
            frame = Geometry.pixelAligned(selection.bounds)
            raster = previewRenderer.rasterize(region: frame, of: document, store: store)
        }
        guard let raster, !frame.isNull else { return }
        let ref = store.register(raster)
        var newID: UUID?
        perform { newID = $0.promoteRegionToLayer(region: frame, rasterized: ref, name: "Promoted Layer").id }
        self.selection = nil // like Photoshop's Layer via Copy, ⌘J consumes the selection
        selectedLayerID = newID
    }

    /// One-click blur-behind: a single full-canvas rasterization becomes a
    /// blurred backdrop layer plus a sharp cutout cropped to the selection
    /// (one undo step). The focus layer ends up selected so its blur radius
    /// or crop can be adjusted immediately.
    func blurBehindSelection() {
        guard let document, let region = selection.map({ Geometry.pixelAligned($0.bounds) }),
              let raster = previewRenderer.rasterize(region: CGRect(origin: .zero, size: document.canvasSize),
                                                     of: document, store: store) else { return }
        let ref = store.register(raster)
        var focusID: UUID?
        perform { focusID = $0.blurBehind(selection: region, rasterized: ref).focus.id }
        selection = nil
        selectedLayerID = focusID
    }
}
