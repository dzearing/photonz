import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The picked layer's transform values, in the popover the tool bar's Info
/// button opens (`transform-values-live-behind-an-info-button-on-t`).
@Suite("Transform values: which values, where the popover sits, and what a typed sum means")
struct TransformBarTests {

    // MARK: Which fields

    @Test("A flat layer shows X, Y, W, H and the angle, nothing about space")
    func flatFields() {
        #expect(TransformBar.fields(inSpace: false, turned: false)
                == [.x, .y, .width, .height, .angle])
    }

    @Test("A layer in space adds Tilt X, Tilt Y and Depth, and Pivot only once it is turned")
    func spaceFields() {
        #expect(TransformBar.fields(inSpace: true, turned: false)
                == [.x, .y, .width, .height, .angle, .tiltX, .tiltY, .depth])
        #expect(TransformBar.fields(inSpace: true, turned: true)
                == [.x, .y, .width, .height, .angle, .tiltX, .tiltY, .depth, .pivotDepth])
    }

    @Test("Each field names itself in a word or two and carries the unit the mock prints")
    func fieldWords() {
        #expect(TransformBar.Field.x.label == "X")
        #expect(TransformBar.Field.width.label == "W")
        #expect(TransformBar.Field.tiltY.label == "Tilt Y")
        #expect(TransformBar.Field.angle.label == "Rotation")
        #expect(TransformBar.Field.angle.unit == "°")
        #expect(TransformBar.Field.tiltX.unit == "°")
        #expect(TransformBar.Field.depth.unit == nil)
        #expect(TransformBar.Field.x.unit == nil)
        for field in TransformBar.Field.allCases {
            #expect(field.label.count <= 8)
            #expect(!field.label.contains("\u{2014}"))
        }
    }

    @Test("Each field is keyed as the property the timeline lists it under")
    func fieldProperties() {
        #expect(TransformBar.Field.x.property == .position)
        #expect(TransformBar.Field.height.property == .scale)
        #expect(TransformBar.Field.angle.property == .rotation)
        #expect(TransformBar.Field.tiltX.property == .rotationX)
        #expect(TransformBar.Field.tiltY.property == .rotationY)
        #expect(TransformBar.Field.depth.property == .depth)
        #expect(TransformBar.Field.pivotDepth.property == .pivotDepth)
    }

    // MARK: Which fields are live

    @Test("The field a gesture is changing is the one outlined")
    func liveFields() {
        #expect(TransformBar.liveFields(for: .move) == [.x, .y])
        #expect(TransformBar.liveFields(for: .nudge) == [.x, .y])
        #expect(TransformBar.liveFields(for: .resize(.bottomRight)) == [.width, .height])
        #expect(TransformBar.liveFields(for: .resize(.right)) == [.width])
        #expect(TransformBar.liveFields(for: .resize(.top)) == [.height])
        #expect(TransformBar.liveFields(for: .rotate) == [.angle])
        #expect(TransformBar.liveFields(for: .tilt(.swing)) == [.tiltY])
        #expect(TransformBar.liveFields(for: .tilt(.tip)) == [.tiltX])
        #expect(TransformBar.liveFields(for: .tilt(.depth)) == [.depth])
        #expect(TransformBar.liveFields(for: .command).isEmpty)
    }

    @Test("Only a 3D handle brings the space fields onto a flat layer")
    func spaceGestures() {
        #expect(TransformBar.Gesture.tilt(.swing).usesSpace)
        #expect(TransformBar.Gesture.tilt(.depth).usesSpace)
        #expect(!TransformBar.Gesture.rotate.usesSpace)
        #expect(!TransformBar.Gesture.move.usesSpace)
    }

    // MARK: Where the popover sits

    static let canvas = CGSize(width: 1000, height: 700)
    static let popover = CGSize(width: 200, height: 180)
    /// The top of the tool bar, or of the tool settings over it.
    static let floor: CGFloat = 640

    @Test("Rises from the Info button, 8 points over the tool bar, centred on the button")
    func risesFromTheButton() {
        let frame = TransformBar.popoverFrame(anchorX: 600, size: Self.popover, canvas: Self.canvas,
                                              floor: Self.floor, keepOut: [])
        #expect(frame.maxY == Self.floor - TransformBar.popoverGap)
        #expect(frame.midX == 600)
        #expect(frame.size == Self.popover)
    }

    @Test("Stays 12 points inside the canvas when the button is near an edge")
    func insideTheCanvas() {
        let right = TransformBar.popoverFrame(anchorX: 980, size: Self.popover, canvas: Self.canvas,
                                              floor: Self.floor, keepOut: [])
        #expect(right.maxX == Self.canvas.width - TransformBar.margin)
        let short = TransformBar.popoverFrame(anchorX: 500, size: CGSize(width: 200, height: 900),
                                              canvas: Self.canvas, floor: Self.floor, keepOut: [])
        #expect(short.minY == TransformBar.margin)
    }

    @Test("Slides sideways off a handle it would cover, to the nearer clear side")
    func slidesOffAHandle() {
        let handle = CGRect(x: 640, y: 560, width: 20, height: 20)
        let frame = TransformBar.popoverFrame(anchorX: 620, size: Self.popover, canvas: Self.canvas,
                                              floor: Self.floor, keepOut: [handle])
        #expect(!frame.intersects(handle))
        #expect(frame.maxX == handle.minX - TransformBar.popoverGap)
        #expect(frame.maxY == Self.floor - TransformBar.popoverGap)
    }

    @Test("Slides past a second handle when the first slide lands on it")
    func slidesPastTwoHandles() {
        let near = CGRect(x: 590, y: 560, width: 20, height: 20)
        let next = CGRect(x: 400, y: 560, width: 20, height: 20)
        let frame = TransformBar.popoverFrame(anchorX: 600, size: Self.popover, canvas: Self.canvas,
                                              floor: Self.floor, keepOut: [near, next])
        #expect(!frame.intersects(near))
        #expect(!frame.intersects(next))
        #expect(frame.minX >= TransformBar.margin)
        #expect(frame.maxX <= Self.canvas.width - TransformBar.margin)
    }

    @Test("A handle above or below its span leaves it where it is")
    func handleElsewhere() {
        let high = CGRect(x: 590, y: 100, width: 20, height: 20)
        let frame = TransformBar.popoverFrame(anchorX: 600, size: Self.popover, canvas: Self.canvas,
                                              floor: Self.floor, keepOut: [high])
        #expect(frame.midX == 600)
    }

    @Test("A layer filling the canvas: clear of its bottom corners and bottom middle")
    func fullCanvasLayer() {
        // The image fitted in the canvas with the tool bar over its lower edge.
        let quad = [CGPoint(x: 40, y: 20), CGPoint(x: 960, y: 20),
                    CGPoint(x: 960, y: 610), CGPoint(x: 40, y: 610)]
        let keepOut = TransformBar.handleKeepOut(quad: quad, knob: CGPoint(x: 500, y: 2), space: nil)
        // Eight squares and the knob.
        #expect(keepOut.count == 9)
        for anchor in stride(from: CGFloat(120), through: 900, by: 60) {
            let frame = TransformBar.popoverFrame(anchorX: anchor, size: Self.popover,
                                                  canvas: Self.canvas, floor: Self.floor, keepOut: keepOut)
            for box in keepOut { #expect(!frame.intersects(box), "anchor \(anchor) covers \(box)") }
        }
    }

    @Test("The knob's 3D arcs and the depth arrow are kept clear as well as the squares")
    func spaceHandlesKeptClear() {
        let quad = [CGPoint(x: 300, y: 300), CGPoint(x: 700, y: 300),
                    CGPoint(x: 700, y: 600), CGPoint(x: 300, y: 600)]
        let space = SpaceHandles(topMid: CGPoint(x: 500, y: 300), middle: CGPoint(x: 500, y: 450),
                                 pivot: CGPoint(x: 500, y: 450))
        let keepOut = TransformBar.handleKeepOut(quad: quad, knob: nil, space: space)
        #expect(keepOut.count == 8 + 4)
        let tip = space.tipArc.points().first ?? .zero
        #expect(keepOut.contains { $0.contains(tip) })
        #expect(keepOut.contains { $0.contains(space.depthArrow.head) })
        #expect(keepOut.contains { $0.contains(space.knob) })
    }

    // MARK: Reset

    @Test("Reset puts an animated size back to the layer's own, keeping its middle where it is")
    func resetSize() {
        let shown = CGRect(x: 100, y: 100, width: 300, height: 150)
        let reset = TransformBar.resetFrame(shown: shown, own: CGSize(width: 200, height: 100))
        #expect(reset.size == CGSize(width: 200, height: 100))
        #expect(reset.midX == shown.midX)
        #expect(reset.midY == shown.midY)
    }

    // MARK: Typed sums

    @Test("A plain number is that number")
    func plainNumber() {
        #expect(TypedSum.value("120", from: 40) == 120)
        #expect(TypedSum.value("-5", from: 40) == -5)
        #expect(TypedSum.value("12.5°", from: 0) == 12.5)
        #expect(TypedSum.value(" 300 px ", from: 0) == 300)
    }

    @Test("A leading +, * or / works from the value already there")
    func relative() {
        #expect(TypedSum.value("+40", from: 960) == 1000)
        #expect(TypedSum.value("*2", from: 150) == 300)
        #expect(TypedSum.value("/4", from: 100) == 25)
        #expect(TypedSum.value("+10", from: nil) == nil)
    }

    @Test("A whole sum is worked out, with the usual order and brackets")
    func sums() {
        #expect(TypedSum.value("100+20", from: 0) == 120)
        #expect(TypedSum.value("100-20*2", from: 0) == 60)
        #expect(TypedSum.value("(100-20)*2", from: 0) == 160)
        #expect(TypedSum.value("1920/2", from: 0) == 960)
        #expect(TypedSum.value("-5+10", from: 0) == 5)
    }

    @Test("Anything that is not a number or a sum is no number at all")
    func nonsense() {
        #expect(TypedSum.value("", from: 3) == nil)
        #expect(TypedSum.value("wide", from: 3) == nil)
        #expect(TypedSum.value("1/0", from: 3) == nil)
        #expect(TypedSum.value("2**3", from: 3) == nil)
        #expect(TypedSum.value("(1+2", from: 3) == nil)
        #expect(TypedSum.value("1e9", from: 3) == nil)
    }
}
