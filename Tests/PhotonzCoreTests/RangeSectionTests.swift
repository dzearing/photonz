import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **A range held with things picked** (`RangeSection.swift`).
///
/// Draw a range, click a sound, and the range stays: a right click inside it
/// offers what can be done to that sound over just that stretch (the user,
/// 2026-10-12). What each kind of pick is offered is one table, and every edit
/// leaves what is outside the range exactly as it was.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("A range acting on the things picked inside it")
struct RangeSectionTests {

    static func movie() -> MovieRef {
        MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 12_000)
    }

    /// A twelve second recording, and music on its own track from 1s to 11s.
    static func edit() -> (doc: PhotonzDocument, clip: UUID, music: UUID) {
        var doc = PhotonzDocument.recording(movie(), name: "Talk")
        let clip = doc.layers[0].id
        let music = doc.addSound(SoundRef(durationMS: 10_000), name: "music", atMS: 1000)
        doc.materializeTracks()
        return (doc, clip, music)
    }

    /// How loud a layer is heard at a moment of the document, out of the mix
    /// itself: nought where it is not heard at all.
    static func heard(_ doc: PhotonzDocument, _ id: UUID, atMS ms: Int) -> Double {
        doc.audioMix(atMS: ms).filter { $0.layerID == id }.map { $0.gain(atMS: ms) }.max() ?? 0
    }

    /// How loud anything is heard at a moment: a sound cut in two by a
    /// Delete Section goes on as two layers.
    static func heardAnything(_ doc: PhotonzDocument, atMS ms: Int) -> Double {
        doc.audioMix(atMS: ms).map { $0.gain(atMS: ms) }.max() ?? 0
    }

    // MARK: The table

    @Test("A sound is offered the sound rows and the cutting rows, nothing for pictures")
    func soundRows() {
        #expect(SectionOperation.offered(for: [.sound]) == [
            .muteSection, .lowerVolume, .normalizeSection, .cleanNoiseInSection,
            .splitAtRangeEdges, .deleteSection, .rippleDeleteSection,
        ])
    }

    @Test("A recording is offered its sound's rows and its picture's")
    func recordingRows() {
        let rows = SectionOperation.offered(for: [.sound, .picture])
        #expect(rows.contains(.muteSection))
        #expect(rows.contains(.speedForSection))
        #expect(rows.contains(.freezeFrameForSection))
        #expect(rows.contains(.addZoomOverRange))
        #expect(rows.contains(.hidePictureForSection))
        #expect(rows.contains(.cleanNoiseInSection))
        #expect(!rows.contains(.trimToRange))
    }

    @Test("A title is offered Trim to Range, and keys Delete Keys in Range")
    func placedAndKeyRows() {
        #expect(SectionOperation.offered(for: [.placed]) == [.trimToRange])
        #expect(SectionOperation.offered(for: [.keys]) == [.deleteKeysInRange])
        #expect(SectionOperation.offered(for: []).isEmpty)
    }

    @Test("Every row the table has is one the app can do, Clean Noise and Hide Picture included")
    func everyRowIsAvailable() {
        let every = SectionOperation.offered(for: Set(SectionKind.allCases))
        #expect(every.contains(.cleanNoiseInSection))
        #expect(every.contains(.hidePictureForSection))
        #expect(every == SectionOperation.allCases)
    }

    @Test("Every row has a short name and at least one kind")
    func everyRowIsNamed() {
        for operation in SectionOperation.allCases {
            #expect(!operation.title.isEmpty && operation.title.count <= 30)
            #expect(!operation.kinds.isEmpty)
            #expect(!operation.title.contains("\u{2014}"))
        }
    }

    // MARK: The level over a section

    @Test("Muting a section pins silence across it with short ramps outside it")
    func muteASection() {
        var level = AudioLevel()
        level.changeSection(fromMS: 2000, toMS: 4000, .set(0), rampMS: 50)
        #expect(level.points.map(\.atMS) == [1950, 2000, 4000, 4050])
        #expect(level.gain(atLayerMS: 1000) == 1)
        #expect(level.gain(atLayerMS: 2000) == 0)
        #expect(level.gain(atLayerMS: 3000) == 0)
        #expect(level.gain(atLayerMS: 4000) == 0)
        #expect(level.gain(atLayerMS: 5000) == 1)
        #expect(!level.isSilent)
    }

    @Test("A section at the very start has no ramp before it")
    func muteFromTheStart() {
        var level = AudioLevel()
        level.changeSection(fromMS: 0, toMS: 1000, .set(0), rampMS: 50)
        #expect(level.points.map(\.atMS) == [0, 1000, 1050])
        #expect(level.gain(atLayerMS: 500) == 0)
        #expect(level.gain(atLayerMS: 2000) == 1)
        // Silence pinned at nought is not taken for a fade in.
        #expect(level.fadeInMS == 0)
    }

    @Test("Lowering a section keeps the shape it already had inside it")
    func lowerASection() {
        var level = AudioLevel(points: [AudioLevelPoint(atMS: 2500, gain: 1),
                                        AudioLevelPoint(atMS: 3000, gain: 0.5)])
        level.changeSection(fromMS: 2000, toMS: 4000, .scaled(0.5), rampMS: 50)
        #expect(level.gain(atLayerMS: 2500) == 0.5)
        #expect(level.gain(atLayerMS: 3000) == 0.25)
        // Outside the section, what it was.
        #expect(level.gain(atLayerMS: 1000) == 1)
        #expect(level.gain(atLayerMS: 5000) == 0.5)
    }

    // MARK: What a pick is

    @Test("A silent recording is a picture; music is a sound; outside the range nothing")
    func kinds() {
        let (doc, clip, music) = Self.edit()
        #expect(doc.sectionKinds(of: clip, within: 3000..<6000) == [.picture])
        #expect(doc.sectionKinds(of: music, within: 3000..<6000) == [.sound])
        #expect(doc.sectionKinds(of: music, within: 0..<900).isEmpty)
    }

    @Test("A title is placed, and has keys where its keys stand")
    func titleKinds() {
        let (doc, id) = KeyLanesTests.keyed()
        #expect(doc.sectionKinds(of: id, within: 2500..<4000) == [.placed, .keys])
        #expect(doc.sectionKinds(of: id, within: 6500..<7500) == [.placed])
    }

    // MARK: Sound

    @Test("Mute Section silences the music inside the range and nowhere else")
    func muteMusic() {
        var (doc, _, music) = Self.edit()
        let did = doc.changeSoundSection([music], within: 3000..<6000, .set(0))
        #expect(did)
        #expect(Self.heard(doc, music, atMS: 2000) == 1)
        #expect(Self.heard(doc, music, atMS: 4500) == 0)
        #expect(Self.heard(doc, music, atMS: 8000) == 1)
        // Measured from the music's own start, which is 1s into the document.
        #expect(doc.layer(id: music)?.soundLevel?.points.map(\.atMS) == [1950, 2000, 5000, 5050])
    }

    @Test("A sound not picked is left alone")
    func onlyThePickedSound() {
        var (doc, _, music) = Self.edit()
        let other = doc.addSound(SoundRef(durationMS: 10_000), name: "voice", atMS: 0)
        doc.changeSoundSection([music], within: 3000..<6000, .set(0))
        #expect(Self.heard(doc, other, atMS: 4500) == 1)
        #expect(doc.layer(id: other)?.soundLevel == nil)
    }

    @Test("A range running off the end of a sound mutes only what it covers")
    func muteToTheEnd() {
        var (doc, _, music) = Self.edit()
        doc.changeSoundSection([music], within: 9000..<12_000, .set(0))
        #expect(Self.heard(doc, music, atMS: 10_500) == 0)
        #expect(Self.heard(doc, music, atMS: 8000) == 1)
    }

    @Test("The stretch of the file a section plays")
    func sourceRanges() {
        let (doc, clip, music) = Self.edit()
        #expect(doc.soundSourceRanges(of: clip, within: 3000..<6000) == [3000..<6000])
        #expect(doc.soundSourceRanges(of: music, within: 3000..<6000) == [2000..<5000])
    }

    // MARK: Cutting

    @Test("Split at Range Edges cuts the picked clip twice and leaves the music whole")
    func splitThePick() {
        var (doc, clip, music) = Self.edit()
        let cuts = doc.splitSection([clip], within: 3000..<6000)
        #expect(cuts == 2)
        #expect(doc.layer(id: clip)?.clipPieces?.count == 3)
        #expect(doc.layer(id: music)?.clipPieces?.count == 1)
    }

    @Test("Delete Section leaves a gap in the picked clip only")
    func liftThePick() {
        var (doc, clip, music) = Self.edit()
        let did = doc.liftSection([music], within: 3000..<6000)
        #expect(did)
        #expect(Self.heardAnything(doc, atMS: 4500) == 0)
        #expect(Self.heardAnything(doc, atMS: 2000) == 1)
        #expect(Self.heardAnything(doc, atMS: 7000) == 1)
        // The recording on its own track is not cut.
        #expect(doc.layer(id: clip)?.clipPieces?.count == 1)
    }

    @Test("Ripple Delete Section closes the gap on the picked clip's track alone")
    func rippleThePick() {
        var (doc, clip, music) = Self.edit()
        let did = doc.rippleDeleteSection([music], within: 3000..<6000)
        #expect(did)
        let time = doc.layer(id: music)?.time
        #expect(time.map { $0.outMS - $0.inMS } == 7000)
        // The recording on its own track is as long as it was.
        #expect(doc.layer(id: clip)?.time?.outMS == 12_000)
    }

    // MARK: Picture

    @Test("Speed for Section plays only the range faster")
    func speedTheSection() {
        var (doc, clip, _) = Self.edit()
        let did = doc.setSectionSpeed([clip], within: 4000..<6000, percent: 200)
        #expect(did)
        let pieces = doc.layer(id: clip)?.clipPieces
        #expect(pieces?.count == 3)
        #expect(pieces?.piece(at: 1)?.speedPercent == 200)
        #expect(pieces?.piece(at: 0)?.speedPercent == 100)
        #expect(doc.layer(id: clip)?.time?.outMS == 11_000)
    }

    @Test("Freeze Frame for Section holds the range's first frame and moves nothing")
    func freezeTheSection() {
        var (doc, clip, _) = Self.edit()
        let did = doc.freezeSection([clip], within: 4000..<6000)
        #expect(did)
        let pieces = doc.layer(id: clip)?.clipPieces
        #expect(pieces?.count == 3)
        #expect(pieces?.piece(at: 1)?.isHeld == true)
        #expect(pieces?.piece(at: 1)?.sourceInMS == 4000)
        #expect(pieces?.piece(at: 1)?.lengthMS == 2000)
        #expect(pieces?.piece(at: 2)?.sourceInMS == 6000)
        #expect(doc.layer(id: clip)?.time?.outMS == 12_000)
    }

    @Test("Add Zoom over Range puts one zoom from the range's start to its end")
    func zoomTheSection() {
        var (doc, clip, _) = Self.edit()
        let made = doc.addZoomOverSection([clip], within: 4000..<7000)
        #expect(made.count == 1)
        let zoom = doc.layer(id: clip)?.zooms?.first
        #expect(zoom?.startMS == 4000)
        #expect(zoom?.endMS == 7000)
    }

    @Test("Picture rows do nothing to a sound")
    func pictureRowsSkipSounds() {
        var (doc, _, music) = Self.edit()
        let froze = doc.freezeSection([music], within: 3000..<6000)
        let sped = doc.setSectionSpeed([music], within: 3000..<6000, percent: 200)
        let zoomed = doc.addZoomOverSection([music], within: 3000..<6000)
        #expect(!froze)
        #expect(!sped)
        #expect(zoomed.isEmpty)
    }

    // MARK: Placed layers and keys

    @Test("Trim to Range brings a title on and off at the range's ends")
    func trimATitle() {
        var (doc, id) = KeyLanesTests.withTitle()
        let did = doc.trimToSection([id], within: 3000..<6000)
        #expect(did)
        #expect(doc.layer(id: id)?.time?.inMS == 3000)
        #expect(doc.layer(id: id)?.time?.outMS == 6000)
    }

    @Test("Trim to Range never makes a title longer")
    func trimNeverGrows() {
        var (doc, id) = KeyLanesTests.withTitle()
        let did = doc.trimToSection([id], within: 0..<9000)
        #expect(!did)
        #expect(doc.layer(id: id)?.time?.inMS == 2000)
        #expect(doc.layer(id: id)?.time?.outMS == 8000)
    }

    @Test("Delete Keys in Range takes the keys inside it and keeps the rest")
    func deleteKeys() {
        var (doc, id) = KeyLanesTests.keyed()
        let did = doc.deleteKeysInSection([id], within: 4500..<6500)
        #expect(did)
        #expect(KeyLanesTests.lane(doc, id, .scale)?.keys.map(\.documentMS) == [3000])
        #expect(KeyLanesTests.lane(doc, id, .opacity)?.keys.map(\.documentMS) == [3000])
    }
}

