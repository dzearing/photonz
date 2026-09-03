import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A group that arranges its own contents: a stack that lays them along one
/// axis, or a grid that fills rows of cells
/// (`docs/design/ui-building.md`, "A group can arrange its own contents").
///
/// The rule the whole feature rests on: the flow owns the axis it flows along,
/// and the placement rules this app already has own the other one. So nothing
/// here invents a second way to say "centre it".
@Suite("A stack or a grid keeps its own contents arranged")
struct GroupLayoutTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    /// A plain group holding the boxes, with an optional layout on it.
    private func group(_ children: [Layer], layout: GroupLayout? = nil,
                       contents: LayerPlacement? = nil,
                       origin: CGPoint = .zero) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        content.contentPlacement = contents
        return Layer(name: "Group", content: .group(content),
                     frame: CGRect(origin: origin, size: .zero))
    }

    /// A screen of `size` holding the boxes, with an optional layout on it.
    private func frame(_ children: [Layer], size: CGSize, layout: GroupLayout? = nil,
                       contents: LayerPlacement? = nil) -> Layer {
        var content = GroupContent(children: children, isFrame: true, backgroundHex: "#FFFFFF")
        content.layout = layout
        content.contentPlacement = contents
        return Layer(name: "Screen", content: .group(content),
                     frame: CGRect(origin: .zero, size: size))
    }

    private func frames(_ layer: Layer) -> [CGRect] {
        layer.children.map(\.frame)
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: layers)
    }

    // MARK: - Nothing happens to a group nobody asked to arrange itself

    @Test("A group with no layout is left exactly as it was drawn")
    func aPlainGroupIsUntouched() {
        let scattered = group([box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
                               box("B", CGRect(x: 77, y: 13, width: 40, height: 20))])
        #expect(frames(GroupFlow.flowing(scattered)) == frames(scattered))
    }

    @Test("A group that never held a layout writes no layout key")
    func anUnsetLayoutEncodesNothing() throws {
        let plain = GroupContent(children: [])
        let data = try JSONEncoder().encode(plain)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("layout"))
        let back = try JSONDecoder().decode(GroupContent.self, from: data)
        #expect(back.layout == nil)
    }

    @Test("A layout survives being saved and opened again")
    func aLayoutRoundTrips() throws {
        var content = GroupContent(children: [])
        content.layout = GroupLayout(kind: .grid, columns: 4, gap: 8, rowGap: 16, padding: 20)
        let data = try JSONEncoder().encode(content)
        let back = try JSONDecoder().decode(GroupContent.self, from: data)
        #expect(back.layout == content.layout)
    }

    // MARK: - A stack can be a size of its own

    /// A stack told how wide it is.
    private func sized(_ layout: GroupLayout, width: CGFloat? = nil,
                       height: CGFloat? = nil) -> GroupLayout {
        var out = layout
        out.width = width
        out.height = height
        return out
    }

    @Test("A stack given a width is that wide, whatever is inside it")
    func aFixedWidthHolds() {
        let stack = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 60, height: 20)),
        ], layout: sized(GroupLayout(kind: .stack, direction: .column, gap: 10), width: 320)))
        #expect(stack.localBounds == CGRect(x: 0, y: 0, width: 320, height: 50))
        // Nothing was stretched: the rows are still the sizes they were drawn.
        #expect(frames(stack) == [CGRect(x: 0, y: 0, width: 40, height: 20),
                                  CGRect(x: 0, y: 30, width: 60, height: 20)])
    }

    @Test("A row set to stretch fills the stack's width rather than the widest row")
    func stretchFillsAFixedStack() {
        let stack = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 60, height: 20)),
        ], layout: sized(GroupLayout(kind: .stack, direction: .column, gap: 10), width: 320),
           contents: LayerPlacement(horizontal: .stretch)))
        #expect(frames(stack).map(\.width) == [320, 320])
        #expect(stack.localBounds.width == 320)
    }

    @Test("A stack with a size of its own keeps its contents inside its padding")
    func paddingWorksOnAStack() {
        let stack = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: sized(GroupLayout(kind: .stack, direction: .column, gap: 10, padding: 16),
                         width: 320),
           contents: LayerPlacement(horizontal: .stretch)))
        #expect(frames(stack) == [CGRect(x: 16, y: 16, width: 288, height: 20),
                                  CGRect(x: 16, y: 46, width: 288, height: 20)])
    }

    @Test("A stack that sizes itself still keeps its padding clear, and grows by it")
    func paddingGrowsAHuggingStack() {
        let stack = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10, padding: 8)))
        #expect(frames(stack) == [CGRect(x: 8, y: 8, width: 40, height: 20),
                                  CGRect(x: 8, y: 38, width: 40, height: 20)])
        #expect(stack.localBounds == CGRect(x: 0, y: 0, width: 56, height: 66))
    }

    @Test("A stack with a size of its own flows the same the second time")
    func aFixedStackSettles() {
        let once = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 9, y: 90, width: 70, height: 30)),
        ], layout: sized(GroupLayout(kind: .stack, direction: .column, gap: 7, padding: 12),
                         width: 300, height: 200),
           contents: LayerPlacement(horizontal: .stretch)))
        #expect(frames(GroupFlow.flowing(once)) == frames(once))
        #expect(GroupFlow.flowing(once).localBounds == once.localBounds)
    }

    @Test("Setting a stack back to sizing itself leaves its contents exactly where they are")
    func backToSizingItselfMovesNothing() {
        let stack = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 60, height: 20)),
        ], layout: sized(GroupLayout(kind: .stack, direction: .column, gap: 10), width: 320),
           contents: LayerPlacement(horizontal: .stretch)))
        var hugging = stack
        hugging.setGroupLayout(sized(GroupLayout(kind: .stack, direction: .column, gap: 10)))
        let flowed = GroupFlow.flowing(hugging)
        #expect(frames(flowed) == frames(stack))
        // The rows really are 320 wide now, so the box it makes for itself is too.
        #expect(flowed.localBounds.width == 320)
    }

    @Test("An empty stack given a size is that size")
    func anEmptyStackTakesItsSize() {
        let empty = group([], layout: sized(GroupLayout(kind: .stack), width: 200, height: 80))
        #expect(empty.localBounds == CGRect(x: 0, y: 0, width: 200, height: 80))
    }

    @Test("A stack that sizes itself writes no size, and one that was given a size keeps it")
    func aSizeRoundTrips() throws {
        var content = GroupContent(children: [])
        content.layout = GroupLayout(kind: .stack)
        let hugging = try JSONEncoder().encode(content)
        #expect(!(try #require(String(data: hugging, encoding: .utf8))).contains("width"))
        #expect(try JSONDecoder().decode(GroupContent.self, from: hugging).layout?.width == nil)

        content.layout = sized(GroupLayout(kind: .stack), width: 320)
        let fixed = try JSONEncoder().encode(content)
        let back = try JSONDecoder().decode(GroupContent.self, from: fixed)
        #expect(back.layout?.width == 320)
        #expect(back.layout?.height == nil)
    }

    // MARK: - Typing a width sizes the stack instead of scaling it

    @Test("Typing a width on a stack sizes the stack and leaves what is inside it alone")
    func typingAWidthSizesTheStack() {
        let stack = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10)))
        let typed = stack.resized(to: CGRect(x: 0, y: 0, width: 320, height: 50))
        #expect(typed.group?.layout?.width == 320)
        #expect(typed.localBounds.width == 320)
        #expect(frames(typed).map(\.width) == [40, 40])
    }

    @Test("Typing only a width leaves the height still sizing itself")
    func onlyTheSideYouChangeIsPinned() {
        let stack = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10)))
        let typed = stack.resized(to: CGRect(x: 0, y: 0, width: 320, height: 50))
        #expect(typed.group?.layout?.height == nil)
        // ...and the box still follows the rows on the axis nobody typed into.
        #expect(typed.localBounds.height == 50)
    }

    @Test("Dragging a stack's corner sizes it and its stretched rows fill the new width")
    func draggingACornerSizesTheStack() {
        var doc = document([group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10),
           contents: LayerPlacement(horizontal: .stretch))])
        let id = doc.layers[0].id
        doc.updateLayer(id: id) { $0 = $0.resized(to: CGRect(x: 0, y: 0, width: 240, height: 90)) }
        doc.reflowLayouts()
        #expect(doc.layers[0].group?.layout?.width == 240)
        #expect(doc.layers[0].group?.layout?.height == 90)
        #expect(frames(doc.layers[0]).map(\.width) == [240, 240])
        #expect(doc.layers[0].localBounds == CGRect(x: 0, y: 0, width: 240, height: 90))
    }

    @Test("A stack stretched across a screen takes the screen's width and its own rows fill it")
    func aStackFillingAScreenPassesTheWidthOn() {
        var inner = group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10),
           contents: LayerPlacement(horizontal: .stretch))
        inner.placement = LayerPlacement(horizontal: .stretch)
        let screen = GroupFlow.flowing(frame([inner], size: CGSize(width: 200, height: 300),
            layout: GroupLayout(kind: .stack, direction: .column, gap: 8, padding: 16)))
        let stack = try? #require(screen.children.first)
        #expect(stack?.localBounds.width == 168)
        #expect(stack?.children.map(\.frame.width) == [168, 168])
    }

    @Test("Switching a padded stack to a grid and back does not walk it across the canvas")
    func switchingKindKeepsAPaddedStackPut() {
        var doc = document([group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10, padding: 8),
           origin: CGPoint(x: 100, y: 50))])
        doc.reflowLayouts()
        let before = doc.layers[0].localBounds
        let id = doc.layers[0].id
        doc.setGroupLayout(id: id, kind: .grid)
        doc.reflowLayouts()
        doc.setGroupLayout(id: id, kind: .stack)
        doc.reflowLayouts()
        #expect(doc.layers[0].localBounds == before)
        #expect(frames(doc.layers[0]) == [CGRect(x: 8, y: 8, width: 40, height: 20),
                                          CGRect(x: 8, y: 38, width: 40, height: 20)])
    }

    @Test("A stack keeps the size it was given when it is turned into a grid and back")
    func theSizeSurvivesSwitchingKind() {
        var doc = document([group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: sized(GroupLayout(kind: .stack, direction: .column, gap: 10), width: 320))])
        let id = doc.layers[0].id
        doc.setGroupLayout(id: id, kind: .grid)
        #expect(doc.layers[0].group?.layout?.width == 320)
        doc.setGroupLayout(id: id, kind: .stack)
        #expect(doc.layers[0].group?.layout?.width == 320)
    }

    // MARK: - A stack lays its contents along one axis

    @Test("A column stack puts an even gap between every pair, top to bottom")
    func aColumnStacksDownward() {
        let stacked = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 60, height: 20)),
            box("B", CGRect(x: 0, y: 200, width: 60, height: 30)),
            box("C", CGRect(x: 0, y: 400, width: 60, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10)))
        #expect(frames(stacked) == [CGRect(x: 0, y: 0, width: 60, height: 20),
                                    CGRect(x: 0, y: 30, width: 60, height: 30),
                                    CGRect(x: 0, y: 70, width: 60, height: 20)])
    }

    @Test("A row stack lays its contents left to right")
    func aRowStacksAcross() {
        let stacked = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 300, y: 0, width: 60, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .row, gap: 12)))
        #expect(frames(stacked) == [CGRect(x: 0, y: 0, width: 40, height: 20),
                                    CGRect(x: 52, y: 0, width: 60, height: 20)])
    }

    @Test("A stack lays out from the group's own corner")
    func theStackFlowsFromItsCorner() {
        let stacked = GroupFlow.flowing(group([
            box("A", CGRect(x: 30, y: 45, width: 40, height: 20)),
            box("B", CGRect(x: 30, y: 300, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 5)))
        #expect(frames(stacked) == [CGRect(x: 0, y: 0, width: 40, height: 20),
                                    CGRect(x: 0, y: 25, width: 40, height: 20)])
    }

    @Test("Switching a group to a stack moves the group's anchor, so nothing on the canvas jumps")
    func turningItOnKeepsThePicturePut() {
        var doc = document([group([
            box("A", CGRect(x: 30, y: 45, width: 40, height: 20)),
            box("B", CGRect(x: 30, y: 70, width: 40, height: 20)),
        ], origin: CGPoint(x: 100, y: 200))])
        let id = doc.layers[0].id
        let before = doc.layers[0].localBounds
        doc.setGroupLayout(id: id, kind: .stack)
        doc.reflowLayouts()
        #expect(doc.layers[0].localBounds == before)
        #expect(doc.layers[0].frame.origin == CGPoint(x: 130, y: 245))
        #expect(frames(doc.layers[0]) == [CGRect(x: 0, y: 0, width: 40, height: 20),
                                          CGRect(x: 0, y: 25, width: 40, height: 20)])
    }

    @Test("Flowing twice changes nothing the second time")
    func theFlowSettles() {
        let once = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 9, y: 90, width: 70, height: 30)),
            box("C", CGRect(x: 4, y: 140, width: 55, height: 25)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 7),
           contents: LayerPlacement(horizontal: .center)))
        #expect(frames(GroupFlow.flowing(once)) == frames(once))
    }

    @Test("The order things stack in is the order they already read in, not the order they were drawn")
    func theFlowReadsThePositionsNotTheStack() {
        // B is drawn first but sits below A, so the stack keeps B second.
        let stacked = GroupFlow.flowing(group([
            box("B", CGRect(x: 0, y: 100, width: 40, height: 20)),
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10)))
        let a = stacked.children.first { $0.name == "A" }
        let b = stacked.children.first { $0.name == "B" }
        #expect(a?.frame.minY == 0)
        #expect(b?.frame.minY == 30)
    }

    @Test("Dragging one item past its neighbour reorders the stack instead of snapping it back")
    func draggingReorders() {
        let stack = group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10))
        var dragged = stack
        // B dragged above A, the way a hand would.
        dragged.children[1].frame.origin.y = -12
        let flowed = GroupFlow.flowing(dragged)
        #expect(flowed.children.first { $0.name == "B" }?.frame.minY == 0)
        #expect(flowed.children.first { $0.name == "A" }?.frame.minY == 30)
    }

    @Test("A hidden layer leaves no hole in the stack")
    func hiddenLayersAreSkipped() {
        var middle = box("B", CGRect(x: 0, y: 30, width: 40, height: 20))
        middle.isVisible = false
        let stacked = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            middle,
            box("C", CGRect(x: 0, y: 60, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10)))
        #expect(stacked.children.first { $0.name == "C" }?.frame.minY == 30)
    }

    // MARK: - The other axis is the placement rules we already have

    @Test("A column stack centres its contents when the group says centre")
    func theCrossAxisFollowsTheGroup() {
        let stacked = GroupFlow.flowing(group([
            box("Wide", CGRect(x: 0, y: 0, width: 100, height: 20)),
            box("Narrow", CGRect(x: 0, y: 40, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10),
           contents: LayerPlacement(horizontal: .center)))
        #expect(stacked.children.first { $0.name == "Narrow" }?.frame.minX == 30)
    }

    @Test("One layer's own rule still beats the group's")
    func aChildOverridesTheGroup() {
        var narrow = box("Narrow", CGRect(x: 0, y: 40, width: 40, height: 20))
        narrow.placement = LayerPlacement(horizontal: .right)
        let stacked = GroupFlow.flowing(group([
            box("Wide", CGRect(x: 0, y: 0, width: 100, height: 20)),
            narrow,
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10),
           contents: LayerPlacement(horizontal: .left)))
        #expect(stacked.children.first { $0.name == "Narrow" }?.frame.minX == 60)
    }

    @Test("Stretch across a column stack gives every row the same width")
    func stretchFillsTheStack() {
        let stacked = GroupFlow.flowing(group([
            box("Wide", CGRect(x: 0, y: 0, width: 100, height: 20)),
            box("Narrow", CGRect(x: 0, y: 40, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10),
           contents: LayerPlacement(horizontal: .stretch)))
        #expect(stacked.children.first { $0.name == "Narrow" }?.frame.width == 100)
    }

    @Test("A stack on a screen starts inside the padding and stretches to the screen's width")
    func aStackOnAScreenUsesItsBox() {
        let screen = GroupFlow.flowing(frame([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 90, width: 40, height: 20)),
        ], size: CGSize(width: 200, height: 300),
           layout: GroupLayout(kind: .stack, direction: .column, gap: 8, padding: 16),
           contents: LayerPlacement(horizontal: .stretch)))
        #expect(frames(screen) == [CGRect(x: 16, y: 16, width: 168, height: 20),
                                   CGRect(x: 16, y: 44, width: 168, height: 20)])
    }

    // MARK: - A grid fills rows of cells

    @Test("A grid fills a row at a time and wraps at the column count")
    func aGridWraps() {
        let tiles = (0..<5).map { box("T\($0)", CGRect(x: CGFloat($0) * 200, y: 0,
                                                       width: 40, height: 40)) }
        let grid = GroupFlow.flowing(group(tiles,
            layout: GroupLayout(kind: .grid, columns: 2, gap: 10, rowGap: 20)))
        #expect(frames(grid) == [CGRect(x: 0, y: 0, width: 40, height: 40),
                                 CGRect(x: 50, y: 0, width: 40, height: 40),
                                 CGRect(x: 0, y: 60, width: 40, height: 40),
                                 CGRect(x: 50, y: 60, width: 40, height: 40),
                                 CGRect(x: 0, y: 120, width: 40, height: 40)])
    }

    @Test("Grid cells are as big as the biggest thing in them")
    func gridCellsFitTheBiggest() {
        let grid = GroupFlow.flowing(group([
            box("Small", CGRect(x: 0, y: 0, width: 20, height: 20)),
            box("Big", CGRect(x: 300, y: 0, width: 60, height: 40)),
            box("Third", CGRect(x: 0, y: 300, width: 20, height: 20)),
        ], layout: GroupLayout(kind: .grid, columns: 2, gap: 10, rowGap: 10)))
        // Row two starts below a 40-high cell, not below the 20-high tile.
        #expect(grid.children.first { $0.name == "Third" }?.frame.minY == 50)
        #expect(grid.children.first { $0.name == "Big" }?.frame.minX == 70)
    }

    @Test("A column count below one is read as one")
    func columnsNeverGoBelowOne() {
        let grid = GroupFlow.flowing(group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 100, y: 0, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .grid, columns: 0, gap: 10, rowGap: 10)))
        #expect(frames(grid) == [CGRect(x: 0, y: 0, width: 40, height: 20),
                                 CGRect(x: 0, y: 30, width: 40, height: 20)])
    }

    @Test("A grid on a screen divides the screen's width between its columns")
    func aGridOnAScreenSharesTheWidth() {
        let tiles = (0..<2).map { box("T\($0)", CGRect(x: CGFloat($0) * 100, y: 0,
                                                       width: 20, height: 20)) }
        let screen = GroupFlow.flowing(frame(tiles, size: CGSize(width: 220, height: 200),
            layout: GroupLayout(kind: .grid, columns: 2, gap: 20, rowGap: 20, padding: 10),
            contents: LayerPlacement(horizontal: .stretch)))
        // 220 - 2×10 padding - 20 gap = 180, split in two.
        #expect(frames(screen) == [CGRect(x: 10, y: 10, width: 90, height: 20),
                                   CGRect(x: 120, y: 10, width: 90, height: 20)])
    }

    // MARK: - Turning what you already arranged into a stack

    @Test("A hand-spaced row read as a stack keeps the direction and the gap it already had")
    func inferenceReadsARow() {
        let boxes = [CGRect(x: 0, y: 0, width: 40, height: 20),
                     CGRect(x: 56, y: 0, width: 40, height: 20),
                     CGRect(x: 112, y: 0, width: 40, height: 20)]
        let layout = GroupLayout.inferred(from: boxes, kind: .stack, container: nil)
        #expect(layout.direction == .row)
        #expect(layout.gap == 16)
    }

    @Test("A hand-spaced column is read as a column")
    func inferenceReadsAColumn() {
        let boxes = [CGRect(x: 0, y: 0, width: 40, height: 20),
                     CGRect(x: 0, y: 32, width: 40, height: 20)]
        let layout = GroupLayout.inferred(from: boxes, kind: .stack, container: nil)
        #expect(layout.direction == .column)
        #expect(layout.gap == 12)
    }

    @Test("Turning an evenly spaced group into a stack moves nothing at all")
    func conversionMovesNothing() {
        var doc = document([group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 56, y: 0, width: 40, height: 20)),
            box("C", CGRect(x: 112, y: 0, width: 40, height: 20)),
        ])])
        let before = frames(doc.layers[0])
        let id = doc.layers[0].id
        doc.setGroupLayout(id: id, kind: .stack)
        doc.reflowLayouts()
        #expect(frames(doc.layers[0]) == before)
        #expect(doc.layers[0].group?.layout?.kind == .stack)
    }

    @Test("A grid read from tiles already laid out keeps the column count it sees")
    func inferenceReadsAGrid() {
        let boxes = [CGRect(x: 0, y: 0, width: 40, height: 40),
                     CGRect(x: 50, y: 0, width: 40, height: 40),
                     CGRect(x: 100, y: 0, width: 40, height: 40),
                     CGRect(x: 0, y: 50, width: 40, height: 40)]
        let layout = GroupLayout.inferred(from: boxes, kind: .grid, container: nil)
        #expect(layout.columns == 3)
        #expect(layout.gap == 10)
        #expect(layout.rowGap == 10)
    }

    // MARK: - Every edit re-flows, without any command knowing about it

    @Test("Adding a layer to a stack re-flows the rest with no dragging")
    func addingReflows() {
        var doc = document([group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10))])
        var history = History(document: doc)
        let groupID = doc.layers[0].id
        history.perform { document in
            document.updateLayer(id: groupID) { layer in
                // Dropped in at the bottom, wherever the hand let go.
                layer.children.append(Layer(name: "C",
                                            content: .image(ImageRef(pixelSize: CGSize(width: 40,
                                                                                       height: 20))),
                                            frame: CGRect(x: 17, y: 300, width: 40, height: 20)))
            }
        }
        doc = history.current
        #expect(doc.layers[0].children.first { $0.name == "C" }?.frame == CGRect(x: 0, y: 60,
                                                                                width: 40, height: 20))
    }

    @Test("Removing a layer closes the gap it left behind")
    func removingReflows() {
        let stack = group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 30, width: 40, height: 20)),
            box("C", CGRect(x: 0, y: 60, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10))
        var history = History(document: document([stack]))
        let middle = try? #require(stack.children[1].id)
        history.perform { document in
            document.updateLayer(id: stack.id) { $0.children.removeAll { $0.id == middle } }
        }
        #expect(history.current.layers[0].children.first { $0.name == "C" }?.frame.minY == 30)
    }

    @Test("A stack inside a component arranges what is inside it")
    func aStackInsideAComponent() {
        let inner = group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 200, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 6))
        var doc = document([Layer(name: "Card",
                                  content: .group(GroupContent(children: [inner])),
                                  frame: .zero)])
        let card = doc.layers[0].id
        #expect(doc.makeComponent(id: card) != nil)
        doc.reflowLayouts()
        let flowed = doc.layer(id: inner.id)
        #expect(flowed?.children.last?.frame.minY == 26)
    }

    @Test("The innermost stack settles before the one holding it")
    func nestedStacksFlowInsideOut() {
        let inner = group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 200, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 0))
        let outer = group([inner,
                           box("Under", CGRect(x: 0, y: 500, width: 40, height: 20))],
                          layout: GroupLayout(kind: .stack, direction: .column, gap: 10))
        let flowed = GroupFlow.flowing(outer)
        // The inner stack is 40 high once it has settled, so Under lands at 50.
        #expect(flowed.children.first { $0.name == "Under" }?.frame.minY == 50)
    }

    // MARK: - A stack places its contents, so Scale stops being a thing

    @Test("A group that arranges itself never offers Scale, and says Left rather than Scale")
    func aStackPlacesRatherThanScales() {
        let free = group([box("A", CGRect(x: 0, y: 0, width: 40, height: 20))])
        #expect(!free.placesItsContents)
        #expect(free.horizontalPlacementChoices.contains(.scale))
        #expect(free.contentPlacementDefault.horizontal == .scale)

        let stacked = group([box("A", CGRect(x: 0, y: 0, width: 40, height: 20))],
                            layout: GroupLayout(kind: .stack))
        #expect(stacked.placesItsContents)
        #expect(!stacked.horizontalPlacementChoices.contains(.scale))
        #expect(!stacked.verticalPlacementChoices.contains(.scale))
        #expect(stacked.contentPlacementDefault.horizontal == .left)
        #expect(stacked.contentPlacementDefault.vertical == .top)
    }

    @Test("A layer inside a stack reads as held to the edge, not scaled")
    func aChildOfAStackReadsAsPlaced() {
        let child = box("A", CGRect(x: 0, y: 0, width: 40, height: 20))
        let stacked = group([child], layout: GroupLayout(kind: .stack))
        #expect(child.resolvedPlacement(in: stacked).horizontal == .left)
        #expect(child.resolvedPlacement(in: stacked).followsHorizontal)
    }

    @Test("A layer in a stack has no typeable position, and the field says who owns it")
    func aStackOwnsItsContentsPositions() {
        let child = box("A", CGRect(x: 0, y: 0, width: 40, height: 20))
        let free = group([child])
        #expect(LayerGeometryEditing(layer: child, in: free).allows(.x))

        let stacked = group([child], layout: GroupLayout(kind: .stack))
        let editing = LayerGeometryEditing(layer: child, in: stacked)
        #expect(!editing.allows(.x))
        #expect(!editing.allows(.y))
        #expect(editing.allows(.width))
        #expect(editing.fixedReason(for: .y) == LayerGeometryEditing.stackedReason)

        let gridded = group([child], layout: GroupLayout(kind: .grid))
        #expect(LayerGeometryEditing(layer: child, in: gridded).fixedReason(for: .x)
                == LayerGeometryEditing.griddedReason)
    }

    // MARK: - What the app is allowed to offer

    @Test("Only a group can be told to arrange its contents")
    func onlyGroupsTakeALayout() {
        let doc = document([box("Photo", CGRect(x: 0, y: 0, width: 40, height: 20)),
                            group([box("A", CGRect(x: 0, y: 0, width: 40, height: 20))])])
        #expect(!doc.canSetGroupLayout(ids: [doc.layers[0].id]))
        #expect(doc.canSetGroupLayout(ids: [doc.layers[1].id]))
        #expect(!doc.canSetGroupLayout(ids: []))
    }

    @Test("Setting the layout back to free leaves everything exactly where the flow left it")
    func turningItOffLeavesThingsPut() {
        var doc = document([group([
            box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
            box("B", CGRect(x: 0, y: 300, width: 40, height: 20)),
        ], layout: GroupLayout(kind: .stack, direction: .column, gap: 10))])
        doc.reflowLayouts()
        let arranged = frames(doc.layers[0])
        doc.setGroupLayout(id: doc.layers[0].id, kind: nil)
        doc.reflowLayouts()
        #expect(doc.layers[0].group?.layout == nil)
        #expect(frames(doc.layers[0]) == arranged)
    }

    @Test("Several layers picked at once become one stacked group")
    func stackingASelection() {
        var doc = document([box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
                            box("B", CGRect(x: 0, y: 32, width: 40, height: 20))])
        let ids = Set(doc.layers.map(\.id))
        let made = doc.stackSelection(ids: ids, kind: .stack)
        #expect(made != nil)
        doc.reflowLayouts()
        let stack = try? #require(doc.layers.first)
        #expect(stack?.group?.layout?.kind == .stack)
        #expect(stack?.group?.layout?.direction == .column)
        #expect(stack?.children.count == 2)
        // Evenly spaced already, so nothing moved.
        #expect(stack?.localBounds == CGRect(x: 0, y: 0, width: 40, height: 52))
    }
}
