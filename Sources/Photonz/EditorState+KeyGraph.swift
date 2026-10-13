import AppKit
import Foundation
import PhotonzCore

/// The value graph: points you add, segments you pick (task
/// `the-value-graph-lets-you-add-points-pick-the-seg`,
/// `docs/design/mocks/pages/video-animate.html`, THE GRAPH).
///
/// The click rule is the one every animated line follows (`AnimatedLine`): a
/// click picks a point or the segment between two, ⌘-click on the line adds a
/// point, Shift adds to the pick. A thin layer over `KeyGraphEdits.swift`:
/// every change goes through `perform`, so each costs one undo step.
extension EditorState {

    // MARK: Picking

    /// What is picked on a layer's lanes and graphs, as the line rule reads it.
    func linePick(layerID: UUID) -> AnimatedLinePick<KeyRef> {
        guard let keySelection, keySelection.layerID == layerID else { return AnimatedLinePick() }
        return keySelection.linePick
    }

    func pickedSegments(layerID: UUID) -> Set<KeyRef> {
        guard let keySelection, keySelection.layerID == layerID else { return [] }
        return keySelection.segments
    }

    /// A click on a segment, named by the key it starts at: it alone is
    /// picked, or with Shift it joins the pick or leaves it. A plain click
    /// also puts the playhead where it landed, so the panel's Curve row speaks
    /// for this segment.
    /// A right click picks it with `movingPlayhead` false: a right click never
    /// moves the playhead (`EditorState+TimelinePointing`).
    func pickSegment(layerID: UUID, _ ref: KeyRef, atMS ms: Int, extending: Bool, movingPlayhead: Bool = true) {
        if selectedLayerID != layerID { selectLayer(layerID) }
        if let property = document?.layer(id: layerID)?.motions?.first(where: { $0.id == ref.motionID })?.property {
            activeKeyProperty = .motion(property)
        }
        var pick = linePick(layerID: layerID)
        pick.pick(segment: ref, extending: extending)
        keySelection = KeySelection(layerID: layerID, pick)
        guard !extending, movingPlayhead else { return }
        if isDocumentPlaying { pauseDocument() }
        scrubDocument(toMS: ms)
    }

    // MARK: Adding a point

    /// ⌘-click on the line, or Add Point Here: a key at that moment holding
    /// the value the line has there, so the curve keeps its shape. It is what
    /// is picked afterwards. One undo step.
    func addKeyOnGraph(layerID: UUID, motionID: UUID, atMS ms: Int) {
        guard !isClipLocked(layerID) else { return }
        if selectedLayerID != layerID { selectLayer(layerID) }
        var made: KeyRef?
        perform { made = $0.addKeyOnCurve(layerID: layerID, motionID: motionID, atDocumentMS: ms) }
        guard let made else { return }
        keySelection = KeySelection(layerID: layerID, refs: [made])
    }

    // MARK: Dragging a point

    /// A point let go of on the graph: carried in time and, for a number, set
    /// to the value it was dropped at. One undo step, and it stays picked.
    func moveGraphKey(layerID: UUID, _ ref: KeyRef, byMS ms: Int, toValue value: Double?) {
        guard !isClipLocked(layerID) else { return }
        var landed: KeyRef?
        perform { landed = $0.moveKeyOnGraph(layerID: layerID, ref, byMS: ms, toValue: value) }
        keySelection = KeySelection(layerID: layerID, refs: [landed ?? ref])
    }

    /// The moments a point dragged on the graph lands on as it comes near:
    /// the playhead, and every other key of the layer.
    func graphKeySnapMoments(layerID: UUID, leaving ref: KeyRef) -> [Int] {
        let keys = keyLanes(layerID: layerID).flatMap(\.keys).filter { $0.ref != ref }.map(\.documentMS)
        return keys + [documentTimeMS]
    }

    // MARK: A segment's curve

    /// The segments a right click or a menu acts on: everything picked where
    /// this one is among it, and this one alone where it is not.
    private func segmentsInHand(layerID: UUID, _ ref: KeyRef) -> Set<KeyRef> {
        let picked = pickedSegments(layerID: layerID)
        return picked.contains(ref) ? picked : [ref]
    }

    func curveSegments(layerID: UUID, _ refs: Set<KeyRef>, _ curve: EasingCurve) {
        guard !isClipLocked(layerID) else { return }
        if selectedLayerID != layerID { selectLayer(layerID) }
        perform { $0.curveStretches(layerID: layerID, refs, curve) }
    }

