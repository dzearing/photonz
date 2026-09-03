import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// A copy follows its original's LOOK, not just its shape
/// (`docs/design/ui-building.md`, "A copy follows the original's look").
///
/// The rule under test: a copy's fade, blur, rounded corners, border and shadow
/// come from the original, part by part, until somebody sets that part on the
/// copy. Then that part is the copy's own and everything else keeps following.
struct ComponentStyleTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// One component of two pieces, and two copies of it out on the canvas.
    private func withTwoCopies() -> (doc: PhotonzDocument, main: UUID, component: UUID,
                                     a: UUID, b: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 60, height: 30)),
                                           box("Label", CGRect(x: 20, y: 50, width: 40, height: 30))])
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Setting")!
        let component = doc.makeComponent(id: group.id)!
        let a = doc.insertComponentInstance(of: component, at: CGPoint(x: 200, y: 200))!
        let b = doc.insertComponentInstance(of: component, at: CGPoint(x: 500, y: 200))!
        doc.syncComponentInstances()
        return (doc, group.id, component, a, b)
    }

    // MARK: - The look follows

    @Test func fadingTheOriginalFadesEveryCopy() {
        var (doc, main, _, a, b) = withTwoCopies()
        doc.updateLayer(id: main) { $0.style.opacity = 0.5 }
        doc.syncComponentInstances()
        #expect(doc.layer(id: a)!.style.opacity == 0.5)
        #expect(doc.layer(id: b)!.style.opacity == 0.5)
    }

    @Test func blurRoundingAndShadowFollowToo() {
        var (doc, main, _, a, _) = withTwoCopies()
        doc.updateLayer(id: main) { layer in
            layer.style.blurRadius = 6
            layer.style.cornerRadius = 14
            layer.style.borderWidth = 2
            layer.style.borderColorHex = "#FF0000"
            layer.style.shadow = ShadowStyle(radius: 20, offset: CGSize(width: 0, height: 8))
        }
        doc.syncComponentInstances()
        let copy = doc.layer(id: a)!
        #expect(copy.style.blurRadius == 6)
        #expect(copy.style.cornerRadius == 14)
        #expect(copy.style.borderWidth == 2)
        #expect(copy.style.borderColorHex == "#FF0000")
        #expect(copy.style.shadow?.radius == 20)
    }

    @Test func aCopyTakesTheOriginalsLookWhenItIsPlaced() {
        var (doc, main, component, _, _) = withTwoCopies()
        doc.updateLayer(id: main) { $0.style.cornerRadius = 9 }
        doc.syncComponentInstances()
        let placed = doc.insertComponentInstance(of: component, at: CGPoint(x: 700, y: 400))!
        #expect(doc.layer(id: placed)!.style.cornerRadius == 9)
        // ...and placing one is not "the original changed", so nothing is announced.
        #expect(doc.syncComponentInstances().updatedInstances == 0)
    }

    // MARK: - What the copy set stays set

    @Test func aCopyYouFadedKeepsItsOwnFade() {
        var (doc, main, _, a, b) = withTwoCopies()
        var history = History(document: doc)
        history.perform { $0.updateLayer(id: a) { $0.style.opacity = 0.25 } }
        history.perform { $0.updateLayer(id: main) { $0.style.opacity = 0.9 } }
        #expect(history.current.layer(id: a)!.style.opacity == 0.25)
        // ...while the copy nobody touched followed.
        #expect(history.current.layer(id: b)!.style.opacity == 0.9)
    }

    /// The whole reason the look follows part by part: a copy that was faded
    /// once still gets the shadow the original gained afterwards.
    @Test func aStyledCopyStillFollowsTheRest() {
        var (doc, main, _, a, _) = withTwoCopies()
        var history = History(document: doc)
        history.perform { $0.updateLayer(id: a) { $0.style.opacity = 0.25 } }
        history.perform { $0.updateLayer(id: main) { layer in
            layer.style.shadow = ShadowStyle(radius: 18)
            layer.style.cornerRadius = 12
        } }
        let copy = history.current.layer(id: a)!
        #expect(copy.style.opacity == 0.25)
        #expect(copy.style.shadow?.radius == 18)
        #expect(copy.style.cornerRadius == 12)
    }

    @Test func aCopySaysWhichPartsOfItsLookAreItsOwn() {
        var (doc, _, _, a, b) = withTwoCopies()
        var history = History(document: doc)
        history.perform { $0.updateLayer(id: a) { $0.style.opacity = 0.25 } }
        #expect(history.current.instanceStyleOverrides(instance: a) == [.opacity])
        #expect(history.current.instanceStyleOverrides(instance: b).isEmpty)
    }

    @Test func aShadowSetOnACopyCountsAsOneThing() {
        var (doc, _, _, a, _) = withTwoCopies()
        var history = History(document: doc)
        history.perform { $0.updateLayer(id: a) { $0.style.shadow = ShadowStyle(radius: 4) } }
        #expect(history.current.instanceStyleOverrides(instance: a) == [.shadow])
    }

    @Test func puttingOnePartBackMakesItFollowAgain() {
        var (doc, main, _, a, _) = withTwoCopies()
        var history = History(document: doc)
        history.perform { $0.updateLayer(id: a) { $0.style.opacity = 0.25 } }
        history.perform { $0.updateLayer(id: main) { $0.style.opacity = 0.6 } }
        history.perform { $0.clearInstanceStyleOverride(instance: a, field: .opacity) }
        #expect(history.current.layer(id: a)!.style.opacity == 0.6)
        #expect(history.current.instanceStyleOverrides(instance: a).isEmpty)
        // ...and it follows the next change too, rather than being frozen at 0.6.
        history.perform { $0.updateLayer(id: main) { $0.style.opacity = 0.3 } }
        #expect(history.current.layer(id: a)!.style.opacity == 0.3)
    }

    @Test func puttingTheWholeLookBackClearsEveryPart() {
        var (doc, main, _, a, _) = withTwoCopies()
        var history = History(document: doc)
        history.perform { $0.updateLayer(id: main) { $0.style.cornerRadius = 8 } }
        history.perform { $0.updateLayer(id: a) { layer in
            layer.style.opacity = 0.25
            layer.style.cornerRadius = 30
        } }
        #expect(history.current.instanceStyleOverrides(instance: a) == [.opacity, .cornerRadius])
        history.perform { $0.clearInstanceStyleOverrides(instance: a) }
        #expect(history.current.instanceStyleOverrides(instance: a).isEmpty)
        #expect(history.current.layer(id: a)!.style == history.current.layer(id: main)!.style)
    }

    /// A copy's own look travels with it, so ⌘J on a faded copy makes another
    /// faded one rather than one that snaps back to the original.
    @Test func duplicatingAStyledCopyKeepsItsLook() {
        var (doc, _, _, a, _) = withTwoCopies()
        var history = History(document: doc)
        history.perform { $0.updateLayer(id: a) { $0.style.opacity = 0.25 } }
        var made: UUID?
        history.perform { made = $0.duplicateLayer(id: a, offsetBy: CGPoint(x: 20, y: 20))?.id }
        #expect(history.current.layer(id: made!)!.style.opacity == 0.25)
        #expect(history.current.instanceStyleOverrides(instance: made!) == [.opacity])
    }

    /// Detaching keeps exactly the picture the copy was drawing, look and all.
    @Test func detachingKeepsTheLookItWasDrawing() {
        var (doc, main, _, a, _) = withTwoCopies()
        var history = History(document: doc)
        history.perform { $0.updateLayer(id: main) { $0.style.cornerRadius = 10 } }
        history.perform { $0.updateLayer(id: a) { $0.style.opacity = 0.4 } }
        history.perform { $0.detachInstance(id: a) }
        let loose = history.current.layer(id: a)!
        #expect(!loose.isComponentInstance)
        #expect(loose.style.opacity == 0.4)
        #expect(loose.style.cornerRadius == 10)
        // ...and it no longer follows.
        history.perform { $0.updateLayer(id: main) { $0.style.cornerRadius = 40 } }
        #expect(history.current.layer(id: a)!.style.cornerRadius == 10)
    }

    // MARK: - What the notice says

    @Test func theNoticeCountsALookChangeLikeAChangeToTheContents() {
        var (doc, main, component, _, _) = withTwoCopies()
        var history = History(document: doc)
        let report = history.perform { $0.updateLayer(id: main) { $0.style.opacity = 0.5 } }
        #expect(report.updatedInstances == 2)
        #expect(report.componentIDs == [component])
    }

    /// A copy that keeps its own fade did not follow, so it is not counted.
    @Test func aCopyThatKeptItsOwnLookIsNotCounted() {
        var (doc, main, _, a, _) = withTwoCopies()
        var history = History(document: doc)
        history.perform { $0.updateLayer(id: a) { $0.style.opacity = 0.25 } }
        let report = history.perform { $0.updateLayer(id: main) { $0.style.opacity = 0.9 } }
        #expect(report.updatedInstances == 1)
    }

    /// Setting a copy's own fade is an edit to the copy in front of you, not an
    /// edit that reached anything out of sight.
    @Test func stylingACopyReportsNoUpdate() {
        var (doc, _, _, a, _) = withTwoCopies()
        var history = History(document: doc)
        let report = history.perform { $0.updateLayer(id: a) { $0.style.opacity = 0.25 } }
        #expect(report.updatedInstances == 0)
    }

    // MARK: - Nothing drifts

    @Test func syncingTwiceChangesNothing() {
        var (doc, main, _, a, _) = withTwoCopies()
        doc.updateLayer(id: main) { $0.style.blurRadius = 4 }
        doc.updateLayer(id: a) { $0.style.opacity = 0.3 }
        doc.syncComponentInstances()
        let settled = doc
        let report = doc.syncComponentInstances()
        #expect(report.updatedInstances == 0)
        #expect(doc == settled)
    }

    /// The look reaches a copy nested inside another component, two levels down.
    @Test func aCopyInsideAnotherComponentFollowsTheLookToo() {
        var (doc, main, inner, _, _) = withTwoCopies()
        let nested = doc.insertComponentInstance(of: inner, at: CGPoint(x: 500, y: 450))!
        let backing = box("Backing", CGRect(x: 400, y: 350, width: 300, height: 200))
        doc.addLayer(backing)
        let card = doc.groupLayers(ids: [nested, backing.id], name: "Card")!
        let outer = doc.makeComponent(id: card.id)!
        let placed = doc.insertComponentInstance(of: outer, at: CGPoint(x: 200, y: 500))!
        doc.syncComponentInstances()

        doc.updateLayer(id: main) { $0.style.cornerRadius = 16 }
        doc.syncComponentInstances()
        #expect(doc.layer(id: nested)!.style.cornerRadius == 16)
        let deepest = doc.layer(id: placed)!.children.first { $0.isComponentInstance }
        #expect(deepest?.style.cornerRadius == 16)
    }

    /// Deleting the original leaves the copy exactly as it was drawing.
    @Test func aCopyWhoseOriginalIsGoneKeepsItsLook() {
        var (doc, main, _, a, _) = withTwoCopies()
        doc.updateLayer(id: main) { $0.style.cornerRadius = 10 }
        doc.syncComponentInstances()
        doc.removeLayer(id: main)
        doc.syncComponentInstances()
        let orphan = doc.layer(id: a)!
        #expect(!orphan.isComponentInstance)
        #expect(orphan.style.cornerRadius == 10)
    }

    // MARK: - Documents that were saved before this

    /// A copy saved before the look followed has no memory of the original's
    /// look, so opening that document must not repaint anything: the copy keeps
    /// drawing exactly what it drew, and every part it differs from the
    /// original by becomes its own. The revert control is how a person who
    /// wanted it to follow says so, in one click.
    @Test func aDocumentSavedBeforeThisOpensLookingTheSame() {
        var (doc, main, _, a, _) = withTwoCopies()
        doc.updateLayer(id: main) { $0.style.cornerRadius = 10 }
        // The copy as it would have been on disk: its own fade, no memory, and
        // a rounding the original gained after it was placed.
        doc.updateLayer(id: a) { layer in
            layer.style.opacity = 0.3
            guard var group = layer.group else { return }
            group.followedStyle = nil
            layer.content = .group(group)
        }
        doc.syncComponentInstances()
        let copy = doc.layer(id: a)!
        #expect(copy.style.opacity == 0.3)
        #expect(copy.style.cornerRadius == 0)
        #expect(doc.instanceStyleOverrides(instance: a) == [.opacity, .cornerRadius])
        doc.clearInstanceStyleOverride(instance: a, field: .cornerRadius)
        doc.syncComponentInstances()
        #expect(doc.layer(id: a)!.style.cornerRadius == 10)
        #expect(doc.layer(id: a)!.style.opacity == 0.3)
    }

    // MARK: - On disk

    @Test func aGroupThatFollowsNothingWritesNoKey() throws {
        let group = Layer(name: "Group", content: .group(GroupContent(children: [])),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(group))
        let content = ((json as! [String: Any])["content"] as! [String: Any])
        let payload = content.values.compactMap { $0 as? [String: Any] }.first!
        #expect(payload["followedStyle"] == nil)
    }

    @Test func aCopysMemoryOfTheOriginalSurvivesASave() throws {
        var (doc, main, _, a, _) = withTwoCopies()
        doc.updateLayer(id: main) { $0.style.cornerRadius = 10 }
        doc.updateLayer(id: a) { $0.style.opacity = 0.3 }
        doc.syncComponentInstances()
        let data = try JSONEncoder().encode(doc)
        var reopened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(reopened.instanceStyleOverrides(instance: a) == [.opacity])
        reopened.syncComponentInstances()
        #expect(reopened.layer(id: a)!.style.opacity == 0.3)
        #expect(reopened.layer(id: a)!.style.cornerRadius == 10)
    }
}
