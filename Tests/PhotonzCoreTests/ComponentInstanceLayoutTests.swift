import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// How a copy arranges its contents is the ORIGINAL's answer, not the copy's.
///
/// A copy is rebuilt from its original after every edit, and that rebuild
/// refills the arrangement and the contents' placement (`syncComponentInstances`).
/// So the Layout section offering those on a copy was offering something it
/// could not keep: padding typed into a copy read back as 24 until the next
/// edit anywhere in the document, and then it was 0 again (found 2026-09-04).
///
/// The honest answer is the one the size fields already give a copy: show the
/// number, refuse the typing, and say who owns it. These tests hold the refusal
/// at the model, so no command, script or keystroke can write an answer that
/// is about to be thrown away.
struct ComponentInstanceLayoutTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// A document holding one component of two pieces, and a copy of it.
    private func withCopy() -> (doc: PhotonzDocument, main: UUID, copy: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 60, height: 30)),
                                           box("Label", CGRect(x: 20, y: 50, width: 40, height: 30))])
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Setting")!
        let componentID = doc.makeComponent(id: group.id)!
        doc.setGroupLayout(id: group.id, kind: .stack)
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        return (doc, group.id, copy)
    }

    // MARK: - The section is not offered

    @Test func aCopyIsNotAskedHowItArrangesItself() {
        let (doc, main, copy) = withCopy()
        #expect(doc.canSetGroupLayout(ids: [copy]) == false)
        // ...and the original still is.
        #expect(doc.canSetGroupLayout(ids: [main]) == true)
    }

    @Test func aCopysArrangementCannotBeChanged() {
        var (doc, _, copy) = withCopy()
        doc.setGroupLayout(id: copy, kind: .grid)
        #expect(doc.layer(id: copy)?.group?.layout?.kind == .stack)
        doc.setGroupLayout(id: copy, kind: nil)
        #expect(doc.layer(id: copy)?.group?.layout?.kind == .stack)
    }

    /// The bug as it was found: 24 of padding typed into a copy, gone by the
    /// next sync. Now it never lands in the first place, so nothing is lost
    /// between one redraw and the next.
    @Test func aNumberTypedOnACopysArrangementIsRefusedRatherThanDropped() {
        var (doc, _, copy) = withCopy()
        doc.updateGroupLayout(id: copy) { $0.padding = GroupPadding(24) }
        #expect(doc.layer(id: copy)?.group?.layout?.padding == GroupPadding.none)
        doc.updateGroupLayout(id: copy) { $0.gap = 40 }
        #expect(doc.layer(id: copy)?.group?.layout?.gap != 40)
        // ...and the picture is the same before and after the copies are put
        // back in step, which is what "not thrown away" means.
        let before = doc.layer(id: copy)
        doc.syncComponentInstances()
        #expect(doc.layer(id: copy) == before)
    }

    @Test func whereACopysContentsSitCannotBeChanged() {
        var (doc, _, copy) = withCopy()
        doc.setContentPlacement(id: copy, horizontal: .center)
        #expect(doc.layer(id: copy)?.group?.contentPlacement?.horizontal == nil)
        doc.setContentPlacement(id: copy, vertical: .stretch)
        #expect(doc.layer(id: copy)?.group?.contentPlacement?.vertical == nil)
    }

    @Test func stackSelectionDoesNothingToACopy() {
        var (doc, _, copy) = withCopy()
        let made = doc.stackSelection(ids: [copy], kind: .grid)
        #expect(made == nil)
        #expect(doc.layer(id: copy)?.group?.layout?.kind == .stack)
    }

    // MARK: - What a copy still decides for itself

    /// Where the copy SITS is its own, and it survives the rebuild: only what
    /// is inside a copy belongs to the original.
    @Test func aCopyStillDecidesWhereItSitsInWhateverHoldsIt() {
        var (doc, _, copy) = withCopy()
        doc.setPlacement(id: copy, horizontal: .right)
        doc.updateLayer(id: copy) { $0.frame.origin = CGPoint(x: 123, y: 45) }
        doc.syncComponentInstances()
        #expect(doc.layer(id: copy)?.placement?.horizontal == .right)
        #expect(doc.layer(id: copy)?.frame.origin == CGPoint(x: 123, y: 45))
    }

    /// The original is untouched by any of this: every row of the Layout
    /// section still answers there, which is where a change reaches every copy.
    @Test func theOriginalStillTakesTheWholeLayoutSection() {
        var (doc, main, copy) = withCopy()
        doc.updateGroupLayout(id: main) { $0.padding = GroupPadding(16) }
        doc.setContentPlacement(id: main, horizontal: .center)
        #expect(doc.layer(id: main)?.group?.layout?.padding == GroupPadding(16))
        #expect(doc.layer(id: main)?.group?.contentPlacement?.horizontal == .center)
        doc.syncComponentInstances()
        // ...and the copy follows it, which is the whole point of refusing.
        #expect(doc.layer(id: copy)?.group?.layout?.padding == GroupPadding(16))
        #expect(doc.layer(id: copy)?.group?.contentPlacement?.horizontal == .center)
    }
}
