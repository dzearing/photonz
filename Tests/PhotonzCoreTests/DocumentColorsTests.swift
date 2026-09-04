import Foundation
import Testing
@testable import PhotonzCore

@Suite("The colors a document is already painted with")
struct DocumentColorsTests {

    private func box(_ fill: String, stroke: String? = nil) -> Layer {
        var layer = Layer(name: "Box",
                          content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 colorHex: stroke ?? fill,
                                                                 fillColorHex: fill)),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        layer.style = LayerStyle()
        return layer
    }

    @Test func anEmptyDocumentHasNoColors() {
        #expect(PhotonzDocument(canvasSize: CGSize(width: 10, height: 10)).colorsInUse.isEmpty)
    }

    @Test func collectsWhatTheLayersArePaintedIn() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        document.layers = [box("#7C4DFF", stroke: "#12C2E9")]
        let colors = document.colorsInUse
        #expect(colors.contains("#7C4DFF"))
        #expect(colors.contains("#12C2E9"))
    }

    @Test func namesEachColorOnceHoweverManyLayersWearIt() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        document.layers = [box("#7C4DFF"), box("#7C4DFF"), box("#7C4DFF")]
        #expect(document.colorsInUse.filter { $0 == "#7C4DFF" }.count == 1)
    }

    @Test func putsTheMostUsedColorFirst() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        document.layers = [box("#12C2E9"), box("#7C4DFF"), box("#7C4DFF"), box("#7C4DFF")]
        #expect(document.colorsInUse.first == "#7C4DFF")
    }

    @Test func writesEveryColorTheSameWay() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        document.layers = [box("#7c4dff"), box("#7C4DFF")]
        #expect(document.colorsInUse == ["#7C4DFF"])
    }

    @Test func countsAShadowsColorToo() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        var layer = box("#FFFFFF")
        layer.style.shadow = ShadowStyle(colorHex: "#150A33")
        document.layers = [layer]
        #expect(document.colorsInUse.contains("#150A33"))
    }

    @Test func countsTheSavedStylesEvenBeforeAnythingWearsThem() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        document.addColorStyle(name: "Brand", colorHex: "#3ECF8E")
        #expect(document.colorsInUse.contains("#3ECF8E"))
    }

    @Test func looksInsideGroups() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        let group = Layer(name: "Group",
                          content: .group(GroupContent(children: [box("#FF5D8F")])),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        document.layers = [group]
        #expect(document.colorsInUse.contains("#FF5D8F"))
    }

    @Test func staysShortEnoughForOneRow() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        document.layers = (0..<60).map { box(String(format: "#%02X0000", $0 * 3)) }
        #expect(document.colorsInUse.count <= PhotonzDocument.colorsInUseLimit)
    }
}
