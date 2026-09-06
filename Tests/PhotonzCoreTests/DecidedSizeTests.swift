import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Every number the app works out for you stops looking like one you can type
/// (`docs/design/mocks/shared/UX-PATTERNS.md`, "What a number you cannot type
/// looks like").
///
/// The rule was written down when a paragraph's height became a readout, and
/// then applied one case at a time: a piece taking the room its stack has left
/// over got it, and every piece the container STRETCHES did not. Three audits
/// in one cycle reported the same wart in three rooms — a piece stretched
/// across a column stack, a title spanning a nav bar, a surface behind a
/// button — and in all of them the panel offered a box, took the number, and
/// the flow put its own answer straight back.
///
/// So the question is asked once, of the layer and its container
/// (`Layer.sizeIsDecidedByItsContainer`), and both halves are checked here:
/// the field refuses the number AND the flow really would have put it back.
@Suite("A size the container works out is a number to read")
struct DecidedSizeTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ width: CGFloat, _ height: CGFloat,
                     _ placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: CGSize(width: width,
                                                                     height: height))),
              frame: CGRect(x: 0, y: 0, width: width, height: height), placement: placement)
    }

    private func group(_ children: [Layer], _ layout: GroupLayout) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        return Layer(name: "Group", content: .group(content),
                     frame: CGRect(origin: .zero, size: .zero))
    }

    private func stack(_ direction: StackDirection, width: CGFloat? = nil,
                       height: CGFloat? = nil) -> GroupLayout {
        GroupLayout(kind: .stack, direction: direction, gap: 10,
                    width: width, height: height)
    }

    /// What the flow leaves this piece at once `value` has been typed into
    /// `field`: the proof that a number the panel refuses really is a number
    /// the app would have taken away again.
    private func flowed(_ container: Layer, typing value: CGFloat,
                        into field: LayerGeometryField) -> CGSize {
        let settled = GroupFlow.flowing(container)
        var piece = settled.children[0].frame.standardized
        switch field {
        case .width: piece.size.width = value
        case .height: piece.size.height = value
        case .x, .y: break
        }
        var again = container
        again.children[0] = settled.children[0].resized(to: piece)
        return GroupFlow.flowing(again).children[0].frame.standardized.size
    }

    // MARK: - Stretched across the axis the container hands out

    @Test("A piece stretched across a column stack reads its width instead of offering a box")
    func stretchedAcrossAColumn() {
        let piece = box("Row", 50, 20, LayerPlacement(horizontal: .stretch))
        let column = group([piece, box("Other", 60, 20)], stack(.column, width: 200))
        let fields = LayerGeometryEditing(layer: piece, in: column)
        #expect(fields.allows(.width) == false)
        #expect(fields.shows(.width))
        #expect(fields.fixedReason(for: .width) == LayerGeometryEditing.filledWidthReason)
        // Down the page is still the piece's own answer in a column stack.
        #expect(fields.allows(.height))
        // And the field is right to refuse: the flow puts 200 straight back.
        #expect(flowed(column, typing: 77, into: .width).width == 200)
    }

    @Test("A piece stretched down a row stack reads its height instead of offering a box")
    func stretchedDownARow() {
        let piece = box("Item", 50, 20, LayerPlacement(vertical: .stretch))
        let row = group([piece, box("Other", 60, 20)], stack(.row, height: 80))
        let fields = LayerGeometryEditing(layer: piece, in: row)
        #expect(fields.allows(.height) == false)
        #expect(fields.shows(.height))
        #expect(fields.fixedReason(for: .height) == LayerGeometryEditing.filledHeightReason)
        #expect(fields.allows(.width))
        #expect(flowed(row, typing: 33, into: .height).height == 80)
    }

    @Test("A piece stretched in a grid reads the width of the cell it was handed")
    func stretchedInAGrid() {
        let piece = box("Card", 50, 20, LayerPlacement(horizontal: .stretch))
        let grid = group([piece, box("Other", 60, 20)],
                         GroupLayout(kind: .grid, columns: 2, gap: 10, width: 210))
        let fields = LayerGeometryEditing(layer: piece, in: grid)
        #expect(fields.allows(.width) == false)
        #expect(flowed(grid, typing: 77, into: .width).width == 100)
    }

    // MARK: - Painted to the container's own edges

    @Test("A piece spanning the way a row runs reads the width the group decided")
    func spanningARow() {
        let piece = box("Title", 50, 20,
                        LayerPlacement(horizontal: .stretch, vertical: .bottom))
        let row = group([piece, box("Other", 60, 20)],
                        stack(.row, width: 300, height: 40))
        let fields = LayerGeometryEditing(layer: piece, in: row)
        #expect(fields.allows(.width) == false)
        #expect(fields.fixedReason(for: .width) == LayerGeometryEditing.filledWidthReason)
        #expect(flowed(row, typing: 77, into: .width).width == 300)
    }

    @Test("The surface behind everything reads both of its numbers")
    func theSurfaceReadsBoth() {
        let surface = box("Background", 50, 20, .fill)
        let card = group([surface, box("Label", 60, 20)],
                         GroupLayout.free(width: 200, height: 90))
        let fields = LayerGeometryEditing(layer: surface, in: card)
        #expect(fields.allows(.width) == false)
        #expect(fields.allows(.height) == false)
        #expect(fields.fixedReason(for: .width) == LayerGeometryEditing.filledWidthReason)
        #expect(fields.fixedReason(for: .height) == LayerGeometryEditing.filledHeightReason)
        #expect(flowed(card, typing: 77, into: .width) == CGSize(width: 200, height: 90))
    }

    // MARK: - Taking the room the flow has left over

    @Test("A piece filling a row keeps naming Fill, not Stretch, as what decides it")
    func fillingStillNamesFill() {
        var filler = box("Search", 50, 20)
        filler.flowFill = FlowFill(sizeBefore: CGSize(width: 50, height: 20))
        let row = group([filler, box("Other", 60, 20)], stack(.row, width: 300))
        let fields = LayerGeometryEditing(layer: filler, in: row)
        #expect(fields.allows(.width) == false)
        #expect(fields.fixedReason(for: .width) == LayerGeometryEditing.fillingReason)
        #expect(fields.allows(.height))
    }

    @Test("A piece filling a column reads its height, and Fill is what it names")
    func fillingAColumn() {
        var filler = box("Body", 50, 20)
        filler.flowFill = FlowFill(sizeBefore: CGSize(width: 50, height: 20))
        let column = group([filler, box("Other", 60, 20)], stack(.column, height: 200))
        let fields = LayerGeometryEditing(layer: filler, in: column)
        #expect(fields.allows(.height) == false)
        #expect(fields.fixedReason(for: .height) == LayerGeometryEditing.fillingReason)
        #expect(fields.allows(.width))
    }

    // MARK: - A size that is still the piece's own

    @Test("A piece whose size is its own keeps both of its boxes")
    func itsOwnSizeStaysTypeable() {
        let piece = box("Item", 50, 20)
        let row = group([piece, box("Other", 60, 20)], stack(.row, width: 300))
        let fields = LayerGeometryEditing(layer: piece, in: row)
        #expect(fields.allows(.width))
        #expect(fields.allows(.height))
        #expect(fields.fixedReason(for: .width) == nil)
        #expect(flowed(row, typing: 77, into: .width).width == 77)
    }

    @Test("A piece pinned to an edge keeps its own width, so the box stays")
    func pinnedKeepsItsBox() {
        let piece = box("Item", 50, 20, LayerPlacement(horizontal: .right))
        let column = group([piece, box("Other", 60, 20)], stack(.column, width: 200))
        #expect(LayerGeometryEditing(layer: piece, in: column).allows(.width))
    }

    @Test("A group that arranges nothing at all leaves a stretched piece its typed width")
    func noLayoutNoDecision() {
        // Stretch here is a rule about what happens the next time the group is
        // resized, not a size the app works out: nothing re-runs, so a typed
        // width stays exactly where it was typed and the box has to stay.
        let piece = box("Item", 50, 20, LayerPlacement(horizontal: .stretch))
        var content = GroupContent(children: [piece, box("Other", 60, 20)])
        content.layout = nil
        let plain = Layer(name: "Group", content: .group(content),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 90))
        #expect(LayerGeometryEditing(layer: piece, in: plain).allows(.width))
    }

    @Test("A layer with no container at all is untouched by any of this")
    func noContainer() {
        let piece = box("Item", 50, 20, LayerPlacement(horizontal: .stretch))
        let fields = LayerGeometryEditing(layer: piece, in: nil)
        #expect(fields.allows(.width))
        #expect(fields.allows(.height))
    }

    // MARK: - What the panel does with it

    @Test("The whole selection calls a decided width read-only and answers a click on it")
    func thePanelReadsItOut() {
        let piece = box("Row", 50, 20, LayerPlacement(horizontal: .stretch))
        let column = group([piece, box("Other", 60, 20)], stack(.column, width: 200))
        let settled = GroupFlow.flowing(column)
        let selection = LayerGeometrySelection([
            .init(id: piece.id, frame: settled.children[0].frame.standardized,
                  editing: LayerGeometryEditing(layer: piece, in: column))
        ])
        #expect(selection.isReadOnly(.width))
        #expect(selection.reading(.width) == .agreed(200))
        #expect(selection.explanation(for: .width) == LayerGeometryEditing.filledWidthReason)
        #expect(selection.isReadOnly(.height) == false)
    }

    @Test("Every reason names who decides the number and the control that does change it")
    func everyReasonNamesTheControl() {
        for reason in [LayerGeometryEditing.filledWidthReason,
                       LayerGeometryEditing.filledHeightReason] {
            #expect(reason.contains("Layout section"))
            #expect(reason.contains("stretched"))
        }
        #expect(LayerGeometryEditing.filledWidthReason.contains("Horizontal"))
        #expect(LayerGeometryEditing.filledHeightReason.contains("Vertical"))
        #expect(LayerGeometryEditing.fillingReason.contains("Layout section"))
    }
}
