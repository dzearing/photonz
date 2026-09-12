import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// One copy wearing its own type for one piece inside it.
///
/// Answered on 2026-09-09: a copy may wear its own text style, the way it
/// already owns its colour, its size, its room, its opacity and its wording.
/// The point of the whole thing is that letting a style go on the words inside
/// ONE button changes that button and nothing else, and that the copy then
/// says so out loud with a press that puts it back.
struct ComponentPieceTextStyleTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                     end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    private let heading = TextTreatment(fontName: "Helvetica", fontSize: 32,
                                        weight: .bold, colorHex: "#FF0000")

    /// A component "Button" holding a box and a "Label", with two copies of it
    /// on the canvas and one saved style on the shelf.
    private struct World {
        var doc: PhotonzDocument
        var componentID: UUID
        var label: UUID
        var first: UUID
        var second: UUID
        var styleID: UUID

        /// The words inside a copy: the piece the pointer would be over.
        func piece(of copy: UUID) -> UUID {
            ComponentIdentity.derived(instance: copy, source: label)
        }
    }

    private func world() -> World {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 800, height: 600),
            layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40)),
                     text("Label", "Button", CGRect(x: 30, y: 20, width: 60, height: 20))])
        let boxID = doc.layers[0].id
        let labelID = doc.layers[1].id
        let main = doc.groupLayers(ids: [boxID, labelID], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        let first = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 300, y: 300))!
        let second = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 600, y: 300))!
        let styleID = doc.addTextStyle(name: "Heading", treatment: heading)
        doc.syncComponentInstances()
        return World(doc: doc, componentID: componentID, label: labelID,
                     first: first, second: second, styleID: styleID)
    }

    // MARK: - It lands, and only here

    /// The whole errand: the words inside THIS button come out in Heading, and
    /// the button beside it, which is the same copy of the same original, does
    /// not move.
    @Test func aStyleSetOnOnePieceReachesThatCopyAlone() {
        var w = world()
        let set = w.doc.setPieceTextStyle(of: w.piece(of: w.first), styleID: w.styleID)
        #expect(set)
        w.doc.syncComponentInstances()
        #expect(w.doc.layer(id: w.piece(of: w.first))?.textTreatment == heading)
        #expect(w.doc.layer(id: w.piece(of: w.first))?.textStyleID == w.styleID)
        #expect(w.doc.layer(id: w.piece(of: w.second))?.textTreatment != heading)
        #expect(w.doc.layer(id: w.piece(of: w.second))?.textStyleID == nil)
    }

    /// The original is not touched. A style let go on a copy that quietly
    /// re-dressed the component would be the opposite of what was asked for.
    @Test func theOriginalIsLeftAlone() {
        var w = world()
        let before = w.doc.layer(id: w.label)?.textTreatment
        _ = w.doc.setPieceTextStyle(of: w.piece(of: w.first), styleID: w.styleID)
        w.doc.syncComponentInstances()
        #expect(w.doc.layer(id: w.label)?.textTreatment == before)
        #expect(w.doc.layer(id: w.label)?.textStyleID == nil)
    }

    /// It survives the copy being put back in step with its original, which is
    /// the thing that used to make this impossible: a sync runs after every
    /// edit, and anything written straight onto a piece is gone by the next
    /// one.
    @Test func itSurvivesEverySync() {
        var w = world()
        _ = w.doc.setPieceTextStyle(of: w.piece(of: w.first), styleID: w.styleID)
        for _ in 0..<3 { w.doc.syncComponentInstances() }
        #expect(w.doc.layer(id: w.piece(of: w.first))?.textTreatment == heading)
    }

    /// An edit to the ORIGINAL still reaches a copy that answered for itself:
    /// the copy takes the original's picture whole and its own few facts are
    /// written over the top, so re-wording the label reaches the copy and the
    /// type it chose stays.
    @Test func theOriginalStillReachesACopyThatChoseItsOwnType() {
        var w = world()
        _ = w.doc.setPieceTextStyle(of: w.piece(of: w.first), styleID: w.styleID)
        w.doc.updateLayer(id: w.label) { layer in
            guard case .text(var content) = layer.content else { return }
            content.string = "Save"
            layer.content = .text(content)
        }
        w.doc.syncComponentInstances()
        let piece = w.doc.layer(id: w.piece(of: w.first))
        #expect(piece?.text?.string == "Save")
        #expect(piece?.textTreatment == heading)
    }

    /// The box grows around bigger type, the same way it grows around longer
    /// words. A 32 point label left in a box measured for 13 hangs out of the
    /// bottom of the button.
    @Test func theWordsAreRemeasuredAtTheirNewSize() {
        var w = world()
        let before = w.doc.layer(id: w.piece(of: w.first))!.frame
        _ = w.doc.setPieceTextStyle(of: w.piece(of: w.first), styleID: w.styleID)
        w.doc.syncComponentInstances()
        let after = w.doc.layer(id: w.piece(of: w.first))!.frame
        #expect(after.height > before.height)
    }

    // MARK: - The way back

    /// What the copy says about itself, and the one press that puts it back.
    @Test func theCopySaysItHasTypeOfItsOwnAndGivesItBack() {
        var w = world()
        #expect(w.doc.instanceOwnTypeLabel(instances: [w.first]) == nil)
        _ = w.doc.setPieceTextStyle(of: w.piece(of: w.first), styleID: w.styleID)
        w.doc.syncComponentInstances()
        #expect(w.doc.instanceOwnTypeLabel(instances: [w.first]) == "Label in Heading")
        let back = w.doc.clearInstancePieceTextStyles(instances: [w.first])
        #expect(back == 1)
        w.doc.syncComponentInstances()
        #expect(w.doc.instanceOwnTypeLabel(instances: [w.first]) == nil)
        #expect(w.doc.layer(id: w.piece(of: w.first))?.textTreatment
                == w.doc.layer(id: w.label)?.textTreatment)
    }

    /// Several copies picked at once answer with a count, the way "its own
    /// look" and "its own size" do, rather than with a list nobody can read.
    @Test func severalCopiesAnswerWithACount() {
        var w = world()
        _ = w.doc.setPieceTextStyle(of: w.piece(of: w.first), styleID: w.styleID)
        w.doc.syncComponentInstances()
        #expect(w.doc.instanceOwnTypeLabel(instances: [w.first, w.second])
                == "1 of the 2 copies has type of its own")
    }

    // MARK: - What the shelf does to it afterwards

    /// The point of dropping a NAME rather than a look: editing Heading
    /// afterwards reaches the copy wearing it.
    @Test func editingTheStyleReachesThePieceWearingIt() {
        var w = world()
        _ = w.doc.setPieceTextStyle(of: w.piece(of: w.first), styleID: w.styleID)
        w.doc.syncComponentInstances()
        var bigger = heading
        bigger.fontSize = 48
        _ = w.doc.setTextStyle(styleID: w.styleID, treatment: bigger)
        w.doc.syncComponentInstances()
        #expect(w.doc.layer(id: w.piece(of: w.first))?.textTreatment == bigger)
    }

    /// Taking a style off the shelf never re-sets somebody's work: the piece
    /// keeps exactly the type it is wearing and simply owns it.
    @Test func deletingTheStyleLeavesThePieceWearingTheType() {
        var w = world()
        _ = w.doc.setPieceTextStyle(of: w.piece(of: w.first), styleID: w.styleID)
        w.doc.syncComponentInstances()
        w.doc.deleteTextStyle(id: w.styleID)
        w.doc.syncComponentInstances()
        #expect(w.doc.layer(id: w.piece(of: w.first))?.textTreatment == heading)
        #expect(w.doc.layer(id: w.piece(of: w.first))?.textStyleID == nil)
        #expect(w.doc.instanceOwnTypeLabel(instances: [w.first]) == "Label in type of its own")
    }

    /// A copy that stops following its original keeps the picture it was
    /// drawing, type and all, and the record of the answer goes with the link.
    @Test func detachingKeepsTheTypeAndDropsTheRecord() {
        var w = world()
        _ = w.doc.setPieceTextStyle(of: w.piece(of: w.first), styleID: w.styleID)
        w.doc.syncComponentInstances()
        let detached = w.doc.detachInstance(id: w.first)
        #expect(detached)
        w.doc.syncComponentInstances()
        #expect(w.doc.layer(id: w.piece(of: w.first))?.textTreatment == heading)
        #expect(w.doc.layer(id: w.first)?.group?.pieceTextStyles.isEmpty == true)
    }

    /// It is written to the file and comes back, which is what makes it a fact
    /// about the document rather than about this session.
    @Test func itRoundTripsThroughTheFile() throws {
        var w = world()
        _ = w.doc.setPieceTextStyle(of: w.piece(of: w.first), styleID: w.styleID)
        let data = try JSONEncoder().encode(w.doc)
        var back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        back.syncComponentInstances()
        #expect(back.layer(id: w.piece(of: w.first))?.textTreatment == heading)
    }

    /// A document written before any of this existed is byte for byte what it
    /// was: a copy that answers nothing writes no key.
    @Test func aCopyWithNoTypeOfItsOwnWritesNothing() throws {
        let w = world()
        let data = try JSONEncoder().encode(w.doc)
        #expect(!String(decoding: data, as: UTF8.self).contains("pieceTextStyles"))
    }

    // MARK: - Where it is refused

    /// A copy inside another copy is rebuilt by the OUTER copy, so an answer
    /// given to the inner one has nowhere to live. It is refused rather than
    /// taken and quietly dropped.
    @Test func aPieceInsideANestedCopyIsRefused() {
        var w = world()
        // A second component holding a copy of Button: the Button copy inside
        // it is nested the moment a copy of the outer one is placed.
        let outerMain = w.doc.groupLayers(ids: [w.first], name: "Bar")!
        let outerID = w.doc.makeComponent(id: outerMain.id)!
        let outerCopy = w.doc.insertComponentInstance(of: outerID, at: CGPoint(x: 400, y: 500))!
        w.doc.syncComponentInstances()
        let innerCopy = ComponentIdentity.derived(instance: outerCopy, source: w.first)
        let nested = ComponentIdentity.derived(instance: innerCopy, source: w.label)
        #expect(w.doc.componentPiece(of: nested)?.isNested == true)
        let set = w.doc.setPieceTextStyle(of: nested, styleID: w.styleID)
        #expect(!set)
    }

    /// A style this document does not have is not a style, and a layer that is
    /// not a piece of a copy is dressed the ordinary way, not this way.
    @Test func nonsenseIsRefused() {
        var w = world()
        let noSuchStyle = w.doc.setPieceTextStyle(of: w.piece(of: w.first), styleID: UUID())
        let notAPiece = w.doc.setPieceTextStyle(of: w.label, styleID: w.styleID)
        #expect(!noSuchStyle)
        #expect(!notAPiece)
    }

    /// A locked copy changes in no way at all until it is unlocked, which is
    /// what locked means everywhere else in the app.
    @Test func aLockedCopyIsRefused() {
        var w = world()
        w.doc.updateLayer(id: w.first) { $0.isLocked = true }
        let set = w.doc.setPieceTextStyle(of: w.piece(of: w.first), styleID: w.styleID)
        #expect(!set)
    }

    // MARK: - One way in for both kinds of target

    /// The drop does not have to know what it landed on. Handing the document
    /// a style and a list of layers dresses each one the way that STICKS where
    /// it is: a piece inside a copy gets the copy's own answer, ordinary text
    /// is bound to the name.
    @Test func oneCallDressesAPieceAndPlainTextTogether() {
        var w = world()
        let plain = Layer(name: "Title", content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 40, y: 40, width: 120, height: 30))
        w.doc.addLayer(plain)
        let dressed = w.doc.applyTextStyle(w.styleID, to: [w.piece(of: w.first), plain.id])
        #expect(dressed)
        w.doc.syncComponentInstances()
        #expect(w.doc.layer(id: plain.id)?.textStyleID == w.styleID)
        #expect(w.doc.layer(id: w.piece(of: w.first))?.textTreatment == heading)
    }
}
