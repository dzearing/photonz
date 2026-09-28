import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **A stretch of a track merged into one clip, and broken apart again**
/// (`MergedClip.swift`).
///
/// Premiere nests a sequence and Final Cut makes a compound clip: the parts of
/// the clips under a range become ONE clip that plays and sounds exactly as they
/// did, and opens back into its parts. Nothing is baked: the merged clip holds
/// the clips themselves, on a clock of their own, and reads that clock the way
/// a clip reads its recording, so a trim, a move and a transition are the ones
/// every clip already has.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("A range merged into one clip")
struct MergedClipTests {

    /// take on V1 from 0 to 8s, b-roll butted on from 8s to 12s.
    /// Both recordings carry sound, so every check of what is heard hears
    /// something.
    static let take = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 10_000, hasSound: true)
    static let broll = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 6000, hasSound: true)

    static func edit() throws -> (doc: PhotonzDocument, take: UUID, broll: UUID) {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        var clip = Layer(name: "b-roll", content: .image(Self.broll.frameRef(atSourceMS: 1500)),
                         frame: CGRect(origin: .zero, size: Self.broll.pixelSize))
        clip.movie = Self.broll
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 1500, sourceLengthMS: 6000)
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 8000,
                                      over: .onto(v1), edit: .overwrite)
        let landed = doc.land(clip, at: landing)
        let broll = try #require(landed)
        #expect(!doc.audioMix(atMS: 7000).isEmpty)
        return (doc, take, broll)
    }

    /// Every frame fetched at a moment, as (recording, moment of it).
    static func seen(_ doc: PhotonzDocument, atMS ms: Int) -> Set<String> {
        Set(doc.movieFrames(atTimeMS: ms).map { "\($0.movie.id):\($0.sourceMS)" })
    }

    /// Every picture drawn at a moment, however deep.
    static func drawnPictures(_ doc: PhotonzDocument, atMS ms: Int) -> Set<UUID> {
        var found = Set<UUID>()
        func walk(_ layers: [Layer]) {
            for layer in layers where layer.isVisible {
                if case .image(let ref) = layer.content { found.insert(ref.id) }
                if case .group(let group) = layer.content { walk(group.children) }
            }
        }
        walk(doc.drawn(atTimeMS: ms).layers)
        return found
    }

    /// What is heard at a moment, as (sound, moment of its file).
    static func heard(_ doc: PhotonzDocument, atMS ms: Int) -> Set<String> {
        Set(doc.audioMix(atMS: ms).map { segment in
            let pace = Double(segment.sourceLengthMS) / Double(max(1, segment.lengthMS))
            let at = segment.sourceInMS + Int((Double(ms - segment.startMS) * pace).rounded())
            return "\(segment.sound.id):\(at)"
        })
    }

    static let moments = stride(from: 0, to: 12_000, by: 250).map { $0 } + [5999, 6000, 7999, 8000, 9999, 10_000]

    static func expectPlaysTheSame(_ before: PhotonzDocument, _ after: PhotonzDocument,
                                   sourceLocation: SourceLocation = #_sourceLocation) {
        for ms in moments {
            #expect(seen(after, atMS: ms) == seen(before, atMS: ms), "frames at \(ms)",
                    sourceLocation: sourceLocation)
            #expect(drawnPictures(after, atMS: ms) == drawnPictures(before, atMS: ms), "pictures at \(ms)",
                    sourceLocation: sourceLocation)
            #expect(heard(after, atMS: ms) == heard(before, atMS: ms), "sound at \(ms)",
                    sourceLocation: sourceLocation)
        }
    }

    static func v1(_ doc: PhotonzDocument) throws -> UUID {
        try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
    }

    /// The clips on a track, left to right, as (in, out).
    static func spans(_ doc: PhotonzDocument, track: UUID) -> [Range<Int>] {
        doc.clipIDs(onTrack: track).compactMap { doc.layer(id: $0)?.time }
            .map { $0.inMS..<$0.outMS }.sorted { $0.lowerBound < $1.lowerBound }
    }

    // MARK: - Merging

    @Test("A range across a cut merges the covered parts into one clip, and the rest stays either side")
    func mergeAcrossACut() throws {
        var (doc, _, _) = try Self.edit()
        let track = try Self.v1(doc)
        #expect(doc.canMergeRange(6000..<10_000))
        let made = doc.mergeRange(6000..<10_000)
        #expect(made.count == 1)
        let id = try #require(made.first)
        #expect(Self.spans(doc, track: track) == [0..<6000, 6000..<10_000, 10_000..<12_000])
        let merged = try #require(doc.layer(id: id))
        #expect(merged.isMergedClip)
        #expect(merged.name == MergedClip.defaultName)
        #expect(doc.trackID(ofClip: id) == track)
        #expect(merged.timelineTrackKind == .video)
    }

    @Test("It plays and sounds exactly as the clips did")
    func playsTheSame() throws {
        var (doc, _, _) = try Self.edit()
        let before = doc
        doc.mergeRange(6000..<10_000)
        Self.expectPlaysTheSame(before, doc)
    }

    @Test("Nothing is baked: the merged clip holds the clips themselves, whole, with the range as its window")
    func holdsTheClips() throws {
        var (doc, take, broll) = try Self.edit()
        let made1 = doc.mergeRange(6000..<10_000)

        let id = try #require(made1.first)
        let merged = try #require(doc.layer(id: id)?.merged)
        // The two clips it covers, whole, on their own clock: nought is where
        // the take starts.
        #expect(merged.layers.count == 2)
        #expect(merged.layers.map { $0.movie?.id } == [Self.take.id,
                                                          Self.broll.id])
        #expect(merged.layers.map { $0.time?.inMS } == [0, 8000])
        #expect(merged.lengthMS == 12_000)
        // ...and the merged clip reads 6s to 10s of that clock, with the rest
        // either side as spare, like any clip's recording.
        let time = try #require(doc.layer(id: id)?.time)
        #expect(time.sourceInMS == 6000)
        #expect(time.sourceLengthMS == 12_000)
        #expect(time.spareBeforeMS == 6000)
        #expect(time.spareAfterMS == 2000)
        // The parts left outside keep the ids somebody may be pointing at.
        #expect(doc.layer(id: take)?.time?.outMS == 6000)
        #expect(doc.layer(id: broll)?.time?.inMS == 10_000)
        // And the clips inside never collide with the ones outside.
        let outside = Set(doc.allLayerIDs)
        #expect(merged.layers.allSatisfy { !outside.contains($0.id) })
    }

    @Test("Undo is one step: merging is one change to the document")
    func oneStep() throws {
        let (doc, _, _) = try Self.edit()
        var history = History(document: doc)
        history.perform { $0.mergeRange(6000..<10_000) }
        #expect(history.current != doc)
        #expect(history.canUndo)
        history.undo()
        #expect(history.current == doc)
    }

    @Test("A range over nothing, or only over a locked track, merges nothing")
    func nothingToMerge() throws {
        var (doc, _, _) = try Self.edit()
        let track = try Self.v1(doc)
        doc.materializeTracks()
        doc.updateTrack(track) { $0.isLocked = true }
        #expect(!doc.canMergeRange(6000..<10_000))
        #expect(doc.mergeRange(6000..<10_000).isEmpty)
    }

    @Test("A merged clip saves and reads back")
    func codable() throws {
        var (doc, _, _) = try Self.edit()
        doc.mergeRange(6000..<10_000)
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back == doc)
    }

    @Test("A document with no merged clip writes nothing new")
    func writesNothingNew() throws {
        let (doc, _, _) = try Self.edit()
        let json = String(decoding: try JSONEncoder().encode(doc), as: UTF8.self)
        #expect(!json.contains("merged"))
    }

    // MARK: - Like any clip

    @Test("Moved along, it plays what it held from its new place")
    func moved() throws {
        var (doc, _, _) = try Self.edit()
        let made2 = doc.mergeRange(6000..<10_000)

        let id = try #require(made2.first)
        let heldAtStart = Self.seen(doc, atMS: 6000)
        let heldAtEnd = Self.seen(doc, atMS: 9000)
        let did12 = doc.moveClip(id, toInMS: 14_000)

        #expect(did12)
        #expect(Self.seen(doc, atMS: 14_000) == heldAtStart)
        #expect(Self.seen(doc, atMS: 17_000) == heldAtEnd)
    }

    @Test("Trimmed, it shows more or less of what it holds, like a clip into its recording")
    func trimmed() throws {
        var (doc, _, _) = try Self.edit()
        let made3 = doc.mergeRange(6000..<10_000)

        let id = try #require(made3.first)
        let take = Self.take
        // A second off the start: it now starts at 7s showing the take at 7s.
        let did13 = doc.trimClipStart(id, ofPiece: 0, byMS: 1000)

        #expect(did13)
        #expect(doc.layer(id: id)?.time?.inMS == 6000)
        #expect(Self.seen(doc, atMS: 6000) == ["\(take.id):\(take.frameSourceMS(atSourceMS: 7000))"])
        // ...and dragged back out past where the range started, into the spare.
        let did14 = doc.trimClipStart(id, ofPiece: 0, byMS: -3000)

        #expect(did14)
        #expect(Self.seen(doc, atMS: 6000) == ["\(take.id):\(take.frameSourceMS(atSourceMS: 4000))"])
    }

    @Test("It takes a transition on the cut it arrives at, paid for out of its spare")
    func takesATransition() throws {
        var (doc, take, _) = try Self.edit()
        let made4 = doc.mergeRange(6000..<10_000)

        let id = try #require(made4.first)
        let cut = try #require(doc.documentCut(at: .edit(outgoing: take, incoming: id)))
        #expect(cut.cut.spareBeforeInMS == 6000)
        let did15 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000),
                                  at: .edit(outgoing: take, incoming: id))

        #expect(did15)
        // Half way into the dissolve both sides are fetched: the take running
        // on, and the merged clip reading early into what it holds.
        let frames = doc.movieFrames(atTimeMS: 5750)
        #expect(frames.count == 2)
        let drawn = doc.drawn(atTimeMS: 5750)
        #expect(drawn.layers.contains { $0.id == Layer.transitionPartnerID(of: take) || $0.id == id })
    }

    @Test("Split, each piece plays its own stretch")
    func split() throws {
        var (doc, _, _) = try Self.edit()
        let before = doc
        let made5 = doc.mergeRange(6000..<10_000)

        let id = try #require(made5.first)
        let did16 = doc.splitClip(id, atMS: 7000)

        #expect(did16)
        Self.expectPlaysTheSame(before, doc)
    }

    @Test("Duplicated, the copy holds copies: no id is shared")
    func duplicated() throws {
        var (doc, _, _) = try Self.edit()
        let made6 = doc.mergeRange(6000..<10_000)

        let id = try #require(made6.first)
        let layer = try #require(doc.layer(id: id))
        let copy = layer.duplicated()
        let inner = Set(layer.merged?.layers.map(\.id) ?? [])
        let copied = Set(copy.merged?.layers.map(\.id) ?? [])
        #expect(copied.count == 2)
        #expect(inner.isDisjoint(with: copied))
    }

    @Test("A merged clip has nothing to arrange, and its sound shows under it like a recording's")
    func panelAndSound() throws {
        var (doc, _, _) = try Self.edit()
        let made = doc.mergeRange(6000..<10_000)
        let id = try #require(made.first)
        #expect(doc.contentsSelection(layerIDs: [id]).isEmpty)
        #expect(doc.layer(id: id)?.hasLinkedSound == true)
    }

    // MARK: - Breaking it apart

    @Test("Break Apart puts the original clips back where they were")
    func breakApartRestores() throws {
        var (doc, take, broll) = try Self.edit()
        let original = doc
        let made7 = doc.mergeRange(6000..<10_000)

        let id = try #require(made7.first)
        #expect(doc.canBreakApart(id))
        doc.breakApart(id)
        let track = try Self.v1(doc)
        #expect(Self.spans(doc, track: track) == [0..<8000, 8000..<12_000])
        #expect(doc.layer(id: take)?.time == original.layer(id: take)?.time)
        #expect(doc.layer(id: broll)?.time == original.layer(id: broll)?.time)
        #expect(doc.layer(id: id) == nil)
        Self.expectPlaysTheSame(original, doc)
    }

    @Test("A transition on the cut inside comes back out with the clips")
    func transitionInsideSurvives() throws {
        var (doc, take, broll) = try Self.edit()
        let did17 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000),
                                  at: .edit(outgoing: take, incoming: broll))

        #expect(did17)
        let original = doc
        let made8 = doc.mergeRange(6000..<10_000)

        let id = try #require(made8.first)
        Self.expectPlaysTheSame(original, doc)
        doc.breakApart(id)
        #expect(doc.layer(id: broll)?.arrivalTransition?.kind == .dissolve)
        Self.expectPlaysTheSame(original, doc)
    }

    @Test("Broken apart after a move, the clips come out where the merged clip was")
    func breakApartAfterMove() throws {
        var (doc, _, _) = try Self.edit()
        let made9 = doc.mergeRange(6000..<10_000)

        let id = try #require(made9.first)
        doc.moveClip(id, toInMS: 14_000)
        let moved = doc
        doc.breakApart(id)
        let track = try Self.v1(doc)
        #expect(Self.spans(doc, track: track) == [0..<6000, 10_000..<12_000, 14_000..<16_000, 16_000..<18_000])
        for ms in stride(from: 14_000, to: 18_000, by: 250) {
            #expect(Self.seen(doc, atMS: ms) == Self.seen(moved, atMS: ms))
        }
    }

    @Test("Broken apart after a trim, only what was showing comes back")
    func breakApartAfterTrim() throws {
        var (doc, _, _) = try Self.edit()
        let made10 = doc.mergeRange(6000..<10_000)

        let id = try #require(made10.first)
        let did18 = doc.trimClipEnd(id, ofPiece: 0, byMS: -1000)

        #expect(did18)
        let trimmed = doc
        doc.breakApart(id)
        let track = try Self.v1(doc)
        #expect(Self.spans(doc, track: track) == [0..<8000, 8000..<9000, 10_000..<12_000])
        for ms in stride(from: 0, to: 12_000, by: 250) {
            #expect(Self.seen(doc, atMS: ms) == Self.seen(trimmed, atMS: ms))
        }
    }

    @Test("Ungroup on a merged clip breaks it apart rather than throwing it away")
    func ungroupBreaksApart() throws {
        var (doc, take, _) = try Self.edit()
        let original = doc
        let made11 = doc.mergeRange(6000..<10_000)

        let id = try #require(made11.first)
        #expect(doc.canUngroup(ids: [id]))
        let freed = doc.ungroupLayers(ids: [id])
        #expect(freed.contains(take))
        Self.expectPlaysTheSame(original, doc)
    }

    // MARK: - Sound

    @Test("Sound clips on a sound track merge into a clip on that track, and are heard the same")
    func soundTrack() throws {
        var (doc, _, _) = try Self.edit()
        let sound = SoundRef(durationMS: 20_000)
        var music = Layer(name: "music", content: .sound(sound), frame: .zero)
        music.time = LayerTime(inMS: 0, outMS: 12_000, sourceInMS: 0, sourceLengthMS: 20_000)
        let landing = doc.clipLanding(kind: .audio, lengthMS: 12_000, atMS: 0, over: nil, edit: .overwrite)
        let put = doc.land(music, at: landing)
        let landed = try #require(put)
        let before = doc
        let made = doc.mergeRange(6000..<10_000)
        #expect(made.count == 2)
        let soundTrack = doc.trackID(ofClip: landed)
        let onSound = try #require(made.first { doc.trackID(ofClip: $0) == soundTrack })
        #expect(doc.layer(id: onSound)?.timelineTrackKind == .audio)
        Self.expectPlaysTheSame(before, doc)
    }

    // MARK: - Saving

    @Test("What a merged clip holds is part of the project's media")
    func mediaInside() throws {
        var (doc, _, _) = try Self.edit()
        doc.mergeRange(0..<12_000)
        #expect(doc.hasMovies)
        let found = ProjectMedia.references(in: doc).compactMap { media -> UUID? in
            if case .recording(let movie) = media { return movie.id }
            return nil
        }
        #expect(Set(found) == [Self.take.id, Self.broll.id])
    }
}
