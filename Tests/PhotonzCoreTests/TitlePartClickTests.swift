import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A title is see-through to the Select tool (task
/// `editing-a-title-never-starts-playback-and-every`): a single click on any
/// part of a title (headline, subtitle, kicker, accent, backing shape,
/// background) picks that part, the way a click on a layer of a graphic in
/// Premiere's Program monitor does. The title is the context the part was
/// picked in, so Escape steps up to the whole title, and a title already held
/// whole stays whole under the next click so it can be dragged.
@Suite("A click on a title picks the part under the pointer")
struct TitlePartClickTests {

    static func placed(_ preset: BuiltInTitle) throws -> (PhotonzDocument, UUID) {
        var doc = TitleRestyleTests.tenSeconds()
        let landed = doc.insertTitle(preset, atTimeMS: 0)
        let inserted = try #require(landed)
        return (doc, inserted.layerID)
    }

    static func part(_ name: String, of title: UUID, in doc: PhotonzDocument) throws -> Layer {
        let layer = try #require(doc.layer(id: title))
        let piece = try #require(TitleDesign.find(name, in: layer))
        return try #require(doc.canvasLayer(id: piece.id))
    }

    static func centre(_ layer: Layer) -> CGPoint {
        CGPoint(x: layer.frame.midX, y: layer.frame.midY)
    }

    @Test("A click on the subtitle picks the subtitle, inside the title")
    func subtitle() throws {
        let (doc, title) = try Self.placed(.keynote)
        let subtitle = try Self.part("Subtitle", of: title, in: doc)
        let pick = try #require(doc.selectionTarget(at: Self.centre(subtitle), inside: nil))
        #expect(pick.id == subtitle.id)
        #expect(pick.context == title)
    }

    @Test("A click on the headline picks the headline")
    func headline() throws {
        let (doc, title) = try Self.placed(.keynote)
        let headline = try Self.part("Title", of: title, in: doc)
        let pick = try #require(doc.selectionTarget(at: Self.centre(headline), inside: nil))
        #expect(pick.id == headline.id)
        #expect(pick.context == title)
    }

    @Test("A click on the open background picks the Background part")
    func background() throws {
        let (doc, title) = try Self.placed(.keynote)
        let backdrop = try Self.part("Background", of: title, in: doc)
        let pick = try #require(doc.selectionTarget(at: CGPoint(x: 20, y: 20), inside: nil))
        #expect(pick.id == backdrop.id)
        #expect(pick.context == title)
    }

    @Test("Inside the title already, a click on another part picks that part")
    func siblingFromAPart() throws {
        let (doc, title) = try Self.placed(.keynote)
        let subtitle = try Self.part("Subtitle", of: title, in: doc)
        let headline = try Self.part("Title", of: title, in: doc)
        let pick = try #require(doc.selectionTarget(at: Self.centre(subtitle), inside: title,
                                                    holding: headline.id))
        #expect(pick.id == subtitle.id)
        #expect(pick.context == title)
    }

    @Test("A title held whole stays whole under the next click, so it can be dragged")
    func heldWhole() throws {
        let (doc, title) = try Self.placed(.keynote)
        let subtitle = try Self.part("Subtitle", of: title, in: doc)
        let pick = try #require(doc.selectionTarget(at: Self.centre(subtitle), inside: nil,
                                                    holding: title))
        #expect(pick.id == title)
        #expect(pick.context == nil)
    }

    @Test("A double click on a part held inside a title goes no deeper, so its words open")
    func doubleClickOpensWords() throws {
        let (doc, title) = try Self.placed(.keynote)
        let subtitle = try Self.part("Subtitle", of: title, in: doc)
        #expect(doc.descendTarget(at: Self.centre(subtitle), inside: title) == nil)
    }

    @Test("Every part of every title is picked by a click on it",
          arguments: BuiltInTitle.shelved)
    func everyPart(_ preset: BuiltInTitle) throws {
        let (doc, title) = try Self.placed(preset)
        let layer = try #require(doc.layer(id: title))
        let recipe = try #require(layer.group?.titleRecipe)
        let parts = Set(recipe.design.parts.compactMap { TitleDesign.find($0.path, in: layer)?.id })
        for part in recipe.design.parts {
            guard let piece = TitleDesign.find(part.path, in: layer),
                  let drawn = doc.canvasLayer(id: piece.id), piece.isVisible,
                  drawn.frame.width > 0, drawn.frame.height > 0 else { continue }
            guard let pick = doc.selectionTarget(at: Self.centre(drawn), inside: nil) else { continue }
            // Whatever lies on top at that point, the click lands on a part
            // of this title and never on the title as a whole.
            if doc.isDescendant(pick.id, of: title) {
                #expect(parts.contains(pick.id), "\(preset): \(part.path) gave \(pick.id)")
                #expect(pick.context == title, "\(preset): \(part.path)")
            }
        }
    }

    @Test("A double click on a title held whole goes in to the part under the pointer")
    func doubleClickIntoAHeldTitle() throws {
        let (doc, title) = try Self.placed(.keynote)
        let backdrop = try Self.part("Background", of: title, in: doc)
        let pick = try #require(doc.descendTarget(at: CGPoint(x: 20, y: 20), inside: nil, holding: title))
        #expect(pick.id == backdrop.id)
        #expect(pick.context == title)
    }

    @Test("A shift-click on a title from the top level adds the title whole")
    func shiftClickAddsTheTitle() throws {
        let (doc, title) = try Self.placed(.keynote)
        let subtitle = try Self.part("Subtitle", of: title, in: doc)
        #expect(doc.extendTarget(at: Self.centre(subtitle), inside: nil) == title)
    }

    // MARK: One part's own in, for its Replay

    @Test("A part's in runs inside the title's own arrival")
    func partArrival() throws {
        let (doc, title) = try Self.placed(.keynote)
        let subtitle = try Self.part("Subtitle", of: title, in: doc)
        let span = try #require(doc.titlePartArrival(layerID: title, pieceID: subtitle.id))
        #expect(span.lowerBound >= 0)
        #expect(span.upperBound > span.lowerBound)
        #expect(span.upperBound <= doc.titleArrivalMS(layerID: title))
    }

    @Test("A part with no in has nothing to replay")
    func partWithNoIn() throws {
        var (doc, title) = try Self.placed(.keynote)
        let layer = try #require(doc.layer(id: title))
        let recipe = try #require(layer.group?.titleRecipe)
        let index = try #require(recipe.design.parts.firstIndex { $0.role == .subtitle })
        #expect(doc.restyleTitle(layerID: title) { $0.design.parts[index].in = nil })
        let subtitle = try Self.part("Subtitle", of: title, in: doc)
        #expect(doc.titlePartArrival(layerID: title, pieceID: subtitle.id) == nil)
    }

    @Test("The title itself is not one of its parts")
    func titleIsNotAPart() throws {
        let (doc, title) = try Self.placed(.keynote)
        #expect(doc.titlePartArrival(layerID: title, pieceID: title) == nil)
    }

    @Test("Replaying one part draws every other part at rest, and that part on its own clock")
    func onlyOnePartMoves() throws {
        let (doc, title) = try Self.placed(.keynote)
        let subtitle = try Self.part("Subtitle", of: title, in: doc)
        let headline = try Self.part("Title", of: title, in: doc)
        let span = try #require(doc.titlePartArrival(layerID: title, pieceID: subtitle.id))
        let early = span.lowerBound + 1
        let held = doc.drawn(atTimeMS: doc.titleArrivalMS(layerID: title))
        let plain = doc.drawn(atTimeMS: early)
        let only = doc.drawn(atTimeMS: early, onlyMoving: subtitle.id, inTitle: title)
        // The headline is where it rests, not where it is part way in.
        #expect(only.layer(id: headline.id) == held.layer(id: headline.id))
        // The subtitle is exactly as the plain moment draws it.
        #expect(only.layer(id: subtitle.id) == plain.layer(id: subtitle.id))
    }

    @Test("Outside the title's own time the drawing is the plain one")
    func onlyOnePartMovesOutside() throws {
        let (doc, title) = try Self.placed(.keynote)
        let subtitle = try Self.part("Subtitle", of: title, in: doc)
        let after = 9_000
        #expect(doc.drawn(atTimeMS: after, onlyMoving: subtitle.id, inTitle: title) == doc.drawn(atTimeMS: after))
    }
}