/// **A sound's level line goes with the sound when a stretch is taken out of
/// it.** Its points are measured from the sound's own start, so when Lift
/// leaves the part after a gap as a second clip, or Extract closes a gap
/// inside one, the points after the gap have to move with what they were
/// drawn over. Until 2026-10-12 neither did, so a mute or a duck turned up
/// seconds away from the words it was put on.
@Suite("A level line follows its sound when a stretch comes out")
struct LevelFollowsATakenStretchTests {

    @Test("Taking a stretch out of a level keeps the shape either side of it")
    func removingAStretch() {
        var level = AudioLevel(points: [AudioLevelPoint(atMS: 1000, gain: 1), AudioLevelPoint(atMS: 2000, gain: 0),
                                        AudioLevelPoint(atMS: 5000, gain: 0), AudioLevelPoint(atMS: 6000, gain: 1)])
        level.removeStretch(fromMS: 3000, toMS: 4000)
        #expect(level.gain(atLayerMS: 500) == 1)
        #expect(level.gain(atLayerMS: 2500) == 0)
        #expect(level.gain(atLayerMS: 3500) == 0)
        #expect(level.gain(atLayerMS: 5000) == 1)
        #expect(level.points.map(\.atMS) == [1000, 2000, 3000, 4000, 5000])
    }

