import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// What a held frame does to everything that is NOT the clip it was taken in
/// (`docs/design/mocks/pages/video-freeze-wt.html`, the "The insert pushes"
/// row, and its own closing question about showing the drift).
///
/// Holding a frame INSERTS time. The question this suite answers is whose
/// time: the picture's alone, so a voice on its own layer carries on talking
/// over the frozen frame, or the whole document's, so the voice pauses with
/// the picture and stays with the shot it belongs to. Both are right, on
/// different days, so both are here and the person says which.
@Suite("A hold pushes the picture, or it pushes everything")
struct HoldPushTests {

    static func movie(durationMS: Int = 8000) -> MovieRef {
        MovieRef(id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
                 pixelSize: CGSize(width: 1920, height: 1080),
                 durationMS: durationMS)
    }

    /// An eight second recording with a voice on its own layer under the whole
    /// of it: the document the freeze clickthrough is drawn on.
    static func withVoice(atMS start: Int = 0,
                          lengthMS: Int = 8000) -> (doc: PhotonzDocument, clip: UUID, voice: UUID) {
        var doc = PhotonzDocument.recording(movie(), name: "Take 1")
        let clip = doc.layers[0].id
        let voice = doc.addSound(SoundRef(durationMS: lengthMS), name: "voice over", atMS: start)
        return (doc, clip, voice)
    }

    // MARK: - The choice itself

    @Test("A hold that pushes only the picture leaves the voice running under it")
    func pictureOnlyLeavesTheVoiceAlone() throws {
        var (doc, clip, voice) = Self.withVoice()
        let before = try #require(doc.layer(id: voice)?.time)
        let did1 = doc.holdFrame(clip, atMS: 4000, forMS: 5000, push: .pictureOnly)
        #expect(did1)
        // The picture is five seconds longer and the voice is where it was:
        // you keep talking over the frozen frame.
        #expect(doc.layer(id: voice)?.time == before)
        #expect(doc.layer(id: voice)?.clipPieces?.count == 1)
        #expect(doc.layer(id: clip)?.time?.outMS == 13_000)
    }

    @Test("A hold that pushes everything pauses the voice with the picture")
    func everythingPausesTheVoice() throws {
        var (doc, clip, voice) = Self.withVoice()
        let did2 = doc.holdFrame(clip, atMS: 4000, forMS: 5000, push: .everything)
        #expect(did2)
        let time = try #require(doc.layer(id: voice)?.time)
        // The voice still starts where it did and now runs as long as the
        // picture, because five seconds of silence went into the middle of it.
        #expect(time.inMS == 0)
        #expect(time.outMS == 13_000)
        let pieces = try #require(doc.layer(id: voice)?.clipPieces)
        #expect(pieces.count == 3)
        #expect(pieces.piece(at: 1)?.isHeld == true)
        #expect(pieces.piece(at: 1)?.lengthMS == 5000)
        // ...and what is heard after the hold is what was being said at four
        // seconds, which is the whole point: the words stay with their shot.
        let mix = doc.audioMix().filter { $0.layerID == voice }
        #expect(mix.count == 2)
        #expect(mix.first?.startMS == 0)
        #expect(mix.last?.startMS == 9000)
        #expect(mix.last?.sourceInMS == 4000)
        // Nothing is heard over the frozen frame.
        #expect(doc.audioMix(atMS: 6000).isEmpty)
    }

    @Test("A sound that starts after the hold moves along by the hold's length")
    func soundAfterTheHoldMovesAlong() throws {
        var (doc, clip, voice) = Self.withVoice(atMS: 6000, lengthMS: 4000)
        let did3 = doc.holdFrame(clip, atMS: 4000, forMS: 5000, push: .everything)
        #expect(did3)
        let time = try #require(doc.layer(id: voice)?.time)
        #expect(time.inMS == 11_000)
        #expect(time.outMS == 15_000)
        // It is not cut: nothing was inserted INTO it, it simply starts later.
        #expect(doc.layer(id: voice)?.clipPieces?.count == 1)
        // The document is as long as the last thing in it.
        #expect(doc.documentDurationMS == 15_000)
    }

