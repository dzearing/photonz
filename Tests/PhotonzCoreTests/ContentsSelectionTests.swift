import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The Contents rows of the Layout section speaking for several picked groups
/// at once: pick two cards and say Stack, 12 apart, once rather than twice
/// over (`docs/design/mocks/shared/UX-PATTERNS.md` §4, "What a control DOES for
/// several picked things").
///
/// Deliberately NOT `PlacementSelection`: that one is about where the picked
/// layers sit in whatever holds them, this is about what the picked groups tell
/// their own contents to do.
struct ContentsSelectionTests {

    private func box(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    /// Two groups of two boxes each, plus a box loose on the canvas.
    private struct Fixture {
        var doc: PhotonzDocument
        var left: UUID
        var right: UUID
        var leftOne: UUID
        var rightOne: UUID
        var loose: UUID
    }

    private func fixture() -> Fixture {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 800, height: 600),
            layers: [box("A", CGRect(x: 10, y: 10, width: 40, height: 20)),
                     box("B", CGRect(x: 60, y: 10, width: 40, height: 20)),
                     box("C", CGRect(x: 10, y: 100, width: 40, height: 20)),
                     box("D", CGRect(x: 60, y: 100, width: 40, height: 20)),
                     box("Loose", CGRect(x: 300, y: 300, width: 40, height: 20))])
        let a = doc.layers[0].id, b = doc.layers[1].id
        let c = doc.layers[2].id, d = doc.layers[3].id
        let loose = doc.layers[4].id
        let left = doc.groupLayers(ids: [a, b], name: "Left")!
        let right = doc.groupLayers(ids: [c, d], name: "Right")!
        return Fixture(doc: doc, left: left.id, right: right.id,
                       leftOne: a, rightOne: c, loose: loose)
    }

    // MARK: - The block is there at all

    @Test("Two groups keep the Contents rows, headed for both")
    func twoGroupsKeepTheRows() {
        let f = fixture()
        let contents = f.doc.contentsSelection(layerIDs: [f.left, f.right])
        #expect(contents.isPresent)
        #expect(contents.ids == [f.left, f.right])
        #expect(contents.heading == "Contents of these 2 groups")
    }

    @Test("One group reads exactly the way two do, so the panel has one path")
    func oneGroupReadsTheSameWay() {
        let f = fixture()
        let contents = f.doc.contentsSelection(layerIDs: [f.left])
        #expect(contents.isPresent)
        #expect(contents.count == 1)
        #expect(contents.heading == "Contents of Left")
    }

    @Test("A layer with no contents brings no rows")
    func nothingToArrange() {
        let f = fixture()
        #expect(!f.doc.contentsSelection(layerIDs: [f.loose]).isPresent)
        #expect(!f.doc.contentsSelection(layerIDs: []).isPresent)
    }

    @Test("Picking a group and a plain layer speaks for the group, and counts it")
    func plainLayersAreLeftOut() {
        let f = fixture()
        let contents = f.doc.contentsSelection(layerIDs: [f.left, f.loose])
        #expect(contents.ids == [f.left])
        #expect(contents.selectionCount == 2)
        #expect(contents.heading == "Contents of Left")
    }

    // MARK: - What each row reads

    @Test("An answer both groups agree on is the answer the row shows")
    func agreementReadsAsTheValue() {
        var f = fixture()
        f.doc.setContentPlacement(id: f.left, horizontal: .right)
        f.doc.setContentPlacement(id: f.right, horizontal: .right)
        let contents = f.doc.contentsSelection(layerIDs: [f.left, f.right])
        #expect(contents.horizontal.value == .right)
        #expect(!contents.horizontal.isMixed)
    }

    @Test("An answer they do not agree on reads Mixed")
    func disagreementReadsMixed() {
        var f = fixture()
        f.doc.setContentPlacement(id: f.left, horizontal: .right)
        f.doc.setContentPlacement(id: f.right, horizontal: .center)
        let contents = f.doc.contentsSelection(layerIDs: [f.left, f.right])
        #expect(contents.horizontal.value == nil)
        #expect(contents.horizontal.isMixed)
    }

    @Test("Two stacks agree on being stacks; a stack and a grid do not")
    func arrangementReading() {
        var f = fixture()
        f.doc.setGroupLayout(id: f.left, kind: .stack)
        f.doc.setGroupLayout(id: f.right, kind: .stack)
        var contents = f.doc.contentsSelection(layerIDs: [f.left, f.right])
        #expect(contents.arrangement.value == .stack)
        #expect(!contents.arrangement.isMixed)
        f.doc.setGroupLayout(id: f.right, kind: .grid)
        contents = f.doc.contentsSelection(layerIDs: [f.left, f.right])
        #expect(contents.arrangement.isMixed)
        #expect(contents.arrangement.value == nil)
    }

    @Test("Two gaps that differ read Mixed, and the same gap reads the number")
    func gapReading() {
        var f = fixture()
        f.doc.setGroupLayout(id: f.left, kind: .stack)
        f.doc.setGroupLayout(id: f.right, kind: .stack)
        f.doc.updateGroupLayout(id: f.left) { $0.gap = 12 }
        f.doc.updateGroupLayout(id: f.right) { $0.gap = 12 }
        var contents = f.doc.contentsSelection(layerIDs: [f.left, f.right])
        #expect(contents.gap.value == 12)
        f.doc.updateGroupLayout(id: f.right) { $0.gap = 20 }
        contents = f.doc.contentsSelection(layerIDs: [f.left, f.right])
        #expect(contents.gap.isMixed)
        #expect(contents.gap.value == nil)
    }

    @Test("No limit on either group is an agreement, not a disagreement")
    func agreeingOnNoLimit() {
        var f = fixture()
        f.doc.setGroupLayout(id: f.left, kind: .stack)
        f.doc.setGroupLayout(id: f.right, kind: .stack)
        var contents = f.doc.contentsSelection(layerIDs: [f.left, f.right])
        #expect(!contents.minWidth.isMixed)
        #expect(contents.minWidth.value == .some(nil))
        f.doc.updateGroupLayout(id: f.left) { $0.minWidth = 96 }
        contents = f.doc.contentsSelection(layerIDs: [f.left, f.right])
        #expect(contents.minWidth.isMixed)
    }

    // MARK: - One pick reaches every group, in one step

    @Test("Setting the contents placement reaches every picked group")
    func setContentPlacementOverSeveral() {
        var f = fixture()
        let reached = f.doc.setContentPlacement(ids: [f.left, f.right], horizontal: .stretch)
        #expect(reached == 2)
        #expect(f.doc.layer(id: f.left)?.group?.contentPlacement?.horizontal == .stretch)
        #expect(f.doc.layer(id: f.right)?.group?.contentPlacement?.horizontal == .stretch)
    }

    @Test("Setting the arrangement reaches every picked group")
    func setArrangementOverSeveral() {
        var f = fixture()
        let reached = f.doc.setGroupLayout(ids: [f.left, f.right], kind: .stack)
        #expect(reached == 2)
        #expect(f.doc.layer(id: f.left)?.group?.layout?.kind == .stack)
        #expect(f.doc.layer(id: f.right)?.group?.layout?.kind == .stack)
    }

    @Test("A typed number reaches every picked group, off each one's own layer")
    func updateArrangementOverSeveral() {
        var f = fixture()
        f.doc.setGroupLayout(ids: [f.left, f.right], kind: .stack)
        var names: [String] = []
        let reached = f.doc.updateGroupLayout(ids: [f.left, f.right]) { layout, layer in
            layout.gap = 16
            names.append(layer.name)
        }
        #expect(reached == 2)
        #expect(names == ["Left", "Right"])
        #expect(f.doc.layer(id: f.left)?.group?.layout?.usedGap == 16)
        #expect(f.doc.layer(id: f.right)?.group?.layout?.usedGap == 16)
    }

    @Test("Clipping reaches every picked group that has a box of its own")
    func clipOverSeveral() {
        var f = fixture()
        f.doc.updateGroupLayout(ids: [f.left, f.right]) { layout, _ in layout.width = 200 }
        let reached = f.doc.setClipsContents(ids: [f.left, f.right], true)
        #expect(reached == 2)
        #expect(f.doc.layer(id: f.left)?.clipsToBounds == true)
        #expect(f.doc.layer(id: f.right)?.clipsToBounds == true)
    }

    // MARK: - Who is not following

    @Test("The list of layers with rules of their own says which group each is in")
    func overridesNameTheirGroup() {
        var f = fixture()
        f.doc.setPlacement(id: f.leftOne, horizontal: .right)
        f.doc.setPlacement(id: f.rightOne, horizontal: .right)
        let contents = f.doc.contentsSelection(layerIDs: [f.left, f.right])
        #expect(contents.overrides.count == 2)
        #expect(Set(contents.overrides.map(\.groupName)) == ["Left", "Right"])
        #expect(contents.overridesHeading == "2 layers across 2 groups have rules of their own")
    }

    @Test("One group's worth of exceptions is headed the way it always was")
    func oneGroupOverridesHeading() {
        var f = fixture()
        f.doc.setPlacement(id: f.leftOne, horizontal: .right)
        let contents = f.doc.contentsSelection(layerIDs: [f.left])
        #expect(contents.overridesHeading == "One layer has a rule of its own")
    }

    @Test("Exceptions that all come from one of the picked groups name that group")
    func oneContributingGroupIsNamed() {
        var f = fixture()
        f.doc.setPlacement(id: f.leftOne, horizontal: .right)
        let contents = f.doc.contentsSelection(layerIDs: [f.left, f.right])
        #expect(contents.overridesHeading == "One layer in Left has a rule of its own")
    }

    // MARK: - Which direction the groups' own flows have taken over

    @Test("Two stacks running the same way hand the same direction to the flow")
    func flowsAgree() {
        var f = fixture()
        f.doc.setGroupLayout(ids: [f.left, f.right], kind: .stack)
        f.doc.updateGroupLayout(ids: [f.left, f.right]) { layout, _ in layout.direction = .column }
        let contents = f.doc.contentsSelection(layerIDs: [f.left, f.right])
        #expect(!contents.flowsDiffer)
        #expect(!contents.flow.canSetVertical)
        #expect(contents.flow.canSetHorizontal)
    }

    @Test("A stack and a grid disagree, so neither direction goes dead")
    func flowsDifferKeepsBothRowsLive() {
        var f = fixture()
        f.doc.setGroupLayout(id: f.left, kind: .stack)
        f.doc.setGroupLayout(id: f.right, kind: .grid)
        let contents = f.doc.contentsSelection(layerIDs: [f.left, f.right])
        #expect(contents.flowsDiffer)
        #expect(contents.flow.canSetHorizontal)
        #expect(contents.flow.canSetVertical)
    }

    @Test("With arrangements switched off nothing is arranging anything")
    func arrangementsOff() {
        var f = fixture()
        f.doc.setGroupLayout(ids: [f.left, f.right], kind: .stack)
        let off = f.doc.contentsSelection(layerIDs: [f.left, f.right], arranging: false)
        #expect(off.nothingArranged)
        #expect(off.flow.canSetHorizontal)
        #expect(off.flow.canSetVertical)
        #expect(!f.doc.contentsSelection(layerIDs: [f.left, f.right]).nothingArranged)
    }
}
