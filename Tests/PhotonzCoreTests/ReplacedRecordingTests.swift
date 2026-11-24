import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A recording whose file was replaced on disk while a document holds it: the
/// document is pointed at the new file everywhere, undo steps included.
struct ReplacedRecordingTests {

    private let old = MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 6000)
    private let new = MovieRef(pixelSize: CGSize(width: 1440, height: 810), durationMS: 9000, hasSound: true)

    private func opened() -> PhotonzDocument {
        var document = PhotonzDocument.recording(old, name: "take")
        document.rememberMedia(.recording(old), named: "take.mp4")
        return document
    }

    @Test func anUntouchedRecordingIsTheNewFileAsIfItHadJustOpened() {
        var document = opened()
        document.replaceRecording(old.id, with: new)
        #expect(document.untouchedRecording == new)
        #expect(document.canvasSize == new.pixelSize)
        #expect(document.documentDurationMS == 9000)
        #expect(document.media.first?.media == .recording(new))
        // Nothing left asks for a frame of the old file.
        #expect(document.movieFrames(atTimeMS: 3000).allSatisfy { $0.movie == new })
        guard case .image(let ref) = document.layers[0].content else { return #expect(Bool(false)) }
        #expect(old.frameIndex(ofFrameID: ref.id) == nil)
        #expect(new.frameIndex(ofFrameID: ref.id) != nil)
    }

    /// An edit keeps its timing and its frame: only what is read off the file
    /// changes.
    @Test func anEditKeepsItsCutsItsCanvasAndItsPlace() {
        var document = opened()
        let id = document.layers[0].id
        document.splitClip(id, atMS: 2000)
        let pieces = document.layer(id: id)?.clipPieces?.pieces
        document.replaceRecording(old.id, with: new)
        let clip = document.layer(id: id)
        #expect(clip?.movie == new)
        #expect(clip?.clipPieces?.pieces == pieces)
        #expect(clip?.clipPieces?.sourceLengthMS == 9000)
        #expect(clip?.time?.sourceLengthMS == 9000)
        #expect(document.canvasSize == CGSize(width: 1280, height: 800))
        #expect(document.documentDurationMS == 6000)
        // 16:9 into the 16:10 box it had: whole, centred, not stretched.
        #expect(clip?.frame == CGRect(x: 0, y: 40, width: 1280, height: 720))
    }

    @Test func aSoundTakenOffItAndAClipMergedAwayFollowToo() {
        let talk = MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 6000, hasSound: true)
        var document = PhotonzDocument.recording(talk, name: "take")
        document.rememberMedia(.sound(SoundRef(id: talk.id, durationMS: 6000)), named: "take.mp4")
        if let detached = document.detachingSound(ofLayer: document.layers[0].id) { document = detached.document }
        document.replaceRecording(talk.id, with: new)
        let sounds = document.allLayers.compactMap(\.sound)
        #expect(sounds == [SoundRef(id: new.id, durationMS: 9000)])
        #expect(ProjectMedia.references(in: document).allSatisfy { DocumentMediaSource(media: $0, name: "").id == new.id })
    }

    @Test func anotherRecordingIsLeftAlone() {
        var document = opened()
        let before = document
        document.replaceRecording(UUID(), with: new)
        #expect(document == before)
    }

    /// Undo must not hand back a picture of the old file.
    @Test func everyStepUndoCanReachIsTheNewFile() {
        var history = History(document: opened())
        let id = history.current.layers[0].id
        history.perform { $0.splitClip(id, atMS: 2000) }
        history.applyOutsideHistory { $0.replaceRecording(old.id, with: new) }
        #expect(history.current.layer(id: id)?.movie == new)
        history.undo()
        #expect(history.current.untouchedRecording == new)
        history.redo()
        #expect(history.current.layer(id: id)?.movie == new)
    }

    /// A project reopened on a file that changed: the same facts for now, under
    /// an id nothing old is filed under.
    @Test func aRecordingGivenANewIdKeepsItsFacts() {
        let fresh = old.underNewID()
        #expect(fresh.id != old.id)
        #expect(fresh.pixelSize == old.pixelSize)
        #expect(fresh.durationMS == old.durationMS)
    }
}
