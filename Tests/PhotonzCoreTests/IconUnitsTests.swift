import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// With the Grid on, an icon's artboard rules itself into its own units
/// (`a-24-unit-artboard-rules-itself-into-units`, icon-draw-wt.html step 1).
///
/// The canvas grid counts from its own zero point at its own spacing, so over
/// an icon it could only ever reach one unit in four. These are the lines that
/// replace it inside the artboard: where they fall, when there is room for
/// them, and what a drag lands on once they are there.
@Suite("An icon's artboard rules itself into units")
struct IconUnitsTests {

    private let everywhere = CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000)

    private func iconDocument(side: CGFloat = 24,
                              origin: CGPoint = CGPoint(x: 100, y: 200)) -> (PhotonzDocument, Layer) {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 1100))
        let frame = document.addFrame(origin: origin, size: CGSize(width: side, height: side))
        return (document, frame)
    }

    private func oval(at box: CGRect = CGRect(x: 4, y: 4, width: 8, height: 8)) -> Layer {
        Layer(name: "Oval",
              content: .annotation(AnnotationContent(shape: .ellipse, start: .zero,
                                                     end: CGPoint(x: box.width, y: box.height))),
              frame: box)
    }

    // MARK: Where the lines fall

    @Test("A 24 unit artboard is crossed by 23 lines each way")
    func twentyThreeEachWay() throws {
        let box = CGRect(x: 0, y: 0, width: 24, height: 24)
        let ruling = try #require(IconUnits.ruling(of: box, zoom: 32, showing: everywhere))
        #expect(ruling.columns == (1...23).map { CGFloat($0) })
        #expect(ruling.rows == (1...23).map { CGFloat($0) })
    }

    @Test("The units count from the artboard's corner, not from the canvas")
    func countsFromTheCorner() throws {
        let box = CGRect(x: 100.5, y: 37.25, width: 24, height: 24)
        let ruling = try #require(IconUnits.ruling(of: box, zoom: 32, showing: everywhere))
        #expect(ruling.columns.first == 101.5)
        #expect(ruling.columns.last == 123.5)
        #expect(ruling.rows.first == 38.25)
        #expect(ruling.rows.last == 60.25)
    }

    @Test("Every fourth unit is the stronger line the mock draws, counted from the corner")
    func everyFourthIsStronger() throws {
        let box = CGRect(x: 10, y: 20, width: 24, height: 24)
        let ruling = try #require(IconUnits.ruling(of: box, zoom: 32, showing: everywhere))
        #expect(ruling.strongColumns == [14, 18, 22, 26, 30])
        #expect(ruling.strongRows == [24, 28, 32, 36, 40])
    }

    @Test("The frame's own edge is not a line of the ruling")
    func edgesAreLeftAlone() throws {
        // Lines on all four edges would trace a closed box round the artboard,
        // which is the selection's mark and no guide's (UX-PATTERNS D16).
        let box = CGRect(x: 0, y: 0, width: 16, height: 16)
        let ruling = try #require(IconUnits.ruling(of: box, zoom: 32, showing: everywhere))
        #expect(!ruling.columns.contains(0))
        #expect(!ruling.columns.contains(16))
        #expect(ruling.columns.count == 15)
    }

    @Test("Any icon size is ruled into its own units")
    func everyIconSize() throws {
        for side: CGFloat in [16, 32, 48] {
            let box = CGRect(x: 0, y: 0, width: side, height: side)
            let ruling = try #require(IconUnits.ruling(of: box, zoom: 12, showing: everywhere))
            #expect(ruling.columns.count == Int(side) - 1)
        }
    }

    @Test("A frame that is not icon sized is not ruled")
    func notAnIcon() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(IconUnits.ruling(of: screen, zoom: 32, showing: everywhere) == nil)
    }

    // MARK: When there is room

    @Test("Six screen points apart is enough, and anything closer is not")
    func theSixPointFloor() {
        let box = CGRect(x: 0, y: 0, width: 24, height: 24)
        #expect(IconUnits.ruling(of: box, zoom: 6, showing: everywhere) != nil)
        #expect(IconUnits.ruling(of: box, zoom: 5.99, showing: everywhere) == nil)
        #expect(IconUnits.fit(zoom: 6))
        #expect(IconUnits.fit(zoom: 5.9999999), "where a pinch to six comes to rest")
        #expect(!IconUnits.fit(zoom: 5.99))
    }

    @Test("A zoom that is not a number rules nothing")
    func badZoom() {
        let box = CGRect(x: 0, y: 0, width: 24, height: 24)
        #expect(IconUnits.ruling(of: box, zoom: .nan, showing: everywhere) == nil)
        #expect(IconUnits.ruling(of: box, zoom: .infinity, showing: everywhere) == nil)
        #expect(IconUnits.ruling(of: box, zoom: 0, showing: everywhere) == nil)
    }

    @Test("Only the lines on screen are handed back")
    func onlyWhatIsOnScreen() throws {
        // A 1024 app icon at 32x is thousands of points across, and the cost
        // has to follow the window rather than the icon.
        let box = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let showing = CGRect(x: 100, y: 200, width: 10, height: 5)
        let ruling = try #require(IconUnits.ruling(of: box, zoom: 32, showing: showing))
        #expect(ruling.columns == (100...110).map { CGFloat($0) })
        #expect(ruling.rows == (200...205).map { CGFloat($0) })
        #expect(ruling.strongColumns == [100, 104, 108])
        #expect(ruling.strongRows == [200, 204])
    }

    // MARK: The canvas grid steps round it

    @Test("A canvas grid line stops at a ruled artboard and carries on past it")
    func gridLineStepsRound() {
        let artboard = CGRect(x: 100, y: 200, width: 50, height: 50)
        let spans = IconUnits.spans(ofLineAt: 120, running: .vertical, from: 0, to: 1000,
                                    clearOf: [artboard])
        #expect(spans == [0...200, 250...1000])
    }

    @Test("A line that misses the artboard is drawn whole")
    func gridLineMisses() {
        let artboard = CGRect(x: 100, y: 200, width: 50, height: 50)
        #expect(IconUnits.spans(ofLineAt: 90, running: .vertical, from: 0, to: 1000,
                                clearOf: [artboard]) == [0...1000])
        #expect(IconUnits.spans(ofLineAt: 300, running: .horizontal, from: 0, to: 1000,
                                clearOf: [artboard]) == [0...1000])
    }

    @Test("A line along the artboard's edge is outside it")
    func gridLineOnTheEdge() {
        let artboard = CGRect(x: 100, y: 200, width: 50, height: 50)
        #expect(IconUnits.spans(ofLineAt: 100, running: .vertical, from: 0, to: 1000,
                                clearOf: [artboard]) == [0...1000])
        #expect(IconUnits.spans(ofLineAt: 150, running: .vertical, from: 0, to: 1000,
                                clearOf: [artboard]) == [0...1000])
    }

    @Test("A row steps round the artboard along its own axis")
    func rowStepsRound() {
        let artboard = CGRect(x: 100, y: 200, width: 50, height: 50)
        #expect(IconUnits.spans(ofLineAt: 220, running: .horizontal, from: 0, to: 1000,
                                clearOf: [artboard]) == [0...100, 150...1000])
    }

    @Test("Two artboards on one line leave three spans, overlapping ones two")
    func manyArtboards() {
        let left = CGRect(x: 100, y: 100, width: 50, height: 50)
        let right = CGRect(x: 300, y: 100, width: 50, height: 50)
        let over = CGRect(x: 130, y: 100, width: 50, height: 50)
        #expect(IconUnits.spans(ofLineAt: 120, running: .horizontal, from: 0, to: 1000,
                                clearOf: [right, left]) == [0...100, 150...300, 350...1000])
        #expect(IconUnits.spans(ofLineAt: 120, running: .horizontal, from: 0, to: 1000,
                                clearOf: [left, over]) == [0...100, 180...1000])
    }

    @Test("An artboard filling the view leaves nothing of the line")
    func artboardFillsTheView() {
        let artboard = CGRect(x: -100, y: -100, width: 2000, height: 2000)
        #expect(IconUnits.spans(ofLineAt: 120, running: .vertical, from: 0, to: 1000,
                                clearOf: [artboard]).isEmpty)
    }

    // MARK: What a drag lands on

    @Test("A shape on an icon frame lands on that frame's units")
    func shapeInAFrame() throws {
        var (document, frame) = iconDocument()
        let shape = oval()
        document.addLayer(shape, toGroup: frame.id)
        #expect(document.iconUnitBox(holding: [shape.id], zoom: 32) == frame.frame)
    }

    @Test("The frame itself is not inside its own units")
    func theFrameItself() {
        let (document, frame) = iconDocument()
        #expect(document.iconUnitBox(holding: [frame.id], zoom: 32) == nil)
    }

    @Test("Too far out to rule, the canvas grid keeps the drag")
    func tooFarOut() {
        var (document, frame) = iconDocument()
        let shape = oval()
        document.addLayer(shape, toGroup: frame.id)
        #expect(document.iconUnitBox(holding: [shape.id], zoom: 5) == nil)
    }

    @Test("Shapes on two icons share no units, and shapes on one do")
    func twoIcons() {
        var (document, first) = iconDocument()
        let second = document.addFrame(origin: CGPoint(x: 400, y: 200),
                                       size: CGSize(width: 24, height: 24))
        let a = oval(), b = oval(), c = oval()
        document.addLayer(a, toGroup: first.id)
        document.addLayer(b, toGroup: first.id)
        document.addLayer(c, toGroup: second.id)
        #expect(document.iconUnitBox(holding: [a.id, b.id], zoom: 32) == first.frame)
        #expect(document.iconUnitBox(holding: [a.id, c.id], zoom: 32) == nil)
    }

    @Test("Nothing held, a shape on a screen and a hidden icon all keep the canvas grid")
    func notOnAnIcon() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 1100))
        let screen = document.addFrame(origin: .zero, size: CGSize(width: 1440, height: 900))
        let shape = oval()
        document.addLayer(shape, toGroup: screen.id)
        #expect(document.iconUnitBox(holding: [], zoom: 32) == nil)
        #expect(document.iconUnitBox(holding: [shape.id], zoom: 32) == nil)

        var (hidden, frame) = iconDocument()
        let inside = oval()
        hidden.addLayer(inside, toGroup: frame.id)
        hidden.updateLayer(id: frame.id) { $0.isVisible = false }
        #expect(hidden.iconUnitBox(holding: [inside.id], zoom: 32) == nil)
    }

    @Test("A picture made as an icon lands on the canvas's units")
    func iconPicture() {
        var document = PhotonzDocument.withBaseImage(
            ImageRef(id: UUID(), pixelSize: CGSize(width: 24, height: 24)))
        document.madeAsIcon = true
        let shape = oval()
        document.layers.append(shape)
        #expect(document.iconUnitBox(holding: [shape.id], zoom: 32)
                == CGRect(x: 0, y: 0, width: 24, height: 24))
    }

    @Test("A point inside an icon answers for that icon, and one outside for none")
    func pointUnder() {
        let (document, frame) = iconDocument()
        #expect(document.iconUnitBox(under: CGPoint(x: 110, y: 210), zoom: 32) == frame.frame)
        #expect(document.iconUnitBox(under: CGPoint(x: 10, y: 10), zoom: 32) == nil)
        #expect(document.iconUnitBox(under: CGPoint(x: 110, y: 210), zoom: 4) == nil)
    }

    @Test("Every icon on the canvas that is showing is listed, with the canvas first")
    func allTheIcons() {
        var (document, frame) = iconDocument()
        let hidden = document.addFrame(origin: CGPoint(x: 400, y: 200),
                                       size: CGSize(width: 24, height: 24))
        document.addFrame(origin: CGPoint(x: 700, y: 0), size: CGSize(width: 1440, height: 900))
        document.updateLayer(id: hidden.id) { $0.isVisible = false }
        #expect(document.shownIconIDs == [frame.id])

        var picture = PhotonzDocument.withBaseImage(
            ImageRef(id: UUID(), pixelSize: CGSize(width: 24, height: 24)))
        picture.madeAsIcon = true
        #expect(picture.shownIconIDs == [PhotonzDocument.iconCanvasID])
    }

    // MARK: The dots on the crossings

    @Test func aDotSitsOnEveryCrossingOfTheLiveArea() throws {
        let box = CGRect(x: 100, y: 200, width: 24, height: 24)
        let ruling = try #require(IconUnits.ruling(of: box, zoom: 16, showing: everywhere))
        let dots = IconUnits.crossings(of: ruling, zoom: 16)
        #expect(dots.count == 441)
        #expect(dots.first == CGPoint(x: 102, y: 202))
        #expect(dots.last == CGPoint(x: 122, y: 222))
    }

    @Test func noDotSitsInTheMargin() throws {
        let box = CGRect(x: 0, y: 0, width: 24, height: 24)
        let ruling = try #require(IconUnits.ruling(of: box, zoom: 16, showing: everywhere))
        let dots = IconUnits.crossings(of: ruling, zoom: 16)
        #expect(dots.allSatisfy { (2...22).contains($0.x) && (2...22).contains($0.y) })
    }

    @Test func onlyTheDotsInViewAreDrawn() throws {
        let box = CGRect(x: 0, y: 0, width: 24, height: 24)
        let showing = CGRect(x: 1.5, y: 1.5, width: 3, height: 3)
        let ruling = try #require(IconUnits.ruling(of: box, zoom: 16, showing: showing))
        #expect(IconUnits.crossings(of: ruling, zoom: 16).count == 9)
    }

    @Test func unitsTooCloseForADotHaveNone() throws {
        let box = CGRect(x: 0, y: 0, width: 24, height: 24)
        let ruling = try #require(IconUnits.ruling(of: box, zoom: 8, showing: everywhere))
        #expect(IconUnits.crossings(of: ruling, zoom: 8).isEmpty)
        #expect(!IconUnits.crossings(of: ruling, zoom: 10).isEmpty)
    }

    @Test func aPictureCountsItsDotsInItsOwnUnits() throws {
        let unit = IconUnits.pictureSide / 24
        let box = CGRect(x: 0, y: 0, width: IconUnits.pictureSide, height: IconUnits.pictureSide)
        let ruling = try #require(IconUnits.ruling(of: box, zoom: 1, showing: everywhere, unit: unit))
        #expect(IconUnits.crossings(of: ruling, zoom: 1, unit: unit).count == 441)
    }

    @Test func moreDotsThanAFrameCanDrawCheaplyAreLeftOut() throws {
        let box = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let ruling = try #require(IconUnits.ruling(of: box, zoom: 10, showing: everywhere))
        #expect(IconUnits.crossings(of: ruling, zoom: 10).isEmpty)
    }
}
