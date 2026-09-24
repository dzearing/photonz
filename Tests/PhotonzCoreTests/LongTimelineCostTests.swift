import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A long captioned recording edits without freezing.**
///
/// A five minute talk writes itself about 170 captions, every one a layer on
/// the timeline. Before this, the menu bar asked "can Extract and Lift take
/// anything?" by running a whole Lift on a copy of the document, and that
/// Lift looked each layer's track up by laying every track out again: a
/// sixth to two thirds of a second on every key press once an In was set.
///
/// The answers asked on every redraw now come from one pass over the layers,
/// and these tests hold them to the same answers the long way gives.
@Suite("A long timeline answers its questions cheaply")
struct LongTimelineCostTests {

    static func movie(durationMS: Int) -> MovieRef {
        MovieRef(id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
                 pixelSize: CGSize(width: 2880, height: 1800),
                 durationMS: durationMS)
    }

    /// A five minute recording talked over from end to end: 173 captions of
    /// six words each, the shape the recogniser gives a real talk.
    static func longTalk() -> PhotonzDocument {
        var doc = PhotonzDocument.recording(movie(durationMS: 300_000), name: "Long Talk")
        let cueLength = 300_000 / 173
        let cues = (0..<173).map { index -> CaptionCue in
            let start = index * cueLength
            let step = (cueLength - 100) / 6
            let words = (0..<6).map { word in
                TranscribedWord("word\(index)-\(word)", startMS: start + word * step,
                                endMS: start + (word + 1) * step)
            }
            return CaptionCue(words: words, inMS: start, outMS: start + cueLength - 100)
        }
        doc.landCaptions(cues)
        return doc
    }

    /// What a whole Lift on a copy says, which is what the query must match.
    static func liftWouldTake(_ doc: PhotonzDocument) -> Bool {
        var trial = doc
        return trial.liftMarkedStretch()
    }

    @Test("Whether Extract and Lift can take anything agrees with a trial Lift")
    func canTakeOutAgreesWithLift() throws {
        var doc = MarkedStretchTests.talk().doc
        #expect(!doc.canTakeOutMarkedStretch)
        #expect(doc.canTakeOutMarkedStretch == Self.liftWouldTake(doc))

        doc.setMarkIn(atMS: 4000)
        doc.setMarkOut(atMS: 8000)
        #expect(doc.canTakeOutMarkedStretch)
        #expect(doc.canTakeOutMarkedStretch == Self.liftWouldTake(doc))
    }

    @Test("A stretch nothing unlocked runs into has nothing to take out")
    func lockedEverywhere() throws {
        var doc = MarkedStretchTests.talk().doc
        doc.materializeTracks()
        for track in doc.timelineTracks { doc.updateTrack(track.id) { $0.isLocked = true } }
        doc.setMarkIn(atMS: 4000)
        doc.setMarkOut(atMS: 8000)
        #expect(!Self.liftWouldTake(doc))
        #expect(!doc.canTakeOutMarkedStretch)
    }

    @Test("A locked track spares only what is on it")
    func oneLockedTrack() throws {
        var doc = PhotonzDocument.recording(Self.movie(durationMS: 12_000), name: "Talk")
        let music = doc.addSound(SoundRef(durationMS: 10_000), name: "music", atMS: 1000)
        doc.materializeTracks()
        let clipTrack = try #require(doc.trackID(ofClip: doc.layers[0].id))
        doc.updateTrack(clipTrack) { $0.isLocked = true }
        doc.setMarkIn(atMS: 4000)
        doc.setMarkOut(atMS: 8000)
        // The music still runs into the stretch on a track nobody locked.
        #expect(doc.canTakeOutMarkedStretch)
        #expect(Self.liftWouldTake(doc))
        let musicTrack = try #require(doc.trackID(ofClip: music))
        doc.updateTrack(musicTrack) { $0.isLocked = true }
        #expect(!doc.canTakeOutMarkedStretch)
        #expect(!Self.liftWouldTake(doc))
    }

    @Test("A stretch past everything has nothing to take out")
    func pastTheEnd() {
        var doc = PhotonzDocument.recording(Self.movie(durationMS: 12_000), name: "Talk")
        doc.setMarkIn(atMS: 11_000)
        doc.setMarkOut(atMS: 12_000)
        #expect(doc.canTakeOutMarkedStretch == Self.liftWouldTake(doc))
    }

    @Test("Every layer's id, in the order the whole list reads them, without copying a layer")
    func allLayerIDsInOrder() {
        let doc = Self.longTalk()
        #expect(doc.allLayerIDs == doc.allLayers.map(\.id))
        #expect(doc.allLayerIDs.count >= 174)
    }

    @Test("Visiting every layer reaches the same layers in the same order as the flattened list")
    func visitEveryLayer() {
        let doc = Self.longTalk()
        var seen: [UUID] = []
        doc.forEachLayer { seen.append($0.id) }
        #expect(seen == doc.allLayers.map(\.id))
    }

    @Test("A bar asks where a hold drifts it once per bar, and 173 bars cost next to nothing")
    func holdDriftsOnALongTalk() {
        let doc = Self.longTalk()
        let ids = doc.captionLayers.map(\.id)
        let clock = ContinuousClock()
        let spent = clock.measure {
            for id in ids { _ = doc.holdDrifts(forLayer: id) }
        }
        #expect(spent < .milliseconds(150), "173 bars took \(spent)")
    }