    @Test("A sound that is over before the hold is not touched by it")
    func soundBeforeTheHoldStaysPut() throws {
        var (doc, clip, voice) = Self.withVoice(atMS: 0, lengthMS: 3000)
        let before = try #require(doc.layer(id: voice)?.time)
        let did4 = doc.holdFrame(clip, atMS: 4000, forMS: 5000, push: .everything)
        #expect(did4)
        #expect(doc.layer(id: voice)?.time == before)
    }

    @Test("Words on screen over the hold stay on screen through it")
    func aTitleOverTheHoldStaysUp() throws {
        var (doc, clip, _) = Self.withVoice()
        var title = Layer(name: "Title",
                          content: .annotation(AnnotationContent(shape: .arrow, strokeWidth: 4,
                                                                 colorHex: "#FF3B30")),
                          frame: CGRect(x: 10, y: 10, width: 100, height: 40))
        title.time = LayerTime(inMS: 2000, outMS: 6000)
        let titleID = title.id
        doc.addLayer(title)
        let did5 = doc.holdFrame(clip, atMS: 4000, forMS: 5000, push: .everything)
        #expect(did5)
        // It arrives on the same frame of the shot and leaves on the same
        // frame of the shot, so it is up for the hold as well.
        #expect(doc.layer(id: titleID)?.time?.inMS == 2000)
        #expect(doc.layer(id: titleID)?.time?.outMS == 11_000)
        // ...and it is not cut into pieces: there is no media in it to pause.
        #expect(doc.layer(id: titleID)?.cuts == nil)
    }

    // MARK: - Changing your mind after the fact

    @Test("A hold made one way can be made the other, and lands exactly where it would have")
    func changingYourMindLandsTheSame() throws {
        var madeThatWay = Self.withVoice().doc
        let clipA = madeThatWay.layers[0].id
        let did6 = madeThatWay.holdFrame(clipA, atMS: 4000, forMS: 5000, push: .everything)
        #expect(did6)

        var changed = Self.withVoice().doc
        let clipB = changed.layers[0].id
        let did7 = changed.holdFrame(clipB, atMS: 4000, forMS: 5000, push: .pictureOnly)
        #expect(did7)
        let did8 = changed.setHoldPush(clipB, ofPiece: 1, to: .everything)
        #expect(did8)

        #expect(changed.layer(id: clipB)?.clipPieces == madeThatWay.layer(id: clipA)?.clipPieces)
        #expect(changed.allLayers.map(\.time) == madeThatWay.allLayers.map(\.time))
        #expect(changed.allLayers.map(\.cuts) == madeThatWay.allLayers.map(\.cuts))
    }

    @Test("Changing it back puts the document back exactly as it was")
    func changingItBackIsAnExactUndo() throws {
        var (doc, clip, _) = Self.withVoice()
        let did9 = doc.holdFrame(clip, atMS: 4000, forMS: 5000, push: .pictureOnly)
        #expect(did9)
        let before = doc
        let did10 = doc.setHoldPush(clip, ofPiece: 1, to: .everything)
        #expect(did10)
        #expect(doc != before)
        let did11 = doc.setHoldPush(clip, ofPiece: 1, to: .pictureOnly)
        #expect(did11)
        // Byte for byte: the silence came out and the two halves of the voice
        // closed back into the one piece they were.
        #expect(doc == before)
    }

    @Test("The choice it already has is not an edit, and a piece that plays has no choice at all")
    func nothingToChange() throws {
        var (doc, clip, _) = Self.withVoice()
        let did12 = doc.holdFrame(clip, atMS: 4000, forMS: 5000, push: .everything)
        #expect(did12)
        let did13 = doc.setHoldPush(clip, ofPiece: 1, to: .everything)
        #expect(!did13)
        let did14 = doc.setHoldPush(clip, ofPiece: 0, to: .pictureOnly)
        #expect(!did14)
        let did15 = doc.setHoldPush(clip, ofPiece: 9, to: .pictureOnly)
        #expect(!did15)
    }

