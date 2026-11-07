import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A line saved under a name, that any path can wear, and that re-sets every
/// path wearing it when it is changed (`SavedStrokes.swift`). The icon mock's
/// "saved as a style, so this is one click rather than three fields, and if the
/// set ever changes weight every glyph follows".
struct SavedStrokeTests {

    // MARK: - Fixtures

    private func path(_ name: String, closed: Bool = false, width: CGFloat = 4,
                      end: PathLineEnd = .flat, corner: PathLineCorner = .sharp,
                      position: BorderPosition = .center) -> Layer {
        let anchors = [PathAnchor(point: .zero), PathAnchor(point: CGPoint(x: 40, y: 0)),
                       PathAnchor(point: CGPoint(x: 40, y: 40))]
        var content = PathContent(anchors: anchors, isClosed: closed, strokeWidth: width,
                                  strokePosition: position, lineEnd: end, lineCorner: corner)
        content.fill = closed ? content.fill : nil
        return Layer(name: name, content: .path(content),
                     frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    private let glyph = StrokeLook(width: 1.75, lineEnd: .round, lineCorner: .round,
                                   strokePosition: .center)

    /// The document as it is kept after an edit, which is where a claim that
    /// has stopped being true lets go.
    private func kept(_ doc: PhotonzDocument, _ change: (inout PhotonzDocument) -> Void) -> PhotonzDocument {
        var history = History(document: doc)
        history.perform(change)
        return history.current
    }

    // MARK: - Saving one

    @Test func savingKeepsTheLineAndPointsThePathAtIt() throws {
        let first = path("Cloud", width: 1.75, end: .round, corner: .round)
        var doc = document([first])
        let savedId = doc.saveStroke(from: [first.id], name: "Glyph / stroke 1.75")
        let id = try #require(savedId)
        #expect(doc.savedStroke(id: id)?.look == glyph)
        #expect(doc.savedStroke(id: id)?.name == "Glyph / stroke 1.75")
        #expect(doc.layer(id: first.id)?.path?.savedStrokeID == id)
        #expect(doc.layer(id: first.id)?.path?.strokeWidth == 1.75)
    }

    @Test func pathsThatDisagreeHaveNoOneLineToSave() {
        let a = path("A", width: 2), b = path("B", width: 3)
        var doc = document([a, b])
        let refused = doc.saveStroke(from: [a.id, b.id])
        #expect(refused == nil)
        #expect(doc.savedStrokes.isEmpty)
    }

    @Test func aPathWithNoLineHasNothingToSave() {
        let bare = path("Bare", closed: true, width: 0)
        var doc = document([bare])
        let refused = doc.saveStroke(from: [bare.id])
        #expect(refused == nil)
    }

    @Test func anOpenPathSavesTheCentreItIsReallyDrawnOn() throws {
        let line = path("Line", width: 2, position: .inside)
        var doc = document([line])
        let savedId = doc.saveStroke(from: [line.id])
        let id = try #require(savedId)
        #expect(doc.savedStroke(id: id)?.look.strokePosition == .center)
        // ...and what it wears has to agree, or the next edit would let go.
        let after = kept(doc) { _ in }
        #expect(after.layer(id: line.id)?.path?.savedStrokeID == id)
    }

    @Test func anUnnamedStrokeGetsAFreshName() throws {
        let a = path("A", width: 2), b = path("B", width: 2)
        var doc = document([a, b])
        let savedFirst = doc.saveStroke(from: [a.id])
        let first = try #require(savedFirst)
        let savedSecond = doc.saveStroke(from: [b.id])
        let second = try #require(savedSecond)
        #expect(doc.savedStroke(id: first)?.name == "Stroke 2")
        #expect(doc.savedStroke(id: second)?.name == "Stroke 2 2")
    }

    // MARK: - The name it opens on

    @Test func aStrokeOnAnIconIsNamedTheWayTheMockNamesIt() {
        #expect(PhotonzDocument.savedStrokeNameBase(width: 1.75, unit: 1, onIcon: true)
                == "Glyph / stroke 1.75")
        #expect(PhotonzDocument.savedStrokeNameBase(width: 4, unit: 1, onIcon: false) == "Stroke 4")
    }

    @Test func aStrokeOnAnIconPictureIsNamedInItsUnits() {
        let unit: CGFloat = 512.0 / 24
        #expect(PhotonzDocument.savedStrokeNameBase(width: 1.75 * unit, unit: unit, onIcon: true)
                == "Glyph / stroke 1.75")
    }