    /// Every bar on the timeline looks its layer up a few times as it draws,
    /// so a zoom that brings 173 bars on screen asks this about a thousand
    /// times. Each search used to copy every layer it walked past.
    @Test("Looking each of 173 captions up five times costs next to nothing")
    func lookUpEveryCue() {
        let doc = Self.longTalk()
        let ids = doc.captionLayers.map(\.id)
        let clock = ContinuousClock()
        var found = 0
        let spent = clock.measure {
            for _ in 0..<5 { for id in ids where doc.layer(id: id) != nil { found += 1 } }
        }
        #expect(found == ids.count * 5)
        // About 25ms in a debug build; the bound catches a return to copying
        // whole layers per step, not a millisecond here or there.
        #expect(spent < .milliseconds(150), "865 lookups took \(spent)")
    }

    /// A caption bar can be drawn without asking about holds at all when no
    /// hold anywhere pushed the picture alone: that is the only thing that
    /// ever puts an "out of step" mark on a bar.
    @Test("Whether any hold pushed the picture alone")
    func pictureOnlyHolds() throws {
        var (doc, clip, _) = HoldPushTests.withVoice()
        #expect(!doc.hasPictureOnlyHolds)
        let held = doc.holdFrame(clip, atMS: 4000, forMS: 2000, push: .everything)
        #expect(held)
        #expect(!doc.hasPictureOnlyHolds)
        let pushed = doc.holdFrame(clip, atMS: 1000, forMS: 2000, push: .pictureOnly)
        #expect(pushed)
        #expect(doc.hasPictureOnlyHolds)
    }

    /// Reading the cues back is asked by the Captions section and the Words
    /// lane each time the document changes. A caption nobody retyped says
    /// exactly the words it heard, so it needs no matching of words at all.
    @Test("Captions nobody retyped read back as the words they heard, quickly")
    func untouchedCuesReadBack() {
        let doc = Self.longTalk()
        let cues = doc.captionCues
        #expect(cues.count == 173)
        for (cue, layer) in zip(cues, doc.captionLayers) {
            #expect(cue.words == layer.captionWords)
        }
        let clock = ContinuousClock()
        let spent = clock.measure { for _ in 0..<5 { _ = doc.captionCues } }
        #expect(spent < .milliseconds(150), "5 readings took \(spent)")
    }

    /// The menu bar asks whether Add Edit to All Tracks would cut anything at
    /// the playhead on every step of it. It used to answer by cutting a copy.
    @Test("Whether every clip can be cut at a moment agrees with cutting a copy")
    func canSplitAgreesWithSplitting() throws {
        var (doc, clip, voice) = HoldPushTests.withVoice(atMS: 2000, lengthMS: 4000)
        for ms in [0, 1, 1500, 2000, 2001, 4000, 5999, 6000, 7990, 8000, 9000] {
            var trial = doc
            #expect(doc.canSplitEveryClip(atMS: ms) == (trial.splitEveryClip(atMS: ms) > 0), "at \(ms)")
        }
        doc.materializeTracks()
        let pictureTrack = try #require(doc.trackID(ofClip: clip))
        let voiceTrack = try #require(doc.trackID(ofClip: voice))
        doc.updateTrack(pictureTrack) { $0.isLocked = true }
        doc.updateTrack(voiceTrack) { $0.isLocked = true }
        var trial = doc
        #expect(!doc.canSplitEveryClip(atMS: 4000))
        #expect(trial.splitEveryClip(atMS: 4000) == 0)
    }

    /// Picking a caption shows the Arrange row, which asks what the caption
    /// lines up against: the box round its 172 siblings. Each sibling was
    /// found by searching the whole document for it, and the row asks
    /// several times per draw, so picking a caption froze for half a second.
    @Test("What a picked caption lines up against is quick to work out among 173 captions")
    func arrangeAmongCaptions() throws {
        let doc = Self.longTalk()
        let first = try #require(doc.captionLayers.first)
        let clock = ContinuousClock()
        var found: ArrangeContainer?
        let spent = clock.measure {
            for _ in 0..<10 { found = doc.arrangeContainer(of: first.id) }
        }
        let group = try #require(doc.layers.first { $0.isCaptionGroup })
        if let found { #expect(found.id == group.id) }
        #expect(spent < .milliseconds(100), "10 askings took \(spent)")
    }

    @Test("Finding a layer anywhere inside another agrees with the flattened list")
    func containsDescendant() throws {
        let doc = Self.longTalk()
        let group = try #require(doc.layers.first { $0.isCaptionGroup })
        let last = try #require(group.children.last)
        #expect(group.containsSelfOrDescendant { $0.id == last.id })
        #expect(group.containsSelfOrDescendant { $0.id == group.id })
        let clip = try #require(doc.layers.first { $0.isClip })
        #expect(!group.containsSelfOrDescendant { $0.id == clip.id })
    }

    /// The bound itself, on the shape of document that froze. A whole Lift
    /// on this took most of a second in the app; the query is a single pass.
    @Test("On a five minute talk with 173 captions the question costs under a millisecond or so")
    func cheapOnALongTalk() {
        var doc = Self.longTalk()
        doc.setMarkIn(atMS: 75_000)
        doc.setMarkOut(atMS: 150_000)
        let clock = ContinuousClock()
        var answer = false
        let spent = clock.measure {
            for _ in 0..<20 { answer = doc.canTakeOutMarkedStretch }
        }
        #expect(answer)
        // Twenty askings, generous for a debug build on a loaded machine.
        #expect(spent < .milliseconds(50), "20 askings took \(spent)")
    }
}