    @Test("A hold made before anybody could choose pushed the picture alone, and still says so")
    func anOlderHoldReadsAsPictureOnly() throws {
        var (doc, clip, _) = Self.withVoice()
        let did16 = doc.holdFrame(clip, atMS: 4000, forMS: 2000)
        #expect(did16)
        #expect(doc.layer(id: clip)?.clipPieces?.piece(at: 1)?.holdPush == .pictureOnly)
        // A piece that plays is not holding anything, so it has nothing to say.
        #expect(doc.layer(id: clip)?.clipPieces?.piece(at: 0)?.holdPush == nil)
    }

    // MARK: - A hold made longer takes what it pushed with it

    @Test("Making a hold that pushes everything longer pushes everything further")
    func alongerHoldPushesFurther() throws {
        var (doc, clip, voice) = Self.withVoice()
        let did17 = doc.holdFrame(clip, atMS: 4000, forMS: 2000, push: .everything)
        #expect(did17)
        #expect(doc.layer(id: voice)?.clipPieces?.piece(at: 1)?.lengthMS == 2000)
        let did18 = doc.setHoldLength(clip, ofPiece: 1, toMS: 5000)
        #expect(did18)
        // One silence, three seconds longer, rather than a second one wedged
        // in beside it.
        let pieces = try #require(doc.layer(id: voice)?.clipPieces)
        #expect(pieces.count == 3)
        #expect(pieces.piece(at: 1)?.lengthMS == 5000)
        #expect(doc.layer(id: voice)?.time?.outMS == 13_000)
        #expect(doc.layer(id: clip)?.time?.outMS == 13_000)
    }

    @Test("Making it shorter again takes the silence back with it")
    func ashorterHoldPullsEverythingBack() throws {
        var (doc, clip, voice) = Self.withVoice()
        let did19 = doc.holdFrame(clip, atMS: 4000, forMS: 5000, push: .everything)
        #expect(did19)
        let did20 = doc.setHoldLength(clip, ofPiece: 1, toMS: 1000)
        #expect(did20)
        let pieces = try #require(doc.layer(id: voice)?.clipPieces)
        #expect(pieces.piece(at: 1)?.lengthMS == 1000)
        #expect(doc.layer(id: voice)?.time?.outMS == 9000)
    }

    @Test("Making a hold that pushes only the picture longer leaves the voice where it is")
    func alongerPictureOnlyHoldMovesNothingElse() throws {
        var (doc, clip, voice) = Self.withVoice()
        let did21 = doc.holdFrame(clip, atMS: 4000, forMS: 2000, push: .pictureOnly)
        #expect(did21)
        let before = try #require(doc.layer(id: voice)?.time)
        let did22 = doc.setHoldLength(clip, ofPiece: 1, toMS: 5000)
        #expect(did22)
        #expect(doc.layer(id: voice)?.time == before)
    }

    // MARK: - What the timeline says about it

    @Test("A bar running under a hold that pushed the picture alone says how far out it now is")
    func thebarSaysHowFarOutItIs() throws {
        var (doc, clip, voice) = Self.withVoice()
        #expect(doc.holdDrifts(forLayer: voice).isEmpty)
        let did23 = doc.holdFrame(clip, atMS: 4000, forMS: 5000, push: .pictureOnly)
        #expect(did23)
        let drifts = doc.holdDrifts(forLayer: voice)
        #expect(drifts.count == 1)
        #expect(drifts.first?.atMS == 4000)
        #expect(drifts.first?.byMS == 5000)
        #expect(drifts.first?.label == "5s out")
        // The clip the hold is IN is not out of step with itself.
        #expect(doc.holdDrifts(forLayer: clip).isEmpty)
    }

    @Test("A hold that pushed everything leaves nothing out of step")
    func everythingLeavesNoDrift() throws {
        var (doc, clip, voice) = Self.withVoice()
        let did24 = doc.holdFrame(clip, atMS: 4000, forMS: 5000, push: .everything)
        #expect(did24)
        #expect(doc.holdDrifts(forLayer: voice).isEmpty)
    }

