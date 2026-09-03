import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Moving something onto a screen means the same thing however it got there.
///
/// A shape drawn on a screen joins it, and a copy dropped on it from the
/// Library joins it. Dragging one that is already on the canvas has to join it
/// too, and dragging it back off has to take it out again — otherwise a screen
/// is a picture of a boundary rather than a thing that holds anything.
@Suite("Dragging onto a screen puts it in the screen")
struct FrameAdoptionTests {

    private func leaf(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)), frame: frame)
    }

    /// Canvas 2000×1200 holding one 390×844 phone frame at (100, 60) with a
    /// button inside it at local (20, 40), and a loose caption on the canvas.
    private func makeDocument() -> PhotonzDocument {
        let button = leaf("Button", CGRect(x: 20, y: 40, width: 120, height: 44))
        let frame = Layer.frameLayer(name: "Home", origin: CGPoint(x: 100, y: 60),
                                     size: CGSize(width: 390, height: 844),
                                     children: [button])
        return PhotonzDocument(canvasSize: CGSize(width: 2000, height: 1200),
                               layers: [leaf("Caption", CGRect(x: 600, y: 20, width: 200, height: 30)), frame])
    }

    private func frameID(in document: PhotonzDocument) -> UUID { document.frames.first!.id }
    private func id(_ document: PhotonzDocument, _ name: String) -> UUID {
        document.allLayers.first { $0.name == name }!.id
    }

    // MARK: - Joining

    @Test("A layer dragged onto a screen becomes part of it, without moving on screen")
    func draggingIn() {
        var document = makeDocument()
        let home = frameID(in: document)
        let caption = id(document, "Caption")
        // Dropped over the middle of the phone.
        document.moveLayer(id: caption, toCanvasOrigin: CGPoint(x: 200, y: 400))
        #expect(document.adoptMovedLayers(ids: [caption]) == [caption])
        #expect(document.parentID(of: caption) == home)
        #expect(document.canvasBounds(of: caption)?.origin == CGPoint(x: 200, y: 400))
    }

    @Test("The layers list shows it nested under the screen")
    func nestedInTheList() {
        var document = makeDocument()
        let home = frameID(in: document)
        let caption = id(document, "Caption")
        document.moveLayer(id: caption, toCanvasOrigin: CGPoint(x: 200, y: 400))
        document.adoptMovedLayers(ids: [caption])
        let rows = document.panelRows(expanded: [home])
        let captionRow = rows.first { $0.id == caption }
        #expect(captionRow?.parentID == home)
        #expect(captionRow?.depth == 1)
        #expect(document.layers.contains { $0.id == caption } == false)
    }

    @Test("It joins the screen its centre lands on, not one it merely overlaps")
    func theCentreDecides() {
        var document = makeDocument()
        let home = frameID(in: document)
        let caption = id(document, "Caption")
        // 200 wide: centre at x = 420, inside the phone, which ends at x = 490.
        document.moveLayer(id: caption, toCanvasOrigin: CGPoint(x: 320, y: 400))
        #expect(document.frameAdoption(of: caption) == .joins(home))
        // Centre at x = 540, past the right edge.
        document.moveLayer(id: caption, toCanvasOrigin: CGPoint(x: 440, y: 400))
        #expect(document.frameAdoption(of: caption) == .stays)
    }

    @Test("A layer dragged from one screen to another changes screens")
    func acrossScreens() {
        var document = makeDocument()
        let home = frameID(in: document)
        let second = document.addFrame(name: "Second", origin: CGPoint(x: 800, y: 60),
                                       size: CGSize(width: 390, height: 844)).id
        let button = id(document, "Button")
        document.moveLayer(id: button, toCanvasOrigin: CGPoint(x: 900, y: 200))
        #expect(document.frameAdoption(of: button) == .joins(second))
        document.adoptMovedLayers(ids: [button])
        #expect(document.parentID(of: button) == second)
        #expect(document.layer(id: home)?.children.isEmpty == true)
        #expect(document.canvasBounds(of: button)?.origin == CGPoint(x: 900, y: 200))
    }

    // MARK: - Leaving

    @Test("A layer dragged out onto bare canvas comes out of the screen")
    func draggingOut() {
        var document = makeDocument()
        let button = id(document, "Button")
        document.moveLayer(id: button, toCanvasOrigin: CGPoint(x: 900, y: 900))
        #expect(document.frameAdoption(of: button) == .leaves)
        #expect(document.adoptMovedLayers(ids: [button]) == [button])
        #expect(document.parentID(of: button) == nil)
        #expect(document.canvasBounds(of: button)?.origin == CGPoint(x: 900, y: 900))
        // It comes out on top, where a thing you just dropped belongs.
        #expect(document.layers.last?.id == button)
    }

    @Test("A drag that stays on the same screen changes nothing")
    func stayingPut() {
        var document = makeDocument()
        let button = id(document, "Button")
        let home = frameID(in: document)
        document.moveLayer(id: button, toCanvasOrigin: CGPoint(x: 150, y: 500))
        let before = document
        #expect(document.frameAdoption(of: button) == .stays)
        #expect(document.adoptMovedLayers(ids: [button]).isEmpty)
        #expect(document.layers == before.layers)
    }

    @Test("A piece moved around inside its group stays in its group")
    func groupsInsideAScreenSurvive() {
        var document = makeDocument()
        let home = frameID(in: document)
        let button = id(document, "Button")
        let card = document.groupLayers(ids: [button], name: "Card")!
        document.moveLayer(id: button, toCanvasOrigin: CGPoint(x: 200, y: 500))
        #expect(document.frameAdoption(of: button) == .stays)
        #expect(document.parentID(of: button) == card.id)
        #expect(document.parentID(of: card.id) == home)
    }

    @Test("A document with no screens in it never reparents anything")
    func noFramesNoChange() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [leaf("A", CGRect(x: 0, y: 0, width: 100, height: 100))])
        let a = id(document, "A")
        #expect(document.frameAdoption(of: a) == .stays)
        #expect(document.adoptMovedLayers(ids: [a]).isEmpty)
    }

    // MARK: - What never happens

    @Test("A screen dragged over another screen stays its own screen")
    func screensAreNeverSwallowed() {
        var document = makeDocument()
        let home = frameID(in: document)
        let second = document.addFrame(name: "Second", origin: CGPoint(x: 1200, y: 60),
                                       size: CGSize(width: 200, height: 200)).id
        document.moveLayer(id: second, toCanvasOrigin: CGPoint(x: 150, y: 150))
        #expect(document.frameAdoption(of: second) == .stays)
        #expect(document.parentID(of: second) == nil)
        #expect(document.layer(id: home)?.children.count == 1)
    }

    @Test("A locked layer is never reparented")
    func lockedStaysPut() {
        var document = makeDocument()
        let caption = id(document, "Caption")
        document.updateLayer(id: caption) { $0.isLocked = true }
        document.moveLayer(id: caption, toCanvasOrigin: CGPoint(x: 200, y: 400))
        #expect(document.frameAdoption(of: caption) == .stays)
    }

    @Test("A locked screen takes nothing in")
    func lockedFrameTakesNothing() {
        var document = makeDocument()
        let home = frameID(in: document)
        document.updateLayer(id: home) { $0.isLocked = true }
        let caption = id(document, "Caption")
        document.moveLayer(id: caption, toCanvasOrigin: CGPoint(x: 200, y: 400))
        #expect(document.frameAdoption(of: caption) == .stays)
    }

    @Test("A group is never dropped inside a screen it is carrying")
    func noLoops() {
        var document = makeDocument()
        let home = frameID(in: document)
        let caption = id(document, "Caption")
        // A group holding the phone screen and the caption: dragging it puts
        // its own centre over the screen it carries.
        let holder = document.groupLayers(ids: [home, caption], name: "Both")!
        #expect(document.frameAdoption(of: holder.id) == .stays)
        #expect(document.adoptMovedLayers(ids: [holder.id]).isEmpty)
    }

    // MARK: - The hint the canvas draws

    @Test("The canvas is told which screen a drag would join")
    func theHint() {
        var document = makeDocument()
        let home = frameID(in: document)
        let caption = id(document, "Caption")
        let landing = CGRect(x: 200, y: 400, width: 200, height: 30)
        #expect(document.frameAdoptionHost(moving: [caption: landing]) == home)
        // Where it already is, there is nothing to promise.
        #expect(document.frameAdoptionHost(moving: [caption: CGRect(x: 600, y: 20, width: 200, height: 30)]) == nil)
    }

    @Test("A whole selection landing on one screen names that screen once")
    func theHintForASelection() {
        var document = makeDocument()
        let home = frameID(in: document)
        let caption = id(document, "Caption")
        document.addLayer(leaf("Note", CGRect(x: 700, y: 20, width: 100, height: 30)))
        let note = id(document, "Note")
        let moves = [caption: CGRect(x: 150, y: 300, width: 200, height: 30),
                     note: CGRect(x: 150, y: 400, width: 100, height: 30)]
        #expect(document.frameAdoptionHost(moving: moves) == home)
    }

    // MARK: - Components stay sane

    /// A screen inside a component's original, and the original itself loose on
    /// the canvas: dragging the original onto that screen would make the
    /// component hold itself.
    private func withComponentAroundAScreen() -> (PhotonzDocument, UUID, UUID) {
        var document = PhotonzDocument(canvasSize: CGSize(width: 2000, height: 1200), layers: [])
        let inner = Layer.frameLayer(name: "Inner", origin: CGPoint(x: 100, y: 100),
                                     size: CGSize(width: 400, height: 400))
        document.addLayer(inner)
        let main = document.groupLayers(ids: [inner.id], name: "Card")!
        _ = document.makeComponent(id: main.id)!
        return (document, main.id, inner.id)
    }

    @Test("A component is never dragged inside a screen it is made of")
    func aComponentNeverHoldsItself() {
        var (document, main, inner) = withComponentAroundAScreen()
        #expect(document.frameAdoption(of: main) == .stays)
        #expect(document.adoptMovedLayers(ids: [main]).isEmpty)
        #expect(document.parentID(of: inner) == main)
    }

    @Test("A copy of a component takes nothing in: its contents are its original's")
    func nothingGoesInsideACopy() {
        var (document, main, _) = withComponentAroundAScreen()
        let componentID = document.layer(id: main)!.componentID!
        let copy = document.insertComponentInstance(of: componentID, at: CGPoint(x: 1200, y: 600))!
        // The screen inside the copy sits under the drop point, but the copy
        // shows its original's pieces, so nothing may be put in there.
        let caption = Layer(name: "Caption", content: .text(TextContent(string: "Caption")),
                            frame: CGRect(x: 1150, y: 550, width: 100, height: 30))
        document.addLayer(caption)
        let centre = document.canvasBounds(of: copy)!
        document.moveLayer(id: caption.id,
                           toCanvasOrigin: CGPoint(x: centre.midX - 50, y: centre.midY - 15))
        #expect(document.frameAdoption(of: caption.id) == .stays)
    }
}
