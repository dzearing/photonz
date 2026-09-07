import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What a press on a screen's own empty surface means.
///
/// A screen is a surface you build on, so the empty room between the things on
/// it belongs to picking them, not to picking the screen up: a drag there
/// sweeps a band over what is on that screen. The screen still moves by a drag
/// once it is picked, and by its name at any time
/// (`docs/design/ui-building.md`, "The two canvas gestures").
@Suite("A band swept inside a screen")
struct BandInsideAScreenTests {

    private func leaf(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)), frame: frame)
    }

    private func screen(_ name: String, _ frame: CGRect, _ children: [Layer]) -> Layer {
        Layer(name: name, content: .group(GroupContent(children: children, isFrame: true)),
              frame: frame)
    }

    /// Canvas 800×600. "Screen" sits at (100, 100) and is 300×200, holding
    /// "Save" at local (20, 20, 60×24) and "Cancel" at local (20, 60, 60×24).
    /// "Aside" is a top-level layer beside the screen at (500, 100, 80×40).
    private func makeDocument() -> PhotonzDocument {
        let screen = screen("Screen", CGRect(x: 100, y: 100, width: 300, height: 200), [
            leaf("Save", CGRect(x: 20, y: 20, width: 60, height: 24)),
            leaf("Cancel", CGRect(x: 20, y: 60, width: 60, height: 24)),
        ])
        return PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                               layers: [leaf("Aside", CGRect(x: 500, y: 100, width: 80, height: 40)),
                                        screen])
    }

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    private func names(_ doc: PhotonzDocument, _ ids: [UUID]) -> [String] {
        ids.compactMap { doc.layer(id: $0)?.name }
    }

    /// A point on the screen's surface with nothing on it: bottom-right of the
    /// screen's room, well clear of both buttons.
    private var emptySurface: CGPoint { CGPoint(x: 350, y: 260) }

    // MARK: - A drag on the empty surface sweeps

    @Test func aPressOnAScreensEmptySurfaceSweepsThatScreen() {
        let doc = makeDocument()
        #expect(doc.screenSurfacePress(at: emptySurface, picked: []) == .sweep(screen: id(doc, "Screen")))
    }

    @Test func aPressOnSomethingSittingOnTheScreenIsNotASurfacePress() {
        let doc = makeDocument()
        // Straight on the Save button.
        #expect(doc.screenSurfacePress(at: CGPoint(x: 150, y: 130), picked: []) == nil)
    }

    @Test func aPressOutOnTheCanvasIsNotASurfacePress() {
        let doc = makeDocument()
        #expect(doc.screenSurfacePress(at: CGPoint(x: 700, y: 500), picked: []) == nil)
        #expect(doc.screenSurfacePress(at: CGPoint(x: 520, y: 120), picked: []) == nil)
    }

    // MARK: - What the band catches

    @Test func theBandTakesOnlyWhatIsOnThatScreen() {
        let doc = makeDocument()
        guard case .sweep(let level)? = doc.screenSurfacePress(at: emptySurface, picked: []) else {
            Issue.record("expected a sweep")
            return
        }
        let whole = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(names(doc, doc.layerIDs(fullyInside: whole, inside: level)) == ["Save", "Cancel"])
    }

    @Test func theBandNeverTakesTheScreenItselfNorAnythingBesideIt() {
        let doc = makeDocument()
        guard case .sweep(let level)? = doc.screenSurfacePress(at: emptySurface, picked: []) else {
            Issue.record("expected a sweep")
            return
        }
        let caught = Set(doc.layerIDs(fullyInside: CGRect(x: 0, y: 0, width: 800, height: 600),
                                      inside: level))
        #expect(!caught.contains(id(doc, "Screen")))
        #expect(!caught.contains(id(doc, "Aside")))
    }

    // MARK: - The screen still moves

    @Test func aScreenThatIsAlreadyPickedMovesInsteadOfSweeping() {
        let doc = makeDocument()
        let screen = id(doc, "Screen")
        #expect(doc.screenSurfacePress(at: emptySurface, picked: [screen]) == .move(screen: screen))
    }

    @Test func aScreenPickedAmongOthersMovesToo() {
        let doc = makeDocument()
        let screen = id(doc, "Screen")
        #expect(doc.screenSurfacePress(at: emptySurface, picked: [screen, id(doc, "Aside")])
                == .move(screen: screen))
    }

    @Test func somethingElseBeingPickedDoesNotStopTheSweep() {
        let doc = makeDocument()
        #expect(doc.screenSurfacePress(at: emptySurface, picked: [id(doc, "Save")])
                == .sweep(screen: id(doc, "Screen")))
    }

    // MARK: - Screens on screens, and the things that are not screens

    @Test func anInnerScreensSurfaceSweepsTheInnerScreen() {
        let inner = screen("Inner", CGRect(x: 40, y: 40, width: 120, height: 100),
                           [leaf("Chip", CGRect(x: 10, y: 10, width: 30, height: 16))])
        let outer = screen("Outer", CGRect(x: 0, y: 0, width: 400, height: 300), [inner])
        let doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [outer])
        // (120, 120) is inside Inner's room but clear of Chip.
        #expect(doc.screenSurfacePress(at: CGPoint(x: 120, y: 120), picked: [])
                == .sweep(screen: id(doc, "Inner")))
        // Out on Outer's own surface, past Inner.
        #expect(doc.screenSurfacePress(at: CGPoint(x: 300, y: 250), picked: [])
                == .sweep(screen: id(doc, "Outer")))
    }

    @Test func aPlainGroupIsNotASurfaceSoItsEmptyRoomIsStillTheCanvas() {
        let group = Layer(name: "Card",
                          content: .group(GroupContent(children: [
                              leaf("Title", CGRect(x: 0, y: 0, width: 40, height: 20)),
                          ])),
                          frame: CGRect(x: 100, y: 100, width: 0, height: 0))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [group])
        #expect(doc.screenSurfacePress(at: CGPoint(x: 200, y: 200), picked: []) == nil)
    }

    @Test func aLockedScreenOffersNoSurfacePress() {
        var doc = makeDocument()
        doc.updateLayer(id: id(doc, "Screen")) { $0.isLocked = true }
        #expect(doc.screenSurfacePress(at: emptySurface, picked: []) == nil)
    }

    @Test func aHiddenScreenOffersNoSurfacePress() {
        var doc = makeDocument()
        doc.updateLayer(id: id(doc, "Screen")) { $0.isVisible = false }
        #expect(doc.screenSurfacePress(at: emptySurface, picked: []) == nil)
    }

    @Test func aCopyOfAComponentIsOneObjectSoItsSurfaceIsNotSwept() {
        var doc = makeDocument()
        doc.updateLayer(id: id(doc, "Screen")) { layer in
            guard var content = layer.group else { return }
            content.instanceOf = UUID()
            layer.content = .group(content)
        }
        #expect(doc.screenSurfacePress(at: emptySurface, picked: []) == nil)
    }
}