    /// The curve every picked segment of a layer runs on, where they agree.
    func pickedSegmentsCurve(layerID: UUID) -> EasingCurve? {
        let refs = pickedSegments(layerID: layerID)
        guard !refs.isEmpty else { return nil }
        return document?.stretchesCurve(layerID: layerID, refs)
    }

    /// A right click on a segment: the shared curve list, ticked where every
    /// segment in hand agrees, then Hold and Draw a Curve, Copy and Paste
    /// Ease, Add Point Here at the moment it landed, and Delete for the
    /// points picked with it. The segment is picked, unless it already is.
    func segmentMenuRows(layerID: UUID, motionID: UUID, _ ref: KeyRef, atMS ms: Int) -> [MenuRow] {
        guard let document, !isClipLocked(layerID) else { return [] }
        if !pickedSegments(layerID: layerID).contains(ref) {
            DispatchQueue.main.async { [weak self] in
                self?.pickSegment(layerID: layerID, ref, atMS: ms, extending: false, movingPlayhead: false)
            }
        }
        let refs = segmentsInHand(layerID: layerID, ref)
        let current = document.stretchesCurve(layerID: layerID, refs)
        func row(_ curve: EasingCurve, _ title: String? = nil) -> MenuRow {
            var made = MenuRow.toggle(title ?? curve.title, isOn: current == curve) {
                self.curveSegments(layerID: layerID, refs, curve)
            }
            made.image = CurveMenuImage.image(for: curve)
            return made
        }
        var rows = EasingCurve.named.prefix(EasingCurve.standardCount).map { row($0) }
        rows.append(.separator)
        rows += EasingCurve.named.dropFirst(EasingCurve.standardCount).map { row($0) }
        rows.append(.separator)
        rows.append(row(.steps(1), "Hold"))
        if let current, current.isDrawn, !EasingCurve.named.contains(current) {
            rows.append(row(current, StretchCurve.title(current)))
        }
        rows.append(.command("Draw a Curve\u{2026}") {
            self.drawingStretchCurve = KeySelection(layerID: layerID, refs: [], segments: refs)
        })
        rows.append(.separator)
        rows.append(.command("Copy Ease", enabled: current != nil) {
            self.copiedStretchCurve = current
        })
        rows.append(.command("Paste Ease", enabled: copiedStretchCurve != nil) {
            if let copied = self.copiedStretchCurve { self.curveSegments(layerID: layerID, refs, copied) }
        })
        rows.append(.separator)
        rows.append(.command("Add Point Here") {
            self.addKeyOnGraph(layerID: layerID, motionID: motionID, atMS: ms)
        })
        let points = pickedKeys(layerID: layerID)
        rows.append(.separator)
        rows.append(.command(points.count > 1 ? "Delete \(points.count) Points" : "Delete Point",
                             enabled: !points.isEmpty, destructive: true) {
            self.keySelection = KeySelection(layerID: layerID, refs: [], segments: refs)
            self.perform { $0.removeKeys(layerID: layerID, points) }
        })
        return rows
    }

    // MARK: The Animate menu's rows for picked segments

    var hasPickedSegments: Bool { !(keySelection?.segments.isEmpty ?? true) }

    /// The curve the picked segments share, for Animate ▸ Copy Ease.
    var pickedSegmentsCurveInHand: EasingCurve? {
        guard let keySelection else { return nil }
        return pickedSegmentsCurve(layerID: keySelection.layerID)
    }

    func drawCurveForPickedSegments() {
        guard let keySelection, hasPickedSegments else { return }
        drawingStretchCurve = KeySelection(layerID: keySelection.layerID, refs: [], segments: keySelection.segments)
    }

    func copyPickedSegmentsEase() {
        if let curve = pickedSegmentsCurveInHand { copiedStretchCurve = curve }
    }

    func pastePickedSegmentsEase() {
        guard let keySelection, hasPickedSegments, let copied = copiedStretchCurve else { return }
        curveSegments(layerID: keySelection.layerID, keySelection.segments, copied)
    }

    /// A curve drawn for the segments Draw a Curve was chosen for.
    func finishDrawingStretchCurve(_ curve: EasingCurve?) {
        guard let drawing = drawingStretchCurve else { return }
        drawingStretchCurve = nil
        guard let curve else { return }
        curveSegments(layerID: drawing.layerID, drawing.segments, curve)
    }
}
