import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A picture made as an icon is 512 points across and 24 units across, so one
/// unit is 512 / 24 points on the canvas, and the file it writes says units.
@Suite("An icon picture draws on 24 units and writes them")
struct IconPictureUnitsTests {

    static let unit: CGFloat = 512.0 / 24

    static func picture(side: CGFloat = 512, layers: [Layer] = []) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: side, height: side), layers: layers)
        document.madeAsIcon = true
        return document
    }

    /// A path through these units, placed the way the Pen places one.
    static func pen(_ units: [(CGFloat, CGFloat)], width: CGFloat = 2) -> Layer {
        let content = PathContent(anchors: units.map { PathAnchor(point: CGPoint(x: $0.0 * unit, y: $0.1 * unit)) },
                                  isClosed: false, paint: Paint(hex: "#000000"), strokeWidth: width * unit)
        return PathBuilder.layer(content, at: content.bounds.origin)
    }

    static func oval(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) -> Layer {
        Layer(name: "Oval",
              content: .annotation(AnnotationContent(shape: .ellipse, strokeWidth: 2 * unit, start: .zero,
                                                     end: CGPoint(x: side * unit, y: side * unit))),
              frame: CGRect(x: x * unit, y: y * unit, width: side * unit, height: side * unit))
    }

    // MARK: Which pictures

    @Test("The Icon row's picture is 24 units across, whatever is on it")
    func iconRow() throws {
        let preset = try #require(BlankCanvas.iconPresets.first { $0.id == "icon" })
        #expect(preset.size.width == IconUnits.pictureSide)
        #expect(Self.picture().pictureIconUnit == Self.unit)
        #expect(Self.picture().iconUnit(of: PhotonzDocument.iconCanvasID) == Self.unit)
    }

    @Test("An icon Ask landed fills the picture with a frame, and that frame has the same units")
    func askFrame() {
        let frame = Layer.frameLayer(name: "Icon", origin: .zero, size: CGSize(width: 512, height: 512),
                                     children: [], backgroundHex: nil)
        let document = PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: [frame])
        #expect(document.pictureIconUnit == Self.unit)
        #expect(document.iconUnit(of: frame.id) == Self.unit)
    }

    @Test("App Icon, a plain square and a 24 frame keep the numbers they have")
    func others() {
        #expect(Self.picture(side: 1024).pictureIconUnit == nil)
        #expect(Self.picture(side: 1024).iconUnit(of: PhotonzDocument.iconCanvasID) == 1)
        #expect(PhotonzDocument(canvasSize: CGSize(width: 512, height: 512)).pictureIconUnit == nil)
        let frame = Layer.frameLayer(name: "Icon", origin: CGPoint(x: 40, y: 40),
                                     size: CGSize(width: 24, height: 24), children: [], backgroundHex: nil)
        let document = PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: [frame])
        #expect(document.iconUnit(of: frame.id) == 1)
    }

    // MARK: On the canvas

    @Test("A point lands on the nearest unit, and the readout counts units")
    func snap() throws {
        let snap = try #require(Self.picture().iconSnap(at: CGPoint(x: 150, y: 150), keylines: false))
        let landed = snap.point(nearest: CGPoint(x: 150, y: 170), zoom: 1)
        #expect(abs(landed.x - 7 * Self.unit) < 1e-9)
        #expect(abs(landed.y - 8 * Self.unit) < 1e-9)
        #expect(snap.readout(for: landed) == "7, 8")
    }

    @Test("A handle ends on a whole unit too")
    func handle() throws {
        let snap = try #require(Self.picture().iconSnap(at: CGPoint(x: 150, y: 150), keylines: false))
        let offset = snap.offset(CGPoint(x: 66, y: -40))
        #expect(abs(offset.x - 3 * Self.unit) < 1e-9)
        #expect(abs(offset.y + 2 * Self.unit) < 1e-9)
    }

    @Test("The keylines stand on units: a live area two units in, a square three")
    func keylines() throws {
        let guides = try #require(IconKeylines.guides(in: CGRect(x: 0, y: 0, width: 512, height: 512),
                                                      unit: Self.unit))
        #expect(abs(guides.liveArea.minX - 2 * Self.unit) < 1e-9)
        #expect(abs((guides.squareKeyline?.minX ?? 0) - 3 * Self.unit) < 1e-9)
        let snap = try #require(Self.picture().iconSnap(at: CGPoint(x: 50, y: 50), keylines: true))
        #expect(snap.xLines.contains { abs($0 - 2 * Self.unit) < 1e-9 })
    }

    @Test("A frame with no unit of its own rounds its keylines to points as it always has")
    func keylinesOnPoints() {
        #expect(IconKeylines.margin(forSide: 512) == 43)
        #expect(IconKeylines.squareInset(forSide: 512) == 64)
    }

    @Test("Twenty three lines rule the picture, from 0.3 zoom up")
    func ruling() throws {
        let box = CGRect(x: 0, y: 0, width: 512, height: 512)
        let ruling = try #require(IconUnits.ruling(of: box, zoom: 1, showing: box, unit: Self.unit))
        #expect(ruling.columns.count == 23)
        #expect(ruling.strongColumns.count == 5)
        #expect(abs(ruling.columns[0] - Self.unit) < 1e-9)
        #expect(IconUnits.ruling(of: box, zoom: 0.25, showing: box, unit: Self.unit) == nil)
        #expect(IconUnits.ruling(of: box, zoom: 0.3, showing: box, unit: Self.unit) != nil)
    }

    @Test("A first line starts at two units, the weight it has on a 24 frame")
    func weight() {
        let width = Self.picture().startingStrokeWidth(armed: 4, chosen: false,
                                                       drawnAt: CGPoint(x: 100, y: 100))
        #expect(abs(width - 2 * Self.unit) < 1e-9)
        #expect(Self.picture().startingStrokeWidth(armed: 4, chosen: true,
                                                   drawnAt: CGPoint(x: 100, y: 100)) == 4)
        #expect(Self.picture(side: 1024).startingStrokeWidth(armed: 4, chosen: false,
                                                             drawnAt: CGPoint(x: 100, y: 100)) == 4)
    }

    // MARK: In the file

    @Test("What was drawn on units writes 24 by 24 in whole numbers")
    func file() {
        let document = Self.picture(layers: [Self.pen([(5, 6), (18, 6), (18, 19)]), Self.oval(6, 8, 8)])
        let text = SVGExport.write(document).text
        #expect(text.contains("width=\"24\" height=\"24\" viewBox=\"0 0 24 24\""))
        #expect(text.contains("stroke-width=\"2\""))
        #expect(SVGWholeUnits.fractionalCoordinates(in: text) == [])
    }

    @Test("A curve that bulges past its points still says the units it was drawn on")
    func curve() {
        var content = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 19 * Self.unit, y: 6 * Self.unit)),
            PathAnchor(point: CGPoint(x: 15 * Self.unit, y: 14 * Self.unit),
                       handleIn: CGPoint(x: -4 * Self.unit, y: 2 * Self.unit),
                       handleOut: CGPoint(x: 4 * Self.unit, y: -2 * Self.unit), kind: .smooth),
            PathAnchor(point: CGPoint(x: 22 * Self.unit, y: 18 * Self.unit))
        ], isClosed: false, paint: Paint(hex: "#000000"), strokeWidth: 2 * Self.unit)
        content.fill = nil
        let layer = PathBuilder.layer(content, at: content.bounds.origin)
        #expect(layer.frame.minX / Self.unit != (layer.frame.minX / Self.unit).rounded())
        let text = SVGExport.write(Self.picture(layers: [layer])).text
        #expect(SVGWholeUnits.fractionalCoordinates(in: text) == [])
    }

    @Test("An icon Ask landed in a frame writes units as well")
    func frameFile() {
        let frame = Layer.frameLayer(name: "Icon", origin: .zero, size: CGSize(width: 512, height: 512),
                                     children: [Self.pen([(5, 6), (18, 6)])], backgroundHex: nil)
        let text = SVGExport.write(PhotonzDocument(canvasSize: CGSize(width: 512, height: 512),
                                                   layers: [frame])).text
        #expect(text.contains("viewBox=\"0 0 24 24\""))
        #expect(SVGWholeUnits.fractionalCoordinates(in: text) == [])
    }

    @Test("A move from one unit to another writes whole units in the moving file")
    func moving() {
        var layer = Self.oval(4, 4, 8)
        layer.motions = [LayerMotion(property: .position,
                                     from: .point(CGPoint(x: 4 * Self.unit, y: 4 * Self.unit)),
                                     to: .point(CGPoint(x: 12 * Self.unit, y: 10 * Self.unit)),
                                     timing: MotionTiming(startMS: 0, durationMS: 1000))]
        let text = SVGExport.write(Self.picture(layers: [layer]),
                                   animation: .moving(cycleMS: 1000)).text
        #expect(text.contains("viewBox=\"0 0 24 24\""))
        #expect(!text.contains("256"), "a place said in points: \(text)")
        #expect(SVGWholeUnits.fractionalCoordinates(in: text) == [])
    }

    @Test("Every length a motion holds comes down with the drawing, and none that is not a length")
    func motionLengths() {
        var move = LayerMotion(property: .position, from: .point(CGPoint(x: 64, y: 128)),
                               to: .point(CGPoint(x: 128, y: 64)),
                               timing: MotionTiming(startMS: 0, durationMS: 1000))
        move.fromBend = CGPoint(x: 32, y: 16)
        move.stops = [MotionStop(atMS: 500, value: .point(CGPoint(x: 16, y: 16)))]
        var turn = LayerMotion(property: .rotation, from: .number(90), to: .number(180),
                               timing: MotionTiming(startMS: 0, durationMS: 1000))
        turn.pivot = .artboard(at: CGPoint(x: 256, y: 256), in: CGRect(x: 0, y: 0, width: 64, height: 64))
        let line = LayerMotion(property: .strokeWidth, from: .number(32), to: .number(64),
                               timing: MotionTiming(startMS: 0, durationMS: 1000))
        let grow = LayerMotion(property: .scale, from: .number(1), to: .number(2),
                               timing: MotionTiming(startMS: 0, durationMS: 1000))
        var layer = Self.oval(0, 0, 3)
        layer.motions = [move, turn, line, grow]
        let half = layer.rescaled(by: 0.5).motions ?? []
        #expect(half[0].from == .point(CGPoint(x: 32, y: 64)))
        #expect(half[0].fromBend == CGPoint(x: 16, y: 8))
        #expect(half[0].stops?.first?.value == .point(CGPoint(x: 8, y: 8)))
        #expect(half[1].from == .number(90))
        #expect(half[1].pivot?.artboard == CGPoint(x: 128, y: 128))
        #expect(half[2].to == .number(32))
        #expect(half[3].to == .number(2))
    }

    @Test("Text on a line rides the line down")
    func textOnALine() throws {
        let guide = PathContent(anchors: [PathAnchor(point: CGPoint(x: 0, y: 0)),
                                          PathAnchor(point: CGPoint(x: 100, y: 0))],
                                isClosed: false, paint: Paint(hex: "#000000"), strokeWidth: 2)
        var text = TextContent(string: "Hi", fontSize: 40)
        text.onPath = TextOnPath(guide: guide)
        guard case .text(let out) = LayerContent.text(text).rescaled(by: 0.5) else {
            Issue.record("not text")
            return
        }
        #expect(try #require(out.onPath).guide.anchors[1].point.x == 50)
    }

    @Test("A picture is asked for at its real size, and lands in units")
    func picture() throws {
        let ref = ImageRef(id: UUID(), pixelSize: CGSize(width: 256, height: 256))
        let photo = Layer(name: "Photo", content: .image(ref),
                          frame: CGRect(x: 128, y: 128, width: 256, height: 256))
        let asked = Asked()
        let text = SVGExport.write(Self.picture(layers: [photo]), picture: { layer, origin in
            asked.note(layer.frame.size, origin)
            return SVGExport.Picture(png: Data([1, 2, 3]), box: CGRect(origin: origin, size: layer.frame.size))
        }).text
        #expect(asked.size == CGSize(width: 256, height: 256))
        #expect(asked.origin == CGPoint(x: 128, y: 128))
        #expect(text.contains("width=\"12\" height=\"12\""))
    }

    @Test("Words are outlined at the size they are drawn, then brought down to units")
    func words() {
        let layer = Layer(name: "Words", content: .text(TextContent(string: "A", fontSize: 128)),
                          frame: CGRect(x: 64, y: 64, width: 256, height: 192))
        let asked = Asked()
        let text = SVGExport.write(Self.picture(layers: [layer]), outlineText: { layer, words in
            asked.note(CGSize(width: words.fontSize, height: 0), .zero)
            return "M64 128 L128 128 C128 64 192 64 192 128 Z"
        }).text
        #expect(asked.size.width == 128)
        #expect(text.contains("M3 6 L6 6 C6 3 9 3 9 6 Z"))
    }

    @Test("A measure's label is a fixed size, so a redlined icon stays in points")
    func measure() {
        let measure = Layer(name: "Gap", content: .measure(MeasureContent(start: .zero, end: CGPoint(x: 100, y: 0))),
                            frame: CGRect(x: 100, y: 100, width: 100, height: 40))
        let text = SVGExport.write(Self.picture(layers: [measure])).text
        #expect(text.contains("viewBox=\"0 0 512 512\""))
    }

    @Test("App Icon and a plain square picture still write their own numbers")
    func notUnits() {
        #expect(SVGExport.write(Self.picture(side: 1024)).text.contains("viewBox=\"0 0 1024 1024\""))
        let plain = PhotonzDocument(canvasSize: CGSize(width: 512, height: 512))
        #expect(SVGExport.write(plain).text.contains("viewBox=\"0 0 512 512\""))
    }

    // MARK: From Ask

    /// A drawing on the 24 grid, as the model writes one.
    static func artwork(_ svg: String) throws -> SVGArtwork {
        try SVGArtwork.parse(svg).get()
    }

    @Test("A drawing Ask made on the 24 grid keeps its whole numbers")
    func askKeepsTheGrid() throws {
        let art = try Self.artwork("""
        <svg viewBox="0 0 24 24"><path d="M4 6 L20 6 L20 19 L4 19 Z" fill="none" stroke="#000000" stroke-width="2"/></svg>
        """)
        let frame = art.iconFrame(named: "Icon", side: 512, origin: .zero)
        let document = PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: [frame])
        let text = SVGExport.write(document).text
        #expect(text.contains("viewBox=\"0 0 24 24\""))
        #expect(SVGWholeUnits.fractionalCoordinates(in: text) == [])
    }

    @Test("A drawing off centre by whole units is brought to the middle by whole units")
    func askCentres() throws {
        let art = try Self.artwork("""
        <svg viewBox="0 0 24 24"><path d="M2 3 L18 3 L18 19 L2 19 Z" fill="#000000"/></svg>
        """)
        let frame = art.iconFrame(named: "Icon", side: 512, origin: .zero)
        let box = frame.children.reduce(CGRect.null) { $0.union($1.localBounds) }
        #expect(abs(box.minX - 4 * Self.unit) < 1e-6)
        #expect(abs(box.minY - 4 * Self.unit) < 1e-6)
        #expect(abs(box.width - 16 * Self.unit) < 1e-6)
    }

    @Test("A line along the live area's edge does not cost a drawing its grid")
    func askLineOnTheEdge() throws {
        let art = try Self.artwork("""
        <svg viewBox="0 0 24 24"><rect x="2" y="3" width="20" height="18" rx="2" fill="none" stroke="#000000" stroke-width="2"/></svg>
        """)
        let frame = art.iconFrame(named: "Icon", side: 512, origin: .zero)
        let text = SVGExport.write(PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: [frame])).text
        #expect(text.contains("stroke-width=\"2\""))
        #expect(SVGWholeUnits.fractionalCoordinates(in: text) == [])
    }

    @Test("Half units land on whole ones, and a drawing that mirrors still mirrors")
    func askHalfUnits() throws {
        let art = try Self.artwork("""
        <svg viewBox="0 0 24 24"><path d="M4.5 6 L12 3.5 L19.5 6 L19.5 20.5 L4.5 20.5 Z" fill="#000000"/></svg>
        """)
        let frame = art.iconFrame(named: "Icon", side: 512, origin: .zero)
        let text = SVGExport.write(PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: [frame])).text
        #expect(SVGWholeUnits.fractionalCoordinates(in: text) == [])
        let box = frame.children.reduce(CGRect.null) { $0.union($1.localBounds) }
        #expect(abs(box.midX - 256) < 1e-6)
    }

    @Test("A drawing that has to be fitted still lands on units, its line weight too")
    func askFittedLandsOnUnits() throws {
        let art = try Self.artwork("""
        <svg viewBox="0 0 24 24"><path d="M1 1 L23 1 L23 23 L1 23 Z" fill="none" stroke="#000000" stroke-width="2"/></svg>
        """)
        let frame = art.iconFrame(named: "Icon", side: 512, origin: .zero)
        let text = SVGExport.write(PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: [frame])).text
        #expect(text.contains("stroke-width=\"2\""))
        #expect(SVGWholeUnits.fractionalCoordinates(in: text) == [])
    }

    @Test("An app icon keeps the numbers it was fitted to")
    func appIconIsNotLanded() {
        #expect(IconGridLanding(side: 1024) == nil)
        #expect(IconGridLanding(side: 512) != nil)
    }

    @Test("A drawing too big or too small for the live area is fitted, as it was")
    func askFits() throws {
        let art = try Self.artwork("""
        <svg viewBox="0 0 24 24"><path d="M0 0 L24 0 L24 24 L0 24 Z" fill="#000000"/></svg>
        """)
        let frame = art.iconFrame(named: "Icon", side: 512, origin: .zero)
        let box = frame.children.reduce(CGRect.null) { $0.union($1.localBounds) }
        #expect(box.minX >= 2 * Self.unit - 1)
    }
}

/// What a closure was handed, read after the export.
private final class Asked: @unchecked Sendable {
    var size = CGSize.zero
    var origin = CGPoint.zero
    func note(_ size: CGSize, _ origin: CGPoint) {
        self.size = size
        self.origin = origin
    }
}
