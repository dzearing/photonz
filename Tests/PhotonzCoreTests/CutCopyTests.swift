import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// When an edited recording can go out by copying the stretches it keeps, and
/// how the copy is laid out frame by frame (`CutCopy.swift`).
struct CutCopyTests {

    private func recordingDocument(durationMS: Int = 4000,
                                   size: CGSize = CGSize(width: 1280, height: 720),
                                   hasSound: Bool = true) -> PhotonzDocument {
        let movie = MovieRef(pixelSize: size, durationMS: durationMS, hasSound: hasSound)
        return .recording(movie, name: "Screen Recording")
    }

    private func whole(_ document: PhotonzDocument) -> Range<Int> {
        document.exportRangeMS(.whole)
    }

    /// The recording cut at each moment, and the pieces at `drop` thrown away.
    private func cut(_ document: PhotonzDocument, at moments: [Int], dropping drop: [Int]) -> PhotonzDocument {
        var document = document
        let id = document.layers[0].id
        for ms in moments { let done = document.splitClip(id, atMS: ms); #expect(done) }
        for index in drop.sorted(by: >) { let done = document.removeClipPiece(id, at: index); #expect(done) }
        return document
    }

    // MARK: - Which documents are nothing but cuts

    @Test func aRecordingJustOpenedIsOneStretchOfItself() {
        let document = recordingDocument()
        let pieces = document.copyablePieces(in: whole(document))
        #expect(pieces?.sourceRangesMS == [0..<4000])
        #expect(pieces?.lengthMS == 4000)
    }

    @Test func piecesThrownAwayLeaveTheStretchesKept() {
        let document = cut(recordingDocument(), at: [1000, 2500], dropping: [1])
        #expect(document.documentDurationMS == 2500)
        let pieces = document.copyablePieces(in: whole(document))
        #expect(pieces?.sourceRangesMS == [0..<1000, 2500..<4000])
        #expect(pieces?.lengthMS == 2500)
    }

    @Test func aTrimmedRecordingIsTheStretchItKeeps() {
        var document = recordingDocument()
        let id = document.layers[0].id
        let done = document.trimClipStart(id, ofPiece: 0, byMS: 500); #expect(done)
        let trimmed = document.trimClipEnd(id, ofPiece: 0, byMS: -1000); #expect(trimmed)
        let pieces = document.copyablePieces(in: whole(document))
        #expect(pieces?.sourceRangesMS == [500..<3000])
    }

    @Test func piecesCarriedIntoAnotherOrderAreCopiedInThatOrder() {
        var document = cut(recordingDocument(), at: [1000], dropping: [])
        let done = document.moveClipPiece(document.layers[0].id, from: 1, to: 0); #expect(done)
        let pieces = document.copyablePieces(in: whole(document))
        #expect(pieces?.sourceRangesMS == [1000..<4000, 0..<1000])
    }

    @Test func theInAndOutMarksKeepOnlyWhatIsBetweenThem() {
        var document = cut(recordingDocument(), at: [1000, 2500], dropping: [1])
        // On the timeline: 0..<1000 plays 0..<1000 of the file, 1000..<2500
        // plays 2500..<4000.
        document.setMarkIn(atMS: 500)
        document.setMarkOut(atMS: 2000)
        let span = document.exportRangeMS(.marked)
        #expect(span == 500..<2000)
        let pieces = document.copyablePieces(in: span)
        #expect(pieces?.sourceRangesMS == [500..<1000, 2500..<3500])
        #expect(pieces?.lengthMS == 1500)
    }

    @Test func musicUnderTheCutsStillCopiesThePicture() {
        var document = cut(recordingDocument(), at: [1000], dropping: [0])
        let music = Layer.sound(SoundRef(id: UUID(), durationMS: 9000), name: "Music",
                                time: LayerTime(inMS: 0, outMS: 3000, sourceInMS: 0, sourceLengthMS: 9000))
        document.layers.append(music)
        #expect(document.copyablePieces(in: whole(document))?.sourceRangesMS == [1000..<4000])
    }

    @Test func soundTakenOffThePictureStillCopiesThePicture() {
        let document = cut(recordingDocument(), at: [1000], dropping: [0])
        let split = document.detachingSound(ofLayer: document.layers[0].id)
        #expect(split != nil)
        guard let detached = split?.document else { return }
        #expect(detached.layers.count == 2)
        #expect(detached.copyablePieces(in: whole(detached))?.sourceRangesMS == [1000..<4000])
    }

    @Test func aQuieterClipStillCopiesThePicture() {
        var document = cut(recordingDocument(), at: [1000], dropping: [0])
        document.layers[0].setSoundLevel(AudioLevel(gain: 0.5))
        #expect(document.copyablePieces(in: whole(document)) != nil)
    }

    @Test func aHeldFrameHasToBeDrawn() {
        var document = recordingDocument()
        let done = document.holdFrame(document.layers[0].id, atMS: 1000); #expect(done)
        #expect(document.copyablePieces(in: whole(document)) == nil)
    }

    @Test func aPieceAtAnotherSpeedHasToBeDrawn() {
        var document = cut(recordingDocument(), at: [1000], dropping: [])
        let done = document.setClipSpeed(document.layers[0].id, ofPiece: 1, percent: 200); #expect(done)
        #expect(document.copyablePieces(in: whole(document)) == nil)
    }

    @Test func aTransitionOnACutHasToBeDrawn() {
        var document = cut(recordingDocument(), at: [2000], dropping: [])
        let done = document.setClipTransition(document.layers[0].id, atCut: 1,
                                           to: ClipTransition(kind: .dipToBlack, lengthMS: 400)); #expect(done)
        #expect(document.copyablePieces(in: whole(document)) == nil)
    }

    @Test func anythingDrawnOverThePictureHasToBeDrawn() {
        var document = cut(recordingDocument(), at: [1000], dropping: [0])
        document.layers.append(Layer(name: "Arrow",
                                     content: .image(ImageRef(pixelSize: CGSize(width: 100, height: 100))),
                                     frame: CGRect(x: 10, y: 10, width: 100, height: 100)))
        #expect(document.copyablePieces(in: whole(document)) == nil)
    }

    @Test func aStyledMovedOrHiddenClipHasToBeDrawn() {
        var faded = cut(recordingDocument(), at: [1000], dropping: [0])
        faded.layers[0].style.opacity = 0.5
        #expect(faded.copyablePieces(in: whole(faded)) == nil)

        var moved = cut(recordingDocument(), at: [1000], dropping: [0])
        moved.layers[0].frame = CGRect(x: 40, y: 0, width: 1280, height: 720)
        #expect(moved.copyablePieces(in: whole(moved)) == nil)

        var cropped = cut(recordingDocument(), at: [1000], dropping: [0])
        cropped.layers[0].crop = CGRect(x: 0, y: 0, width: 640, height: 360)
        #expect(cropped.copyablePieces(in: whole(cropped)) == nil)

        var hidden = cut(recordingDocument(), at: [1000], dropping: [0])
        hidden.layers[0].isVisible = false
        #expect(hidden.copyablePieces(in: whole(hidden)) == nil)
    }

    @Test func aZoomOrClickEffectsHaveToBeDrawn() {
        var zoomed = cut(recordingDocument(), at: [1000], dropping: [0])
        let zoom = zoomed.addZoom(toClip: zoomed.layers[0].id, atTimeMS: 500, around: nil)
        #expect(zoom != nil)
        #expect(zoomed.copyablePieces(in: whole(zoomed)) == nil)

        var clicked = cut(recordingDocument(), at: [1000], dropping: [0])
        clicked.layers[0].clickEffect = ClickEffect(isOn: true)
        #expect(clicked.copyablePieces(in: whole(clicked)) == nil)
    }

    @Test func aBiggerCanvasHasToBeDrawn() {
        var document = cut(recordingDocument(), at: [1000], dropping: [0])
        document.canvasSize = CGSize(width: 1920, height: 1080)
        #expect(document.copyablePieces(in: whole(document)) == nil)
    }

    @Test func aDocumentRunningPastItsClipHasToBeDrawn() {
        var document = cut(recordingDocument(), at: [1000], dropping: [0])
        document.durationMS = 5000
        #expect(document.copyablePieces(in: whole(document)) == nil)
    }

    @Test func aPictureIsNotARecording() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [
            Layer(name: "Shape", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                  frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
        ])
        #expect(document.copyablePieces(in: 0..<1000) == nil)
    }

    // MARK: - Laying the copy out

    /// A file the way a screen recording is stored: a key frame every
    /// `gop` frames, each `step` ticks long, with two frames of reordering
    /// (an I, then a P, then the two Bs before it), in decode order.
    private func storedFrames(count: Int, gop: Int, step: Int64 = 10,
                              reorders: Bool = true) -> [CutCopyPlan.StoredFrame] {
        var frames: [CutCopyPlan.StoredFrame] = []
        var start = 0
        while start < count {
            let end = min(count, start + gop)
            // Display order inside the group, rearranged into decode order:
            // I0, P3, B1, B2, P6, B4, B5, ...
            var order: [Int] = [start]
            var next = start + 1
            while next < end {
                let anchor = min(end - 1, next + 2)
                order.append(anchor)
                if reorders { for b in next..<anchor { order.append(b) } } else {
                    order.removeLast()
                    for f in next...anchor { order.append(f) }
                }
                next = anchor + 1
            }
            for (decodeIndex, shown) in order.enumerated() {
                let delay: Int64 = reorders ? 2 * step : 0
                frames.append(CutCopyPlan.StoredFrame(
                    showsAt: Int64(shown) * step,
                    decodesAt: Int64(start + decodeIndex) * step - delay,
                    isKey: shown == start))
            }
            start = end
        }
        return frames
    }

    @Test func theWholeFileIsCopiedWithoutDrawingAFrame() throws {
        let frames = storedFrames(count: 90, gop: 30)
        let plan = try #require(CutCopyPlan.make(frames: frames, pieces: [0..<900]))
        #expect(plan.renderedFrames == 0)
        #expect(plan.copiedFrames == 90)
        #expect(plan.durationTicks == 900)
    }

    @Test func aCutOnAKeyFrameCopiesBothSides() throws {
        let frames = storedFrames(count: 90, gop: 30)
        // Keep 0..<300 and 600..<900: both whole groups of pictures.
        let plan = try #require(CutCopyPlan.make(frames: frames, pieces: [0..<300, 600..<900]))
        #expect(plan.renderedFrames == 0)
        #expect(plan.copiedFrames == 60)
        #expect(plan.durationTicks == 600)
        // The second piece starts where the first one ends.
        let shown = plan.placed.map(\.showsAt).sorted()
        #expect(shown == (0..<60).map { Int64($0) * 10 })
    }

    @Test func aCutBetweenKeyFramesDrawsOnlyUpToTheNextKeyFrame() throws {
        let frames = storedFrames(count: 90, gop: 30)
        // From frame 35 to the end: frames 35..<60 drawn again, 60..<90 copied.
        let plan = try #require(CutCopyPlan.make(frames: frames, pieces: [350..<900]))
        #expect(plan.renderedFrames == 25)
        #expect(plan.copiedFrames == 30)
        #expect(plan.durationTicks == 550)
        guard case .render(let group, let drawn) = plan.runs.first else {
            Issue.record("the piece should open on frames drawn again"); return
        }
        // The decoder starts at the key frame before the cut.
        #expect(frames[group.lowerBound].isKey)
        #expect(frames[group.lowerBound].showsAt == 300)
        #expect(drawn.first?.showsAt == 0)
        #expect(drawn.map { frames[$0.index].showsAt } == (35..<60).map { Int64($0) * 10 })
    }

    @Test func aPieceEndingBetweenKeyFramesDrawsItsLastFramesAgain() throws {
        let frames = storedFrames(count: 90, gop: 30)
        // 0..<450: the first group copied, 30..<45 drawn (the group they sit in
        // reaches past the end, and its later frames are what its Bs lean on).
        let plan = try #require(CutCopyPlan.make(frames: frames, pieces: [0..<450]))
        #expect(plan.copiedFrames == 30)
        #expect(plan.renderedFrames == 15)
        #expect(plan.durationTicks == 450)
    }

    @Test func aPieceInsideOneGroupIsDrawnWhole() throws {
        let frames = storedFrames(count: 90, gop: 30)
        let plan = try #require(CutCopyPlan.make(frames: frames, pieces: [420..<480]))
        #expect(plan.copiedFrames == 0)
        #expect(plan.renderedFrames == 6)
        #expect(plan.durationTicks == 60)
    }

    @Test func aCutBetweenTwoFramesStartsOnTheOneShowingThen() throws {
        let frames = storedFrames(count: 90, gop: 30)
        // 355 falls inside frame 35 (350..<360): that frame opens the piece, at
        // the piece's very start.
        let plan = try #require(CutCopyPlan.make(frames: frames, pieces: [355..<600]))
        let first = try #require(plan.placed.min { $0.showsAt < $1.showsAt })
        #expect(frames[first.index].showsAt == 350)
        #expect(first.showsAt == 0)
        // The next one keeps its distance from the cut: 360 is 5 ticks in.
        let second = plan.placed.map(\.showsAt).sorted()[1]
        #expect(second == 5)
    }

    @Test func decodeTimesAlwaysClimbAndNeverPassTheirPictures() throws {
        let frames = storedFrames(count: 300, gop: 30)
        let pieces: [Range<Int64>] = [55..<725, 1210..<1500, 2995..<2999, 1500..<2400, 0..<20]
        let plan = try #require(CutCopyPlan.make(frames: frames, pieces: pieces))
        let written = plan.placed
        for (one, next) in zip(written, written.dropFirst()) {
            #expect(one.decodesAt < next.decodesAt)
        }
        for frame in written { #expect(frame.decodesAt <= frame.showsAt) }
        // Nothing is crammed in a tick behind its neighbour, which a player
        // that counts in coarser steps reads as two frames decoded at once.
        let gaps = zip(written, written.dropFirst()).map { $1.decodesAt - $0.decodesAt }
        #expect(gaps.filter { $0 < 3 }.isEmpty, "decode gaps \(gaps)")
        #expect(plan.durationTicks == pieces.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) })
        // No two pictures land on the same moment, and none past the end.
        let shown = written.map(\.showsAt)
        #expect(Set(shown).count == shown.count)
        #expect(shown.allSatisfy { $0 >= 0 && $0 < plan.durationTicks })
    }

    @Test func aFileWithoutReorderingCopiesTheSameWay() throws {
        let frames = storedFrames(count: 90, gop: 30, reorders: false)
        let plan = try #require(CutCopyPlan.make(frames: frames, pieces: [350..<900]))
        #expect(plan.renderedFrames == 25)
        #expect(plan.copiedFrames == 30)
    }

    @Test func aDecodeClockRunningAheadOfThePicturesIsMovedBack() throws {
        // A QuickTime file can count decode times from nought and let a frame
        // show before it is decoded on paper: only the order means anything.
        let frames = storedFrames(count: 90, gop: 30).map {
            CutCopyPlan.StoredFrame(showsAt: $0.showsAt, decodesAt: $0.decodesAt + 20, isKey: $0.isKey)
        }
        let plan = try #require(CutCopyPlan.make(frames: frames, pieces: [350..<900]))
        #expect(plan.copiedFrames == 30)
        for frame in plan.placed { #expect(frame.decodesAt <= frame.showsAt) }
    }

    @Test func anOpenGroupOfPicturesIsRefused() {
        // A B frame after the second key frame shows BEFORE it: it leans on
        // the group behind, so that group cannot be copied on its own.
        var frames = storedFrames(count: 60, gop: 30)
        let key = frames.firstIndex { $0.isKey && $0.showsAt == 300 }!
        frames[key + 2] = CutCopyPlan.StoredFrame(showsAt: 295, decodesAt: frames[key + 2].decodesAt,
                                                  isKey: false)
        #expect(CutCopyPlan.make(frames: frames, pieces: [0..<600]) == nil)
    }

    @Test func nothingToCopyIsNoPlan() {
        #expect(CutCopyPlan.make(frames: [], pieces: [0..<100]) == nil)
        #expect(CutCopyPlan.make(frames: storedFrames(count: 30, gop: 30), pieces: []) == nil)
    }

    // MARK: - What the Export sheet says about a copy

    /// Three minutes kept of a five minute Retina recording, cut and nothing
    /// else, at a cost of 400 KB a second.
    private func cutOnlySource(isCutOnly: Bool = true) -> RecordingExport.Source {
        RecordingExport.Source(sourceDuration: 180, keptDuration: 180,
                               sourceSize: CGSize(width: 2880, height: 1800),
                               fileBytes: 0, isEdited: true, sourceFPS: 30, hasAudio: true,
                               footageBytesPerSecond: 400_000, isCutOnly: isCutOnly)
    }

    @Test func aCutOnlyEditAtTheTopChoiceIsCopied() {
        let source = cutOnlySource()
        #expect(RecordingExport.copiesPieces(format: .mp4, quality: .high, source: source))
        #expect(RecordingExport.copiesPieces(format: .mp4, quality: .high, source: source, size: .full))
        // A smaller file, a smaller picture or another format has to be made.
        #expect(!RecordingExport.copiesPieces(format: .mp4, quality: .standard, source: source))
        #expect(!RecordingExport.copiesPieces(format: .mp4, quality: .high, source: source, size: .p1080))
        #expect(!RecordingExport.copiesPieces(format: .gif, quality: .high, source: source))
        // Anything drawn is made frame by frame.
        #expect(!RecordingExport.copiesPieces(format: .mp4, quality: .high,
                                              source: cutOnlySource(isCutOnly: false)))
    }

    @Test func aCopyIsWeighedOffItsFootageAndKeepsItsPicture() {
        let source = cutOnlySource()
        // What the recording costs for the seconds kept, not the encoder's
        // budget for a picture this size.
        #expect(RecordingExport.weight(format: .mp4, quality: .high, source: source)
                == .about(72_000_000))
        #expect(RecordingExport.outputSize(format: .mp4, quality: .high, source: source)
                == CGSize(width: 2880, height: 1800))
        // No frame rate is claimed: the copy runs at whatever it was recorded at.
        #expect(!RecordingExport.shapeLine(format: .mp4, quality: .high, source: source)
                    .contains("fps"))
    }

    @Test func aCopyTheSheetHasWrittenIsWeighedToTheByte() {
        let written = RecordingExport.Weighing(format: .mp4, quality: .high, size: .full,
                                               fraction: 1, bytes: 70_123_456)
        #expect(RecordingExport.weight(format: .mp4, quality: .high, source: cutOnlySource(),
                                       weighing: written, size: .full) == .exact(70_123_456))
    }
}