    // MARK: - Wearing one

    @Test func wearingOneSetsAllFourValuesOnEveryPickedPath() throws {
        let saved = path("Cloud", closed: true, width: 1.75, end: .round, corner: .round)
        let other = path("Arrow", width: 6, end: .flat, corner: .sharp)
        var doc = document([saved, other])
        let savedId = doc.saveStroke(from: [saved.id])
        let id = try #require(savedId)
        let took = doc.wearSavedStroke(layerIDs: [other.id], styleID: id)
        #expect(took == 1)
        let worn = try #require(doc.layer(id: other.id)?.path)
        #expect(worn.strokeWidth == 1.75)
        #expect(worn.lineEnd == .round)
        #expect(worn.lineCorner == .round)
        #expect(worn.savedStrokeID == id)
    }

    @Test func aClosedPathWithNoLineGainsOneThatReads() throws {
        let saved = path("Cloud", width: 1.75, end: .round, corner: .round)
        var bare = path("Blob", closed: true, width: 0)
        if case .path(var content) = bare.content {
            content.paint = Paint(hex: "#112233")
            content.fill = Paint(hex: "#112233")
            bare.content = .path(content)
        }
        var doc = document([saved, bare])
        let savedId = doc.saveStroke(from: [saved.id])
        let id = try #require(savedId)
        doc.wearSavedStroke(layerIDs: [bare.id], styleID: id)
        let worn = try #require(doc.layer(id: bare.id)?.path)
        #expect(worn.strokeWidth == 1.75)
        #expect(worn.paint != worn.fill, "a line in its own fill's colour draws nothing")
    }

    @Test func aLockedPathSitsOut() throws {
        let saved = path("Cloud", width: 1.75)
        var locked = path("Locked", width: 6)
        locked.isLocked = true
        var doc = document([saved, locked])
        let savedId = doc.saveStroke(from: [saved.id])
        let id = try #require(savedId)
        let took = doc.wearSavedStroke(layerIDs: [locked.id], styleID: id)
        #expect(took == 0)
        #expect(doc.layer(id: locked.id)?.path?.strokeWidth == 6)
    }

    @Test func aPathStaysClosableWithoutLettingGo() throws {
        let saved = path("Cloud", closed: true, width: 1.75, position: .inside)
        let open = path("Arrow", width: 4)
        var doc = document([saved, open])
        let savedId = doc.saveStroke(from: [saved.id])
        let id = try #require(savedId)
        doc.wearSavedStroke(layerIDs: [open.id], styleID: id)
        // An open line draws centred whatever it holds, but it keeps the side,
        // so closing it later is not a change of look that breaks the name.
        let closed = kept(doc) { d in
            d.updateLayer(id: open.id) { layer in
                guard var content = layer.path else { return }
                content.isClosed = true
                layer.content = .path(content)
            }
        }
        #expect(closed.layer(id: open.id)?.path?.savedStrokeID == id)
    }

    // MARK: - Changing one

    @Test func changingTheWeightMovesEveryPathInOneUndoStep() throws {
        let a = path("A", width: 1.75), b = path("B", width: 8), loose = path("Loose", width: 9)
        var doc = document([a, b, loose])
        let savedId = doc.saveStroke(from: [a.id])
        let id = try #require(savedId)
        doc.wearSavedStroke(layerIDs: [b.id], styleID: id)
        var history = History(document: doc)
        var heavier = try #require(doc.savedStroke(id: id)?.look)
        heavier.width = 2.5
        history.perform { $0.setSavedStroke(styleID: id, look: heavier) }
        #expect(history.current.layer(id: a.id)?.path?.strokeWidth == 2.5)
        #expect(history.current.layer(id: b.id)?.path?.strokeWidth == 2.5)
        #expect(history.current.layer(id: loose.id)?.path?.strokeWidth == 9)
        #expect(history.current.layer(id: b.id)?.path?.savedStrokeID == id)
        history.undo()
        #expect(history.current.layer(id: a.id)?.path?.strokeWidth == 1.75)
        #expect(history.current.layer(id: b.id)?.path?.strokeWidth == 1.75)
        #expect(history.current.savedStroke(id: id)?.look.width == 1.75)
    }

