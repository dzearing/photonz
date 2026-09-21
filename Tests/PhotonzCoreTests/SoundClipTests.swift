import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Sound on the document's own timeline (`docs/design/video-audio.md`).
///
/// Written before the model, which is the rule for `PhotonzCore`. Three
/// invariants are what this file is for:
///
/// 1. **No samples, ever.** A sound layer carries which file and how long, in
///    exactly the bargain `MovieRef` and `ImageRef` already strike. Peaks and
///    buffers live outside the document.
/// 2. **Sound is a layer.** It has an in and an out, it is cut into pieces, it
///    is switched off with the same eye — so everything the timeline already
///    does to a picture it does to sound without a second model.
/// 3. **One plan.** What plays and what exports are read off the same
///    function, so the two cannot drift.
@Suite("Sound is a layer with a file behind it")
struct SoundClipTests {

    static let movieID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    static func movie(durationMS: Int = 8000, hasSound: Bool = true) -> MovieRef {
        MovieRef(id: movieID, pixelSize: CGSize(width: 1920, height: 1080),
                 durationMS: durationMS, hasSound: hasSound)
    }

    static func recording(durationMS: Int = 8000, hasSound: Bool = true) -> PhotonzDocument {
        PhotonzDocument.recording(movie(durationMS: durationMS, hasSound: hasSound),
                                  name: "Screen Recording")
    }

    // MARK: - The reference itself

    @Test("A sound reference is a file's identity and its length, and no samples")
    func referenceCarriesNoSamples() throws {
        let ref = SoundRef(durationMS: 14_000)
        let written = try JSONEncoder().encode(ref)
        let read = try JSONDecoder().decode(SoundRef.self, from: written)
        #expect(read == ref)
        // The whole of it, said out loud: an id and a length. A path, a sample
        // rate and a buffer are all somebody else's business.
        let fields = try #require(try JSONSerialization.jsonObject(with: written) as? [String: Any])
        #expect(Set(fields.keys) == ["id", "durationMS"])
    }

    @Test("A recording's sound is the same file as its picture, so it needs no second identity")
    func soundOfARecordingSharesTheMovieID() throws {
        let sound = try #require(Self.movie().soundRef)
        #expect(sound.id == Self.movieID)
        #expect(sound.durationMS == 8000)
    }

    @Test("A recording with no sound track has no sound to take off it")
    func silentRecordingHasNoSound() {
        #expect(Self.movie(hasSound: false).soundRef == nil)
        let doc = Self.recording(hasSound: false)
        #expect(doc.hasAudio == false)
        #expect(doc.canDetachSound(ofLayer: doc.layers[0].id) == false)
    }

    // MARK: - A clip arrives with its sound on it

    @Test("A recording opens with its sound welded to its picture: one layer, both")
    func recordingOpensWithItsSound() throws {
        let doc = Self.recording()
        let clip = try #require(doc.layers.first)
        #expect(clip.isClip)
        #expect(clip.sound?.id == Self.movieID)
        #expect(doc.hasAudio)
        // One layer, not two: nothing has been separated yet.
        #expect(doc.allLayers.count == 1)
    }

    // MARK: - Taking the sound off the picture

    @Test("Detaching a clip's sound leaves the picture silent and puts the sound on its own layer")
    func detachingSplitsPictureFromSound() throws {
        let doc = Self.recording()
        let clipID = try #require(doc.layers.first?.id)
        #expect(doc.canDetachSound(ofLayer: clipID))

        let split = try #require(doc.detachingSound(ofLayer: clipID))
        let after = split.document
        #expect(after.allLayers.count == 2)

        let clip = try #require(after.layer(id: clipID))
        #expect(clip.movie != nil)          // the picture is untouched
        #expect(clip.sound == nil)          // ...and makes no sound any more

        let sound = try #require(after.layer(id: split.soundLayerID))
        #expect(sound.sound?.id == Self.movieID)
        #expect(sound.isSoundOnly)
        #expect(sound.time == clip.time)     // it lands where its picture is
    }

    @Test("A clip with its sound already off it cannot have it taken off twice")
    func detachingIsOnce() throws {
        let doc = Self.recording()
        let clipID = try #require(doc.layers.first?.id)
        let after = try #require(doc.detachingSound(ofLayer: clipID)).document
        #expect(after.canDetachSound(ofLayer: clipID) == false)
        #expect(after.detachingSound(ofLayer: clipID) == nil)
    }

    @Test("The detached sound keeps the cuts the picture already had, so they start in step")
    func detachedSoundKeepsThePieces() throws {
        var doc = Self.recording()
        let clipID = try #require(doc.layers.first?.id)
        let cut = doc.splitClip(clipID, atMS: 3000)
        #expect(cut)
        let split = try #require(doc.detachingSound(ofLayer: clipID))
        let sound = try #require(split.document.layer(id: split.soundLayerID))
        #expect(sound.clipPieces?.count == 2)
        #expect(sound.clipPieces == split.document.layer(id: clipID)?.clipPieces)
    }

