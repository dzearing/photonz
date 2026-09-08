import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Every effect measured in the same unit as the frame it sits on.
///
/// A magnified document states its frames in output pixels, so anything
/// measured in points that goes with them has to be restated too. The list
/// used to be reached through `blurRadius` and `shadows`, which meant a border
/// somebody ADDED was never scaled at all — it drew half as thick on a 2x
/// render — and a blur that was switched OFF read as nought and had its radius
/// wiped on the way through.
@Suite("Effect magnification")
struct EffectMagnificationTests {

    @Test("An added border is as thick at 2x as it is at 1x")
    func borderWidth() {
        var style = LayerStyle()
        style.effects = [.border(BorderEffect(width: 6, colorHex: "#00FF00", position: .outside))]
        let big = style.magnified(by: 2)
        #expect(big.borderEffects.first?.width == 12)
        // ...and reaches twice as far past the edge, so the room made for it
        // grows with it.
        #expect(big.borderEffectOutset == 12)
    }

    @Test("A switched-off blur keeps the radius it is holding")
    func offBlurKeepsItsRadius() {
        var style = LayerStyle()
        style.effects = [.blur(BlurEffect(radius: 9, isOn: false))]
        let big = style.magnified(by: 2)
        #expect(big.effects.first?.blur?.radius == 18)
        #expect(big.effects.first?.blur?.isOn == false)
    }

    @Test("A blur and a shadow still scale the way they always did")
    func blurAndShadow() {
        var style = LayerStyle()
        style.blurRadius = 4
        style.shadows = [ShadowStyle(radius: 10, offset: CGSize(width: 2, height: 5),
                                     spread: 3, kind: .drop)]
        let big = style.magnified(by: 2)
        #expect(big.blurRadius == 8)
        let shadow = big.shadows.first
        #expect(shadow?.radius == 20)
        #expect(shadow?.spread == 6)
        #expect(shadow?.offset == CGSize(width: 4, height: 10))
    }

    @Test("The order of the list survives the trip")
    func orderHolds() {
        var style = LayerStyle()
        style.effects = [.blur(BlurEffect(radius: 2)),
                         .shadow(ShadowStyle()),
                         .border(BorderEffect(width: 1))]
        #expect(style.magnified(by: 3).effects.map(\.kind) == [.blur, .shadow, .border])
    }
}