    @Test func aPathInsideAGroupFollowsToo() throws {
        let a = path("A", width: 1.75), inner = path("Inner", width: 1.75)
        let group = Layer(name: "Group", content: .group(GroupContent(children: [inner])),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        var doc = document([a, group])
        let savedId = doc.saveStroke(from: [a.id, inner.id])
        let id = try #require(savedId)
        var look = try #require(doc.savedStroke(id: id)?.look)
        look.width = 3
        let followed = doc.setSavedStroke(styleID: id, look: look)
        #expect(followed == 2)
        #expect(doc.layer(id: inner.id)?.path?.strokeWidth == 3)
    }

    @Test func aStrokeCannotBeChangedToNoLineAtAll() throws {
        let a = path("A", width: 2)
        var doc = document([a])
        let savedId = doc.saveStroke(from: [a.id])
        let id = try #require(savedId)
        var look = try #require(doc.savedStroke(id: id)?.look)
        look.width = 0
        let followed = doc.setSavedStroke(styleID: id, look: look)
        #expect(followed == 0)
        #expect(doc.layer(id: a.id)?.path?.strokeWidth == 2)
    }

    // MARK: - Letting go

    @Test func tuningAPathByHandLetsGoAndKeepsTheLine() throws {
        let a = path("A", width: 2)
        var doc = document([a])
        let savedId = doc.saveStroke(from: [a.id])
        let id = try #require(savedId)
        let after = kept(doc) { $0.setPathLineCorner(layerIDs: [a.id], to: .round) }
        #expect(after.layer(id: a.id)?.path?.savedStrokeID == nil)
        #expect(after.layer(id: a.id)?.path?.lineCorner == .round)
        #expect(after.layer(id: a.id)?.path?.strokeWidth == 2)
    }

    @Test func aDashedPathStillWearsIt() throws {
        let a = path("A", width: 2)
        var doc = document([a])
        let savedId = doc.saveStroke(from: [a.id])
        let id = try #require(savedId)
        let after = kept(doc) { $0.setPathLinePattern(layerIDs: [a.id], to: .dashed) }
        #expect(after.layer(id: a.id)?.path?.savedStrokeID == id,
                "the saved stroke is the mock's four values, and dashes are not one of them")
    }

    @Test func aNameTheDocumentDoesNotHaveLetsGo() {
        var layer = path("A", width: 2)
        if case .path(var content) = layer.content {
            content.savedStrokeID = UUID()
            layer.content = .path(content)
        }
        var doc = document([layer])
        let broke = doc.reconcileSavedStrokes()
        #expect(broke == 1)
        #expect(doc.layer(id: layer.id)?.path?.savedStrokeID == nil)
    }

    @Test func unlinkingKeepsTheLine() throws {
        let a = path("A", width: 2)
        var doc = document([a])
        let saved = doc.saveStroke(from: [a.id])
        #expect(saved != nil)
        doc.unwearSavedStroke(layerIDs: [a.id])
        #expect(doc.layer(id: a.id)?.path?.savedStrokeID == nil)
        #expect(doc.layer(id: a.id)?.path?.strokeWidth == 2)
    }

    @Test func removingAStrokeLeavesEveryPathItsLine() throws {
        let a = path("A", width: 2)
        var doc = document([a])
        let savedId = doc.saveStroke(from: [a.id])
        let id = try #require(savedId)
        doc.deleteSavedStroke(id: id)
        #expect(doc.savedStrokes.isEmpty)
        #expect(doc.layer(id: a.id)?.path?.savedStrokeID == nil)
        #expect(doc.layer(id: a.id)?.path?.strokeWidth == 2)
    }

    @Test func aLineTunedOffAStrokeIsReportedAndSwitchingItOffIsNot() throws {
        let a = path("A", closed: true, width: 2)
        var doc = document([a])
        let savedId = doc.saveStroke(from: [a.id], name: "Glyph")
        let id = try #require(savedId)
        let tuned = kept(doc) { $0.setPathLineCorner(layerIDs: [a.id], to: .round) }
        let report = LinkBreakReport.between(doc, tuned)
        #expect(report.breaks.map(\.kind) == [.savedStroke])
        #expect(report.breaks.first?.source == "Glyph")
        let off = kept(doc) { $0.setPathOutline(layerIDs: [a.id], on: false) }
        #expect(off.layer(id: a.id)?.path?.savedStrokeID == nil)
        #expect(LinkBreakReport.between(doc, off).breaks.isEmpty)
        _ = id
    }

