import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The small glass bar of transform values that rides beside a layer while it
/// is in hand (`a-small-overlay-shows-transform-values-to-type-i`,
/// `pages/video-animate.html`, "Where the bar sits").
@Suite("Transform bar: which values, where it sits, and what a typed sum means")
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

    // MARK: Which side, which fields are live

    @Test("A bottom handle in hand puts the bar above; everything else keeps it below")
    func sides() {
        for handle in [ResizeHandle.bottom, .bottomLeft, .bottomRight] {
            #expect(TransformBar.side(for: .resize(handle)) == .above)
        }
        for handle in [ResizeHandle.top, .topLeft, .topRight, .left, .right] {
            #expect(TransformBar.side(for: .resize(handle)) == .below)
        }
        #expect(TransformBar.side(for: .move) == .below)
        #expect(TransformBar.side(for: .rotate) == .below)
        #expect(TransformBar.side(for: .tilt(.swing)) == .below)
        #expect(TransformBar.side(for: .nudge) == .below)
        #expect(TransformBar.side(for: .command) == .below)
    }

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

    // MARK: Where it sits

    static let canvas = CGSize(width: 1000, height: 700)
    static let bar = CGSize(width: 400, height: 32)
    /// The top of the tool bar: the bar never comes down past it.
    static let floor: CGFloat = 640

    @Test("Under the object, 12 points below its frame, centred on it")
    func underTheObject() {
        let box = CGRect(x: 400, y: 200, width: 200, height: 100)
        let frame = TransformBar.frame(around: box, bar: Self.bar, canvas: Self.canvas,
                                       floor: Self.floor, side: .below)
        #expect(frame.minY == 312)
        #expect(frame.midX == box.midX)
        #expect(frame.size == Self.bar)
    }

    @Test("Above it, clear of the turn knob, while a bottom handle is in hand")
    func aboveForABottomHandle() {
        let box = CGRect(x: 400, y: 200, width: 200, height: 100)
        let frame = TransformBar.frame(around: box, bar: Self.bar, canvas: Self.canvas,
                                       floor: Self.floor, side: .above)
        #expect(frame.maxY == box.minY - TransformBar.knobClearance - TransformBar.gap)
        #expect(frame.maxY <= box.minY - 12)
    }

    @Test("Above it when there is no room between the object and the tool bar")
    func aboveWhenNoRoomBelow() {
        let box = CGRect(x: 400, y: 560, width: 200, height: 60)
        let frame = TransformBar.frame(around: box, bar: Self.bar, canvas: Self.canvas,
                                       floor: Self.floor, side: .below)
        #expect(frame.maxY <= box.minY)
        #expect(frame.maxY <= Self.floor)
    }

    @Test("Below it when the side asked for is above and there is no room at the top")
    func belowWhenNoRoomAbove() {
        let box = CGRect(x: 400, y: 20, width: 200, height: 60)
        let frame = TransformBar.frame(around: box, bar: Self.bar, canvas: Self.canvas,
                                       floor: Self.floor, side: .above)
        #expect(frame.minY == box.maxY + 12)
    }

    @Test("Slid sideways to stay 12 points inside the canvas")
    func againstTheEdge() {
        let left = CGRect(x: -40, y: 200, width: 120, height: 80)
        let atLeft = TransformBar.frame(around: left, bar: Self.bar, canvas: Self.canvas,
                                        floor: Self.floor, side: .below)
        #expect(atLeft.minX == 12)
        let right = CGRect(x: 950, y: 200, width: 120, height: 80)
        let atRight = TransformBar.frame(around: right, bar: Self.bar, canvas: Self.canvas,
                                         floor: Self.floor, side: .below)
        #expect(atRight.maxX == Self.canvas.width - 12)
    }

    @Test("A layer smaller than the bar has the bar centred under it, at its own size")
    func smallLayer() {
        let box = CGRect(x: 480, y: 300, width: 20, height: 14)
        let frame = TransformBar.frame(around: box, bar: Self.bar, canvas: Self.canvas,
                                       floor: Self.floor, side: .below)
        #expect(frame.midX == box.midX)
        #expect(frame.size == Self.bar)
    }

    @Test("Never over the tool bar and never off the top, even for a layer filling the canvas")
    func hugeLayer() {
        let box = CGRect(x: -100, y: -100, width: 1200, height: 900)
        let frame = TransformBar.frame(around: box, bar: Self.bar, canvas: Self.canvas,
                                       floor: Self.floor, side: .below)
        #expect(frame.minY >= 12)
        #expect(frame.maxY <= Self.floor)
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
