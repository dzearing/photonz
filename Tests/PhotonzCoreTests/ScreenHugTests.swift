import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A screen that arranges its contents can be told to hug them
/// (`docs/design/ui-building.md`, "A screen can hug what it holds").
///
/// A screen is a box somebody drew, and it stays the size they drew it unless
/// they say otherwise: that is what keeps something hanging off its edge from
/// ever resizing it. What changed is that a screen set to a row or a column can
/// now be SAID otherwise, one axis at a time, with the same Hug the Width and
/// Height rows already offer a group.
@Suite("A screen can hug what it holds")
struct ScreenHugTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ size: CGSize, at origin: CGPoint = .zero) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: size)),
              frame: CGRect(origin: origin, size: size))
    }

    /// A 400 by 300 screen at 100, 50 holding a column of what it is given,
    /// 16 clear inside its edges and 10 between the rows.
    private func screen(_ children: [Layer], layout: GroupLayout? = GroupLayout(
        kind: .stack, direction: .column, gap: 10, padding: GroupPadding(16))) -> Layer {
        var made = Layer.frameLayer(name: "Screen", origin: CGPoint(x: 100, y: 50),
                                    size: CGSize(width: 400, height: 300), children: children)
        made.setGroupLayout(layout)
        return made
    }

    private func hugging(_ layout: GroupLayout?, width: Bool = true,
                         height: Bool = true) -> GroupLayout? {
        guard var layout else { return nil }
        layout.screenHugsWidth = width
        layout.screenHugsHeight = height
        return layout
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 1200, height: 900), layers: layers)
    }

    private let button = CGSize(width: 120, height: 36)
    private let card = CGSize(width: 200, height: 80)

    // MARK: - The flow

    @Test("A hugging column screen is its contents plus its padding, and keeps its corner")
    func aHuggingScreenIsItsContentsPlusPadding() {
        let flowed = GroupFlow.flowing(screen([box("Button", button), box("Card", card)],
                                              layout: hugging(screen([]).group?.layout)))
        // Widest row 200 + 16 each side; 36 + 10 + 80 + 16 top and bottom.
        #expect(flowed.frame == CGRect(x: 100, y: 50, width: 232, height: 158))
        #expect(flowed.localBounds == flowed.frame)
    }

    @Test("One axis hugs and the other keeps the size it was drawn")
    func oneAxisAtATime() {
        let flowed = GroupFlow.flowing(screen([box("Button", button), box("Card", card)],
                                              layout: hugging(screen([]).group?.layout,
                                                              width: false, height: true)))
        #expect(flowed.frame == CGRect(x: 100, y: 50, width: 400, height: 158))
    }

    @Test("A screen nobody told to hug keeps the size it was drawn, whatever goes in")
    func aFixedScreenStaysPut() {
        let flowed = GroupFlow.flowing(screen([box("Button", button), box("Card", card)]))
        #expect(flowed.frame == CGRect(x: 100, y: 50, width: 400, height: 300))
    }

    @Test("A free screen never hugs, even carrying the switch, so nothing off its edge resizes it")
    func aFreeScreenNeverHugs() {
        var free = GroupLayout.free(padding: GroupPadding(16))
        free.screenHugsWidth = true
        free.screenHugsHeight = true
        let flowed = GroupFlow.flowing(screen([box("Hanging", card, at: CGPoint(x: 350, y: 260))],
                                              layout: free))
        #expect(flowed.frame == CGRect(x: 100, y: 50, width: 400, height: 300))
        #expect(!free.screenHugs(horizontal: true))
        #expect(!free.screenHugs(horizontal: false))
    }

    @Test("An empty hugging screen holds the size it has, since there is nothing to hug")
    func anEmptyScreenHoldsItsSize() {
        let flowed = GroupFlow.flowing(screen([], layout: hugging(screen([]).group?.layout)))
        #expect(flowed.frame == CGRect(x: 100, y: 50, width: 400, height: 300))
    }

    @Test("A hugging row screen grows across as things go in")
    func aRowGrowsAcross() {
        let row = GroupLayout(kind: .stack, direction: .row, gap: 8, padding: GroupPadding(12))
        let flowed = GroupFlow.flowing(screen([box("A", button), box("B", button)],
                                              layout: hugging(row)))
        #expect(flowed.frame.size == CGSize(width: 12 + 120 + 8 + 120 + 12, height: 12 + 36 + 12))
    }

    // MARK: - Through an edit

    @Test("Adding grows a hugging screen and removing shrinks it, each one undo step")
    func addingAndRemovingThroughHistory() throws {
        let start = GroupFlow.flowing(screen([box("Button", button)],
                                             layout: hugging(screen([]).group?.layout)))
        let id = start.id
        var history = History(document: document([start]))
        #expect(history.current.layer(id: id)?.frame.size == CGSize(width: 152, height: 68))

        history.perform { $0.updateLayer(id: id) { $0.children.append(self.box("Card", self.card)) } }
        #expect(history.current.layer(id: id)?.frame.size == CGSize(width: 232, height: 158))

        let cardID = try #require(history.current.layer(id: id)?.children.last?.id)
        history.perform { _ = $0.removeLayer(id: cardID) }
        #expect(history.current.layer(id: id)?.frame.size == CGSize(width: 152, height: 68))

        history.undo()
        #expect(history.current.layer(id: id)?.frame.size == CGSize(width: 232, height: 158))
        history.undo()
        #expect(history.current.layer(id: id)?.frame.size == CGSize(width: 152, height: 68))
    }

    @Test("Picking Hug is one undo step that puts the drawn size back")
    func pickingHugUndoes() {
        let start = screen([box("Button", button)])
        let id = start.id
        var history = History(document: document([start]))
        history.perform { document in
            document.updateGroupLayout(ids: [id]) { layout, layer in
                layout.setHugging(true, horizontal: true, onAScreen: layer.isFrame,
                                  holding: layer.localBounds.width)
            }
        }
        #expect(history.current.layer(id: id)?.frame.size == CGSize(width: 152, height: 300))
        history.undo()
        #expect(history.current.layer(id: id)?.frame.size == CGSize(width: 400, height: 300))
    }

    @Test("Resizing a hugging screen by hand turns only that axis Fixed")
    func resizingByHandFixesThatAxis() {
        let start = GroupFlow.flowing(screen([box("Button", button)],
                                             layout: hugging(screen([]).group?.layout)))
        let resized = start.resized(to: CGRect(x: 100, y: 50, width: 500, height: start.frame.height))
        let layout = resized.group?.layout
        #expect(layout?.screenHugsWidth == false)
        #expect(layout?.screenHugsHeight == true)
        #expect(GroupFlow.flowing(resized).frame.size == CGSize(width: 500, height: 68))
    }

    // MARK: - The words the rows read

    @Test("Hug and Fixed on a screen write the switch; on a group they write the size")
    func settingHug() {
        var layout = GroupLayout(kind: .stack)
        layout.setHugging(true, horizontal: true, onAScreen: true, holding: 400)
        #expect(layout.screenHugsWidth && layout.width == nil)
        #expect(layout.hugs(onAScreen: true, horizontal: true))
        layout.setHugging(false, horizontal: true, onAScreen: true, holding: 400)
        #expect(!layout.screenHugsWidth && layout.width == nil)
        #expect(!layout.hugs(onAScreen: true, horizontal: true))

        var group = GroupLayout(kind: .stack)
        group.setHugging(false, horizontal: false, onAScreen: false, holding: 87.6)
        #expect(group.height == 88 && !group.screenHugsHeight)
        #expect(!group.hugs(onAScreen: false, horizontal: false))
        group.setHugging(true, horizontal: false, onAScreen: false, holding: 88)
        #expect(group.height == nil)
    }

    @Test("A screen that arranges offers Width and Height; a free one does not")
    func theRowsAreOfferedOnlyWhereTheyMeanSomething() throws {
        let column = screen([box("Button", button)])
        let free = screen([box("Button", button)], layout: .free())
        let plain = screen([box("Button", button)], layout: nil)
        let doc = document([column, free, plain])
        let arranged = doc.contentsSelection(layerIDs: [column.id])
        #expect(arranged.offersHug)
        #expect(!arranged.offersASizeOfItsOwn)
        #expect(arranged.hugsWidth.value == false)
        #expect(!doc.contentsSelection(layerIDs: [free.id]).offersHug)
        #expect(!doc.contentsSelection(layerIDs: [plain.id]).offersHug)
        #expect(!doc.contentsSelection(layerIDs: [column.id, free.id]).offersHug)
        // Switched off, nothing arranges, so a screen has nothing to hug.
        #expect(!doc.contentsSelection(layerIDs: [column.id], arranging: false).offersHug)

        let hugged = screen([box("Button", button)], layout: hugging(column.group?.layout))
        let reading = document([hugged]).contentsSelection(layerIDs: [hugged.id])
        #expect(reading.hugsWidth.value == true)
        #expect(reading.hugsHeight.value == true)
        // A hugging screen is the size of its contents along the flow, so it
        // has no room left over to share out.
        #expect(!reading.canSpread)
    }

    // MARK: - Saved documents

    @Test("Every screen saved before this opens fixed, and a fixed one writes nothing new")
    func olderFilesOpenUnchanged() throws {
        let older = Data(#"{"kind":"stack","direction":"column","columns":3,"gap":12,"rowGap":12,"padding":16}"#.utf8)
        let layout = try JSONDecoder().decode(GroupLayout.self, from: older)
        #expect(!layout.screenHugsWidth && !layout.screenHugsHeight)
        let written = String(decoding: try JSONEncoder().encode(layout), as: UTF8.self)
        #expect(!written.contains("Hug"))
    }

    @Test("A hugging screen saves and opens hugging")
    func huggingRoundTrips() throws {
        let layout = try #require(hugging(GroupLayout(kind: .stack), width: true, height: false))
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(GroupLayout.self, from: data) == layout)
    }
}
