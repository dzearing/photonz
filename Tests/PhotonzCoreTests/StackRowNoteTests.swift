import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the layers list says about a group that arranges itself and about the
/// pieces inside it (`ui-autolayout.html`, the Layers rows' `.lmeta`): the
/// group says row or column, and each piece says whether it hugs, fills or
/// keeps a fixed size along the way the stack runs. A plain group and a loose
/// layer say nothing, so a list nobody stacked reads exactly as it did.
@Suite("A stacked group's rows say how it is laid out")
struct StackRowNoteTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    private func label(_ string: String, _ origin: CGPoint = .zero) -> Layer {
        let content = TextContent(string: string, fontSize: 14)
        return Layer(name: string, content: .text(content),
                     frame: CGRect(origin: origin, size: TextMeasurement.size(of: content)))
    }

    private func group(_ children: [Layer], layout: GroupLayout? = nil,
                       name: String = "Group") -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        return Layer(name: name, content: .group(content), frame: .zero)
    }

    private func stack(_ direction: StackDirection, _ children: [Layer]) -> Layer {
        group(children, layout: GroupLayout(kind: .stack, direction: direction), name: "Stack")
    }

    /// Every row with the group open, keyed by name.
    private func notes(_ layers: [Layer], saysLayout: Bool = true) -> [String: StackRowNote?] {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: layers)
        let rows = doc.layerRows(expanded: doc.openableGroupIDs, selected: [],
                                 saysLayout: saysLayout)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0.layoutNote) })
    }

    // MARK: - The group says which way it runs

    @Test func aRowSaysRowAndAColumnSaysColumn() {
        let row = notes([stack(.row, [box("A", CGRect(x: 0, y: 0, width: 40, height: 20))])])
        #expect(row["Stack"]??.text == "row")
        let column = notes([stack(.column, [box("A", CGRect(x: 0, y: 0, width: 40, height: 20))])])
        #expect(column["Stack"]??.text == "column")
    }

    @Test func aGridSaysGridAndItsCellsSayNothing() {
        let grid = group([box("A", CGRect(x: 0, y: 0, width: 40, height: 20))],
                         layout: GroupLayout(kind: .grid), name: "Grid")
        let rows = notes([grid])
        #expect(rows["Grid"]??.text == "grid")
        // A cell decides its size, so there is no hug, fill or fixed to say.
        #expect(rows["A"]! == nil)
    }

    // MARK: - Each piece says how it is sized along the stack

    @Test func aPictureKeepsItsSizeSoItIsFixed() {
        let rows = notes([stack(.row, [box("A", CGRect(x: 0, y: 0, width: 40, height: 20))])])
        #expect(rows["A"]??.text == "fixed")
    }

    @Test func wordsSizedByThemselvesHug() {
        let rows = notes([stack(.row, [label("Save")])])
        #expect(rows["Save"]??.text == "hug")
        let down = notes([stack(.column, [label("Save")])])
        #expect(down["Save"]??.text == "hug")
    }

    @Test func wordsDraggedNarrowerAreFixedAcrossARow() {
        var paragraph = label("A longer line of words")
        paragraph.frame.size.width = 40
        let rows = notes([stack(.row, [paragraph])])
        #expect(rows["A longer line of words"]??.text == "fixed")
    }

    @Test func aPieceSetToFillSaysFill() {
        // A row with room to spare, so Fill the Row has something to take.
        var bar = GroupLayout(kind: .stack, direction: .row)
        bar.width = 400
        var logo = box("Logo", CGRect(x: 0, y: 0, width: 40, height: 20))
        logo.flowFill = FlowFill(sizeBefore: logo.frame.size)
        let rows = notes([group([logo, box("Menu", CGRect(x: 52, y: 0, width: 40, height: 20))],
                                layout: bar, name: "Bar")])
        #expect(rows["Logo"]??.text == "fill")
        #expect(rows["Menu"]??.text == "fixed")
    }

    @Test func aGroupInsideTakesTheSizeOfWhatItHolds() {
        let inner = group([box("Dot", CGRect(x: 0, y: 0, width: 10, height: 10))], name: "Inner")
        let rows = notes([stack(.row, [inner])])
        #expect(rows["Inner"]??.text == "hug")
    }

    @Test func aStackInsideAStackSaysBoth() {
        var sized = GroupLayout(kind: .stack, direction: .column)
        sized.width = 120
        let inner = group([box("Dot", CGRect(x: 0, y: 0, width: 10, height: 10))],
                          layout: sized, name: "Card")
        let hugging = group([box("Dot 2", CGRect(x: 0, y: 0, width: 10, height: 10))],
                            layout: GroupLayout(kind: .stack, direction: .column), name: "Tag")
        let rows = notes([stack(.row, [inner, hugging])])
        // Its own arrangement first, then how the row around it sizes it.
        #expect(rows["Card"]??.text == "column \u{00B7} fixed")
        #expect(rows["Tag"]??.text == "column \u{00B7} hug")
    }

    // MARK: - Nothing changes for anything nobody stacked

    @Test func plainGroupsAndLooseLayersSayNothing() {
        let rows = notes([group([box("A", CGRect(x: 0, y: 0, width: 40, height: 20))]),
                          box("Loose", CGRect(x: 0, y: 0, width: 40, height: 20))])
        #expect(rows["Group"]! == nil)
        #expect(rows["A"]! == nil)
        #expect(rows["Loose"]! == nil)
    }

    @Test func aGroupWithRoomButNoArrangementSaysNothing() {
        let free = group([box("A", CGRect(x: 0, y: 0, width: 40, height: 20))],
                         layout: .free(padding: GroupPadding(8)), name: "Padded")
        let rows = notes([free])
        #expect(rows["Padded"]! == nil)
        #expect(rows["A"]! == nil)
    }

    @Test func withTheSwitchOffNoRowSaysAnything() {
        let rows = notes([stack(.row, [label("Save")])], saysLayout: false)
        #expect(rows["Stack"]! == nil)
        #expect(rows["Save"]! == nil)
    }

    // MARK: - Short enough for the row, with the rest on hover

    @Test func everyWordFitsTheRowAndExplainsItselfOnHover() {
        let arrangements: [StackRowNote.Arrangement?] = [nil] + StackRowNote.Arrangement.allCases
        let sizings: [StackRowNote.Sizing?] = [nil] + StackRowNote.Sizing.allCases
        for arrangement in arrangements {
            for sizing in sizings {
                guard let note = StackRowNote(arrangement: arrangement, sizing: sizing,
                                              across: true) else { continue }
                #expect(note.text.count <= 18, "\(note.text)")
                #expect(!note.help.isEmpty)
                #expect(!note.help.contains("\u{2014}"), "no em dashes: \(note.help)")
            }
        }
        #expect(StackRowNote(arrangement: nil, sizing: nil, across: true) == nil)
        #expect(StackRowNote(arrangement: nil, sizing: .fill, across: true)?.help
            == "Takes the room the row has left")
        #expect(StackRowNote(arrangement: nil, sizing: .hug, across: false)?.help
            == "As tall as what is in it")
    }

    @Test func aSearchResultKeepsItsNote() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [stack(.row, [label("Save")])])
        let found = doc.layerRows(matching: "Save", selected: [])
        #expect(found.first?.layoutNote?.text == "hug")
    }
}
