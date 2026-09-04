import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// A copy can be given a size of its own, and keeps it.
///
/// Everything else inside a copy belongs to the original and is refilled after
/// every edit, which is why the width and height boxes on a copy used to be
/// dead: a number typed there was gone by the next redraw. The size is the one
/// answer worth keeping, because the same nav bar is 1200 wide on a desktop
/// screen and 375 wide on a phone, and breaking the copy away from its family
/// to say so is not an answer.
///
/// So the copy holds its own width and height, one axis at a time, and the
/// sync writes them over the original's rather than the other way round. An
/// axis nobody has touched still follows the original. See
/// `docs/design/ui-building.md`, "A copy can be given its own size".
struct ComponentInstanceSizeTests {

    // MARK: - Documents to work with

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width,
                                                                              y: rect.height))),
              frame: rect)
    }

    /// A bar 320 by 48 with a surface that stretches to fill it and a title
    /// pinned to the left, made a component, with one copy of it out. The nav
    /// bar of the task, small enough to check by hand.
    private func withBar() -> (doc: PhotonzDocument, main: UUID, copy: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 900),
                                  layers: [box("Surface", CGRect(x: 0, y: 0, width: 320, height: 48)),
                                           box("Title", CGRect(x: 16, y: 16, width: 60, height: 16))])
        let surface = doc.layers[0].id
        let title = doc.layers[1].id
        doc.setPlacement(id: surface, horizontal: .stretch)
        doc.setPlacement(id: surface, vertical: .stretch)
        doc.setPlacement(id: title, horizontal: .left)
        let group = doc.groupLayers(ids: [surface, title], name: "Nav Bar")!
        doc.updateGroupLayout(id: group.id) { $0.width = 320; $0.height = 48 }
        let componentID = doc.makeComponent(id: group.id)!
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 800, y: 400))!
        return (doc, group.id, copy)
    }

    /// A control that is as wide as the word inside it: no width of its own,
    /// which is the other half of the question a size override has to answer.
    private func withHuggingButton() -> (doc: PhotonzDocument, main: UUID, copy: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Label", CGRect(x: 0, y: 0, width: 60, height: 20))])
        let group = doc.groupLayers(ids: [doc.layers[0].id], name: "Button")!
        doc.updateGroupLayout(id: group.id) { $0.padding = GroupPadding(8) }
        let componentID = doc.makeComponent(id: group.id)!
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!
        return (doc, group.id, copy)
    }

    private func size(of doc: PhotonzDocument, _ id: UUID) -> CGSize {
        doc.layer(id: id)?.localBounds.size ?? .zero
    }

    /// The box a copy is resized to, in the space its numbers are shown in.
    private func widened(_ doc: PhotonzDocument, _ id: UUID, to width: CGFloat) -> CGRect {
        let box = doc.layer(id: id)!.localBounds
        return CGRect(x: box.minX, y: box.minY, width: width, height: box.height)
    }

    // MARK: - The boxes are live

    @Test("A copy offers the eight handles and takes a typed width and height")
    func aCopyTakesAWidthAndAHeight() {
        let (doc, _, copy) = withBar()
        let layer = doc.layer(id: copy)!
        #expect(layer.allowsFrameResize)
        let editing = LayerGeometryEditing(layer: layer)
        #expect(editing.allows(.width))
        #expect(editing.allows(.height))
        #expect(editing.fixedReason(for: .width) == nil)
        #expect(editing.fixedReason(for: .height) == nil)
    }

    @Test("A copy nobody has resized reads the original's size and follows it")
    func anUntouchedCopyFollowsTheOriginal() {
        var (doc, main, copy) = withBar()
        #expect(size(of: doc, copy) == CGSize(width: 320, height: 48))
        #expect(doc.instanceOwnsSize(id: copy) == false)
        doc.updateGroupLayout(id: main) { $0.width = 500 }
        doc.reflowLayouts()
        doc.syncComponentInstances()
        #expect(size(of: doc, copy) == CGSize(width: 500, height: 48))
    }

    // MARK: - A resize survives the sync

    @Test("A width typed into a copy is still there after the copies are put back in step")
    func aTypedWidthSurvivesTheSync() {
        var (doc, _, copy) = withBar()
        let wide = widened(doc, copy, to: 1200)
        doc.updateLayer(id: copy) { $0 = $0.resized(to: wide) }
        #expect(size(of: doc, copy).width == 1200)
        doc.syncComponentInstances()
        doc.reflowLayouts()
        #expect(size(of: doc, copy).width == 1200)
        #expect(doc.instanceOwnsSize(id: copy))
    }

    @Test("A resized copy keeps its width while the original is edited around it")
    func aResizedCopyKeepsItsWidth() {
        var (doc, main, copy) = withBar()
        let wide = widened(doc, copy, to: 1200)
        doc.updateLayer(id: copy) { $0 = $0.resized(to: wide) }
        // Everything a person would do to the original next: its spacing, its
        // own size, and one of its pieces.
        doc.updateGroupLayout(id: main) { $0.padding = GroupPadding(20) }
        doc.updateGroupLayout(id: main) { $0.width = 375 }
        doc.reflowLayouts()
        doc.syncComponentInstances()
        doc.reflowLayouts()
        #expect(size(of: doc, copy).width == 1200)
        // ...and the padding, which the copy does NOT own, did follow.
        #expect(doc.layer(id: copy)?.group?.layout?.padding == GroupPadding(20))
    }

    @Test("Only the axis that was resized stops following the original")
    func theOtherAxisStillFollows() {
        var (doc, main, copy) = withBar()
        let wide = widened(doc, copy, to: 1200)
        doc.updateLayer(id: copy) { $0 = $0.resized(to: wide) }
        doc.updateGroupLayout(id: main) { $0.width = 375; $0.height = 64 }
        doc.reflowLayouts()
        doc.syncComponentInstances()
        #expect(size(of: doc, copy) == CGSize(width: 1200, height: 64))
    }

    // MARK: - What is inside lines up in the new size

    @Test("A stretched piece spreads across a widened copy, as it would on the original")
    func whatIsInsideSpreads() {
        var (doc, _, copy) = withBar()
        let wide = widened(doc, copy, to: 1200)
        doc.updateLayer(id: copy) { $0 = $0.resized(to: wide) }
        doc.syncComponentInstances()
        doc.reflowLayouts()
        let surface = doc.layer(id: copy)?.children.first { $0.name == "Surface" }
        #expect(surface?.frame.width == 1200)
        // The title was pinned to the left, so it stayed there rather than
        // being magnified with the box.
        let title = doc.layer(id: copy)?.children.first { $0.name == "Title" }
        #expect(title?.frame.width == 60)
        #expect(title?.frame.minX == 16)
    }

    /// The bug the first real run of this found: a copy is REBUILT from its
    /// original after every edit, so its contents always arrive laid out for
    /// the original's box. A stack puts them right on its own; a group that
    /// arranges nothing does not, so a widened nav bar copy kept its title
    /// where 320 put it while the same bar resized as the original centred it.
    @Test("A centred piece re-centres in a widened copy, as it would on the original")
    func whatIsInsideIsPlacedForTheCopysOwnBox() {
        var (doc, main, copy) = withBar()
        let title = doc.layer(id: main)!.children.first { $0.name == "Title" }!.id
        // Put it in the middle of the original first: Center keeps a piece's
        // offset from the middle, so a title sitting left of centre stays left
        // of centre, and only one already in the middle stays in the middle.
        doc.updateLayer(id: title) { $0.frame.origin.x = 130 }
        doc.setPlacement(id: title, horizontal: .center)
        doc.syncComponentInstances()
        let wide = widened(doc, copy, to: 1200)
        doc.updateLayer(id: copy) { $0 = $0.resized(to: wide) }
        doc.syncComponentInstances()
        doc.reflowLayouts()

        // 60 wide, centred in 1200, starting from the copy's own left edge.
        let box = doc.layer(id: copy)!.localBounds
        let placed = doc.layer(id: copy)!.children.first { $0.name == "Title" }!
        #expect(placed.frame.width == 60)
        #expect(placed.frame.midX == box.width / 2)
        // The original is untouched, so its title is still centred in 320.
        let onTheOriginal = doc.layer(id: main)!.children.first { $0.name == "Title" }!
        #expect(onTheOriginal.frame.midX == 160)
        #expect(doc.layer(id: main)?.localBounds.width == 320)
    }

    @Test("An original that hugs its contents still hands a copy a size it can pin")
    func aHuggingOriginalCanStillBeResizedPerCopy() {
        var (doc, main, copy) = withHuggingButton()
        let natural = size(of: doc, copy)
        #expect(natural.width == 76) // 60 of label plus 8 of room each side
        let wide = widened(doc, copy, to: 200)
        doc.updateLayer(id: copy) { $0 = $0.resized(to: wide) }
        doc.syncComponentInstances()
        doc.reflowLayouts()
        #expect(size(of: doc, copy).width == 200)
        // The original is untouched: it is still as wide as its label.
        #expect(size(of: doc, main).width == 76)
        // ...and the height, which nobody pinned, still hugs.
        #expect(doc.layer(id: copy)?.group?.layout?.height == nil)
    }

    // MARK: - The way back

    @Test("Putting a copy back on the original's size gives back both axes")
    func theResetPutsACopyBack() {
        var (doc, _, copy) = withBar()
        let wide = widened(doc, copy, to: 1200)
        doc.updateLayer(id: copy) { $0 = $0.resized(to: wide) }
        doc.syncComponentInstances()
        #expect(doc.instanceOwnsSize(id: copy))
        #expect(doc.clearInstanceSize(instances: [copy]) == 1)
        doc.syncComponentInstances()
        doc.reflowLayouts()
        #expect(size(of: doc, copy) == CGSize(width: 320, height: 48))
        #expect(doc.instanceOwnsSize(id: copy) == false)
        // Nothing to put back is not an edit.
        #expect(doc.clearInstanceSize(instances: [copy]) == 0)
    }

    @Test("The Component section says which sides a copy owns, in plain words")
    func theSectionSaysWhatTheCopyOwns() {
        var (doc, _, copy) = withBar()
        #expect(doc.instanceOwnSizeLabel(instance: copy) == nil)
        let wide = widened(doc, copy, to: 1200)
        doc.updateLayer(id: copy) { $0 = $0.resized(to: wide) }
        #expect(doc.instanceOwnSizeLabel(instance: copy) == "1200 wide")
        let box = doc.layer(id: copy)!.localBounds
        doc.updateLayer(id: copy) {
            $0 = $0.resized(to: CGRect(x: box.minX, y: box.minY, width: 1200, height: 80))
        }
        #expect(doc.instanceOwnSizeLabel(instance: copy) == "1200 wide, 80 tall")
    }

    @Test("One undo puts a resize back")
    func oneUndoPutsAResizeBack() {
        let (document, _, copy) = withBar()
        var history = History(document: document)
        let box = history.current.layer(id: copy)!.localBounds
        history.perform { doc in
            doc.updateLayer(id: copy) {
                $0 = $0.resized(to: CGRect(x: box.minX, y: box.minY, width: 1200, height: box.height))
            }
        }
        #expect(history.current.layer(id: copy)?.localBounds.width == 1200)
        history.undo()
        #expect(history.current.layer(id: copy)?.localBounds.width == 320)
        #expect(history.current.instanceOwnsSize(id: copy) == false)
    }

    // MARK: - What must NOT claim a size

    /// The one that would have gone wrong quietly: a copy inside a stack that
    /// stretches it goes through the same resize a handle drag does. The
    /// container's answer is not the copy's answer, so nothing is recorded and
    /// the copy still follows its original.
    @Test("A copy stretched by the container it sits in does not claim that size")
    func aStretchedCopyClaimsNothing() {
        var (doc, main, copy) = withBar()
        let shelf = doc.groupLayers(ids: [copy], name: "Shelf")!
        doc.setGroupLayout(id: shelf.id, kind: .stack)
        doc.updateGroupLayout(id: shelf.id) { $0.width = 900 }
        doc.setContentPlacement(id: shelf.id, horizontal: .stretch)
        doc.reflowLayouts()
        doc.syncComponentInstances()
        #expect(doc.instanceOwnsSize(id: copy) == false)
        #expect(doc.instanceOwnSizeLabel(instance: copy) == nil)
        // ...and the original still decides, so widening it reaches this copy.
        doc.updateGroupLayout(id: main) { $0.height = 64 }
        doc.reflowLayouts()
        doc.syncComponentInstances()
        #expect(size(of: doc, copy).height == 64)
    }

    /// The size is the ONE thing the copy owns. Everything else the Layout
    /// section offers is still refused on a copy and still the original's, so
    /// widening one does not quietly hand it the rest of the section.
    @Test("A copy's arrangement, spacing and room are still the original's")
    func onlyTheSizeIsTheCopysOwn() {
        var (doc, main, copy) = withBar()
        let wide = widened(doc, copy, to: 1200)
        doc.updateLayer(id: copy) { $0 = $0.resized(to: wide) }
        doc.updateGroupLayout(id: copy) { $0.padding = GroupPadding(24) }
        doc.setGroupLayout(id: copy, kind: .grid)
        doc.syncComponentInstances()
        let mainLayout = doc.layer(id: main)?.group?.layout
        #expect(doc.layer(id: copy)?.group?.layout?.padding == mainLayout?.padding)
        #expect(doc.layer(id: copy)?.group?.layout?.kind == mainLayout?.kind)
        #expect(mainLayout?.kind == nil)
        #expect(size(of: doc, copy).width == 1200)
    }

    // MARK: - Detaching, saving and opening

    @Test("A detached copy keeps the size it was wearing and stops holding a copy's record")
    func detachKeepsTheSize() {
        var (doc, _, copy) = withBar()
        let wide = widened(doc, copy, to: 1200)
        doc.updateLayer(id: copy) { $0 = $0.resized(to: wide) }
        doc.syncComponentInstances()
        let detached = doc.detachInstance(id: copy)
        #expect(detached)
        #expect(size(of: doc, copy).width == 1200)
        #expect(doc.layer(id: copy)?.group?.instanceSize == nil)
    }

    @Test("A copy's own size is saved and opens again; a copy without one writes no key")
    func theSizeSurvivesSavingAndOpening() throws {
        var (doc, _, copy) = withBar()
        let plain = try JSONEncoder().encode(doc.layer(id: copy)!)
        #expect(!String(decoding: plain, as: UTF8.self).contains("instanceSize"))

        let wide = widened(doc, copy, to: 1200)
        doc.updateLayer(id: copy) { $0 = $0.resized(to: wide) }
        doc.syncComponentInstances()
        let data = try JSONEncoder().encode(doc)
        var reopened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(reopened.instanceOwnsSize(id: copy))
        reopened.syncComponentInstances()
        reopened.reflowLayouts()
        #expect(size(of: reopened, copy).width == 1200)
    }

    // MARK: - A copy of a screen

    @Test("A copy of a screen takes its own box, and the other side still follows")
    func aCopyOfAScreenTakesItsOwnBox() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 2000, height: 1200),
                                  layers: [box("Bar", CGRect(x: 0, y: 0, width: 375, height: 48))])
        let screen = doc.frameSelection(ids: [doc.layers[0].id], name: "Phone")!.id
        doc.setFrameSize(id: screen, size: CGSize(width: 375, height: 812))
        let componentID = doc.makeComponent(id: screen)!
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 1200, y: 600))!
        #expect(size(of: doc, copy) == CGSize(width: 375, height: 812))

        let box = doc.layer(id: copy)!.localBounds
        doc.updateLayer(id: copy) {
            $0 = $0.resized(to: CGRect(x: box.minX, y: box.minY, width: 1200, height: box.height))
        }
        doc.syncComponentInstances()
        doc.reflowLayouts()
        #expect(size(of: doc, copy) == CGSize(width: 1200, height: 812))
        // The original still owns the height, so a taller phone reaches it.
        doc.setFrameSize(id: screen, size: CGSize(width: 375, height: 900))
        doc.syncComponentInstances()
        #expect(size(of: doc, copy) == CGSize(width: 1200, height: 900))
    }
}