/// What the pointer SAYS about a press on a screen's surface, before the
/// button goes down.
///
/// The same drag has two meanings on a screen's empty room — sweep a band over
/// what is on the screen, or carry the screen — and which one you get depends
/// on something you cannot see in the pointer: whether the screen is picked.
/// The rule the app draws from this is one mark, the open hand: it means THIS
/// DRAG CARRIES THE SCREEN, and it is absent everywhere a drag bands instead.
@Suite("What a screen's surface says a drag will do")
struct ScreenSurfaceCueTests {

    private func leaf(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)), frame: frame)
    }

    /// Canvas 800×600, "Screen" at (100, 100) 300×200 with two buttons on it.
    private func makeDocument() -> PhotonzDocument {
        let screen = Layer(name: "Screen",
                           content: .group(GroupContent(children: [
                               leaf("Save", CGRect(x: 20, y: 20, width: 60, height: 24)),
                               leaf("Cancel", CGRect(x: 20, y: 60, width: 60, height: 24)),
                           ], isFrame: true)),
                           frame: CGRect(x: 100, y: 100, width: 300, height: 200))
        return PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                               layers: [leaf("Aside", CGRect(x: 500, y: 100, width: 80, height: 40)),
                                        screen])
    }

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    /// Empty room on the screen, well clear of both buttons.
    private var emptySurface: CGPoint { CGPoint(x: 350, y: 260) }

    // MARK: - The two meanings

    @Test func aScreenThatIsNotPickedSaysItWillSweep() {
        let doc = makeDocument()
        #expect(doc.screenSurfaceCue(at: emptySurface, picked: [], optionHeld: false)
                == .sweep(screen: id(doc, "Screen")))
    }

    @Test func aScreenThatIsPickedSaysItWillMove() {
        let doc = makeDocument()
        let screen = id(doc, "Screen")
        #expect(doc.screenSurfaceCue(at: emptySurface, picked: [screen], optionHeld: false)
                == .move(screen: screen))
    }

    /// The cue and the press are the same answer, always: a pointer that
    /// offered a move where the press would band would be worse than no
    /// pointer at all.
    @Test func theCueNeverDisagreesWithThePress() {
        let doc = makeDocument()
        let screen = id(doc, "Screen")
        for picked in [Set<UUID>(), [screen], [screen, id(doc, "Aside")], [id(doc, "Save")]] {
            let press = doc.screenSurfacePress(at: emptySurface, picked: picked)
            let cue = doc.screenSurfaceCue(at: emptySurface, picked: picked, optionHeld: false)
            switch (press, cue) {
            case (.sweep(let a)?, .sweep(let b)?), (.move(let a)?, .move(let b)?):
                #expect(a == b)
            default:
                Issue.record("press \(String(describing: press)) and cue \(String(describing: cue)) disagree")
            }
        }
    }

    // MARK: - What ⌥ does there

    /// ⌥ dragging a picked screen still leaves the original behind, so the
    /// pointer keeps its copy badge.
    @Test func optionOverAPickedScreenSaysItWillLeaveACopy() {
        let doc = makeDocument()
        let screen = id(doc, "Screen")
        #expect(doc.screenSurfaceCue(at: emptySurface, picked: [screen], optionHeld: true)
                == .moveCopy(screen: screen))
    }

    /// ⌥ dragging a screen that is NOT picked used to duplicate it and now
    /// sweeps a band, so the copy badge has to go: a badge there would promise
    /// a duplicate the press does not make.
    @Test func optionOverAnUnpickedScreenStillSaysSweep() {
        let doc = makeDocument()
        #expect(doc.screenSurfaceCue(at: emptySurface, picked: [], optionHeld: true)
                == .sweep(screen: id(doc, "Screen")))
    }

    // MARK: - Everywhere else says nothing

    @Test func somethingSittingOnTheScreenGetsNoCue() {
        let doc = makeDocument()
        #expect(doc.screenSurfaceCue(at: CGPoint(x: 150, y: 130), picked: [], optionHeld: false) == nil)
        #expect(doc.screenSurfaceCue(at: CGPoint(x: 150, y: 130),
                                     picked: [id(doc, "Screen")], optionHeld: false) == nil)
    }

    @Test func bareCanvasGetsNoCue() {
        let doc = makeDocument()
        #expect(doc.screenSurfaceCue(at: CGPoint(x: 700, y: 500), picked: [], optionHeld: false) == nil)
    }

    @Test func aLockedScreenGetsNoCue() {
        var doc = makeDocument()
        let screen = id(doc, "Screen")
        doc.updateLayer(id: screen) { $0.isLocked = true }
        #expect(doc.screenSurfaceCue(at: emptySurface, picked: [screen], optionHeld: false) == nil)
    }

    @Test func aCopyOfAComponentGetsNoCue() {
        var doc = makeDocument()
        doc.updateLayer(id: id(doc, "Screen")) { layer in
            guard var content = layer.group else { return }
            content.instanceOf = UUID()
            layer.content = .group(content)
        }
        #expect(doc.screenSurfaceCue(at: emptySurface, picked: [], optionHeld: false) == nil)
    }
}
