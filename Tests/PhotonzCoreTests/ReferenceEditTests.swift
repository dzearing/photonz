import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **The reference edit** (`ReferenceEdit.swift`, task
/// `a-long-reference-edit-opens-in-the-probe-in-one`).
///
/// Every speed fix for video measures against the same long, busy edit, so a
/// number before a change and a number after it mean something. Written before
/// the builder: the edit holds what the video-perf objective lists, the same
/// seed gives the same document, and the long versions are the recipe carried
/// on with varied cuts rather than one stretch looped.
@Suite("The reference edit")
struct ReferenceEditTests {

    static let six = ReferenceEdit.build(minutes: 6)

    @Test("The 6 minute edit holds everything the video-perf objective lists")
    func sixMinutesHoldsTheObjectivesList() {
        let census = ReferenceEdit.census(of: Self.six)
        #expect(census.lengthMS == 360_000)
        #expect(census.pictureTracks >= 3)
        #expect(census.cuts >= 30)
        // Dissolves at most cuts, plus at least one push and one in depth.
        let dissolves = census.transitions[.dissolve] ?? 0
        #expect(dissolves * 2 > census.cuts)
        #expect((census.transitions[.push] ?? 0) >= 1)
        #expect(census.transitions.keys.contains { $0.isInDepth })
        #expect(census.titles >= 4)
        #expect(census.titlesOnAMovingBackground >= 1)
        #expect(census.zooms >= 6)
        #expect(census.movingBackgrounds >= 1)
        #expect(census.recordingSize == CGSize(width: 3456, height: 2234))
        #expect(census.clipsWithSound >= 30)
        #expect(census.musicClips >= 1)
        #expect(census.musicCoverageMS == census.lengthMS)
        #expect(ReferenceEdit.shortfalls(census, minutes: 6).isEmpty,
                "\(ReferenceEdit.shortfalls(census, minutes: 6))")
    }

    @Test("The bar bites: a plain recording falls short of it on every line that matters")
    func theBarBites() {
        let movie = MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 360_000, hasSound: true)
        let plain = PhotonzDocument.recording(movie, name: "plain")
        let short = ReferenceEdit.shortfalls(ReferenceEdit.census(of: plain), minutes: 6)
        #expect(short.count >= 6)
        #expect(short.contains { $0.contains("cuts") })
        #expect(short.contains { $0.contains("Retina") })
    }

    @Test("Same seed, same document; another seed, another edit")
    func sameSeedSameDocument() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let a = try encoder.encode(ReferenceEdit.build(minutes: 6, seed: 7))
        let b = try encoder.encode(ReferenceEdit.build(minutes: 6, seed: 7))
        #expect(a == b)
        let c = try encoder.encode(ReferenceEdit.build(minutes: 6, seed: 8))
        #expect(a != c)
        // ...and the default is a seed, not chance.
        let d = try encoder.encode(Self.six)
        let e = try encoder.encode(ReferenceEdit.build(minutes: 6))
        #expect(d == e)
    }

    @Test("Every cut's transition is one the cut can pay for, and nothing on a track overlaps")
    func everyTransitionFits() {
        let doc = Self.six
        #expect(!doc.clipsOverlapOnATrack)
        let cuts = doc.transitionCuts()
        #expect(cuts.count >= 30)
        // The census counts what the model's own list of cuts holds.
        let census = ReferenceEdit.census(of: doc)
        #expect(cuts.count == census.cuts)
        var kinds: [ClipTransitionKind: Int] = [:]
        for cut in cuts { if let kind = cut.cut.transition?.kind { kinds[kind, default: 0] += 1 } }
        #expect(kinds == census.transitions)
        for cut in cuts {
            guard let transition = cut.cut.transition else { continue }
            #expect(transition.lengthMS <= cut.cut.longestMS(for: transition), "\(cut.atMS)")
        }
        // Every recording clip reads inside its file.
        for layer in doc.allLayers {
            guard let movie = layer.movie, let time = layer.time else { continue }
            #expect(time.sourceInMS >= 0)
            #expect(time.sourceInMS + time.lengthMS <= movie.durationMS)
            #expect(ReferenceEdit.footage.contains { $0.movie == movie })
        }
    }

    @Test("Zooms sit inside the stretch of recording their clip plays")
    func zoomsInsideTheirClips() {
        var seen = 0
        for layer in Self.six.allLayers {
            guard let zooms = layer.zooms, let time = layer.time else { continue }
            for zoom in zooms {
                seen += 1
                #expect(zoom.startMS >= time.sourceInMS)
                #expect(zoom.endMS <= time.sourceInMS + time.lengthMS)
            }
        }
        #expect(seen >= 6)
    }

    @Test("20 and 60 minute versions are the recipe carried on with varied cuts, not one stretch looped")
    func longVersionsCarryOn() {
        let twenty = ReferenceEdit.census(of: ReferenceEdit.build(minutes: 20))
        #expect(twenty.lengthMS == 1_200_000)
        #expect(ReferenceEdit.shortfalls(twenty, minutes: 20).isEmpty, "\(ReferenceEdit.shortfalls(twenty, minutes: 20))")

        let hour = ReferenceEdit.build(minutes: 60)
        let census = ReferenceEdit.census(of: hour)
        #expect(census.lengthMS == 3_600_000)
        #expect(census.clips >= 300)
        #expect(census.cuts >= 300)
        #expect(ReferenceEdit.shortfalls(census, minutes: 60).isEmpty, "\(ReferenceEdit.shortfalls(census, minutes: 60))")

        // Each six minute stretch of the hour is cut differently: which
        // recording, from where and for how long.
        let main = hour.allLayers
            .filter { $0.movie != nil && $0.name.hasPrefix(ReferenceEdit.mainClipPrefix) }
            .compactMap { layer -> (Int, Int, Int, UUID)? in
                guard let time = layer.time, let movie = layer.movie else { return nil }
                return (time.inMS, time.sourceInMS, time.lengthMS, movie.id)
            }
            .sorted { $0.0 < $1.0 }
        var stretches: [[String]] = []
        for block in 0..<10 {
            let range = (block * 360_000)..<((block + 1) * 360_000)
            stretches.append(main.filter { range.contains($0.0) }
                .map { "\($0.1)/\($0.2)/\($0.3)" })
        }
        #expect(Set(stretches).count == 10)
    }

    @Test("Opening it needs only the recordings and the music it names")
    func namesItsFiles() {
        let refs = ProjectMedia.references(in: Self.six)
        let ids = Set(refs.map { DocumentMediaSource(media: $0, name: "").id })
        let named = Set(ReferenceEdit.footage.map(\.movie.id) + [ReferenceEdit.music.sound.id])
        #expect(ids == named)
        #expect(ReferenceEdit.footage.count >= 3)
        for footage in ReferenceEdit.footage {
            #expect(footage.movie.pixelSize == ReferenceEdit.pixelSize)
            #expect(footage.movie.hasSound)
            #expect(footage.fileName.hasSuffix(".mov"))
        }
        // The files are re-made when the recipe changes: its version is in
        // the folder they are kept in.
        #expect(ReferenceEdit.footageFolderName.contains("\(ReferenceEdit.recipeVersion)"))
    }

    @Test("A walk asks for it by length, and only a length it is kept at")
    func aWalkAsksForIt() throws {
        #expect(try PlaytestSetup(fields: ["referenceEdit": 6]).referenceEdit == 6)
        #expect(try PlaytestSetup(fields: ["referenceEdit": 60]).isEmpty == false)
        #expect(try PlaytestSetup(fields: [:]).referenceEdit == nil)
        #expect(throws: PlaytestScriptError.self) { try PlaytestSetup(fields: ["referenceEdit": 7]) }
        #expect(throws: PlaytestScriptError.self) { try PlaytestSetup(fields: ["referenceEdit": true]) }
    }

    @Test("Its contact sheet looks at twelve moments, four of them in the middle of a transition")
    func twelveMoments() {
        let moments = ReferenceEdit.sheetMoments(of: Self.six)
        #expect(moments.count == 12)
        #expect(moments.map(\.ms) == moments.map(\.ms).sorted())
        #expect(moments.filter { $0.what.hasPrefix("mid-") }.count >= 4)
        #expect(moments.allSatisfy { $0.ms >= 0 && $0.ms < 360_000 })
    }
}
