import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A part of something placed in time has a stretch of its own, set by
/// dragging its bar on the timeline (task
/// `any-timeline-row-that-holds-sub-layers-expands-a`).
///
/// Written before the code. A part of a group placed at two seconds is on
/// screen while its group is; dragging the part's bar gives it a stretch of its
/// own INSIDE its group's, measured on the group's clock, so moving the group
/// carries its parts along and a part can never be on screen while its group is
/// not. Sliding the bar's middle carries the part's keys with it, the way an
/// After Effects layer bar does.
@Suite("A part of something placed in time has its own stretch")
struct LayerPartTimeTests {

    // MARK: - Fixtures

    static func shape(_ name: String) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
              frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    static func group(_ name: String, _ children: [Layer]) -> Layer {
        Layer(name: name, content: .group(GroupContent(children: children)),
              frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    /// A logo placed from 2 s to 6 s holding a Mark and a Word, and inside the
    /// Word a group of two Letters: three levels, the deepest a grandchild.
    static func logo() -> (PhotonzDocument, logo: UUID, mark: UUID, word: UUID, letter: UUID) {
        let letter = shape("Letter A")
        let word = group("Word", [letter, shape("Letter B")])
        let mark = shape("Mark")
        var logo = group("Logo", [mark, word])
        logo.time = LayerTime(inMS: 2_000, outMS: 6_000)
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [logo]
        doc.durationMS = 8_000
        return (doc, logo.id, mark.id, word.id, letter.id)
    }

    static func visible(_ doc: PhotonzDocument, at ms: Int) -> Set<String> {
        func walk(_ list: [Layer]) -> [String] {
            list.flatMap { layer -> [String] in
                guard layer.isVisible else { return [] }
                return [layer.name] + walk(layer.children)
            }
        }
        return Set(walk(doc.drawn(atTimeMS: ms).layers))
    }

    // MARK: - Reading

    @Test("A part with no stretch of its own runs across the thing it is inside")
    func plainPartSpansItsParent() throws {
        let (doc, _, mark, _, letter) = Self.logo()
        let stretch = try #require(doc.partStretch(of: mark))
        #expect(stretch.startMS == 2_000)
        #expect(stretch.endMS == 6_000)
        #expect(stretch.boundsStartMS == 2_000)
        #expect(stretch.boundsEndMS == 6_000)
        #expect(!stretch.hasOwnTime)
        // ...and so does a grandchild.
        let deep = try #require(doc.partStretch(of: letter))
        #expect(deep.startMS == 2_000 && deep.endMS == 6_000)
    }

    @Test("Only a part of something placed in time has a part stretch")
    func onlyPartsOfPlacedThings() {
        let (doc, logo, _, _, _) = Self.logo()
        // The logo itself is a clip with a time of its own.
        #expect(doc.partStretch(of: logo) == nil)
        // A group with no time at the top: its parts are simply there.
        var loose = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        let piece = Self.shape("Piece")
        loose.layers = [Self.group("Loose", [piece])]
        #expect(loose.partStretch(of: piece.id) == nil)
    }

    // MARK: - Retiming

    @Test("Dragging a part's start later starts it later and leaves its end")
    func startLater() throws {
        var (doc, _, mark, _, _) = Self.logo()
        let r1 = doc.retimePart(mark, grab: .start, byMS: 500)
        #expect(r1)
        let stretch = try #require(doc.partStretch(of: mark))
        #expect(stretch.startMS == 2_500)
        #expect(stretch.endMS == 6_000)
        #expect(stretch.hasOwnTime)
        // Written on the logo's clock, which starts at the logo's in.
        let part = try #require(doc.layer(id: mark)?.partTime)
        #expect(part.fromMS == 500)
        #expect(part.toMS == 4_000)
        #expect(part.shiftMS == 0)
    }

    @Test("Dragging a part's end earlier ends it earlier and leaves its start")
    func endEarlier() throws {
        var (doc, _, mark, _, _) = Self.logo()
        let r2 = doc.retimePart(mark, grab: .end, byMS: -1_000)
        #expect(r2)
        let stretch = try #require(doc.partStretch(of: mark))
        #expect(stretch.startMS == 2_000)
        #expect(stretch.endMS == 5_000)
    }

    @Test("A part never runs outside the thing it is inside, and never shrinks below a frame")
    func clampedToParent() throws {
        var (doc, _, mark, _, _) = Self.logo()
        // An end pushed past the logo's out stops at it: nothing to change.
        let r3 = doc.retimePart(mark, grab: .end, byMS: 900)
        #expect(!r3)
        // A start pulled past the end stops a frame short of it.
        let r4 = doc.retimePart(mark, grab: .start, byMS: 9_000)
        #expect(r4)
        let stretch = try #require(doc.partStretch(of: mark))
        #expect(stretch.endMS == 6_000)
        #expect(stretch.startMS == 6_000 - LayerTime.shortestMS)
    }

    @Test("Sliding a part's middle moves both ends and stops at the thing it is inside")
    func slide() throws {
        var (doc, _, mark, _, _) = Self.logo()
        let r5 = doc.retimePart(mark, grab: .end, byMS: -2_000)
        #expect(r5)   // 2.0 to 4.0
        let r6 = doc.retimePart(mark, grab: .body, byMS: 1_000)
        #expect(r6)   // 3.0 to 5.0
        var stretch = try #require(doc.partStretch(of: mark))
        #expect(stretch.startMS == 3_000 && stretch.endMS == 5_000)
        // Slid on past the logo's out, it stops with its end on it.
        let r7 = doc.retimePart(mark, grab: .body, byMS: 5_000)
        #expect(r7)
        stretch = try #require(doc.partStretch(of: mark))
        #expect(stretch.startMS == 4_000 && stretch.endMS == 6_000)
        #expect(doc.layer(id: mark)?.partTime?.shiftMS == 2_000)
    }

    @Test("Dragging a bar back over the whole of its parent gives it back to its parent")
    func backToPlain() throws {
        var (doc, _, mark, _, _) = Self.logo()
        let r8 = doc.retimePart(mark, grab: .start, byMS: 500)
        #expect(r8)
        let r9 = doc.retimePart(mark, grab: .start, byMS: -500)
        #expect(r9)
        #expect(doc.layer(id: mark)?.partTime == nil)
    }

    @Test("Retiming one part changes nothing else in the document")
    func onlyThatPart() throws {
        var (doc, logo, mark, word, letter) = Self.logo()
        let before = doc
        let r10 = doc.retimePart(mark, grab: .start, byMS: 500)
        #expect(r10)
        #expect(doc.layer(id: logo)?.time == before.layer(id: logo)?.time)
        #expect(doc.layer(id: word) == before.layer(id: word))
        #expect(doc.layer(id: letter) == before.layer(id: letter))
        #expect(doc.durationMS == before.durationMS)
    }

    @Test("A grandchild is retimed inside its own group's stretch")
    func grandchild() throws {
        var (doc, _, _, word, letter) = Self.logo()
        let r11 = doc.retimePart(word, grab: .start, byMS: 1_000)
        #expect(r11)      // Word 3.0 to 6.0
        let inside = try #require(doc.partStretch(of: letter))
        #expect(inside.boundsStartMS == 3_000)
        #expect(inside.startMS == 3_000)
        // It fills the whole Word, so it has nowhere to slide or start sooner.
        let r12 = doc.retimePart(letter, grab: .body, byMS: -400)
        #expect(!r12)
        let r13 = doc.retimePart(letter, grab: .start, byMS: -400)
        #expect(!r13)
        let r14 = doc.retimePart(letter, grab: .end, byMS: -1_500)
        #expect(r14)     // Letter A 3.0 to 4.5
        let stretch = try #require(doc.partStretch(of: letter))
        #expect(stretch.startMS == 3_000 && stretch.endMS == 4_500)
    }

    @Test("A part inside a copy of a component is not retimed: its contents are its original's")
    func notInsideACopy() {
        var (doc, logo, mark, _, _) = Self.logo()
        doc.updateLayer(id: logo) {
            guard case .group(var content) = $0.content else { return }
            content.instanceOf = UUID()
            $0.content = .group(content)
        }
        let r15 = doc.retimePart(mark, grab: .start, byMS: 500)
        #expect(!r15)
    }

    // MARK: - On screen

    @Test("A part is drawn only inside its own stretch")
    func drawnOnlyInsideItsStretch() {
        var (doc, _, mark, _, _) = Self.logo()
        _ = doc.retimePart(mark, grab: .start, byMS: 1_000)       // Mark from 3.0
        #expect(!Self.visible(doc, at: 2_500).contains("Mark"))
        #expect(Self.visible(doc, at: 2_500).contains("Word"))
        #expect(Self.visible(doc, at: 3_200).contains("Mark"))
        #expect(!Self.visible(doc, at: 6_500).contains("Logo"))
    }

    @Test("A part travels with the thing it is inside when that moves")
    func travelsWithItsParent() throws {
        var (doc, logo, mark, _, _) = Self.logo()
        _ = doc.retimePart(mark, grab: .start, byMS: 1_000)       // Mark 3.0 to 6.0
        _ = doc.moveClip(logo, toInMS: 1_000)                      // Logo 1.0 to 5.0
        let stretch = try #require(doc.partStretch(of: mark))
        #expect(stretch.startMS == 2_000 && stretch.endMS == 5_000)
        #expect(!Self.visible(doc, at: 1_500).contains("Mark"))
        #expect(Self.visible(doc, at: 2_200).contains("Mark"))
    }

    @Test("Sliding a part carries its keys with it")
    func keysTravel() throws {
        var (doc, _, mark, _, _) = Self.logo()
        // A fade from 0.5 s to 1.5 s on the logo's clock: 2.5 s to 3.5 s.
        doc.updateLayer(id: mark) {
            $0.motions = [LayerMotion(property: .opacity, from: .number(0), to: .number(100),
                                      timing: MotionTiming(startMS: 500, durationMS: 1_000))]
        }
        func opacity(_ ms: Int) -> CGFloat {
            doc.drawn(atTimeMS: ms).layer(id: mark)?.style.opacity ?? -1
        }
        let before = [2_600, 3_000, 3_400].map { opacity($0) }
        #expect(before.contains { $0 > 0.1 })
        _ = doc.retimePart(mark, grab: .end, byMS: -1_000)        // 2.0 to 5.0
        _ = doc.retimePart(mark, grab: .body, byMS: 1_000)        // 3.0 to 6.0, keys 3.5 to 4.5
        #expect(opacity(3_200) < 0.1)
        #expect([3_600, 4_000, 4_400].map { opacity($0) } == before)
        // ...and the strip draws its lane where it now happens.
        let lane = try #require(doc.motionStrip().first { $0.layerID == mark }?.lanes.first)
        #expect(lane.timing.startMS == 3_500)
        let row = try #require(doc.motionStrip().first { $0.layerID == mark })
        #expect(row.span?.inMS == 3_000 && row.span?.outMS == 6_000)
    }

    @Test("A part's own stretch is saved and opened again")
    func roundTrips() throws {
        var (doc, _, mark, _, _) = Self.logo()
        _ = doc.retimePart(mark, grab: .start, byMS: 500)
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.layer(id: mark)?.partTime == doc.layer(id: mark)?.partTime)
    }

    @Test("A layer written before parts had stretches opens with none")
    func oldFilesHaveNone() throws {
        let (doc, _, mark, _, _) = Self.logo()
        let data = try JSONEncoder().encode(doc)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("partTime"))
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.layer(id: mark)?.partTime == nil)
    }
}
