import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A straight line from the Line tool, and the edge of a box or an oval, wearing
/// a saved stroke beside the Pen's paths (`SavedStrokes.swift`), so changing the
/// set's weight moves every part of a glyph, not only its paths.
struct SavedStrokeShapesTests {

    // MARK: - Fixtures

    private func path(_ name: String, width: CGFloat = 1.75) -> Layer {
        let anchors = [PathAnchor(point: .zero), PathAnchor(point: CGPoint(x: 40, y: 0)),
                       PathAnchor(point: CGPoint(x: 40, y: 40))]
        let content = PathContent(anchors: anchors, isClosed: false, strokeWidth: width,
                                  strokePosition: .center, lineEnd: .round, lineCorner: .round)
        return Layer(name: name, content: .path(content),
                     frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    private func line(_ name: String = "Line", width: CGFloat = 4,
                      end: PathLineEnd = .flat) -> Layer {
        var content = AnnotationContent(shape: .line, strokeWidth: width, colorHex: "#000000")
        content.lineEnd = end
        var layer = AnnotationBuilder.layer(content: content, from: CGPoint(x: 10, y: 20),
                                            to: CGPoint(x: 90, y: 20))
        layer.name = name
        return layer
    }

    private func shape(_ kind: AnnotationShape, _ name: String, width: CGFloat = 3) -> Layer {
        let content = AnnotationContent(shape: kind, strokeWidth: width, colorHex: "#000000")
        return Layer(name: name, content: .annotation(content),
                     frame: CGRect(x: 100, y: 100, width: 60, height: 40))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    private func kept(_ doc: PhotonzDocument, _ change: (inout PhotonzDocument) -> Void) -> PhotonzDocument {
        var history = History(document: doc)
        history.perform(change)
        return history.current
    }

    private func glyphStroke(_ doc: inout PhotonzDocument, from layer: Layer) throws -> UUID {
        let saved = doc.saveStroke(from: [layer.id], name: "Glyph / stroke 1.75")
        return try #require(saved)
    }

    private func endpoints(_ layer: Layer?) -> (CGPoint?, CGPoint?) {
        (layer?.annotationEndpoint(.start), layer?.annotationEndpoint(.end))
    }

    // MARK: - A line

    @Test func aLineTakesTheWidthAndCapsInOneStep() throws {
        let glyph = path("Glyph"), rule = line(width: 4, end: .flat)
        var doc = document([glyph, rule])
        let id = try glyphStroke(&doc, from: glyph)
        let before = endpoints(doc.layer(id: rule.id))
        let after = kept(doc) { #expect($0.wearSavedStroke(layerIDs: [rule.id], styleID: id) == 1) }
        let worn = try #require(after.layer(id: rule.id)?.annotation)
        #expect(worn.strokeWidth == 1.75)
        #expect(worn.lineEnd == .round)
        #expect(worn.savedStrokeID == id, "the next edit must not let go of it")
        let moved = endpoints(after.layer(id: rule.id))
        #expect(moved.0 == before.0 && moved.1 == before.1, "its ends stay where they were drawn")
    }

    @Test func changingTheWeightMovesTheLineWithThePathsInOneUndoStep() throws {
        let glyph = path("Glyph"), rule = line(width: 4)
        var doc = document([glyph, rule])
        let id = try glyphStroke(&doc, from: glyph)
        doc.wearSavedStroke(layerIDs: [rule.id], styleID: id)
        var history = History(document: doc)
        var heavier = try #require(doc.savedStroke(id: id)?.look)
        heavier.width = 2.5
        heavier.lineEnd = .square
        history.perform { #expect($0.setSavedStroke(styleID: id, look: heavier) == 2) }
        #expect(history.current.layer(id: glyph.id)?.path?.strokeWidth == 2.5)
        #expect(history.current.layer(id: rule.id)?.annotation?.strokeWidth == 2.5)
        #expect(history.current.layer(id: rule.id)?.annotation?.lineEnd == .square)
        #expect(history.current.layer(id: rule.id)?.annotation?.savedStrokeID == id)
        history.undo()
        #expect(history.current.layer(id: rule.id)?.annotation?.strokeWidth == 1.75)
        #expect(history.current.layer(id: glyph.id)?.path?.strokeWidth == 1.75)
    }

    @Test func aLineCanBeSavedFromAndReadsAsAStraightCentredLine() throws {
        let rule = line(width: 2, end: .round)
        var doc = document([rule])
        let saved = doc.saveStroke(from: [rule.id])
        let id = try #require(saved)
        #expect(doc.savedStroke(id: id)?.look
                == StrokeLook(width: 2, lineEnd: .round, lineCorner: .round, strokePosition: .center))
        #expect(doc.layer(id: rule.id)?.annotation?.savedStrokeID == id)
    }

    @Test func aLineAndAPathDrawingTheSameLineReadAsOne() {
        let glyph = path("Glyph", width: 2), rule = line(width: 2, end: .round)
        let doc = document([glyph, rule])
        let selection = doc.savedStrokeSelection(layerIDs: [glyph.id, rule.id])
        #expect(selection.layerIDs == [glyph.id, rule.id])
        #expect(selection.savableStrokeLook?.width == 2)
    }

    @Test func tuningALineByHandLetsGoAndIsReported() throws {
        let glyph = path("Glyph"), rule = line()
        var doc = document([glyph, rule])
        let id = try glyphStroke(&doc, from: glyph)
        doc.wearSavedStroke(layerIDs: [rule.id], styleID: id)
        let tuned = kept(doc) { $0.setShapeLineEnd(layerIDs: [rule.id], to: .flat) }
        #expect(tuned.layer(id: rule.id)?.annotation?.savedStrokeID == nil)
        #expect(tuned.layer(id: rule.id)?.annotation?.strokeWidth == 1.75)
        let report = LinkBreakReport.between(doc, tuned)
        #expect(report.breaks.map(\.kind) == [.savedStroke])
    }

    @Test func anArrowKeepsItsOwnLine() throws {
        let glyph = path("Glyph")
        let arrow = AnnotationBuilder.layer(
            content: AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#000000"),
            from: .zero, to: CGPoint(x: 80, y: 0))
        var doc = document([glyph, arrow])
        let id = try glyphStroke(&doc, from: glyph)
        #expect(doc.wearSavedStroke(layerIDs: [arrow.id], styleID: id) == 0)
        #expect(doc.layer(id: arrow.id)?.annotation?.strokeWidth == 4)
    }

    // MARK: - A box and an oval

    @Test func aBoxAndAnOvalWearItOnTheirEdge() throws {
        let glyph = path("Glyph")
        let box = shape(.rectangle, "Box", width: 3), oval = shape(.ellipse, "Oval", width: 5)
        var doc = document([glyph, box, oval])
        let id = try glyphStroke(&doc, from: glyph)
        let after = kept(doc) {
            #expect($0.wearSavedStroke(layerIDs: [box.id, oval.id], styleID: id) == 2)
        }
        for layer in [box, oval] {
            let edge = try #require(after.layer(id: layer.id)?.style.borderEffects.first)
            #expect(edge.width == 1.75)
            #expect(edge.position == .center, "the side the saved stroke says")
            #expect(edge.savedStrokeID == id)
        }
    }

    @Test func changingTheWeightMovesTheEdgesWithThePaths() throws {
        let glyph = path("Glyph"), oval = shape(.ellipse, "Oval")
        var doc = document([glyph, oval])
        let id = try glyphStroke(&doc, from: glyph)
        doc.wearSavedStroke(layerIDs: [oval.id], styleID: id)
        var history = History(document: doc)
        var heavier = try #require(doc.savedStroke(id: id)?.look)
        heavier.width = 2.25
        history.perform { #expect($0.setSavedStroke(styleID: id, look: heavier) == 2) }
        #expect(history.current.layer(id: oval.id)?.style.borderEffects.first?.width == 2.25)
        #expect(history.current.layer(id: glyph.id)?.path?.strokeWidth == 2.25)
        history.undo()
        #expect(history.current.layer(id: oval.id)?.style.borderEffects.first?.width == 1.75)
    }

    @Test func aChosenBorderInTheListIsTheOneThatWearsIt() throws {
        let glyph = path("Glyph")
        var box = shape(.rectangle, "Box")
        box.style.effects.append(.border(BorderEffect(width: 9, position: .outside)))
        var doc = document([glyph, box])
        let id = try glyphStroke(&doc, from: glyph)
        let second = try #require(box.style.effects.lastIndex { $0.kind == .border })
        #expect(doc.wearSavedStroke(layerIDs: [box.id], styleID: id, borderAt: second) == 1)
        let borders = try #require(doc.layer(id: box.id)?.style.borderEffects)
        #expect(borders.first?.width == 3 && borders.first?.savedStrokeID == nil)
        #expect(borders.last?.width == 1.75 && borders.last?.savedStrokeID == id)
    }

    @Test func aBoxWithNoEdgeHasNothingToDress() throws {
        let glyph = path("Glyph"), bare = shape(.rectangle, "Bare", width: 0)
        var doc = document([glyph, bare])
        let id = try glyphStroke(&doc, from: glyph)
        #expect(doc.wearSavedStroke(layerIDs: [bare.id], styleID: id) == 0)
        #expect(doc.layer(id: bare.id)?.style.borderEffects.isEmpty == true)
    }

    @Test func aBoxCannotBeSavedFromBecauseItsCornersAreNotAStroke() {
        let box = shape(.rectangle, "Box")
        var doc = document([box])
        #expect(doc.savedStrokeSelection(layerIDs: [box.id], borderAt: box.style.borderEffectIndex)
            .savableStrokeLook == nil)
        #expect(doc.saveStroke(from: [box.id]) == nil)
    }

    @Test func tuningAnEdgeByHandLetsGoAndIsReported() throws {
        let glyph = path("Glyph"), box = shape(.rectangle, "Box")
        var doc = document([glyph, box])
        let id = try glyphStroke(&doc, from: glyph)
        doc.wearSavedStroke(layerIDs: [box.id], styleID: id)
        let index = try #require(doc.layer(id: box.id)?.style.borderEffectIndex)
        let tuned = kept(doc) { doc in
            doc.updateLayer(id: box.id) { $0.style.updateBorderEffect(at: index) { $0.width = 6 } }
        }
        #expect(tuned.layer(id: box.id)?.style.borderEffects.first?.savedStrokeID == nil)
        #expect(tuned.layer(id: box.id)?.style.borderEffects.first?.width == 6)
        #expect(LinkBreakReport.between(doc, tuned).breaks.map(\.kind) == [.savedStroke])
        // Recolouring the edge is not a change to the line.
        let painted = kept(doc) { doc in
            doc.updateLayer(id: box.id) {
                $0.style.updateBorderEffect(at: index) { $0.colorHex = "#FF0000" }
            }
        }
        #expect(painted.layer(id: box.id)?.style.borderEffects.first?.savedStrokeID == id)
    }

    // MARK: - Everything that counts wearers

    @Test func usesUnlinkAndRemoveReachLinesAndEdges() throws {
        let glyph = path("Glyph"), rule = line(), oval = shape(.ellipse, "Oval")
        var doc = document([glyph, rule, oval])
        let id = try glyphStroke(&doc, from: glyph)
        doc.wearSavedStroke(layerIDs: [rule.id, oval.id], styleID: id)
        #expect(doc.savedStrokeUsageCount(id: id) == 3)
        #expect(Set(doc.layersUsingSavedStroke(id: id)) == [glyph.id, rule.id, oval.id])
        #expect(doc.savedStrokeChoices(limit: 3).map(\.id) == [id])

        var unlinked = doc
        unlinked.unwearSavedStroke(layerIDs: [rule.id, oval.id])
        #expect(unlinked.layer(id: rule.id)?.annotation?.savedStrokeID == nil)
        #expect(unlinked.layer(id: oval.id)?.style.borderEffects.first?.savedStrokeID == nil)
        #expect(unlinked.layer(id: oval.id)?.style.borderEffects.first?.width == 1.75)

        doc.deleteSavedStroke(id: id)
        #expect(doc.layer(id: rule.id)?.annotation?.savedStrokeID == nil)
        #expect(doc.layer(id: oval.id)?.style.borderEffects.first?.savedStrokeID == nil)
        #expect(doc.layer(id: rule.id)?.annotation?.strokeWidth == 1.75)
    }

    @Test func aSelectionOfLinesAndEdgesReadsWhatTheyWear() throws {
        let glyph = path("Glyph"), rule = line(), box = shape(.rectangle, "Box")
        var doc = document([glyph, rule, box])
        let id = try glyphStroke(&doc, from: glyph)
        doc.wearSavedStroke(layerIDs: [rule.id], styleID: id)
        #expect(doc.savedStrokeSelection(layerIDs: [glyph.id, rule.id]).boundSavedStrokeID == id)
        let edge = doc.layer(id: box.id)?.style.borderEffectIndex
        let unworn = doc.savedStrokeSelection(layerIDs: [box.id], borderAt: edge)
        #expect(unworn.layerIDs == [box.id])
        #expect(unworn.hasALine)
        #expect(unworn.boundSavedStrokeID == nil)
        doc.wearSavedStroke(layerIDs: [box.id], styleID: id, borderAt: edge)
        #expect(doc.savedStrokeSelection(layerIDs: [box.id], borderAt: edge).boundSavedStrokeID == id)
        // A box has no line of its own in Appearance: its edge is in Effects.
        #expect(doc.savedStrokeSelection(layerIDs: [box.id]).isEmpty)
    }

    @Test func whatTheyWearSurvivesAWrite() throws {
        let glyph = path("Glyph"), rule = line(), oval = shape(.ellipse, "Oval")
        var doc = document([glyph, rule, oval])
        let id = try glyphStroke(&doc, from: glyph)
        doc.wearSavedStroke(layerIDs: [rule.id, oval.id], styleID: id)
        let read = try JSONDecoder().decode(PhotonzDocument.self, from: JSONEncoder().encode(doc))
        #expect(read.layer(id: rule.id)?.annotation?.savedStrokeID == id)
        #expect(read.layer(id: oval.id)?.style.borderEffects.first?.savedStrokeID == id)
        let plain = try JSONEncoder().encode(document([line(), shape(.ellipse, "O")]))
        #expect(String(decoding: plain, as: UTF8.self).contains("savedStroke") == false)
    }
}
