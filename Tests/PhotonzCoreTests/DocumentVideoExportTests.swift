import CoreGraphics
import Testing
@testable import PhotonzCore

/// What a video export of a document is made of, before a single pixel is
/// written (`DocumentVideoExport.swift`).
struct DocumentVideoExportTests {

    private func recordingDocument(durationMS: Int = 4000,
                                   size: CGSize = CGSize(width: 1280, height: 720),
                                   hasSound: Bool = false) -> PhotonzDocument {
        let movie = MovieRef(pixelSize: size, durationMS: durationMS, hasSound: hasSound)
        return .recording(movie, name: "Screen Recording")
    }

    // MARK: - The plan

    @Test func aMovieIsPlannedOnTheGridAClipsFramesAreFetchedOn() {
        let plan = DocumentVideoExport.plan(durationMS: 2000,
                                            canvasSize: CGSize(width: 1280, height: 720),
                                            format: .mp4, quality: .standard)
        // 33ms apart, which is the grid `MovieRef.frameStepMS` decodes on: a
        // faster export would photograph the same decoded frame twice.
        #expect(plan.fps == DocumentVideoExport.movieFPS)
        #expect(plan.frameCount == 61)
        #expect(plan.timeMS(at: 1) == 33)
        #expect(plan.size == CGSize(width: 1280, height: 720))
        #expect(plan.durationMS == 2000)
    }

    @Test func everyFrameLandsInsideTheDocumentAndTheFirstOneIsTheFirstFrame() {
        let plan = DocumentVideoExport.plan(durationMS: 1000,
                                            canvasSize: CGSize(width: 640, height: 480),
                                            format: .mp4, quality: .standard)
        #expect(plan.timeMS(at: 0) == 0)
        for index in 0..<plan.frameCount {
            #expect(plan.timeMS(at: index) <= 999)
        }
        // ...and they are in order, one per step of the clock.
        for index in 1..<plan.frameCount {
            #expect(plan.timeMS(at: index) > plan.timeMS(at: index - 1))
        }
    }

    @Test func aMoviesPictureIsAnEvenNumberOfPixelsOnEverySide() {
        // H.264 cannot describe an odd side; a canvas that is odd still has to
        // come out as a file that plays.
        let plan = DocumentVideoExport.plan(durationMS: 1000,
                                            canvasSize: CGSize(width: 1281, height: 721),
                                            format: .mp4, quality: .standard)
        #expect(plan.size == CGSize(width: 1280, height: 720))
    }

    @Test func anAnimatedPictureTakesTheSizePresetTheRecordingSheetAlreadyOffers() {
        let plan = DocumentVideoExport.plan(durationMS: 2000,
                                            canvasSize: CGSize(width: 1600, height: 800),
                                            format: .gif, quality: .small)
        #expect(plan.fps == VideoExportQuality.small.targetFPS)
        #expect(plan.frameCount == 20)
        #expect(plan.size == CGSize(width: 480, height: 240))
    }

    @Test func somethingShorterThanAFrameStillWritesOneFrame() {
        let plan = DocumentVideoExport.plan(durationMS: 10,
                                            canvasSize: CGSize(width: 100, height: 100),
                                            format: .mp4, quality: .standard)
        #expect(plan.frameCount == 1)
        #expect(plan.timeMS(at: 0) == 0)
    }

    @Test func aDocumentWithNoTimeHasNothingToPlan() {
        let plan = DocumentVideoExport.plan(durationMS: 0,
                                            canvasSize: CGSize(width: 100, height: 100),
                                            format: .mp4, quality: .standard)
        #expect(plan.frameCount == 0)
        #expect(plan.isEmpty)
    }

    // MARK: - The recording nobody has touched

    @Test func aRecordingJustOpenedIsStillNothingButTheRecording() {
        let document = recordingDocument()
        #expect(document.untouchedRecording != nil)
        #expect(document.untouchedRecording?.durationMS == 4000)
    }

    @Test func aCutTakesTheFastPathAway() {
        var document = recordingDocument()
        var pieces = document.layers[0].clipPieces ?? ClipPieces(single: document.layers[0].time!)
        let cut = pieces.split(atMS: 2000)
        #expect(cut)
        document.layers[0].setClipPieces(pieces)
        #expect(document.untouchedRecording == nil)
    }

    @Test func throwingAPieceAwayTakesTheFastPathAway() {
        var document = recordingDocument()
        var pieces = ClipPieces(single: document.layers[0].time!)
        _ = pieces.split(atMS: 2000)
        _ = pieces.remove(at: 0)
        document.layers[0].setClipPieces(pieces)
        #expect(document.untouchedRecording == nil)
    }

    @Test func aTrimTakesTheFastPathAway() {
        var document = recordingDocument()
        let time = document.layers[0].time!
        document.layers[0].time = time.withOut(3000)
        document.durationMS = 3000
        #expect(document.untouchedRecording == nil)
    }

    @Test func anythingDrawnOverThePictureTakesTheFastPathAway() {
        var document = recordingDocument()
        document.layers.append(Layer(name: "Arrow", content: .image(ImageRef(pixelSize: CGSize(width: 100, height: 100))),
                                     frame: CGRect(x: 10, y: 10, width: 100, height: 100)))
        #expect(document.untouchedRecording == nil)
    }

    @Test func aStyledClipTakesTheFastPathAway() {
        var document = recordingDocument()
        document.layers[0].style.opacity = 0.5
        #expect(document.untouchedRecording == nil)

        var rounded = recordingDocument()
        rounded.layers[0].style.cornerRadius = 24
        #expect(rounded.untouchedRecording == nil)

        var hidden = recordingDocument()
        hidden.layers[0].isVisible = false
        #expect(hidden.untouchedRecording == nil)
    }

    @Test func aResizedOrMovedClipTakesTheFastPathAway() {
        var document = recordingDocument()
        document.layers[0].frame = CGRect(x: 40, y: 0, width: 1280, height: 720)
        #expect(document.untouchedRecording == nil)
    }

    @Test func aPictureWithNoRecordingInItIsNotARecording() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
        document.layers.append(Layer(name: "Shape", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                                     frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        #expect(document.untouchedRecording == nil)
    }

    @Test func soundTakenOffThePictureTakesTheFastPathAway() {
        let movie = MovieRef(pixelSize: CGSize(width: 640, height: 480),
                             durationMS: 3000, hasSound: true)
        var document = PhotonzDocument.recording(movie, name: "With sound")
        #expect(document.untouchedRecording != nil)
        let split = document.detachingSound(ofLayer: document.layers[0].id)
        #expect(split != nil)
        document = split!.document
        #expect(document.untouchedRecording == nil)
    }
}
