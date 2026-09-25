import AppKit
import Foundation
import PhotonzCore
import PhotonzRender

// Fixing a caption one word at a time (`CaptionWordEdits.swift`,
// `docs/design/mocks/pages/video-captions.html`, the Words lane).
//
// A word is opened for typing by a double click on it, on the picture or on
// its chip in the Words lane. Return or a click away keeps what was typed,
// Escape throws it away, and Tab and Shift-Tab keep what was typed and open the
// next or previous word, so a run of typos is fixed without the mouse. On the
// lane a chip is dragged to retime the word and the ones after it, and its
// edges stretch it. Every one of those is one step to undo.

/// The word open for typing, and where its field is.
struct CaptionWordEditSession: Equatable {
    enum Place: Equatable { case canvas, lane }
    var ref: CaptionWordRef
    var place: Place
    /// The word as it was when the field opened, which is what the field
    /// starts out holding.
    var original: String
}

/// A word chip under a hand on the Words lane.
struct CaptionWordDragSession: Equatable {
    var ref: CaptionWordRef
    var grab: CaptionWordGrab
    /// Where the hand has it, and where that lands once snapped and held
    /// between the words either side.
    var handMS: Int
    var landedMS: Int
    /// What a moving edge snaps to: the playhead and every edge that is not
    /// moving.
    var targets: [Int]
    /// The word as it was taken hold of.
    var word: TranscribedWord
}

extension EditorState {

    var canEditCaptionWords: Bool {
        Experiments.shared.captionsFromTheSoundEnabled && hasCaptions && !isWritingCaptions
    }

    // MARK: - The Words lane's chips

    /// One chip on the Words lane: which word it is, and when it is said now.
    struct CaptionWordChip {
        let ref: CaptionWordRef
        let word: TranscribedWord
    }

    /// Every word under these cues, where it now sits in time, for the Words
    /// lane. A word chip in the hand is drawn where the hand has it.
    func captionWordChips(cueIDs: [UUID]) -> [CaptionWordChip] {
        guard let document = shownDocument else { return [] }
        // One pass over the document, not a search per cue: a long talk has
        // 170 cues, and this is asked on every step of the playhead.
        let wanted = Set(cueIDs)
        var chips: [UUID: [CaptionWordChip]] = [:]
        document.forEachLayer { layer in
            guard wanted.contains(layer.id), let time = layer.time,
                  let cue = document.captionCue(of: layer) else { return }
            chips[layer.id] = CaptionCue.words(cue.words, fittedTo: time).enumerated().map {
                CaptionWordChip(ref: CaptionWordRef(cueID: layer.id, index: $0.offset), word: $0.element)
            }
        }
        return cueIDs.flatMap { chips[$0] ?? [] }
    }

    /// One word as it sits now.
    func captionWord(_ ref: CaptionWordRef) -> TranscribedWord? {
        guard let words = document?.captionWordsAsShown(of: ref.cueID),
              words.indices.contains(ref.index) else { return nil }
        return words[ref.index]
    }

    // MARK: - Typing one word

    /// Open one word for typing, where it was double clicked.
    func beginEditingCaptionWord(_ ref: CaptionWordRef, place: CaptionWordEditSession.Place) {
        guard canEditCaptionWords, let word = captionWord(ref) else { return }
        cancelCaptionWordDrag()
        pauseDocument()
        // On the picture, the word has to be ON the picture: a word stepped to
        // with Tab that is not on screen yet brings the playhead to it.
        if place == .canvas, !isOnScreen(ref) {
            documentTimeMS = min(max(0, word.startMS), lastDocumentTimeMS)
            documentMomentChanged()
        }
        if selectedLayerID != ref.cueID { selectLayer(ref.cueID) }
        captionWordEdit = CaptionWordEditSession(ref: ref, place: place, original: word.text)
    }

    /// Return, or a click away: keep what was typed.
    func commitCaptionWordEdit(_ typed: String) {
        guard let session = captionWordEdit else { return }
        captionWordEdit = nil
        write(typed, over: session)
    }

    /// Escape: the word stays as it was.
    func cancelCaptionWordEdit() {
        captionWordEdit = nil
    }

    /// Tab and Shift-Tab: keep what was typed and open the next or previous
    /// word, running on into the next line.
    func stepCaptionWordEdit(_ typed: String, by step: Int) {
        guard let session = captionWordEdit else { return }
        let pieces = typed.split(whereSeparator: \.isWhitespace).count
        let changed = write(typed, over: session)
        // A word typed as two is two words now, and one typed as nothing is
        // none: step on from the last of what is there.
        var from = session.ref
        if changed, step > 0 { from.index += pieces - 1 }
        guard let document, let next = document.captionWord(from: from, step: step) else {
            captionWordEdit = nil
            return
        }
        beginEditingCaptionWord(next, place: session.place)
    }