    @Test("Taking the start off a level begins it where the rest of it was")
    func removingTheStart() {
        var level = AudioLevel(points: [AudioLevelPoint(atMS: 1000, gain: 1), AudioLevelPoint(atMS: 3000, gain: 0)])
        level.removeStretch(fromMS: 0, toMS: 2000)
        #expect(level.gain(atLayerMS: 0) == 0.5)
        #expect(level.gain(atLayerMS: 1000) == 0)
        #expect(level.gain(atLayerMS: 2000) == 0)
    }

    @Test("Lift: the part after the gap keeps its own level, not the first part's")
    func liftCarriesTheLevel() {
        var (doc, _, music) = RangeSectionTests.edit()
        // Silent from 0:03 to 0:05 of the document; the music starts at 0:01.
        doc.changeSoundSection([music], within: 3000..<5000, .set(0))
        let did = doc.liftStretch(fromMS: 6000, toMS: 8000, onlyLayers: [music])
        #expect(did)
        #expect(RangeSectionTests.heardAnything(doc, atMS: 4000) == 0)
        #expect(RangeSectionTests.heardAnything(doc, atMS: 9000) == 1)
        #expect(RangeSectionTests.heardAnything(doc, atMS: 10_500) == 1)
    }

    @Test("Extract: a mute after the gap moves up with the sound under it")
    func extractCarriesTheLevel() {
        var (doc, _, music) = RangeSectionTests.edit()
        doc.changeSoundSection([music], within: 5000..<7000, .set(0))
        let track = doc.trackID(ofClip: music)
        let did = doc.extractStretch(fromMS: 2000, toMS: 3000, onTracks: track.map { [$0] })
        #expect(did)
        // What was silent from 0:05 to 0:07 is now silent from 0:04 to 0:06.
        #expect(RangeSectionTests.heardAnything(doc, atMS: 4500) == 0)
        #expect(RangeSectionTests.heardAnything(doc, atMS: 6500) == 1)
        #expect(RangeSectionTests.heardAnything(doc, atMS: 3500) == 1)
    }
}

