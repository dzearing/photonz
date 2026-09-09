import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A border can stand off the edge it sits against.
///
/// Position alone puts a ring in one of three places and nowhere else, which
/// makes a second border on the same shape a near-copy of the first. An offset
/// is what makes the pair useful: a tight ring on the edge and a second one
/// standing ten points off it. Centred straddles the edge and has no side to
/// measure from, so it has no offset at all.
///
/// The whole of the geometry is one signed number, `ringOutset`: where the
/// ring's OUTER edge sits relative to the layer's edge, positive past it and
/// negative inside it. The reach the rest of the app makes room for is that
/// number clamped at nought, because a ring drawn further IN never asks the
/// canvas for more room.
@Suite("Border offset")
struct BorderOffsetTests {

    // MARK: Where the ring lands

    @Test("An outside ring with an offset stands that much further out")
    func outsideStandsOff() {
        #expect(BorderPosition.outside.ringOutset(width: 4, offset: 0) == 4)
        #expect(BorderPosition.outside.ringOutset(width: 4, offset: 10) == 14)
        // ...and the reach grows with it, because those pixels are on canvas.
        #expect(BorderPosition.outside.outset(width: 4, offset: 10) == 14)
    }

    @Test("An inside ring with an offset moves that much further in")
    func insideMovesIn() {
        #expect(BorderPosition.inside.ringOutset(width: 4, offset: 0) == 0)
        #expect(BorderPosition.inside.ringOutset(width: 4, offset: 10) == -10)
        // Drawn further in, so it still asks the canvas for no extra room.
        #expect(BorderPosition.inside.outset(width: 4, offset: 10) == 0)
    }

    @Test("A centred ring has no edge to stand off from, so an offset does nothing")
    func centreIgnoresIt() {
        #expect(BorderPosition.center.ringOutset(width: 8, offset: 20) == 4)
        #expect(BorderPosition.center.outset(width: 8, offset: 20) == 4)
        #expect(!BorderPosition.center.appliesOffset)
        #expect(BorderPosition.inside.appliesOffset)
        #expect(BorderPosition.outside.appliesOffset)
    }

    @Test("A line of no width is no line, however far it is offset")
    func noWidthNoRing() {
        for position in BorderPosition.allCases {
            #expect(position.ringOutset(width: 0, offset: 25) == 0)
            #expect(position.outset(width: 0, offset: 25) == 0)
        }
    }

    @Test("An offset below nought is not a way of reversing the position")
    func negativeOffsetIsIgnored() {
        #expect(BorderPosition.outside.ringOutset(width: 4, offset: -10) == 4)
        #expect(BorderPosition.inside.ringOutset(width: 4, offset: -10) == 0)
    }

    // MARK: What one border reports

    @Test("The effect carries the offset through to its own geometry")
    func effectGeometry() {
        var border = BorderEffect(width: 4, colorHex: "#FF0000", position: .outside)
        #expect(border.offset == 0)
        border.offset = 10
        #expect(border.ringOutset == 14)
        #expect(border.outset == 14)

        border.position = .inside
        #expect(border.ringOutset == -10)
        #expect(border.outset == 0)

        border.position = .center
        #expect(border.ringOutset == 2)
        #expect(border.outset == 2)
    }

    @Test("A switched-off border still reaches nowhere, offset or not")
    func offReachesNothing() {
        var style = LayerStyle()
        style.effects = [.border(BorderEffect(width: 4, position: .outside, isOn: false))]
        style.updateBorderEffect(at: 0) { $0.offset = 30 }
        #expect(style.borderEffectOutset == 0)
    }

    // MARK: The room the app makes for it

    @Test("A big outside offset grows the layer's reach so nothing clips it")
    func reachAtALargeOffset() {
        var style = LayerStyle()
        style.effects = [.border(BorderEffect(width: 3, colorHex: "#000000", position: .outside))]
        style.updateBorderEffect(at: 0) { $0.offset = 36 }
        #expect(style.borderEffectOutset == 39)
        // The padding a drag sprite, a dirty rect and a group's box all start
        // from has to hold it too, or the ring is cut off at the frame.
        #expect(style.previewPadding >= 39)

        var layer = Layer(name: "Box", content: .image(ImageRef(pixelSize: CGSize(width: 80, height: 40))),
                          frame: CGRect(x: 10, y: 10, width: 80, height: 40))
        layer.style = style
        #expect(layer.outlineOutset == 39)
        #expect(layer.reachPadding >= 39)
    }

    @Test("An inside offset asks for no more room than an inside border ever did")
    func insideAsksForNothing() {
        var style = LayerStyle()
        style.effects = [.border(BorderEffect(width: 3, colorHex: "#000000", position: .inside))]
        style.updateBorderEffect(at: 0) { $0.offset = 36 }
        #expect(style.borderEffectOutset == 0)
    }

    @Test("Two rings on one shape overlap rather than stacking, so the furthest decides")
    func furthestDecides() {
        var style = LayerStyle()
        style.effects = [
            .border(BorderEffect(width: 2, colorHex: "#000000", position: .outside)),
            .border(BorderEffect(width: 2, colorHex: "#FF0000", position: .outside)),
        ]
        style.updateBorderEffect(at: 1) { $0.offset = 12 }
        #expect(style.borderEffectOutset == 14)
    }

    // MARK: Files written before this

    @Test("A border saved before offsets existed opens with none and draws as it did")
    func oldFileOpensUnchanged() throws {
        let json = Data("""
        {"width":6,"colorHex":"#112233","position":"outside","isOn":true}
        """.utf8)
        let border = try JSONDecoder().decode(BorderEffect.self, from: json)
        #expect(border.offset == 0)
        #expect(border.outset == 6)
    }

    @Test("A border with no offset writes none, so an older build reads what it always read")
    func zeroOffsetIsNotWritten() throws {
        let plain = BorderEffect(width: 6, colorHex: "#112233", position: .outside)
        let text = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!text.contains("offset"))
    }

    @Test("An offset survives a save and a reopen")
    func roundTrips() throws {
        var border = BorderEffect(width: 6, colorHex: "#112233", position: .inside)
        border.offset = 9
        let data = try JSONEncoder().encode(border)
        #expect(String(decoding: data, as: UTF8.self).contains("offset"))
        let back = try JSONDecoder().decode(BorderEffect.self, from: data)
        #expect(back.offset == 9)
        #expect(back.ringOutset == -9)
    }

    // MARK: The same distance at every magnification

    @Test("An offset is as far at 2x as it is at 1x")
    func magnifies() {
        var style = LayerStyle()
        style.effects = [.border(BorderEffect(width: 3, colorHex: "#00FF00", position: .outside))]
        style.updateBorderEffect(at: 0) { $0.offset = 10 }
        let big = style.magnified(by: 2)
        #expect(big.borderEffects.first?.offset == 20)
        #expect(big.borderEffectOutset == 26)
    }
}
