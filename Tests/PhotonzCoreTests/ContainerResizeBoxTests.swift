import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The box the canvas outlines while a container's handle is being dragged.
///
/// A group that arranges itself does not move its contents when its box
/// changes — a left aligned column of rows stays exactly where it was however
/// wide the stack gets — so a drag on one used to change nothing on screen at
/// all. These are the rules for what gets drawn instead: which containers need
/// a box, and that the box drawn is the box the drag lands in, never an
/// approximation of it.
@Suite("A container being resized shows the box it is making")
struct ContainerResizeBoxTests {

    private func box(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    /// Three 200×80 rows in a left aligned column with a 30 gap: box 200×300
    /// at (60, 450). Exactly the shape the walk builds.
    private func stack(_ layout: GroupLayout = GroupLayout(kind: .stack, direction: .column,
                                                           gap: 30)) -> Layer {
        var layer = Layer(name: "Stack",
                          content: .group(GroupContent(children: [
                              box("A", CGRect(x: 0, y: 0, width: 200, height: 80)),
                              box("B", CGRect(x: 0, y: 110, width: 200, height: 80)),
                              box("C", CGRect(x: 0, y: 220, width: 200, height: 80)),
                          ])),
                          frame: CGRect(x: 60, y: 450, width: 200, height: 300))
        layer.setGroupLayout(layout)
        return GroupFlow.flowing(layer)
    }

    // MARK: - Which containers need one

    @Test("A stack dragged wider shows the box it is becoming")
    func aStackShowsItsBox() {
        let target = CGRect(x: 60, y: 450, width: 320, height: 410)
        #expect(ContainerResizeBox.box(of: stack(), draggedTo: target) == target)
    }

    @Test("A grid shows its box too: its cells do not reach its edges either")
    func aGridShowsItsBox() {
        let grid = stack(GroupLayout(kind: .grid, direction: .row, columns: 2, gap: 30))
        let target = CGRect(x: 60, y: 450, width: 500, height: 200)
        #expect(ContainerResizeBox.box(of: grid, draggedTo: target) == target)
    }

    @Test("A plain group shows nothing: its contents scale, so the picture says it")
    func aPlainGroupIsLeftAlone() {
        var plain = stack()
        plain.setGroupLayout(nil)
        #expect(ContainerResizeBox.box(of: plain,
                                       draggedTo: CGRect(x: 60, y: 450, width: 320, height: 410))
                    == nil)
    }

    @Test("A group given a size but no arrangement is left alone: it scales too")
    func aFreeGroupWithASizeIsLeftAlone() {
        let free = stack(.free(width: 200, height: 300))
        #expect(ContainerResizeBox.box(of: free,
                                       draggedTo: CGRect(x: 60, y: 450, width: 320, height: 410))
                    == nil)
    }

    @Test("A frame shows nothing extra: its own edge hairline is already live")
    func aFrameIsLeftAlone() {
        var frame = stack()
        if case .group(var content) = frame.content {
            content.isFrame = true
            frame.content = .group(content)
        }
        #expect(ContainerResizeBox.box(of: frame,
                                       draggedTo: CGRect(x: 60, y: 450, width: 320, height: 410))
                    == nil)
    }

    @Test("A copy of a component is left alone: its contents are placed as it grows")
    func aCopyIsLeftAlone() {
        var copy = stack()
        if case .group(var content) = copy.content {
            content.instanceOf = UUID()
            copy.content = .group(content)
        }
        #expect(ContainerResizeBox.box(of: copy,
                                       draggedTo: CGRect(x: 60, y: 450, width: 320, height: 410))
                    == nil)
    }

    @Test("A layer that is not a group at all has no box to show")
    func aShapeIsLeftAlone() {
        let shape = box("Rect", CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(ContainerResizeBox.box(of: shape,
                                       draggedTo: CGRect(x: 0, y: 0, width: 200, height: 90))
                    == nil)
    }

    // MARK: - It is the box the drag LANDS in, not the box the pointer is at

    @Test("Dragged past the widest it may be, the box stops where the stack will")
    func theBoxStopsAtTheLimit() {
        var layout = GroupLayout(kind: .stack, direction: .column, gap: 30)
        layout.maxWidth = 250
        layout.maxHeight = 380
        let held = stack(layout)
        let target = CGRect(x: 60, y: 450, width: 400, height: 900)
        let shown = ContainerResizeBox.box(of: held, draggedTo: target)
        #expect(shown == CGRect(x: 60, y: 450, width: 250, height: 380))
        #expect(shown == held.resized(to: target).localBounds)
    }

    @Test("Dragged in past the narrowest it may be, the box stops there as well")
    func theBoxStopsAtTheFloor() {
        var layout = GroupLayout(kind: .stack, direction: .column, gap: 30)
        layout.minWidth = 150
        let held = stack(layout)
        let target = CGRect(x: 60, y: 450, width: 40, height: 300)
        #expect(ContainerResizeBox.box(of: held, draggedTo: target)?.width == 150)
    }

    @Test("Dragged in from the left, the box follows the corner that is moving")
    func theBoxFollowsTheMovingCorner() {
        let target = CGRect(x: 140, y: 500, width: 120, height: 250)
        #expect(ContainerResizeBox.box(of: stack(), draggedTo: target) == target)
    }

    @Test("Pulled smaller than its rows, the box is smaller than its rows, as it lands")
    func theBoxMayBeSmallerThanWhatIsInIt() {
        let held = stack()
        let target = CGRect(x: 60, y: 450, width: 80, height: 120)
        let shown = ContainerResizeBox.box(of: held, draggedTo: target)
        #expect(shown == target)
        #expect(shown == held.resized(to: target).localBounds)
    }

    @Test("Whatever is shown is where the stack lands, at every size along a drag")
    func theBoxAlwaysAgreesWithTheLanding() {
        var layout = GroupLayout(kind: .stack, direction: .column, gap: 30)
        layout.maxWidth = 420
        layout.minHeight = 160
        layout.padding = GroupPadding(top: 12, right: 12, bottom: 12, left: 12)
        let held = stack(layout)
        for width in stride(from: 40.0, through: 600.0, by: 37.0) {
            for height in stride(from: 40.0, through: 700.0, by: 53.0) {
                let target = CGRect(x: 60, y: 450, width: width, height: height)
                #expect(ContainerResizeBox.box(of: held, draggedTo: target)
                            == held.resized(to: target).localBounds)
            }
        }
    }

    @Test("A box dragged inside out is still the box it lands in, and never negative")
    func theBoxSurvivesAnInsideOutDrag() {
        let held = stack()
        let target = CGRect(x: 60, y: 450, width: -80, height: -40)
        let shown = ContainerResizeBox.box(of: held, draggedTo: target)
        #expect(shown == held.resized(to: target).localBounds)
        #expect(shown?.width ?? -1 >= 0)
        #expect(shown?.height ?? -1 >= 0)
    }
}
