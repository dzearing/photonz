import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A document has no KIND, and it must not grow one
/// (study: `docs/design/project-kinds.md`).
///
/// The question asked was whether the app should ask what you are making before
/// you start, and then show one set of tools for an icon and another for a
/// recording. The answer is no, and the reason is not taste: a frame is an
/// ordinary layer, the size list holds screens and icons together, and so ONE
/// document legitimately holds a 24 point glyph beside a 1440 point screen. A
/// document-level kind would have to answer "what kind is this" about a
/// document that is honestly two kinds, and every answer it could give is
/// wrong for half of what is on the canvas.
///
/// What carries the context instead is the FRAME you are working in, and these
/// tests pin that too: the same document says icon about one frame and not
/// about the other, at the same moment, with nothing chosen up front.
struct DocumentHasNoKindTests {

    /// The size list itself refuses to separate them: one list, both groups.
    @Test("The sizes an icon and a screen are made at live in one list")
    func oneSizeList() {
        #expect(FramePreset.all.contains { $0.group == .screens })
        #expect(FramePreset.all.contains { $0.group == .icons })
        // Nothing in the list carries a document kind; a preset is a size and
        // a group heading, and the group is about how the list READS.
        #expect(FramePreset.icons.allSatisfy { $0.size.width == $0.size.height })
    }

    /// The document that breaks project types: both kinds of work, at once,
    /// with no kind chosen and nothing complaining.
    @Test("One document holds an icon frame and a screen frame at the same time")
    func oneDocumentHoldsBoth() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 4000, height: 2400))
        let icon = document.addFrame(name: "notification-bell",
                                     origin: CGPoint(x: 80, y: 80),
                                     size: CGSize(width: 24, height: 24))
        let screen = document.addFrame(name: "Settings",
                                       origin: CGPoint(x: 400, y: 80),
                                       size: CGSize(width: 1440, height: 1024))
        #expect(document.frames.count == 2)
        #expect(icon.isFrame && screen.isFrame)
        // Both are ordinary frames. Neither knows what the other is, and the
        // document does not hold a kind that could be wrong about either.
        #expect(document.isIconFrame(id: icon.id))
        #expect(!document.isIconFrame(id: screen.id))
    }

    /// The context follows the frame the mark lands in, which is why it can be
    /// right about both at once.
    @Test("The same document gives icon context in one frame and not the other")
    func contextFollowsTheFrame() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 4000, height: 2400))
        let icon = document.addFrame(origin: CGPoint(x: 80, y: 80),
                                     size: CGSize(width: 24, height: 24))
        let screen = document.addFrame(origin: CGPoint(x: 400, y: 80),
                                       size: CGSize(width: 1440, height: 1024))

        let glyph = Layer(name: "Stroke", content: .text(TextContent(string: "S")),
                          frame: CGRect(x: 86, y: 86, width: 12, height: 12))
        document.addLayerDrawnOnFrame(glyph)
        let callout = Layer(name: "Callout", content: .text(TextContent(string: "C")),
                            frame: CGRect(x: 500, y: 200, width: 120, height: 40))
        document.addLayerDrawnOnFrame(callout)

        #expect(document.iconFrameID(containing: glyph.id) == icon.id)
        #expect(document.iconFrameID(containing: callout.id) == nil)
        #expect(document.frameID(containing: callout.id) == screen.id)

        // And the starting weight of a line follows the same rule: two points
        // inside the glyph's frame, the tool's own four on the screen.
        let armed = AnnotationContent.defaultStrokeWidth
        #expect(IconStrokeWeight.startingWidth(armed: armed,
                                               onFrameSized: CGSize(width: 24, height: 24)) == 2)
        #expect(IconStrokeWeight.startingWidth(armed: armed,
                                               onFrameSized: CGSize(width: 1440, height: 1024)) == armed)
    }
}