    // MARK: - What the shelf and the row read

    @Test func usesCountEveryPathWearingIt() throws {
        let a = path("A", width: 2), b = path("B", width: 2), c = path("C", width: 9)
        var doc = document([a, b, c])
        let savedId = doc.saveStroke(from: [a.id, b.id])
        let id = try #require(savedId)
        #expect(doc.savedStrokeUsageCount(id: id) == 2)
        #expect(Set(doc.layersUsingSavedStroke(id: id)) == [a.id, b.id])
        #expect(doc.savedStrokeLibraryEntries.first?.detail == "2 uses")
        #expect(doc.savedStrokeLibraryEntries.first?.scope == .styles)
    }

    @Test func theRowOffersTheMostUsedStrokesFirstAndNoMoreThanItHasRoomFor() throws {
        let a = path("A", width: 1), b = path("B", width: 2), c = path("C", width: 2)
        let d = path("D", width: 3), e = path("E", width: 4)
        var doc = document([a, b, c, d, e])
        let savedOne = doc.saveStroke(from: [a.id])
        let one = try #require(savedOne)
        let savedTwo = doc.saveStroke(from: [b.id, c.id])
        let two = try #require(savedTwo)
        let savedThree = doc.saveStroke(from: [d.id])
        let three = try #require(savedThree)
        let saved = doc.saveStroke(from: [e.id])
        #expect(saved != nil)
        let offered = doc.savedStrokeChoices(limit: 3).map(\.id)
        #expect(offered.count == 3)
        #expect(offered.first == two)
        #expect(offered.dropFirst().elementsEqual([one, three]), "a tie stays in saved order")
    }

    @Test func aSelectionReadsWhatItsPathsWear() throws {
        let a = path("A", width: 2), b = path("B", width: 2), c = path("C", width: 5)
        var doc = document([a, b, c])
        let own = doc.pathLineStyleSelection(layerIDs: [a.id, b.id])
        #expect(own.savedStrokeReading == .own(a.path?.strokeLook ?? glyph))
        #expect(own.savableStrokeLook != nil)
        let savedId = doc.saveStroke(from: [a.id, b.id])
        let id = try #require(savedId)
        let worn = doc.pathLineStyleSelection(layerIDs: [a.id, b.id])
        #expect(worn.savedStrokeReading == .style(id))
        #expect(worn.boundSavedStrokeID == id)
        #expect(worn.savableStrokeLook == nil)
        let mixed = doc.pathLineStyleSelection(layerIDs: [a.id, c.id])
        #expect(mixed.savedStrokeReading == .mixed)
        #expect(mixed.wearsAnySavedStroke)
        #expect(mixed.boundSavedStrokeID == nil)
    }

    // MARK: - On disk

    @Test func aDocumentWithNoStrokesWritesNoKey() throws {
        let doc = document([path("A")])
        let json = try #require(String(data: JSONEncoder().encode(doc), encoding: .utf8))
        #expect(!json.contains("savedStroke"))
    }

    @Test func strokesAndWhatWearsThemSurviveAWrite() throws {
        let a = path("A", width: 1.75, end: .round, corner: .round)
        var doc = document([a])
        let savedId = doc.saveStroke(from: [a.id], name: "Glyph")
        let id = try #require(savedId)
        let read = try JSONDecoder().decode(PhotonzDocument.self, from: JSONEncoder().encode(doc))
        #expect(read.savedStroke(id: id)?.name == "Glyph")
        #expect(read.layer(id: a.id)?.path?.savedStrokeID == id)
    }

    // MARK: - Edit Original

    @Test func aStrokeChangedInAComponentsSpaceComesBack() throws {
        let a = path("A", width: 2)
        var doc = document([a])
        let savedId = doc.saveStroke(from: [a.id])
        let id = try #require(savedId)
        var space = doc
        var look = try #require(space.savedStroke(id: id)?.look)
        look.width = 6
        space.setSavedStroke(styleID: id, look: look)
        doc.adoptStyles(from: space)
        #expect(doc.savedStroke(id: id)?.look.width == 6)
        #expect(doc.layer(id: a.id)?.path?.strokeWidth == 6)
    }
}
