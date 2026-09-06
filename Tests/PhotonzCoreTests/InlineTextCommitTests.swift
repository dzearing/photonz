import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// Landing an inline text edit, in the right coordinate space.
///
/// The inline editor floats over the picture, so everything it knows — where
/// it sits, how wide the words came out — is in CANVAS coordinates. A layer
/// inside a group stores its frame relative to that group. Writing the one
/// into the other moves the layer by the group's origin, which for a label
/// inside a button throws the label clean off the button and looks, to the
/// person who just typed it, exactly like the words being thrown away.
/// (Reported 2026-09-04.)
struct InlineTextCommitTests {

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// A "Button": a box with a label on it, grouped, sitting well away from
    /// the canvas origin so a space mix-up cannot hide behind a small number.
    private func withButton() -> (doc: PhotonzDocument, group: UUID, label: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024),
                                  layers: [box("Background", CGRect(x: 400, y: 380, width: 128, height: 36)),
                                           text("Label", "Button", CGRect(x: 436, y: 388, width: 56, height: 20))])
        let boxID = doc.layers[0].id
        let labelID = doc.layers[1].id
        let group = doc.groupLayers(ids: [boxID, labelID], name: "Button")!
        return (doc, group.id, labelID)
    }

    @Test func aLabelInsideAGroupStaysWhereItWasTyped() {
        var c = withButton()
        let before = c.doc.canvasFrame(of: c.label)!
        c.doc.commitTextEdit(id: c.label, content: TextContent(string: "Save"),
                             canvasFrame: CGRect(origin: before.origin,
                                                 size: CGSize(width: 40, height: 20)))
        #expect(c.doc.layer(id: c.label)?.text?.string == "Save")
        // Where it is on the CANVAS is where the editor was, to the point.
        #expect(c.doc.canvasFrame(of: c.label)?.origin == before.origin)
        // ...and it is still inside the button it was typed in.
        #expect(c.doc.canvasBounds(of: c.group)?.contains(c.doc.canvasFrame(of: c.label)!) == true)
    }

    /// The same edit on a layer sitting loose on the canvas is unchanged: for
    /// a top-level layer the two spaces are the same one.
    @Test func aLooseLabelIsUnaffected() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024),
                                  layers: [text("Label", "Button", CGRect(x: 200, y: 100, width: 56, height: 20))])
        let id = doc.layers[0].id
        doc.commitTextEdit(id: id, content: TextContent(string: "Save"),
                           canvasFrame: CGRect(x: 200, y: 100, width: 40, height: 20))
        #expect(doc.layer(id: id)?.frame == CGRect(x: 200, y: 100, width: 40, height: 20))
    }

    /// Landing an edit on something that is not text does nothing at all,
    /// rather than turning a shape into words.
    @Test func nothingButTextTakesAnInlineEdit() {
        var c = withButton()
        let boxID = c.doc.layer(id: c.group)!.children.first { $0.name == "Background" }!.id
        c.doc.commitTextEdit(id: boxID, content: TextContent(string: "Save"),
                             canvasFrame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(c.doc.layer(id: boxID)?.text == nil)
    }

    /// A bar title stays on one line, and typing a new one over it does not
    /// quietly turn it back into something that wraps. The inline editor
    /// builds its content out of the new-text style, which has never heard of
    /// the box it is landing on, so the box's own answers have to survive the
    /// trip. (Reported 2026-09-06: a long title wrapped out of the bottom of
    /// its bar.)
    @Test func wordsThatStayOnOneLineGoOnStayingOnOneLine() {
        var one = TextContent(string: "Title")
        one.staysOnOneLine = true
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024),
                                  layers: [Layer(name: "Title", content: .text(one),
                                                 frame: CGRect(x: 10, y: 10,
                                                               width: 56, height: 20))])
        let id = doc.layers[0].id
        doc.commitTextEdit(id: id, content: TextContent(string: "A much longer title"),
                           canvasFrame: CGRect(x: 10, y: 10, width: 56, height: 20))
        #expect(doc.layer(id: id)?.text?.staysOnOneLine == true)
        // And a box that never said it was one line is not given the answer.
        var plain = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024),
                                    layers: [text("Label", "Body", CGRect(x: 10, y: 10,
                                                                          width: 56, height: 20))])
        let plainID = plain.layers[0].id
        plain.commitTextEdit(id: plainID, content: TextContent(string: "Longer body"),
                             canvasFrame: CGRect(x: 10, y: 10, width: 56, height: 20))
        #expect(plain.layer(id: plainID)?.text?.staysOnOneLine == nil)
    }

    /// A button centres its label, so re-wording it keeps it centred rather
    /// than growing off the right edge from wherever the caret was.
    @Test func aCentredLabelStaysCentred() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024),
                                  layers: [box("Background", CGRect(x: 400, y: 380, width: 128, height: 36)),
                                           text("Label", "Button", CGRect(x: 436, y: 388, width: 56, height: 20))])
        let boxID = doc.layers[0].id
        let labelID = doc.layers[1].id
        let group = doc.groupLayers(ids: [boxID, labelID], name: "Button")!
        doc.setContentPlacement(id: group.id, horizontal: .center)
        doc.setContentPlacement(id: group.id, vertical: .center)
        let middleBefore = doc.canvasFrame(of: labelID)!.midX
        let origin = doc.canvasFrame(of: labelID)!.origin
        doc.commitTextEdit(id: labelID, content: TextContent(string: "Save this"),
                           canvasFrame: CGRect(origin: origin, size: CGSize(width: 90, height: 20)))
        #expect(abs(doc.canvasFrame(of: labelID)!.midX - middleBefore) <= 0.5)
    }
}
