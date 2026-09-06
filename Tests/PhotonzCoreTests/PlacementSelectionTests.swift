import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The Layout section speaking for several picked layers at once: pick three
/// buttons in a bar and say Stretch once, rather than three times over
/// (`docs/design/mocks/shared/UX-PATTERNS.md` §4, "What a control DOES for
/// several picked things").
struct PlacementSelectionTests {

    private func box(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    /// A document with one group holding three boxes, and a fourth box loose on
    /// the canvas beside it.
    private struct Fixture {
        var doc: PhotonzDocument
        var group: UUID
        var one: UUID
        var two: UUID
        var three: UUID
        var loose: UUID
    }

    private func fixture() -> Fixture {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 800, height: 600),
            layers: [box("One", CGRect(x: 10, y: 10, width: 40, height: 20)),
                     box("Two", CGRect(x: 60, y: 10, width: 40, height: 20)),
                     box("Three", CGRect(x: 110, y: 10, width: 40, height: 20)),
                     box("Loose", CGRect(x: 300, y: 300, width: 40, height: 20))])
        let one = doc.layers[0].id
        let two = doc.layers[1].id
        let three = doc.layers[2].id
        let loose = doc.layers[3].id
        let group = doc.groupLayers(ids: [one, two, three], name: "Bar")!
        return Fixture(doc: doc, group: group.id, one: one, two: two, three: three, loose: loose)
    }

    // MARK: - The section is there at all

    @Test("Two layers in one group keep the section, speaking for both")
    func twoInOneGroupKeepTheSection() {
        let f = fixture()
        let selection = f.doc.placementSelection(layerIDs: [f.one, f.two])
        #expect(selection.isPresent)
        #expect(selection.layers == [f.one, f.two])
        #expect(selection.containerID == f.group)
        #expect(!selection.hasDifferentContainers)
    }

    @Test("One layer reads exactly what several do, so the panel has one path")
    func onePickedReadsTheSameWay() {
        var f = fixture()
        f.doc.setPlacement(id: f.one, horizontal: .right)
        let selection = f.doc.placementSelection(layerIDs: [f.one])
        #expect(selection.isPresent)
        #expect(selection.count == 1)
        #expect(selection.horizontal.value == .right)
        #expect(!selection.horizontal.follows)
    }

    @Test("Layers loose on the canvas bring no section: there is nothing holding them")
    func looseLayersBringNoSection() {
        var f = fixture()
        let second = f.doc.duplicateLayer(id: f.loose)!
        let selection = f.doc.placementSelection(layerIDs: [f.loose, second.id])
        #expect(!selection.isPresent)
        #expect(!selection.hasDifferentContainers)
    }

    @Test("Nothing picked brings no section")
    func nothingPicked() {
        let f = fixture()
        #expect(!f.doc.placementSelection(layerIDs: []).isPresent)
    }

    // MARK: - What the rows read

    @Test("A row the picked layers agree on shows that value")
    func agreementShowsTheValue() {
        var f = fixture()
        f.doc.setPlacement(id: f.one, horizontal: .center)
        f.doc.setPlacement(id: f.two, horizontal: .center)
        let selection = f.doc.placementSelection(layerIDs: [f.one, f.two])
        #expect(selection.horizontal.value == .center)
        #expect(!selection.horizontal.isMixed)
        #expect(!selection.horizontal.follows)
    }

    @Test("A row they do not agree on reads Mixed")
    func disagreementReadsMixed() {
        var f = fixture()
        f.doc.setPlacement(id: f.one, horizontal: .left)
        f.doc.setPlacement(id: f.two, horizontal: .right)
        let selection = f.doc.placementSelection(layerIDs: [f.one, f.two])
        #expect(selection.horizontal.isMixed)
        #expect(selection.horizontal.value == nil)
        #expect(PlacementSelection.mixedText == "Mixed")
    }

    @Test("Layers that have all said nothing read the group's answer, and say they are following")
    func unsetLayersFollowTheGroup() {
        var f = fixture()
        f.doc.setContentPlacement(id: f.group, horizontal: .right)
        let selection = f.doc.placementSelection(layerIDs: [f.one, f.two])
        #expect(selection.horizontal.value == .right)
        #expect(selection.horizontal.follows)
        #expect(selection.vertical.value == .scale)
        #expect(selection.vertical.follows)
    }

    @Test("One layer with a rule of its own stops the row reading as following")
    func oneOverrideStopsFollowing() {
        var f = fixture()
        f.doc.setContentPlacement(id: f.group, horizontal: .right)
        f.doc.setPlacement(id: f.one, horizontal: .right)
        let selection = f.doc.placementSelection(layerIDs: [f.one, f.two])
        #expect(selection.horizontal.value == .right)
        #expect(!selection.horizontal.isMixed)
        #expect(!selection.horizontal.follows)
    }

    @Test("Each axis is read on its own: mixed across, agreed down")
    func axesAreReadSeparately() {
        var f = fixture()
        f.doc.setPlacement(id: f.one, horizontal: .left)
        f.doc.setPlacement(id: f.two, horizontal: .right)
        f.doc.setPlacement(id: f.one, vertical: .top)
        f.doc.setPlacement(id: f.two, vertical: .top)
        let selection = f.doc.placementSelection(layerIDs: [f.one, f.two])
        #expect(selection.horizontal.isMixed)
        #expect(selection.vertical.value == .top)
        #expect(!selection.vertical.isMixed)
    }

    @Test("Taking the room left over reads across the picked layers too")
    func fillingIsReadAcrossThem() {
        var f = fixture()
        f.doc.setGroupLayout(id: f.group, kind: .stack)
        #expect(f.doc.placementSelection(layerIDs: [f.one, f.two]).fills.value == false)
        f.doc.setFillsTheFlow(id: f.one, true)
        #expect(f.doc.placementSelection(layerIDs: [f.one, f.two]).fills.isMixed)
        f.doc.setFillsTheFlow(id: f.two, true)
        #expect(f.doc.placementSelection(layerIDs: [f.one, f.two]).fills.value == true)
    }

    // MARK: - Layers in different containers

    @Test("Layers in two different containers keep the section and say so in one sentence")
    func differentContainersSaySo() {
        var f = fixture()
        let selection = f.doc.placementSelection(layerIDs: [f.one, f.loose])
        #expect(selection.isPresent)
        #expect(selection.hasDifferentContainers)
        #expect(selection.layers.isEmpty)
        #expect(selection.containerID == nil)
        #expect(!PlacementSelection.differentContainersNote.isEmpty)
        // Two groups rather than a group and the canvas: the same answer.
        let other = f.doc.groupLayers(ids: [f.loose], name: "Aside")!
        let across = f.doc.placementSelection(layerIDs: [f.one, other.children[0].id])
        #expect(across.hasDifferentContainers)
    }

    // MARK: - A piece inside a copy owns none of this

    @Test("Pieces inside a copy are not reached: the original decides where they sit")
    func piecesInsideACopyAreNotReached() {
        var f = fixture()
        let componentID = f.doc.makeComponent(id: f.group)!
        let copy = f.doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 400))!
        let pieces = f.doc.layer(id: copy)!.children.map(\.id)
        #expect(pieces.count == 3)
        let selection = f.doc.placementSelection(layerIDs: [pieces[0], pieces[1]])
        #expect(!selection.isPresent)
        #expect(selection.layers.isEmpty)
    }

    // MARK: - Setting a row reaches every picked layer

    @Test("Setting a row across sets every picked layer")
    func settingAcrossReachesThemAll() {
        var f = fixture()
        let count = f.doc.setPlacement(ids: [f.one, f.two, f.three], horizontal: .stretch)
        #expect(count == 3)
        for id in [f.one, f.two, f.three] {
            #expect(f.doc.layer(id: id)?.placement?.horizontal == .stretch)
        }
    }

    @Test("Setting a row down sets every picked layer, and handing it back clears them all")
    func settingDownAndHandingItBack() {
        var f = fixture()
        f.doc.setPlacement(ids: [f.one, f.two], vertical: .bottom)
        #expect(f.doc.layer(id: f.one)?.placement?.vertical == .bottom)
        #expect(f.doc.layer(id: f.two)?.placement?.vertical == .bottom)
        f.doc.setPlacement(ids: [f.one, f.two], vertical: nil)
        #expect(f.doc.layer(id: f.one)?.placement == nil)
        #expect(f.doc.layer(id: f.two)?.placement == nil)
    }

    @Test("Telling the picked layers to take the room left over reaches them all")
    func fillingReachesThemAll() {
        var f = fixture()
        f.doc.setGroupLayout(id: f.group, kind: .stack)
        f.doc.setFillsTheFlow(ids: [f.one, f.two], true)
        #expect(f.doc.layer(id: f.one)?.fillsTheFlow == true)
        #expect(f.doc.layer(id: f.two)?.fillsTheFlow == true)
        f.doc.setFillsTheFlow(ids: [f.one, f.two], false)
        #expect(f.doc.layer(id: f.one)?.fillsTheFlow == false)
        #expect(f.doc.layer(id: f.two)?.fillsTheFlow == false)
    }

    @Test("A set over the picked layers is read back from the document, not echoed")
    func theRowReadsBackWhatLanded() {
        var f = fixture()
        f.doc.setPlacement(ids: [f.one, f.two], horizontal: .left)
        let selection = f.doc.placementSelection(layerIDs: [f.one, f.two])
        #expect(selection.horizontal.value == .left)
        #expect(!selection.horizontal.follows)
    }
}
