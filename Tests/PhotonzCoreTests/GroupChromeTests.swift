import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A piece stretched the way a stack runs spans the stack instead of joining it
/// (`docs/design/ui-building.md`, "A group can arrange its own contents").
///
/// The thing this answers: a bar is not only the controls on it. It is a
/// surface, a hairline along its bottom edge, and then the controls. The
/// surface already stepped out of the flow, because stretching BOTH ways can
/// only mean "be the size of the box". A hairline stretches one way and hugs an
/// edge on the other, and until now a row counted it as a fourth control and
/// stood it in the line — which is why the one starter shaped like a bar could
/// not be built as a row at all.
///
/// The rule that keeps it small: **stretching along the way a stack runs is not
/// a request the flow can honour**, because the flow is what hands out the room
/// along itself. So it means the same thing there that it means on both axes at
/// once: step out, and be painted to the group's own edges. Taking the room
/// left over is a different answer with a different name, and it is Fill.
@Suite("A piece stretched the way a stack runs spans it")
struct GroupChromeTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect,
                     placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)),
              frame: frame, placement: placement)
    }

    private func group(_ children: [Layer], layout: GroupLayout? = nil,
                       contents: LayerPlacement? = nil) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        content.contentPlacement = contents
        return Layer(name: "Group", content: .group(content), frame: .zero)
    }

    private func piece(_ layer: Layer, _ name: String) -> CGRect {
        layer.children.first { $0.name == name }?.frame ?? .null
    }

    /// A bar: a surface, a hairline along the bottom, and two controls.
    private func bar(width: CGFloat?, height: CGFloat = 48,
                     padding: GroupPadding = GroupPadding(top: 0, right: 14,
                                                          bottom: 0, left: 14)) -> Layer {
        let layout = GroupLayout(kind: .stack, direction: .row, gap: 12,
                                 padding: padding, width: width, height: height)
        return group([box("Background", CGRect(x: 0, y: 0, width: 320, height: 48),
                          placement: LayerPlacement(horizontal: .stretch, vertical: .stretch)),
                      box("Divider", CGRect(x: 0, y: 47, width: 320, height: 1),
                          placement: LayerPlacement(horizontal: .stretch, vertical: .bottom)),
                      box("Back", CGRect(x: 14, y: 14, width: 36, height: 20)),
                      box("Next", CGRect(x: 70, y: 14, width: 40, height: 20))],
                     layout: layout,
                     contents: LayerPlacement(horizontal: .left, vertical: .center))
    }

    // MARK: - The hairline

    @Test("A hairline stretched across a row spans the bar and hugs its bottom")
    func aHairlineSpansTheBar() {
        let laid = GroupFlow.flowing(bar(width: 640))
        #expect(piece(laid, "Divider") == CGRect(x: 0, y: 47, width: 640, height: 1))
    }

    @Test("The row lines the rest up as though the hairline were not there")
    func theHairlineTakesNoPlaceInTheRow() {
        let laid = GroupFlow.flowing(bar(width: 640))
        // The first control starts at the room kept at the left edge, not
        // after a 640 point hairline and a gap.
        #expect(piece(laid, "Back") == CGRect(x: 14, y: 14, width: 36, height: 20))
        #expect(piece(laid, "Next") == CGRect(x: 62, y: 14, width: 40, height: 20))
    }

    @Test("The surface behind the row is still painted to the group's own edges")
    func theSurfaceStillFills() {
        let laid = GroupFlow.flowing(bar(width: 640))
        #expect(piece(laid, "Background") == CGRect(x: 0, y: 0, width: 640, height: 48))
    }

    @Test("A taller bar takes its hairline down with it")
    func theHairlineFollowsTheBottom() {
        let laid = GroupFlow.flowing(bar(width: 640, height: 96))
        #expect(piece(laid, "Divider") == CGRect(x: 0, y: 95, width: 640, height: 1))
        #expect(piece(laid, "Background") == CGRect(x: 0, y: 0, width: 640, height: 96))
    }

    @Test("A row that hugs its contents still spans its hairline across them")
    func aHuggingRowStillSpansIt() {
        let laid = GroupFlow.flowing(bar(width: nil))
        // 14 + 36 + 12 + 40 + 14 across, and the hairline is that wide too.
        #expect(laid.localBounds.width == 116)
        #expect(piece(laid, "Divider") == CGRect(x: 0, y: 47, width: 116, height: 1))
    }

    // MARK: - The same rule down a column

    @Test("A rail stretched down a column spans it and stays at the edge it was given")
    func aRailSpansAColumn() {
        let layout = GroupLayout(kind: .stack, direction: .column, gap: 8,
                                 padding: GroupPadding(10), width: 200, height: 300)
        let panel = group([box("Rail", CGRect(x: 199, y: 0, width: 1, height: 300),
                               placement: LayerPlacement(horizontal: .right, vertical: .stretch)),
                           box("Row 1", CGRect(x: 10, y: 10, width: 60, height: 20)),
                           box("Row 2", CGRect(x: 10, y: 38, width: 60, height: 20))],
                          layout: layout)
        let laid = GroupFlow.flowing(panel)
        #expect(piece(laid, "Rail") == CGRect(x: 199, y: 0, width: 1, height: 300))
        #expect(piece(laid, "Row 1") == CGRect(x: 10, y: 10, width: 60, height: 20))
        #expect(piece(laid, "Row 2") == CGRect(x: 10, y: 38, width: 60, height: 20))
    }

    @Test("Stretching ACROSS a column is still one of its rows")
    func stretchingAcrossAColumnStillFlows() {
        let layout = GroupLayout(kind: .stack, direction: .column, gap: 8,
                                 padding: GroupPadding(10), width: 200)
        let panel = group([box("Row 1", CGRect(x: 10, y: 10, width: 60, height: 20),
                               placement: LayerPlacement(horizontal: .stretch)),
                           box("Row 2", CGRect(x: 10, y: 38, width: 60, height: 20))],
                          layout: layout)
        let laid = GroupFlow.flowing(panel)
        #expect(piece(laid, "Row 1") == CGRect(x: 10, y: 10, width: 180, height: 20))
        #expect(piece(laid, "Row 2") == CGRect(x: 10, y: 38, width: 60, height: 20))
    }

    // MARK: - What the Layout section says about it

    @Test("A piece that spans the box answers both of its own directions")
    func spanningPieceOwnsBothAxes() {
        let layout = GroupLayout(kind: .stack, direction: .row, gap: 12, width: 640)
        let hairline = ResolvedPlacement(horizontal: .stretch, vertical: .bottom,
                                         followsHorizontal: false, followsVertical: false)
        let editing = PlacementEditing(arrangement: layout, placing: hairline)
        #expect(editing.canSetHorizontal)
        #expect(editing.canSetVertical)
        #expect(editing.setByTheFlow == nil)
        // A control in the same row is still the row's to place across.
        let control = ResolvedPlacement(horizontal: .left, vertical: .center,
                                        followsHorizontal: true, followsVertical: true)
        #expect(!PlacementEditing(arrangement: layout, placing: control).canSetHorizontal)
    }

    @Test("The group lists the piece that spans it beside the surface")
    func theGroupListsIt() {
        let laid = GroupFlow.flowing(bar(width: 640))
        let listed = laid.contentsWithTheirOwnPlacement(arrangement: laid.group?.layout)
        let divider = listed.first { $0.name == "Divider" }
        #expect(divider?.summary == "Stretch across, Bottom down")
        #expect(divider?.isSurface == false)
        #expect(listed.first { $0.name == "Background" }?.summary == "Surface behind the rest")
    }

    // MARK: - The starter that is shaped like a bar

    /// The Nav Bar on the Library shelf, dropped and dragged wider. Everything
    /// the task asked for is here: nothing typed into the Layout section, and
    /// the four pieces still doing what a bar's four pieces do.
    private func droppedBar() -> Layer? {
        var document = PhotonzDocument(canvasSize: CGSize(width: 900, height: 700))
        guard let id = document.insertStarterComponent(.navBar, at: CGPoint(x: 400, y: 300))
        else { return nil }
        return document.layer(id: id)
    }

    @Test("The Nav Bar arrives as a row")
    func theBarIsARow() throws {
        let bar = try #require(droppedBar())
        let layout = try #require(bar.group?.layout)
        #expect(layout.kind == .stack)
        #expect(layout.direction == .row)
        #expect(layout.usedWidth == 320)
        #expect(layout.usedHeight == 48)
        #expect(layout.usedPadding.left == 14)
        #expect(layout.usedPadding.right == 14)
    }

    @Test("Dragging the Nav Bar wider keeps the back label at the left edge")
    func theBackLabelHoldsTheLeftEdge() throws {
        let bar = try #require(droppedBar())
        let wider = bar.resized(to: CGRect(x: 0, y: 0, width: 640, height: 48))
        #expect(piece(wider, "Back").minX == 14)
        #expect(piece(wider, "Back") == piece(GroupFlow.flowing(bar), "Back"))
    }

    @Test("Dragging the Nav Bar wider keeps its title in the middle of the room left for it")
    func theTitleStaysInTheMiddle() throws {
        let bar = try #require(droppedBar())
        for width in [CGFloat(200), 320, 640, 1280] {
            let sized = bar.resized(to: CGRect(x: 0, y: 0, width: width, height: 48))
            let title = try #require(sized.children.first { $0.name == "Title" })
            let back = try #require(sized.children.first { $0.name == "Back" })
            // The title is IN the row now, taking whatever the back label and
            // the row's gap leave, so its box runs from there to the far edge
            // and its words centre in that box however wide the bar gets.
            #expect(title.contentBounds.minX == back.contentBounds.maxX + 12)
            #expect(abs(title.contentBounds.maxX - (width - 14)) <= 1)
            #expect(title.text?.alignment == .center)
        }
    }

    /// The bug this is here for: a Badge and a Button added to the bar used to
    /// walk across it and stand on top of the word Title, which was drawn
    /// underneath them and simply disappeared.
    @Test("Controls added to the Nav Bar never land on top of its title")
    func addedControlsNeverCoverTheTitle() throws {
        var history = History(document: PhotonzDocument(canvasSize: CGSize(width: 900, height: 700)))
        var placed: UUID?
        history.perform { placed = $0.insertStarterComponent(.navBar, at: CGPoint(x: 400, y: 300)) }
        guard let barID = placed, let box = history.current.canvasBounds(of: barID)
        else { Issue.record("the bar did not land"); return }
        // Let go at the far end of the bar, which is where a person adding a
        // control to a bar reaches for.
        for kind in [StarterComponent.badge, .button] {
            history.perform {
                $0.insertStarterComponent(kind, at: CGPoint(x: box.maxX - 20, y: box.midY),
                                          inside: barID)
            }
        }
        let bar = try #require(history.current.layer(id: barID))
        let title = try #require(bar.children.first { $0.name == "Title" })
        #expect(bar.children.count == 6)
        #expect(title.contentBounds.width > 0)
        // Everything but the two pieces that are painted to the bar's own
        // edges rather than lined up in it.
        for other in bar.children where !["Title", "Background", "Divider"].contains(other.name) {
            #expect(!other.contentBounds.insetBy(dx: 0.5, dy: 0.5)
                .intersects(title.contentBounds),
                    "\(other.name) is standing on the title")
        }
    }

    /// What pays for the title no longer sitting on the bar's exact middle:
    /// turn the back label off and there is nothing else in the row, so the
    /// room left over is the whole bar and the words are dead centre again.
    @Test("A Nav Bar with its back label turned off centres the title on the bar")
    func theTitleCentresOnABareBar() throws {
        var bar = try #require(droppedBar())
        guard let index = bar.children.firstIndex(where: { $0.name == "Back" })
        else { Issue.record("the bar has no back label"); return }
        bar.children[index].isVisible = false
        let laid = GroupFlow.flowing(bar)
        let title = try #require(laid.children.first { $0.name == "Title" })
        #expect(abs(title.contentBounds.midX - laid.localBounds.width / 2) <= 1)
    }

    @Test("Dragging the Nav Bar about keeps its hairline and its surface honest")
    func theHairlineAndSurfaceHold() throws {
        let bar = try #require(droppedBar())
        let sized = bar.resized(to: CGRect(x: 0, y: 0, width: 640, height: 72))
        #expect(piece(sized, "Divider") == CGRect(x: 0, y: 71, width: 640, height: 1))
        #expect(piece(sized, "Background") == CGRect(x: 0, y: 0, width: 640, height: 72))
    }

    @Test("A control dropped beside the back label lines up next to it")
    func aSecondControlLinesUp() throws {
        var bar = try #require(droppedBar())
        // Let go between the back label and the title, which is the leading
        // end of the bar.
        bar.children.append(box("Menu", CGRect(x: 50, y: 0, width: 24, height: 24)))
        let laid = GroupFlow.flowing(bar)
        // 14 in from the left, then the words of the back label, then the
        // row's gap.
        let back = try #require(laid.children.first { $0.name == "Back" })
        #expect(piece(laid, "Menu").minX == back.contentBounds.maxX + 12)
    }

    /// The other half of the same rule, and the reason the bar gets two ends
    /// for free: the title takes the room in between, so a control let go past
    /// it is pushed out to the far edge instead of marching across it.
    @Test("A control dropped past the title lands at the far end of the bar")
    func aControlPastTheTitleTakesTheFarEnd() throws {
        var bar = try #require(droppedBar())
        bar.children.append(box("Menu", CGRect(x: 200, y: 0, width: 24, height: 24)))
        let laid = GroupFlow.flowing(bar)
        let title = try #require(laid.children.first { $0.name == "Title" })
        #expect(piece(laid, "Menu").maxX == laid.localBounds.width - 14)
        #expect(piece(laid, "Menu").minX == title.contentBounds.maxX + 12)
    }

    @Test("The bar's Layout section reads as the bar a person can see")
    func theLayoutSectionReadsRight() throws {
        let bar = try #require(droppedBar())
        let listed = bar.contentsWithTheirOwnPlacement(arrangement: bar.group?.layout)
        #expect(listed.first { $0.name == "Background" }?.summary == "Surface behind the rest")
        #expect(listed.first { $0.name == "Divider" }?.summary == "Stretch across, Bottom down")
        // The title is one of the pieces the row lines up now, and the only
        // thing it says for itself is that it takes what is left.
        #expect(listed.first { $0.name == "Title" }?.summary == "Takes the room left over")
        // The back label is the one piece the row is actually lining up, so it
        // is not on the list of pieces doing something else.
        #expect(listed.first { $0.name == "Back" } == nil)
    }

    @Test("Clicking the back label picks the back label, not the title over it")
    func theBackLabelIsStillClickable() throws {
        let bar = try #require(droppedBar())
        let back = try #require(bar.children.first { $0.name == "Back" })
        let point = CGPoint(x: back.contentBounds.midX, y: back.contentBounds.midY)
        // Topmost first, the way a click reads the picture. The title is in
        // the row beside the back label rather than lying across it, so
        // neither can answer for the other.
        let hit = bar.children.reversed().first { $0.contains(canvasPoint: point) }
        #expect(hit?.name == "Back")
        #expect(bar.children.map(\.name) == ["Background", "Divider", "Title", "Back"])
    }
}