    @discardableResult
    private func write(_ typed: String, over session: CaptionWordEditSession) -> Bool {
        guard typed != session.original, var probe = document,
              probe.setCaptionWord(session.ref, to: typed) else { return false }
        perform { _ = $0.setCaptionWord(session.ref, to: typed) }
        documentMomentChanged()
        return true
    }

    private func isOnScreen(_ ref: CaptionWordRef) -> Bool {
        guard let time = document?.layer(id: ref.cueID)?.time else { return false }
        return documentTimeMS >= time.inMS && documentTimeMS < time.outMS
    }

    // MARK: - On the picture

    /// The caption word under a point on the picture, if there is one.
    func captionWord(atCanvasPoint point: CGPoint) -> CaptionWordRef? {
        guard canEditCaptionWords, let shown = canvasGeometryDocument else { return nil }
        for layer in shown.captionLayers.reversed() where layer.isVisible {
            guard let placed = shown.canvasLayer(id: layer.id), placed.frame.contains(point),
                  case .text(let text) = placed.content else { continue }
            let origin = placed.frame.origin
            let rects = TextRasterizer.wordRects(text, size: placed.frame.size).map {
                $0?.offsetBy(dx: origin.x, dy: origin.y)
            }
            if let index = CaptionWordHit.index(at: point, in: rects, slack: text.fontSize * 0.35) {
                return CaptionWordRef(cueID: layer.id, index: index)
            }
        }
        return nil
    }

    /// A double click on the picture: open the word under it, if it is a word
    /// of a caption. Nothing else is touched when it is not.
    func editCaptionWord(atCanvasPoint point: CGPoint) -> Bool {
        guard let ref = captionWord(atCanvasPoint: point) else { return false }
        beginEditingCaptionWord(ref, place: .canvas)
        return true
    }

    /// Where the word open for typing on the picture is drawn, in document
    /// points, and the size its letters are set at.
    var captionWordCanvasPlace: (rect: CGRect, text: TextContent)? {
        guard let session = captionWordEdit, session.place == .canvas,
              let placed = canvasGeometryDocument?.canvasLayer(id: session.ref.cueID),
              case .text(let text) = placed.content else { return nil }
        let rects = TextRasterizer.wordRects(text, size: placed.frame.size)
        guard rects.indices.contains(session.ref.index), let rect = rects[session.ref.index] else { return nil }
        return (rect.offsetBy(dx: placed.frame.minX, dy: placed.frame.minY), text)
    }

    // MARK: - What a right click on a word does

    /// The right click menu on one word, on the picture or on the Words lane.
    /// `atMS` is where along the word the click was, for Split Here.
    func captionWordMenuRows(_ ref: CaptionWordRef, place: CaptionWordEditSession.Place,
                             atMS: Int? = nil) -> [MenuRow] {
        guard let word = captionWord(ref) else { return [] }
        var rows: [MenuRow] = [
            .command("Edit Word") { self.beginEditingCaptionWord(ref, place: place) },
        ]
        if word.text.count >= 2 {
            rows.append(.command("Split Here") { self.splitCaptionWord(ref, atMS: atMS) })
        }
        if canMergeCaptionWord(ref) {
            rows.append(.command("Merge with Next") { self.mergeCaptionWordWithNext(ref) })
        }
        rows.append(.command("Delete Word", destructive: true) { self.deleteCaptionWord(ref) })
        rows.append(.separator)
        rows.append(.command("Move to Next Line") { self.moveCaptionWordToNextLine(ref) })
        rows.append(.command("Play From Here") { self.playFromCaptionWord(ref) })
        return rows
    }

    /// A right click on the picture that lands on a word of a caption.
    func captionWordMenuRows(atCanvasPoint point: CGPoint?) -> [MenuRow]? {
        guard let point, let ref = captionWord(atCanvasPoint: point) else { return nil }
        return captionWordMenuRows(ref, place: .canvas)
    }

    /// **Split Here.** At the moment clicked, or in the middle.
    func splitCaptionWord(_ ref: CaptionWordRef, atMS: Int? = nil) {
        edit { $0.splitCaptionWord(ref, atMS: atMS) }
    }

    func canMergeCaptionWord(_ ref: CaptionWordRef) -> Bool {
        guard let words = document?.captionWordsAsShown(of: ref.cueID) else { return false }
        return ref.index + 1 < words.count
    }

    /// **Merge with Next.**
    func mergeCaptionWordWithNext(_ ref: CaptionWordRef) {
        edit { $0.mergeCaptionWordWithNext(ref) }
    }

    /// **Delete Word.**
    func deleteCaptionWord(_ ref: CaptionWordRef) {
        edit { $0.deleteCaptionWord(ref) }
    }