    @Test("The silence a hold pushes into one layer is not read as a hold of its own")
    func silenceIsNotAHoldOfItsOwn() throws {
        var (doc, clip, voice) = Self.withVoice()
        let music = doc.addSound(SoundRef(durationMS: 14_000), name: "music", atMS: 0)
        let didA = doc.holdFrame(clip, atMS: 4000, forMS: 5000, push: .everything)
        #expect(didA)
        // Every layer waited, so nothing is out of step with anything. The
        // first run of `hold-pushes-the-sound-walk` drew "5s out" on all three
        // bars here, because the silence pushed into the music read as a hold
        // that had pushed the picture alone.
        #expect(doc.holdDrifts(forLayer: voice).isEmpty)
        #expect(doc.holdDrifts(forLayer: music).isEmpty)
        #expect(doc.holdDrifts(forLayer: clip).isEmpty)
        // ...and the silence says what it is: time everything waited for.
        #expect(doc.layer(id: music)?.clipPieces?.piece(at: 1)?.holdPush == .everything)
    }

    @Test("Two holds that pushed the picture alone add up, because the drift does")
    func twoHoldsAddUp() throws {
        var (doc, clip, voice) = Self.withVoice()
        let did25 = doc.holdFrame(clip, atMS: 2000, forMS: 1000, push: .pictureOnly)
        #expect(did25)
        let did26 = doc.holdFrame(clip, atMS: 6000, forMS: 2000, push: .pictureOnly)
        #expect(did26)
        let drifts = doc.holdDrifts(forLayer: voice)
        #expect(drifts.count == 2)
        #expect(drifts.map(\.atMS) == [2000, 6000])
        // From the second one on, the voice is three seconds out, not two.
        #expect(drifts.map(\.byMS) == [1000, 3000])
    }

    @Test("Sound that starts after the hold was never in step with it, so it is not called drift")
    func nodriftForSoundPlacedAfterwards() throws {
        var (doc, clip, voice) = Self.withVoice(atMS: 6000, lengthMS: 4000)
        let did27 = doc.holdFrame(clip, atMS: 4000, forMS: 5000, push: .pictureOnly)
        #expect(did27)
        #expect(doc.holdDrifts(forLayer: voice).isEmpty)
    }

    // MARK: - What it is called

    @Test("Both choices say what you would hear, not what the edit is called")
    func thewordsSayWhatYouWouldHear() {
        #expect(HoldPush.everything.title == "Everything waits")
        #expect(HoldPush.pictureOnly.title == "The rest carries on")
        #expect(HoldPush.everything.sentence(holdMS: 5000)
            == "The voice, the music and anything else on the timeline pause with the picture, "
            + "so what was said over a shot stays over that shot.")
        #expect(HoldPush.pictureOnly.sentence(holdMS: 5000)
            == "Everything else keeps running under the frozen frame, so you can talk over it. "
            + "What comes after it lands 5s out of step with the picture.")
        // What a hold does is written on the hold, so the panel and the
        // timeline never say it two ways.
        #expect(HoldPush.allCases.count == 2)
    }

    // MARK: - Written down

    @Test("What a hold pushes survives being saved and opened again")
    func thechoiceIsWrittenDown() throws {
        var (doc, clip, _) = Self.withVoice()
        let did28 = doc.holdFrame(clip, atMS: 4000, forMS: 5000, push: .everything)
        #expect(did28)
        let data = try JSONEncoder().encode(doc)
        let read = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(read.layer(id: clip)?.clipPieces?.piece(at: 1)?.holdPush == .everything)
        #expect(read == doc)
    }

    @Test("A clip written before anybody could choose reads back unchanged")
    func anolderDocumentReadsBack() throws {
        // Exactly what a hold was written as before this existed: a piece at
        // speed nought and nothing else.
        let json = #"{"pieces":[{"sourceInMS":0,"lengthMS":4000},"#
            + #"{"sourceInMS":4000,"lengthMS":2000,"speedPercent":0},"#
            + #"{"sourceInMS":4000,"lengthMS":4000}],"sourceLengthMS":8000}"#
        let pieces = try JSONDecoder().decode(ClipPieces.self, from: Data(json.utf8))
        #expect(pieces.piece(at: 1)?.holdPush == .pictureOnly)
        // ...and it writes back the way it arrived, so opening a document does
        // not rewrite it.
        let again = try JSONEncoder().encode(pieces)
        #expect(!String(decoding: again, as: UTF8.self).contains("push"))
    }
}
