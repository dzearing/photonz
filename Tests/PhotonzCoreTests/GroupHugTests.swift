import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A container that closes around what is inside it
/// (`docs/design/ui-building.md`, "A container closes around its contents").
///
/// The complaint this answers: give a button a longer label and the button
/// stays the width it was, so the words hang out of the pill. A container can
/// now be told to be as big as its contents plus the room it keeps at its
/// edges, and the surface behind those contents takes the box rather than
/// setting it.
@Suite("A container closes around what is inside it")
struct GroupHugTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect,
                     placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)),
              frame: frame, placement: placement)
    }

    private func group(_ children: [Layer], layout: GroupLayout? = nil,
                       contents: LayerPlacement? = nil,
                       origin: CGPoint = .zero) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        content.contentPlacement = contents
        return Layer(name: "Group", content: .group(content),
                     frame: CGRect(origin: origin, size: .zero))
    }

    private func frames(_ layer: Layer) -> [CGRect] { layer.children.map(\.frame) }

    private func piece(_ layer: Layer, _ name: String) -> CGRect {
        layer.children.first { $0.name == name }?.frame ?? .null
    }

    private func document(_ layers: [Layer] = []) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: layers)
    }

    /// A button as the starters draw one: a surface that fills, and a word
    /// sitting in the middle of it.
    private func plate(padding: GroupPadding = GroupPadding(top: 8, right: 16,
                                                            bottom: 8, left: 16),
                       width: CGFloat? = nil, height: CGFloat? = nil,
                       word: CGRect = CGRect(x: 41, y: 8, width: 50, height: 20)) -> Layer {
        group([box("Background", CGRect(x: 0, y: 0, width: 128, height: 36),
                   placement: .fill),
               box("Label", word)],
              layout: .free(padding: padding, width: width, height: height),
              contents: LayerPlacement(horizontal: .center, vertical: .center))
    }

    // MARK: - The box a hugging container makes

    @Test("A group told to hug is as big as its contents plus the room at its edges")
    func aHuggingGroupIsItsContentsPlusItsPadding() {
        let hugging = GroupFlow.flowing(
            group([box("Words", CGRect(x: 10, y: 4, width: 50, height: 20))],
                  layout: .free(padding: GroupPadding(8))))
        #expect(hugging.localBounds == CGRect(x: 0, y: 0, width: 66, height: 36))
        // The contents start inside the near edges, so the room typed is the
        // room actually kept on every side.
        #expect(frames(hugging) == [CGRect(x: 8, y: 8, width: 50, height: 20)])
    }

    @Test("Room on each of the four sides makes its own room, not an average of them")
    func unevenRoomOnAHuggingGroup() {
        let hugging = GroupFlow.flowing(
            group([box("Words", CGRect(x: 0, y: 0, width: 50, height: 20))],
                  layout: .free(padding: GroupPadding(top: 12, right: 8, bottom: 24, left: 16))))
        #expect(frames(hugging) == [CGRect(x: 16, y: 12, width: 50, height: 20)])
        #expect(hugging.localBounds.size == CGSize(width: 16 + 50 + 8, height: 12 + 20 + 24))
    }

    @Test("Hugging one axis leaves the other one exactly as it was given")
    func hugIsPerAxis() {
        let hugging = GroupFlow.flowing(
            group([box("Words", CGRect(x: 0, y: 0, width: 50, height: 20))],
                  layout: .free(padding: GroupPadding(10), height: 90)))
        #expect(hugging.localBounds.size == CGSize(width: 70, height: 90))
        // The axis with a size of its own is not the flow's business: the piece
        // is left exactly where it was put down the page.
        #expect(frames(hugging) == [CGRect(x: 10, y: 0, width: 50, height: 20)])
    }

    @Test("The contents keep the arrangement they have: a hugging axis has no room to place them in")
    func huggingKeepsTheArrangementItWasGiven() {
        let two = GroupFlow.flowing(
            group([box("A", CGRect(x: 20, y: 0, width: 40, height: 20)),
                   box("B", CGRect(x: 70, y: 30, width: 40, height: 20))],
                  layout: .free(padding: GroupPadding(6))))
        // Both pieces moved by the same amount, so nothing about the way they
        // were arranged changed; the box simply closed around them.
        #expect(frames(two) == [CGRect(x: 6, y: 6, width: 40, height: 20),
                                CGRect(x: 56, y: 36, width: 40, height: 20)])
        #expect(two.localBounds.size == CGSize(width: 6 + 90 + 6, height: 6 + 50 + 6))
    }

    // MARK: - What Stretch means inside a container with no spare room

    @Test("A piece that stretches both ways takes the box rather than setting it")
    func aStretchedPieceIsTheSurface() {
        let button = GroupFlow.flowing(plate())
        // The 128-wide background no longer decides how wide the button is:
        // the word does, plus the room on each side.
        #expect(button.localBounds.size == CGSize(width: 16 + 50 + 16, height: 8 + 20 + 8))
        #expect(piece(button, "Label") == CGRect(x: 16, y: 8, width: 50, height: 20))
        // ...and the surface fills the box it ended up with, edge to edge,
        // because the padding is room INSIDE the surface, not around it.
        #expect(piece(button, "Background") == CGRect(x: 0, y: 0, width: 82, height: 36))
    }

    @Test("A piece that stretches one way is measured on the other one only")
    func aPieceStretchedAcrossTakesTheWidthTheRestMade() {
        let card = GroupFlow.flowing(
            group([box("Rule", CGRect(x: 0, y: 40, width: 300, height: 1),
                       placement: LayerPlacement(horizontal: .stretch)),
                   box("Words", CGRect(x: 0, y: 0, width: 60, height: 20))],
                  layout: .free(padding: GroupPadding(10))))
        // The 300-wide rule does not decide the width: it takes the width the
        // words made, inside the room at the edges.
        #expect(piece(card, "Rule") == CGRect(x: 10, y: 50, width: 60, height: 1))
        // ...and it is still measured DOWN the page, where it does not stretch.
        #expect(card.localBounds.size == CGSize(width: 10 + 60 + 10, height: 10 + 41 + 10))
    }

    @Test("A group whose every piece fills it keeps the size those pieces make")
    func everythingStretchingFallsBackToWhatIsThere() {
        let all = GroupFlow.flowing(
            group([box("Under", CGRect(x: 0, y: 0, width: 100, height: 40), placement: .fill),
                   box("Over", CGRect(x: 0, y: 0, width: 60, height: 40), placement: .fill)],
                  layout: .free()))
        #expect(all.localBounds.size == CGSize(width: 100, height: 40))
    }

    @Test("A piece that stretches both ways is the surface, not a row in a stack")
    func aSurfaceStepsOutOfAStacksFlow() {
        let stack = GroupFlow.flowing(
            group([box("Background", CGRect(x: 0, y: 0, width: 100, height: 80),
                       placement: .fill),
                   box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
                   box("B", CGRect(x: 0, y: 30, width: 40, height: 20))],
                  layout: GroupLayout(kind: .stack, gap: 10)))
        // The two rows are the stack; the surface takes no turn and no gap.
        #expect(piece(stack, "A") == CGRect(x: 0, y: 0, width: 40, height: 20))
        #expect(piece(stack, "B") == CGRect(x: 0, y: 30, width: 40, height: 20))
        #expect(piece(stack, "Background") == CGRect(x: 0, y: 0, width: 40, height: 50))
    }

    // MARK: - A size of its own still behaves exactly as it did

    @Test("A group given a size holds it, and its contents are left where they were put")
    func aFixedGroupIsUntouchedApartFromItsSurface() {
        let fixed = GroupFlow.flowing(plate(width: 200, height: 60))
        #expect(fixed.localBounds.size == CGSize(width: 200, height: 60))
        #expect(piece(fixed, "Label") == CGRect(x: 41, y: 8, width: 50, height: 20))
        #expect(piece(fixed, "Background") == CGRect(x: 0, y: 0, width: 200, height: 60))
    }

    @Test("A group nobody asked to close up is left exactly as it was drawn")
    func aGroupWithNoLayoutIsUntouched() {
        let plain = group([box("Background", CGRect(x: 0, y: 0, width: 128, height: 36),
                               placement: .fill),
                           box("Label", CGRect(x: 41, y: 8, width: 50, height: 20))])
        #expect(frames(GroupFlow.flowing(plain)) == frames(plain))
        #expect(GroupFlow.flowing(plain).localBounds == plain.localBounds)
    }

    @Test("Room bigger than the size the group was given never squashes the surface away")
    func moreRoomThanThereIsDoesNotLoseTheSurface() {
        // 28 of room top and bottom inside a group told it is 36 tall leaves
        // nothing between the edges. The surface is painted to the box, not to
        // what is left between the edges, so it is still there — and a shape
        // squashed to no height could never be given one back.
        let button = GroupFlow.flowing(plate(padding: GroupPadding(28), height: 36))
        #expect(piece(button, "Background") == CGRect(x: 0, y: 0,
                                                      width: button.localBounds.width, height: 36))
        #expect(button.localBounds.size == CGSize(width: 28 + 50 + 28, height: 36))
        // ...and going back to less room puts everything back.
        let back = GroupFlow.flowing(plate(padding: GroupPadding(8), height: 36))
        #expect(piece(back, "Background").height == 36)
    }

    // MARK: - It settles, and it settles once

    @Test("The box settles in one pass: running the flow again moves nothing")
    func theFlowSettlesInOnePass() {
        for layout in [GroupLayout.free(padding: GroupPadding(8)),
                       GroupLayout.free(padding: GroupPadding(8), width: 240),
                       GroupLayout.free(padding: GroupPadding(top: 4, right: 9,
                                                              bottom: 14, left: 20))] {
            let once = GroupFlow.flowing(plate(padding: layout.padding,
                                               width: layout.width, height: layout.height))
            #expect(frames(GroupFlow.flowing(once)) == frames(once))
            #expect(GroupFlow.flowing(once).localBounds == once.localBounds)
        }
    }

    // MARK: - Turning it on, and dragging it afterwards

    @Test("Turning hug on leaves everything exactly where it was")
    func pressingHugMovesNothing() {
        var doc = document([group([box("Background", CGRect(x: 0, y: 0, width: 128, height: 36),
                                       placement: .fill),
                                   box("Label", CGRect(x: 41, y: 8, width: 50, height: 21))],
                                  contents: LayerPlacement(horizontal: .center, vertical: .center),
                                  origin: CGPoint(x: 100, y: 60))])
        guard let id = doc.layers.first?.id else { Issue.record("no group"); return }
        let before = doc.layer(id: id).map { ($0.localBounds, $0.children.map(\.frame)) }
        doc.setGroupLayout(id: id, kind: nil)
        doc.reflowLayouts()
        guard let after = doc.layer(id: id) else { Issue.record("group went missing"); return }
        // The room it keeps is read off where its contents already sit, so
        // nothing on the canvas moves at the moment it starts hugging.
        #expect(after.group?.layout != nil)
        #expect(after.localBounds == before?.0)
        #expect(after.children.map(\.frame) == before?.1)
        // ...and now a longer word makes it wider.
        let padding = after.group?.layout?.usedPadding
        #expect(padding?.left == 41 && padding?.right == 37)
    }

    @Test("Dragging a hugging group's handle gives it a size of its own on that axis alone")
    func draggingAHuggingGroupPinsTheAxisItWasDragged() {
        let button = GroupFlow.flowing(plate())
        let wider = button.resized(to: CGRect(x: 0, y: 0, width: 260,
                                              height: button.localBounds.height))
        #expect(wider.group?.layout?.usedWidth == 260)
        // The other axis is still the size of what is inside it.
        #expect(wider.group?.layout?.hugsHeight == true)
        #expect(piece(wider, "Background") == CGRect(x: 0, y: 0, width: 260, height: 36))
        // The word stays in the middle of the pill, because a fixed axis is
        // still the placement rules' to answer.
        #expect(abs(piece(wider, "Label").midX - 130) <= 1)
    }

    // MARK: - The thing the user actually complained about

    @Test("A longer label makes a starter button wider and keeps its padding")
    func awordingChangeWidensTheButton() {
        var history = History(document: document())
        var buttonID: UUID?
        history.perform { buttonID = $0.insertStarterComponent(.button, at: CGPoint(x: 400, y: 300)) }
        guard let buttonID, let before = history.current.layer(id: buttonID) else {
            Issue.record("no button")
            return
        }
        let room = before.group?.layout?.usedPadding ?? .none
        #expect(before.group?.layout?.hugsWidth == true)
        let label = before.children.first { $0.name == "Label" }
        #expect(label?.frame.minX == room.left)
        // A measured text box carries its slack on the far edge, so the room
        // that shows is the room around the WORDS.
        let words = (label?.frame.width ?? 0) - TextMeasurement.slack
        #expect(before.localBounds.width == room.left + words + room.right)

        // Re-word it, the way typing over the word in the canvas does.
        guard let labelID = label?.id else { Issue.record("no label"); return }
        history.perform { doc in
            doc.updateLayer(id: labelID) { piece in
                guard case .text(var content) = piece.content else { return }
                content.string = "Save all the changes now"
                piece.content = .text(content)
                piece = piece.textRefitted(hugging: true, anchor: .center)
            }
        }
        guard let after = history.current.layer(id: buttonID),
              let grown = after.children.first(where: { $0.name == "Label" }),
              let surface = after.children.first(where: { $0.name == "Background" })
        else { Issue.record("the button lost a piece"); return }
        #expect(grown.frame.width > (label?.frame.width ?? 0))
        // The pill grew with the words and kept exactly the room it had.
        #expect(grown.frame.minX == room.left)
        #expect(after.localBounds.width
                == room.left + grown.frame.width - TextMeasurement.slack + room.right)
        #expect(surface.frame == CGRect(origin: .zero, size: after.localBounds.size))
        // ...and it did not have to be dragged to get there.
        #expect(after.localBounds.height == before.localBounds.height)
    }

    @Test("A copy told to say something longer grows too")
    func aCopyGrowsWithItsOwnWording() {
        var history = History(document: document())
        var mainID: UUID?
        history.perform { mainID = $0.insertStarterComponent(.button, at: CGPoint(x: 200, y: 200)) }
        var copyID: UUID?
        history.perform {
            copyID = $0.insertComponentInstance(of: StarterComponent.button.componentID,
                                                at: CGPoint(x: 200, y: 400))
        }
        guard let mainID, let copyID,
              let property = history.current.instanceProperties(instance: copyID).first
        else { Issue.record("no copy with a knob"); return }
        let before = history.current.layer(id: copyID)?.localBounds.width ?? 0
        history.perform {
            $0.setInstanceOverride(instance: copyID, property: property.id,
                                   value: .text("Save all the changes now"))
        }
        guard let copy = history.current.layer(id: copyID) else { Issue.record("copy gone"); return }
        #expect(copy.localBounds.width > before)
        #expect(copy.children.first { $0.name == "Background" }?.frame.width
                == copy.localBounds.width)
        // The original never answered the knob, so it is the size it was.
        #expect(history.current.layer(id: mainID)?.localBounds.width == before)
    }

    // MARK: - What gets written down

    @Test("A group that hugs writes no arrangement, and one that never had a layout writes nothing")
    func whatIsSavedStaysSmall() throws {
        let free = try #require(String(data: try JSONEncoder().encode(GroupLayout.free(padding: 12)),
                                       encoding: .utf8))
        #expect(!free.contains("kind"))
        #expect(free.contains("padding"))
        // A layout saved with no kind opens as a group that arranges nothing
        // and simply closes around what is in it.
        let read = try JSONDecoder().decode(GroupLayout.self, from: Data(free.utf8))
        #expect(read.kind == nil)
        #expect(read.usedPadding == GroupPadding(12))
        // Every document written before any of this had no layout at all.
        let plain = group([box("A", CGRect(x: 0, y: 0, width: 10, height: 10))])
        let written = try #require(String(data: try JSONEncoder().encode(plain), encoding: .utf8))
        #expect(!written.contains("layout"))
    }
}
