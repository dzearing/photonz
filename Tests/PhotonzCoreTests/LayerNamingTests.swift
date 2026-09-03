import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Names for layers nobody has named yet. Drawing two rectangles used to leave
/// a document holding two layers both called "Rectangle", so a layers list, a
/// variant menu or a spec could not tell them apart without clicking each one.
/// A new layer whose automatic name is already spoken for takes the next free
/// number instead.
@Suite("A second rectangle is not called Rectangle")
struct LayerNamingTests {

    private func doc() -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
    }

    private func shape(_ shape: AnnotationShape = .rectangle,
                       _ frame: CGRect = CGRect(x: 10, y: 10, width: 40, height: 30)) -> Layer {
        AnnotationBuilder.layer(content: AnnotationContent(shape: shape),
                                from: frame.origin,
                                to: CGPoint(x: frame.maxX, y: frame.maxY))
    }

    private func named(_ name: String, _ frame: CGRect = CGRect(x: 0, y: 0, width: 10, height: 10)) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    @Test("A second and third rectangle are numbered")
    func numbersRepeats() {
        var document = doc()
        document.addLayer(shape())
        document.addLayer(shape())
        document.addLayer(shape())
        #expect(document.layers.map(\.name) == ["Rectangle", "Rectangle 2", "Rectangle 3"])
    }

    @Test("Different shapes each start at their own name")
    func perShapeNumbering() {
        var document = doc()
        document.addLayer(shape(.rectangle))
        document.addLayer(shape(.ellipse))
        document.addLayer(shape(.rectangle))
        #expect(document.layers.map(\.name) == ["Rectangle", "Ellipse", "Rectangle 2"])
    }

    @Test("A name in use inside a group counts as taken")
    func takenAnywhere() {
        var document = doc()
        let inside = named("Rectangle")
        document.addLayer(Layer(name: "Card",
                                content: .group(GroupContent(children: [inside])),
                                frame: CGRect(x: 0, y: 0, width: 100, height: 100)))
        document.addLayer(shape())
        #expect(document.layers.last?.name == "Rectangle 2")
    }

    @Test("A layer added inside a group is numbered too")
    func numbersInsideGroup() {
        var document = doc()
        document.addLayer(shape())
        let group = Layer(name: "Card", content: .group(GroupContent(children: [])),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        document.addLayer(group)
        let added = document.addLayer(shape(), toGroup: group.id)
        #expect(added)
        #expect(document.layer(id: group.id)?.children.first?.name == "Rectangle 2")
    }

    @Test("Drawing onto a screen numbers against the whole document")
    func numbersOnFrame() {
        var document = doc()
        document.addLayer(shape())
        let frame = document.addFrame(origin: .zero, size: CGSize(width: 200, height: 200))
        document.addLayerDrawnOnFrame(shape(.rectangle, CGRect(x: 20, y: 20, width: 40, height: 30)))
        #expect(document.layer(id: frame.id)?.children.last?.name == "Rectangle 2")
    }

    @Test("A freed number is used again")
    func reusesFreedNumbers() {
        var document = doc()
        document.addLayer(shape())
        document.addLayer(shape())
        _ = document.removeLayer(id: document.layers[0].id)
        document.addLayer(shape())
        #expect(document.layers.map(\.name) == ["Rectangle 2", "Rectangle"])
    }

    @Test("A name a person chose is never renumbered")
    func keepsChosenNames() {
        var document = doc()
        document.addLayer(shape())
        document.updateLayer(id: document.layers[0].id) { $0.name = "Hero" }
        document.addLayer(shape())
        document.addLayer(shape())
        #expect(document.layers.map(\.name) == ["Hero", "Rectangle", "Rectangle 2"])
    }

    @Test("A layer arriving under a person's name keeps it, repeat or not")
    func keepsRepeatedChosenNames() {
        var document = doc()
        document.addLayer(named("Hero"))
        document.addLayer(named("Hero"))
        #expect(document.layers.map(\.name) == ["Hero", "Hero"])
    }

    @Test("Renaming by hand is never undone by a later layer")
    func renameSurvives() {
        var document = doc()
        document.addLayer(shape())
        document.addLayer(shape())
        document.updateLayer(id: document.layers[1].id) { $0.name = "Rectangle 2 (outline)" }
        document.addLayer(shape())
        #expect(document.layers.map(\.name) == ["Rectangle", "Rectangle 2 (outline)", "Rectangle 2"])
    }

    @Test("Text layers number and stay recognizable as unnamed")
    func numbersText() {
        var document = doc()
        document.addLayer(TextBuilder.layer(content: TextContent(string: "One"), at: .zero,
                                            naturalSize: CGSize(width: 40, height: 20)))
        document.addLayer(TextBuilder.layer(content: TextContent(string: "Two"), at: CGPoint(x: 0, y: 40),
                                            naturalSize: CGSize(width: 40, height: 20)))
        #expect(document.layers.map(\.name) == ["Text", "Text 2"])
        #expect(ComponentNaming.isPlaceholderLayerName("Text 2"))
    }

    @Test("Groups and frames keep the numbering they already had")
    func groupsAndFramesStillNumber() {
        var document = doc()
        _ = document.addFrame(origin: .zero, size: CGSize(width: 100, height: 100))
        _ = document.addFrame(origin: CGPoint(x: 120, y: 0), size: CGSize(width: 100, height: 100))
        #expect(document.layers.map(\.name) == ["Frame", "Frame 2"])
    }

    @Test("Measurements keep their stock name, which is how the list reads them")
    func measurementsAreLeftAlone() {
        var document = doc()
        let first = MeasureBuilder.layer(content: MeasureContent(mode: .horizontal),
                                         from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 10))
        let second = MeasureBuilder.layer(content: MeasureContent(mode: .horizontal),
                                          from: CGPoint(x: 10, y: 40), to: CGPoint(x: 90, y: 40))
        document.addLayer(first)
        document.addLayer(second)
        #expect(document.layers.map(\.name) == [MeasureBuilder.defaultName, MeasureBuilder.defaultName])
        // The rows never showed that name in the first place: a caliper reads
        // as what it measures, so it is already tellable apart.
        #expect(document.layers.allSatisfy { MeasureSpecList.displayName(for: $0) != MeasureBuilder.defaultName })
    }

    @Test("The stem of an automatic name is what it gets numbered from")
    func readsStems() {
        #expect(LayerNaming.stem(of: "Rectangle") == "Rectangle")
        #expect(LayerNaming.stem(of: "Rectangle 7") == "Rectangle")
        #expect(LayerNaming.stem(of: "Rectangle (outline)") == nil)
        #expect(LayerNaming.stem(of: "Hero") == nil)
        #expect(LayerNaming.stem(of: MeasureBuilder.defaultName) == nil)
        #expect(LayerNaming.stem(of: "Group 3") == "Group")
    }
}