    /// **Move to Next Line.**
    func moveCaptionWordToNextLine(_ ref: CaptionWordRef) {
        edit { $0.moveCaptionWordsToNextCue(from: ref) }
    }

    /// **Play From Here.**
    func playFromCaptionWord(_ ref: CaptionWordRef) {
        guard let word = captionWord(ref) else { return }
        moveDocumentPlayhead(toMS: word.startMS)
        playDocument()
    }

    private func edit(_ change: @escaping (inout PhotonzDocument) -> Bool) {
        guard canEditCaptionWords, var probe = document, change(&probe) else { return }
        captionWordEdit = nil
        perform { _ = change(&$0) }
        documentMomentChanged()
    }

    // MARK: - A word chip under the hand

    /// Take hold of a word chip, or one of its edges.
    func beginCaptionWordDrag(_ ref: CaptionWordRef, grab: CaptionWordGrab) {
        // Nothing on a locked track moves (`DocumentTracks.swift`).
        guard canEditCaptionWords, let document, let word = captionWord(ref),
              !document.isClipOnLockedTrack(ref.cueID) else { return }
        captionWordEdit = nil
        pauseDocument()
        var targets = [documentTimeMS]
        let cues = document.captionLayers.map(\.id)
        if let at = cues.firstIndex(of: ref.cueID) {
            for cue in cues[max(0, at - 1)...min(cues.count - 1, at + 1)] {
                for (index, other) in (document.captionWordsAsShown(of: cue) ?? []).enumerated()
                where !(cue == ref.cueID && index == ref.index) {
                    targets += [other.startMS, other.endMS]
                }
            }
        }
        captionWordDrag = CaptionWordDragSession(ref: ref, grab: grab, handMS: 0, landedMS: 0,
                                                 targets: targets, word: word)
        watchForCaptionWordEscape()
    }

    /// The hand moved. Nothing is written down: the lane and the picture both
    /// read the landing, so they follow at once and the drag is still one step
    /// to undo. The grab can change mid drag, as Shift or Command go down.
    func updateCaptionWordDrag(byMS delta: Int, grab: CaptionWordGrab? = nil) {
        guard var session = captionWordDrag, let document else { return }
        if let grab, session.grab != .start, session.grab != .end { session.grab = grab }
        session.handMS = delta
        let edges: [Int] = switch session.grab {
        case .start: [session.word.startMS]
        case .end: [session.word.endMS]
        case .carryRest, .carryTrack, .alone: [session.word.startMS, session.word.endMS]
        }
        let snapped = CaptionWordSnap.snapped(deltaMS: delta, edges: edges, targets: session.targets,
                                              withinMS: clipSnapMS)
        let range = document.captionWordDragRange(session.ref, grab: session.grab) ?? 0...0
        session.landedMS = min(max(snapped, range.lowerBound), range.upperBound)
        captionWordDrag = session
        rerender()
    }

    /// Let go: one step for undo covering the whole drag.
    func commitCaptionWordDrag() {
        stopWatchingForCaptionWordEscape()
        guard let session = captionWordDrag else { return }
        captionWordDrag = nil
        guard session.landedMS != 0 else {
            documentMomentChanged()
            return
        }
        perform { $0.dragCaptionWord(session.ref, grab: session.grab, byMS: session.landedMS) }
        documentMomentChanged()
    }

    /// Escape, or a drag that went nowhere. Costs nothing.
    func cancelCaptionWordDrag() {
        stopWatchingForCaptionWordEscape()
        guard captionWordDrag != nil else { return }
        captionWordDrag = nil
        documentMomentChanged()
    }

    /// The document as the hand has it: the chip in the hand where it is being
    /// dragged to.
    func withDraggedCaptionWord(_ document: PhotonzDocument) -> PhotonzDocument {
        guard let session = captionWordDrag, session.landedMS != 0 else { return document }
        var document = document
        document.dragCaptionWord(session.ref, grab: session.grab, byMS: session.landedMS)
        return document
    }

    /// What the drag is doing, said in one line while it is in the hand.
    var captionWordDragReadout: String? {
        guard let session = captionWordDrag else { return nil }
        let seconds = String(format: "%+.2fs", Double(session.landedMS) / 1000)
        let what: String = switch session.grab {
        case .carryRest: "with the rest of the line"
        case .carryTrack: "with every later line"
        case .alone: "alone"
        case .start, .end: "stretched"
        }
        return "\(session.word.text) \(seconds) \(what)"
    }

    private func watchForCaptionWordEscape() {
        guard captionWordEscapeWatch == nil else { return }
        captionWordEscapeWatch = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, captionWordDrag != nil else { return event }
            cancelCaptionWordDrag()
            return nil
        }
    }

    private func stopWatchingForCaptionWordEscape() {
        if let watch = captionWordEscapeWatch { NSEvent.removeMonitor(watch) }
        captionWordEscapeWatch = nil
    }
}