    @Test("Once detached, cutting the picture leaves the sound alone")
    func aCutToThePictureDoesNotCutTheSound() throws {
        let opened = Self.recording()
        var doc = try #require(opened.detachingSound(ofLayer: opened.layers[0].id)).document
        let clipID = try #require(doc.layers.first(where: \.isClip)?.id)
        let soundID = try #require(doc.allLayers.first(where: \.isSoundOnly)?.id)
        let cut = doc.splitClip(clipID, atMS: 2000)
        #expect(cut)
        #expect(doc.layer(id: clipID)?.clipPieces?.count == 2)
        // This is the whole case the cut clickthrough is built around: the
        // voiceover over a cut survives the cut.
        #expect(doc.layer(id: soundID)?.clipPieces?.count == 1)
        // ...and throwing the piece of picture away does not shorten the sound.
        let soundLength = doc.layer(id: soundID)?.time?.lengthMS
        let dropped = doc.removeClipPiece(clipID, at: 0)
        #expect(dropped)
        #expect(doc.layer(id: soundID)?.time?.lengthMS == soundLength)
    }

    @Test("A detached sound is cut and moved like anything else, and the picture stays put")
    func theSoundIsAnOrdinaryLayer() throws {
        let opened = Self.recording()
        var doc = try #require(opened.detachingSound(ofLayer: opened.layers[0].id)).document
        let clipID = try #require(doc.layers.first(where: \.isClip)?.id)
        let soundID = try #require(doc.allLayers.first(where: \.isSoundOnly)?.id)
        let pictureTime = doc.layer(id: clipID)?.time

        // Cut the SOUND in two and throw the first half away.
        let cut = doc.splitClip(soundID, atMS: 4000)
        #expect(cut)
        #expect(doc.layer(id: soundID)?.clipPieces?.count == 2)
        let dropped = doc.removeClipPiece(soundID, at: 0)
        #expect(dropped)
        #expect(doc.layer(id: soundID)?.time?.lengthMS == 4000)

        // ...and slide what is left along. The picture has not moved through
        // any of it.
        doc.updateLayer(id: soundID) { layer in
            if let time = layer.time { layer.time = time.moved(toInMS: 2000) }
        }
        #expect(doc.layer(id: soundID)?.time?.inMS == 2000)
        #expect(doc.layer(id: clipID)?.time == pictureTime)
        // What plays follows it: the segment lands where the bar is and reads
        // the part of the file the cut kept.
        let segment = try #require(doc.audioMix().first { $0.layerID == soundID })
        #expect(segment.startMS == 2000)
        #expect(segment.sourceInMS == 4000)
    }

    // MARK: - Bringing sound in

    @Test("A sound brought in from a file is a layer on the timeline, drawing nothing")
    func soundBroughtInIsALayer() throws {
        var doc = Self.recording()
        let music = SoundRef(durationMS: 14_000)
        let id = doc.addSound(music, name: "music", atMS: 1000)
        let layer = try #require(doc.layer(id: id))
        #expect(layer.isSoundOnly)
        #expect(layer.name == "music")
        #expect(layer.time?.inMS == 1000)
        #expect(layer.time?.outMS == 15_000)
        #expect(layer.frame == .zero)       // nothing to draw and nothing to grab
        #expect(layer.sound == music)
    }

    @Test("Sound longer than the document stretches the document to hold it")
    func soundCanOutlastThePicture() throws {
        var doc = Self.recording(durationMS: 8000)
        _ = doc.addSound(SoundRef(durationMS: 20_000), name: "music", atMS: 0)
        #expect(doc.documentDurationMS == 20_000)
    }

    @Test("A sound layer round trips through the file it is written to")
    func soundLayerIsCodable() throws {
        var doc = Self.recording()
        _ = doc.addSound(SoundRef(durationMS: 14_000), name: "music", atMS: 500)
        let read = try JSONDecoder().decode(PhotonzDocument.self,
                                            from: try JSONEncoder().encode(doc))
        #expect(read.allLayers.count == doc.allLayers.count)
        #expect(read.allLayers.compactMap(\.sound) == doc.allLayers.compactMap(\.sound))
    }

    @Test("A document written before sound existed reads back with none")
    func oldDocumentsHaveNoSound() throws {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100),
                                  layers: [Layer(name: "shape", content: .image(ImageRef(pixelSize: .zero)),
                                                 frame: .zero)])
        let written = try JSONEncoder().encode(doc)
        let text = try #require(String(data: written, encoding: .utf8))
        #expect(!text.contains("sound"))
        #expect(!text.contains("soundDetached"))
        #expect(try JSONDecoder().decode(PhotonzDocument.self, from: written).hasAudio == false)
    }
}
