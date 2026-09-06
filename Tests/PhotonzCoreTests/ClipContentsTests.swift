import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A container with a size of its own can cut off what does not fit.
///
/// A screen has always done this. A card, a menu or any other group given a
/// width, a height or a largest size has a box of its own too, so the same
/// switch belongs on it — off until somebody asks for it, so nothing already
/// drawn changes.
@Suite("Clip contents")
struct ClipContentsTests {

    private func leaf(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)), frame: frame)
    }

    /// A group holding one child that runs 40 points past the bottom of the
    /// 100×100 box the group was given.
    private func sizedGroup(width: CGFloat? = 100, height: CGFloat? = 100,
                            clips: Bool? = nil) -> Layer {
        var content = GroupContent(children: [leaf("Title", CGRect(x: 0, y: 0,
                                                                   width: 60, height: 140))],
                                   clipsContents: clips)
        content.layout = .free(width: width, height: height)
        return Layer(name: "Card", content: .group(content),
                     frame: CGRect(x: 10, y: 10, width: 0, height: 0))
    }

    // MARK: - Who is offered the switch

    @Test("A group that closes around its contents is not offered it")
    func huggingGroupIsNotOffered() {
        let plain = Layer(name: "Group",
                          content: .group(GroupContent(children: [leaf("A", CGRect(x: 0, y: 0,
                                                                                   width: 10,
                                                                                   height: 10))])),
                          frame: .zero)
        #expect(plain.hasBoxOfItsOwn == false)

        var arranged = plain
        arranged.setGroupLayout(.free(padding: GroupPadding(8)))
        #expect(arranged.hasBoxOfItsOwn == false)
    }

    @Test("A group given a width, a height or a largest size has a box of its own")
    func sizedGroupIsOffered() {
        #expect(sizedGroup(width: 100, height: nil).hasBoxOfItsOwn)
        #expect(sizedGroup(width: nil, height: 100).hasBoxOfItsOwn)

        var capped = sizedGroup(width: nil, height: nil)
        capped.setGroupLayout(GroupLayout(kind: nil, maxWidth: 80))
        #expect(capped.hasBoxOfItsOwn)

        // A floor only ever makes the box bigger than its contents, so it
        // leaves nothing hanging out to cut off.
        var floored = sizedGroup(width: nil, height: nil)
        floored.setGroupLayout(GroupLayout(kind: nil, minWidth: 80))
        #expect(floored.hasBoxOfItsOwn == false)
    }

    @Test("A screen is offered it, as it always was")
    func aScreenIsOffered() {
        let frame = Layer.frameLayer(name: "Home", origin: .zero,
                                     size: CGSize(width: 100, height: 100))
        #expect(frame.hasBoxOfItsOwn)
        #expect(frame.clipsToBounds)
    }

    // MARK: - Off by default

    @Test("A sized group cuts off nothing until somebody turns it on")
    func offByDefault() {
        let card = sizedGroup()
        #expect(card.group?.clipsContents == false)
        #expect(card.clipsToBounds == false)
        // Its drawing still reaches past the box, so the overhang is drawn.
        #expect(card.renderBounds.maxY > card.localBounds.maxY)
    }

    @Test("Turning it on stops the drawing at the edge")
    func onStopsTheDrawing() {
        let card = sizedGroup(clips: true)
        #expect(card.clipsToBounds)
        #expect(card.renderBounds.maxY == card.localBounds.maxY)
    }

    @Test("A group with the switch on but no size of its own still cuts off nothing")
    func aHuggingGroupNeverClips() {
        var card = sizedGroup(width: nil, height: nil, clips: true)
        card.setGroupLayout(nil)
        #expect(card.group?.clipsContents == true)
        #expect(card.clipsToBounds == false)
    }

    // MARK: - What is not drawn is not clicked

    @Test("A click past the edge misses what hangs out of a clipping group")
    func clippedContentsAreNotClicked() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 300, height: 300),
                                       layers: [sizedGroup()])
        let id = document.layers[0].id
        // The child runs from y=10 to y=150 on the canvas; the box stops at 110.
        let inside = CGPoint(x: 30, y: 60)
        let overhang = CGPoint(x: 30, y: 130)
        #expect(document.hitTest(inside) != nil)
        #expect(document.hitTest(overhang) != nil)

        document.setClipsContents(id: id, true)
        #expect(document.hitTest(inside) != nil)
        #expect(document.hitTest(overhang) == nil)
        #expect(document.layer(id: id)!.contains(canvasPoint: overhang) == false)
    }

    @Test("A clipping group is still not a surface: its empty room takes no click")
    func aGroupIsStillNotASurface() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 300, height: 300),
                                       layers: [sizedGroup()])
        document.setClipsContents(id: document.layers[0].id, true)
        // Inside the 100×100 box but past the 60-wide child: a group has no
        // surface of its own, so nothing is picked there.
        #expect(document.hitTest(CGPoint(x: 100, y: 60)) == nil)
    }

    // MARK: - Setting it

    @Test("Only a container with a box of its own can be told")
    func onlyABoxCanBeTold() {
        let hugging = Layer(name: "Group",
                            content: .group(GroupContent(children: [leaf("A", .zero)])),
                            frame: .zero)
        var document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100),
                                       layers: [hugging])
        document.setClipsContents(id: document.layers[0].id, true)
        #expect(document.layers[0].group?.clipsContents == false)
    }

    @Test("A screen is told the same way it always was")
    func aScreenIsToldTheSameWay() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: [
            Layer.frameLayer(name: "Home", origin: .zero, size: CGSize(width: 100, height: 100))
        ])
        let id = document.layers[0].id
        document.setClipsContents(id: id, false)
        #expect(document.layer(id: id)?.clipsToBounds == false)
        document.setClipsContents(id: id, true)
        #expect(document.layer(id: id)?.clipsToBounds == true)
    }

    // MARK: - A copy takes it from its original

    @Test("Duplicating carries the setting")
    func duplicateCarriesTheSetting() {
        let copy = sizedGroup(clips: true).duplicated()
        #expect(copy.clipsToBounds)
    }

    @Test("A copy of a component takes the setting from its original")
    func anInstanceTakesTheSetting() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                       layers: [sizedGroup(clips: true)])
        let mainID = document.layers[0].id
        guard let componentID = document.makeComponent(id: mainID) else {
            Issue.record("no component"); return
        }
        guard let copyID = document.insertComponentInstance(of: componentID,
                                                            at: CGPoint(x: 250, y: 250)) else {
            Issue.record("no copy"); return
        }
        #expect(document.layer(id: copyID)?.clipsToBounds == true)

        // …and it keeps taking it: turning the original's switch off turns
        // every copy's off with it, the same way the rest of the arrangement
        // follows.
        document.setClipsContents(id: mainID, false)
        _ = document.syncComponentInstances()
        #expect(document.layer(id: copyID)?.clipsToBounds == false)
    }

    // MARK: - On disk

    @Test("A group that was never asked writes nothing, and one that was keeps its answer")
    func coding() throws {
        let quiet = GroupContent(children: [leaf("A", .zero)])
        let json = String(data: try JSONEncoder().encode(quiet), encoding: .utf8) ?? ""
        #expect(!json.contains("clipsContents"))
        let back = try JSONDecoder().decode(GroupContent.self, from: Data(json.utf8))
        // A group saved before this switch existed opens cutting off nothing,
        // so no picture anybody has already drawn changes.
        #expect(back.clipsContents == false)

        var asked = quiet
        asked.clipsContents = true
        asked.layout = .free(width: 100)
        let saved = try JSONEncoder().encode(asked)
        #expect(try JSONDecoder().decode(GroupContent.self, from: saved) == asked)
        #expect(try JSONDecoder().decode(GroupContent.self, from: saved).clipsContents)
    }
}
