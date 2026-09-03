import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What ONE piece lines up inside: the screen it sits on, or the rest of the
/// group that holds it (`docs/design/ui-building.md`, "A piece lines up inside
/// the group that holds it").
@Suite("A piece lines up inside the thing that holds it")
struct ArrangeContainerTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    private func group(_ children: [Layer], layout: GroupLayout? = nil,
                       origin: CGPoint = .zero) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        return Layer(name: "Button", content: .group(content),
                     frame: CGRect(origin: origin, size: .zero))
    }

    private func frame(_ children: [Layer], size: CGSize, layout: GroupLayout? = nil) -> Layer {
        var content = GroupContent(children: children, isFrame: true, backgroundHex: "#FFFFFF")
        content.layout = layout
        return Layer(name: "Screen", content: .group(content),
                     frame: CGRect(origin: .zero, size: size))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: layers)
    }

    /// The case the whole feature exists for: a word sitting on a button's
    /// background, both wrapped in a plain group.
    private func button(labelAt label: CGRect,
                        background: CGRect = CGRect(x: 0, y: 0, width: 200, height: 60),
                        origin: CGPoint = CGPoint(x: 100, y: 100)) -> (PhotonzDocument, UUID, UUID) {
        let back = box("Background", background)
        let word = box("Label", label)
        let holder = group([back, word], origin: origin)
        return (document([holder]), word.id, holder.id)
    }

    // MARK: - A piece inside a plain group

    @Test("A word on a button lines up inside the button's background")
    func aWordAnswersToTheRestOfTheGroup() {
        let (doc, word, holder) = button(labelAt: CGRect(x: 10, y: 10, width: 60, height: 20))
        let container = doc.arrangeContainer(of: word)
        #expect(container?.id == holder)
        // Canvas space: the group sits at 100, 100 and the background fills it.
        #expect(container?.bounds == CGRect(x: 100, y: 100, width: 200, height: 60))
        #expect(container?.horizontal == true)
        #expect(container?.vertical == true)
    }

    @Test("One press centres the word on the button, and a second press does nothing")
    func centringInsideAGroupSettlesInOnePress() {
        let (doc, word, _) = button(labelAt: CGRect(x: 10, y: 10, width: 60, height: 20))
        guard let container = doc.arrangeContainer(of: word),
              let start = doc.canvasBounds(of: word) else { Issue.record("no container"); return }
        let piece = LayerArrangement.Box(id: word, frame: start)
        let moves = LayerArrangement.aligned([piece], to: .horizontalCenter,
                                             within: container.bounds)
        // The group spans 100…300, so a 60 wide word centres at 170.
        #expect(moves[word] == CGPoint(x: 170, y: 110))

        var moved = doc
        moved.moveLayer(id: word, toCanvasOrigin: moves[word]!)
        let again = moved.arrangeContainer(of: word)
        #expect(again?.bounds == container.bounds) // the reference held still
        let settled = LayerArrangement.Box(id: word, frame: moved.canvasBounds(of: word)!)
        #expect(LayerArrangement.aligned([settled], to: .horizontalCenter,
                                         within: again!.bounds).isEmpty)
    }

    @Test("Lining a piece up leaves the group exactly the size it was")
    func theGroupDoesNotResizeUnderThePiece() {
        let (doc, word, holder) = button(labelAt: CGRect(x: 10, y: 10, width: 60, height: 20))
        let before = doc.canvasBounds(of: holder)
        guard let container = doc.arrangeContainer(of: word) else { Issue.record("no container"); return }
        for alignment in LayerAlignment.allCases {
            let piece = LayerArrangement.Box(id: word, frame: doc.canvasBounds(of: word)!)
            var moved = doc
            if let origin = LayerArrangement.aligned([piece], to: alignment,
                                                     within: container.bounds)[word] {
                moved.moveLayer(id: word, toCanvasOrigin: origin)
            }
            #expect(moved.canvasBounds(of: holder) == before, "\(alignment) resized the group")
        }
    }

    @Test("A word hanging off the button comes back inside it, not half way")
    func aPieceOutsideTheGroupIsPulledIn() {
        // The word starts 20 points left of the background, so the group's own
        // box is wider than the background. Centring answers to the background
        // all the same, which is the only answer that stays put.
        let (doc, word, holder) = button(labelAt: CGRect(x: -20, y: 10, width: 60, height: 20))
        #expect(doc.canvasBounds(of: holder)?.width == 220)
        guard let container = doc.arrangeContainer(of: word) else { Issue.record("no container"); return }
        #expect(container.bounds == CGRect(x: 100, y: 100, width: 200, height: 60))
        let piece = LayerArrangement.Box(id: word, frame: doc.canvasBounds(of: word)!)
        #expect(LayerArrangement.aligned([piece], to: .horizontalCenter,
                                         within: container.bounds)[word]
            == CGPoint(x: 170, y: 110))
    }

    // MARK: - Nothing to line up inside

    @Test("A group of one holds nothing to line its only child up inside")
    func aGroupOfOneIsNoContainer() {
        let only = box("Only", CGRect(x: 0, y: 0, width: 40, height: 20))
        let doc = document([group([only])])
        #expect(doc.arrangeContainer(of: only.id) == nil)
    }

    @Test("A piece exactly as big as the rest of the group offers nothing")
    func aPieceThatFillsTheGroupIsNoContainer() {
        let back = box("Background", CGRect(x: 0, y: 0, width: 200, height: 60))
        let cover = box("Cover", CGRect(x: 0, y: 0, width: 200, height: 60))
        let doc = document([group([back, cover])])
        #expect(doc.arrangeContainer(of: cover.id) == nil)
    }

    @Test("A piece wider than the rest of the group keeps only the axis that moves")
    func onlyTheAxisWithRoomIsOffered() {
        // The word is wider than the background but shorter, so sideways there
        // is nowhere to go and up and down there is.
        let back = box("Background", CGRect(x: 0, y: 0, width: 100, height: 60))
        let word = box("Label", CGRect(x: 0, y: 0, width: 140, height: 20))
        let doc = document([group([back, word])])
        let container = doc.arrangeContainer(of: word.id)
        #expect(container?.horizontal == false)
        #expect(container?.vertical == true)
        #expect(container?.allows(.left) == false)
        #expect(container?.allows(.horizontalCenter) == false)
        #expect(container?.allows(.top) == true)
        #expect(container?.allowsNothing == false)
    }

    @Test("A layer alone on the canvas has nothing holding it")
    func aLooseLayerHasNoContainer() {
        let loose = box("Loose", CGRect(x: 10, y: 10, width: 40, height: 20))
        let doc = document([loose])
        #expect(doc.arrangeContainer(of: loose.id) == nil)
    }

    @Test("A stack puts its own contents where they go, so it offers no align")
    func anArrangedGroupOffersNothing() {
        let one = box("One", CGRect(x: 0, y: 0, width: 200, height: 40))
        let two = box("Two", CGRect(x: 0, y: 48, width: 60, height: 20))
        let stack = group([one, two], layout: GroupLayout(kind: .stack))
        #expect(document([stack]).arrangeContainer(of: two.id) == nil)
        // The same is true of a screen that arranges itself.
        let screen = frame([one, two], size: CGSize(width: 400, height: 300),
                           layout: GroupLayout(kind: .stack))
        #expect(document([screen]).arrangeContainer(of: two.id) == nil)
    }

    // MARK: - A piece on a screen still answers to the screen

    @Test("A layer on a screen lines up inside the screen's own box")
    func aScreenIsStillTheReference() {
        let small = box("Box", CGRect(x: 30, y: 20, width: 120, height: 40))
        let screen = frame([small], size: CGSize(width: 400, height: 360))
        let doc = document([screen])
        let container = doc.arrangeContainer(of: small.id)
        #expect(container?.id == screen.id)
        #expect(container?.bounds == CGRect(x: 0, y: 0, width: 400, height: 360))
        // A screen of one is still a screen: its box is its own, so the single
        // layer on it has all six commands.
        #expect(container?.horizontal == true)
        #expect(container?.vertical == true)
    }

    @Test("A layer bigger than its screen still lines up on the screen's edges")
    func aScreenOffersBothAxesWhatever() {
        let big = box("Big", CGRect(x: -50, y: -20, width: 600, height: 500))
        let screen = frame([big], size: CGSize(width: 400, height: 360))
        let container = document([screen]).arrangeContainer(of: big.id)
        #expect(container?.allowsNothing == false)
        #expect(container?.horizontal == true)
    }

    @Test("The search never climbs past the thing directly holding the piece")
    func theSearchDoesNotClimb() {
        // A word inside a button inside a screen answers to the button.
        let back = box("Background", CGRect(x: 0, y: 0, width: 200, height: 60))
        let word = box("Label", CGRect(x: 10, y: 10, width: 60, height: 20))
        let holder = group([back, word], origin: CGPoint(x: 40, y: 40))
        let screen = frame([holder], size: CGSize(width: 400, height: 360))
        let container = document([screen]).arrangeContainer(of: word.id)
        #expect(container?.id == holder.id)
        #expect(container?.bounds == CGRect(x: 40, y: 40, width: 200, height: 60))
    }
}
