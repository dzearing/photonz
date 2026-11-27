import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Changing a clip's speed keeps the edit joined up** (`PhotonzDocument.setClipSpeed`, `ClipPieces.swift`).
///
/// A clip played at 200 percent takes half as long. Before this, the clips
/// after it on its track stayed where they were, so the edit had a stretch of
/// black where the clip used to be, and the transition on the next cut stopped
/// being drawn, because a transition between two clips is only drawn while
/// they meet. Now the clips after it on its own track move along by however
/// much the clip grew or shrank, the way Final Cut's primary storyline and
/// Premiere's Speed with Ripple Edit do, and the cut after it keeps its
/// transition.
@Suite("Changing a clip's speed keeps the edit joined up")
struct SpeedRippleTests {

    /// Twenty seconds recorded, so every clip has spare media either side.
    static let take = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 20_000)

    /// Three clips butted on V1: A 0 to 4s, B 4 to 7s, C 7 to 10s, with a
    /// dissolve on both cuts, and a title on its own track over C at 8 to 9s.
    static func edit() throws -> (doc: PhotonzDocument, a: UUID, b: UUID, c: UUID, v1: UUID, title: UUID) {
        var doc = PhotonzDocument.recording(Self.take, name: "A")
        let a = doc.layers[0].id
        doc.updateLayer(id: a) {
            $0.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 1000, sourceLengthMS: 20_000)
        }
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        func clip(_ name: String, at: Int, length: Int, from: Int) throws -> UUID {
            var layer = Layer(name: name, content: .image(Self.take.frameRef(atSourceMS: from)),
                              frame: CGRect(origin: .zero, size: Self.take.pixelSize))
            layer.movie = Self.take
            layer.time = LayerTime(inMS: 0, outMS: length, sourceInMS: from, sourceLengthMS: 20_000)
            let landing = doc.clipLanding(kind: .video, lengthMS: length, atMS: at,
                                          over: .onto(v1), edit: .overwrite)
            let landed = doc.land(layer, at: landing)
            return try #require(landed)
        }
        let b = try clip("B", at: 4000, length: 3000, from: 6000)
        let c = try clip("C", at: 7000, length: 3000, from: 12_000)
        let dissolve = ClipTransition(kind: .dissolve, lengthMS: 800)
        let did1 = doc.setTransition(dissolve, at: .edit(outgoing: a, incoming: b))
        #expect(did1)
        let did2 = doc.setTransition(dissolve, at: .edit(outgoing: b, incoming: c))
        #expect(did2)
        var title = Layer(name: "callout", content: .text(TextContent(string: "Hi")),
                          frame: CGRect(x: 0, y: 0, width: 50, height: 20))
        title.time = LayerTime(inMS: 8000, outMS: 9000)
        doc.layers.append(title)
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [4000, 7000])
        return (doc, a, b, c, v1, title.id)
    }

    static func span(_ doc: PhotonzDocument, _ id: UUID) -> [Int] {
        guard let time = doc.layer(id: id)?.time else { return [] }
        return [time.inMS, time.outMS]
    }

    @Test("At 200 percent the clip after it moves up to meet it: no black, and its transition is still on the cut")
    func fasterClosesTheGap() throws {
        var (doc, a, b, c, v1, _) = try Self.edit()
        let did3 = doc.setClipSpeed(b, ofPiece: 0, percent: 200)
        #expect(did3)
        #expect(Self.span(doc, b) == [4000, 5500])
        #expect(Self.span(doc, c) == [5500, 8500])
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [4000, 5500])
        let next = try #require(doc.documentCut(at: .edit(outgoing: b, incoming: c)))
        #expect(next.cut.transition?.kind == .dissolve)
        #expect(doc.documentCut(at: .edit(outgoing: a, incoming: b))?.cut.transition?.kind == .dissolve)
        // The edit now runs to the callout's end, on its own track, at 9s.
        #expect(doc.durationMS == 9000)
    }

    @Test("At 50 and 25 percent the clip after it is pushed along rather than run over")
    func slowerPushesAlong() throws {
        for (percent, length) in [(50, 6000), (25, 12_000)] {
            var (doc, _, b, c, v1, _) = try Self.edit()
            let did4 = doc.setClipSpeed(b, ofPiece: 0, percent: percent)
            #expect(did4)
            #expect(Self.span(doc, b) == [4000, 4000 + length], "\(percent)")
            #expect(Self.span(doc, c) == [4000 + length, 7000 + length], "\(percent)")
            #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [4000, 4000 + length], "\(percent)")
            #expect(doc.documentCut(at: .edit(outgoing: b, incoming: c))?.cut.transition?.kind == .dissolve)
        }
    }

    @Test("Back to 100 percent puts every clip where it started")
    func backAgain() throws {
        let (start, _, b, _, _, _) = try Self.edit()
        var doc = start
        let did5 = doc.setClipSpeed(b, ofPiece: 0, percent: 200)
        #expect(did5)
        let did6 = doc.setClipSpeed(b, ofPiece: 0, percent: 100)
        #expect(did6)
        for layer in start.allLayers {
            #expect(doc.layer(id: layer.id)?.time == layer.time, "\(layer.name)")
        }
    }

    @Test("A gap somebody left after the clip travels with the clips after it")
    func aGapKeepsItsLength() throws {
        var (doc, _, b, c, _, _) = try Self.edit()
        let did7 = doc.moveClip(c, toInMS: 8000)
        #expect(did7)
        let did8 = doc.setClipSpeed(b, ofPiece: 0, percent: 200)
        #expect(did8)
        #expect(Self.span(doc, c) == [6500, 9500])
    }

    @Test("Only the clip's own track moves: a title on another track stays where it was put")
    func otherTracksStay() throws {
        var (doc, _, b, _, _, title) = try Self.edit()
        let did9 = doc.setClipSpeed(b, ofPiece: 0, percent: 200)
        #expect(did9)
        #expect(Self.span(doc, title) == [8000, 9000])
    }

    @Test("Undo puts everything back in one step")
    func undoInOneStep() throws {
        let (start, _, b, _, _, _) = try Self.edit()
        var history = History(document: start)
        history.perform { doc in _ = doc.setClipSpeed(b, ofPiece: 0, percent: 200) }
        history.undo()
        for layer in start.allLayers {
            #expect(history.current.layer(id: layer.id)?.time == layer.time, "\(layer.name)")
        }
        #expect(!history.canUndo)
    }

    @Test("A piece inside a cut clip pushes the clips after the whole clip")
    func aPieceOfACutClip() throws {
        var (doc, _, b, c, _, _) = try Self.edit()
        let did10 = doc.splitClip(b, atMS: 5500)
        #expect(did10)
        let did11 = doc.setClipSpeed(b, ofPiece: 1, percent: 50)
        #expect(did11)
        #expect(Self.span(doc, b) == [4000, 8500])
        #expect(Self.span(doc, c) == [8500, 11_500])
    }

    @Test("Speed for a section across a cut retimes both sides and leaves no gap between them")
    func aSectionAcrossACut() throws {
        var (doc, a, b, c, v1, _) = try Self.edit()
        let did = doc.setSectionSpeed([a, b], within: 3000..<5000, percent: 200)
        #expect(did)
        #expect(Self.span(doc, a) == [0, 3500])
        #expect(Self.span(doc, b) == [3500, 6000])
        #expect(Self.span(doc, c) == [6000, 9000])
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [3500, 6000])
    }
}