/// **Clean Noise in Section and Hide Picture for Section** (`RangeSection.swift`).
///
/// The whole-clip versions already existed: Clean Noise on a sound, a layer's
/// eye. Over a range they act on the stretch inside it only, the way Premiere
/// puts an effect on a cut segment or disables one: the clip is cut at the
/// range's edges, as Speed for Section and Freeze Frame for Section cut it, and
/// the piece in the middle is marked. A split adds a piece, never a second
/// clip, so the mark lives on the piece.
@Suite("A stretch of a clip cleaned or hidden")
struct SectionCleanAndHideTests {

    /// A twelve second recording WITH its own sound, and music from 1s.
    static func talking() -> (doc: PhotonzDocument, clip: UUID, music: UUID) {
        var doc = PhotonzDocument.recording(
            MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 12_000, hasSound: true),
            name: "Talk")
        let clip = doc.layers[0].id
        let music = doc.addSound(SoundRef(durationMS: 10_000), name: "music", atMS: 1000)
        doc.materializeTracks()
        return (doc, clip, music)
    }

    static func segment(_ doc: PhotonzDocument, _ id: UUID, atMS ms: Int) -> AudioMixSegment? {
        doc.audioMix(atMS: ms).first { $0.layerID == id }
    }

    static func shows(_ doc: PhotonzDocument, _ id: UUID, atMS ms: Int) -> Bool {
        doc.drawn(atTimeMS: ms).layers.first { $0.id == id }?.isVisible ?? false
    }

    // MARK: Hide Picture

    @Test("Hide Picture for Section takes the picture off inside the range and nowhere else")
    func hideThePicture() {
        var (doc, clip, _) = Self.talking()
        #expect(doc.sectionKinds(of: clip, within: 4000..<6000) == [.sound, .picture])
        let did = doc.hidePictureSection([clip], within: 4000..<6000)
        #expect(did)
        #expect(Self.shows(doc, clip, atMS: 3000))
        #expect(!Self.shows(doc, clip, atMS: 4000))
        #expect(!Self.shows(doc, clip, atMS: 5500))
        #expect(Self.shows(doc, clip, atMS: 6000))
        // Cut at both edges, one clip, the middle piece marked.
        let pieces = doc.layer(id: clip)?.clipPieces
        #expect(pieces?.count == 3)
        #expect(pieces?.pieces.map(\.pictureHidden) == [false, true, false])
        #expect(doc.layers.count == 2)
        // Nothing moved: the clip is as long as it was.
        #expect(doc.layer(id: clip)?.time?.outMS == 12_000)
    }

    @Test("Its sound plays on under the hidden stretch")
    func hiddenKeepsItsSound() {
        var (doc, clip, _) = Self.talking()
        doc.hidePictureSection([clip], within: 4000..<6000)
        #expect(RangeSectionTests.heard(doc, clip, atMS: 5000) == 1)
    }

    @Test("Hiding a stretch already hidden changes nothing")
    func hideTwice() {
        var (doc, clip, _) = Self.talking()
        doc.hidePictureSection([clip], within: 4000..<6000)
        let again = doc.hidePictureSection([clip], within: 4000..<6000)
        #expect(!again)
    }

    @Test("A range over the whole clip hides it all and keeps it one piece")
    func hideTheWholeClip() {
        var (doc, clip, _) = Self.talking()
        let did = doc.hidePictureSection([clip], within: 0..<12_000)
        #expect(did)
        #expect(doc.layer(id: clip)?.clipPieces?.count == 1)
        #expect(doc.layer(id: clip)?.clipPieces?.piece(at: 0)?.pictureHidden == true)
        #expect(!Self.shows(doc, clip, atMS: 100))
    }

    @Test("Hide Picture does nothing to a sound")
    func hideSkipsSounds() {
        var (doc, _, music) = Self.talking()
        let did1 = doc.hidePictureSection([music], within: 3000..<6000)
        #expect(!did1)
    }

    @Test("Show Picture brings a hidden piece back")
    func showAgain() {
        var (doc, clip, _) = Self.talking()
        doc.hidePictureSection([clip], within: 4000..<6000)
        let did = doc.setPictureHidden(clip, ofPiece: 1, false)
        #expect(did)
        #expect(Self.shows(doc, clip, atMS: 5000))
        let did2 = doc.setPictureHidden(clip, ofPiece: 1, false)
        #expect(!did2)
    }

    @Test("A hidden stretch cannot be clicked on the canvas")
    func hiddenIsOffScreenForClicks() {
        var (doc, clip, _) = Self.talking()
        doc.hidePictureSection([clip], within: 4000..<6000)
        #expect(doc.hidingWhatIsOffScreen(atTimeMS: 5000).layer(id: clip)?.isVisible == false)
        #expect(doc.hidingWhatIsOffScreen(atTimeMS: 3000).layer(id: clip)?.isVisible == true)
    }

    // MARK: Clean Noise

    @Test("Clean Noise in Section plays a cleaned copy inside the range and the file outside it")
    func cleanTheSection() {
        var (doc, clip, music) = Self.talking()
        let did = doc.cleanNoiseSection([music], within: 4000..<6000)
        #expect(did)
        let inside = Self.segment(doc, music, atMS: 5000)
        #expect(inside?.sound.cleaning?.reduction == .standard)
        // Learned from the stretch it cleans: 3s to 5s of the music's file.
        #expect(inside?.sound.cleaning?.learnFromMS == [3000..<5000])
        #expect(inside?.sound.sourceID == doc.layer(id: music)?.sound?.id)
        #expect(Self.segment(doc, music, atMS: 3000)?.sound.cleaning == nil)
        #expect(Self.segment(doc, music, atMS: 7000)?.sound.cleaning == nil)
        // The recording on its own track is not touched.
        #expect(Self.segment(doc, clip, atMS: 5000)?.sound.cleaning == nil)
        // Cut at both edges, still one clip, nothing moved.
        #expect(doc.layer(id: music)?.clipPieces?.count == 3)
        #expect(doc.layer(id: music)?.time?.outMS == 11_000)
    }

    @Test("A recording's own sound can be cleaned over a stretch")
    func cleanARecording() {
        var (doc, clip, _) = Self.talking()
        let did = doc.cleanNoiseSection([clip], within: 4000..<6000)
        #expect(did)
        #expect(Self.segment(doc, clip, atMS: 5000)?.sound.cleaning?.reduction == .standard)
        #expect(Self.shows(doc, clip, atMS: 5000))
    }

    @Test("Cleaning a stretch already clean, or a sound cleaned whole, changes nothing")
    func cleanTwice() {
        var (doc, _, music) = Self.talking()
        doc.cleanNoiseSection([music], within: 4000..<6000)
        let did3 = doc.cleanNoiseSection([music], within: 4000..<6000)
        #expect(!did3)
        var (whole, _, wholeMusic) = Self.talking()
        whole.updateLayer(id: wholeMusic) { layer in
            var level = AudioLevel()
            level.noiseReduction = .medium
            layer.setSoundLevel(level)
        }
        let did4 = whole.cleanNoiseSection([wholeMusic], within: 4000..<6000)
        #expect(!did4)
    }

    @Test("Two cleaned stretches of one sound play one cleaned copy, learned from both")
    func twoStretchesOneCopy() {
        var (doc, _, music) = Self.talking()
        doc.cleanNoiseSection([music], within: 2000..<3000)
        doc.cleanNoiseSection([music], within: 6000..<8000)
        let first = Self.segment(doc, music, atMS: 2500)?.sound
        let second = Self.segment(doc, music, atMS: 7000)?.sound
        #expect(first != nil && first == second)
        #expect(first?.cleaning?.learnFromMS == [1000..<2000, 5000..<7000])
    }

    @Test("Removing noise cleaning takes the stretches back to the file too")
    func removeCleaning() {
        var (doc, _, music) = Self.talking()
        doc.cleanNoiseSection([music], within: 4000..<6000)
        let did = doc.clearSectionNoiseCleaning(music)
        #expect(did)
        #expect(Self.segment(doc, music, atMS: 5000)?.sound.cleaning == nil)
        let did5 = doc.clearSectionNoiseCleaning(music)
        #expect(!did5)
    }

    @Test("A cleaned section keeps the EQ the whole sound has")
    func cleanedSectionKeepsTheEQ() {
        var (doc, _, music) = Self.talking()
        doc.updateLayer(id: music) { layer in
            var level = AudioLevel()
            level.addEffect(.eq)
            layer.setSoundLevel(level)
        }
        doc.cleanNoiseSection([music], within: 4000..<6000)
        let inside = Self.segment(doc, music, atMS: 5000)?.sound.cleaning
        #expect(inside?.reduction == .standard)
        #expect(inside?.eq != nil)
    }

    @Test("Clean Noise does nothing to a silent recording")
    func cleanSkipsPictures() {
        var (doc, clip, _) = RangeSectionTests.edit()
        let did6 = doc.cleanNoiseSection([clip], within: 3000..<6000)
        #expect(!did6)
    }

    // MARK: The marks on a piece

    @Test("Both marks survive a cut, and a piece with a mark never joins one without")
    func marksSurviveACut() {
        let piece = ClipPiece(sourceInMS: 0, lengthMS: 4000).hidingPicture(true).cleaning(.strong)
        let halves = piece.split(atOffsetMS: 1000)
        #expect(halves?.0.pictureHidden == true && halves?.1.pictureHidden == true)
        #expect(halves?.0.noiseReduction == .strong && halves?.1.noiseReduction == .strong)
        #expect(piece.trimmedEnd(byMS: -500).pictureHidden)
        #expect(piece.trimmedStart(byMS: 500).noiseReduction == .strong)
        #expect(piece.atSpeed(percent: 200).pictureHidden)
        var pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 1000),
                                         ClipPiece(sourceInMS: 1000, lengthMS: 1000).hidingPicture(true)])
        #expect(!pieces.isOnePlainPiece)
        let did7 = pieces.setPictureHidden(ofPiece: 1, false)
        #expect(did7)
        #expect(!ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 1000).cleaning(.light)]).isOnePlainPiece)
    }

    @Test("A piece with no mark writes nothing about either, and one with marks reads back")
    func marksAreWrittenOnlyWhenSet() throws {
        let plain = ClipPiece(sourceInMS: 0, lengthMS: 1000)
        let written = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!written.contains("picture") && !written.contains("noise"))
        let marked = plain.hidingPicture(true).cleaning(.medium)
        let back = try JSONDecoder().decode(ClipPiece.self, from: try JSONEncoder().encode(marked))
        #expect(back == marked)
        #expect(back.pictureHidden && back.noiseReduction == .medium)
    }
}
