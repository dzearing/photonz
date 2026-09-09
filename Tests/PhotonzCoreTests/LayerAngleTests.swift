import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("The angle a layer is turned to")
struct LayerAngleTests {

    // MARK: The two units meeting in one place

    @Test("Radians in, degrees out, and back again unchanged")
    func roundTrips() {
        #expect(LayerAngle.degrees(fromRadians: .pi / 4) == 45)
        #expect(LayerAngle.degrees(fromRadians: -.pi / 2) == -90)
        #expect(abs(LayerAngle.radians(fromDegrees: 45) - .pi / 4) < 1e-12)
        #expect(abs(LayerAngle.degrees(fromRadians: LayerAngle.radians(fromDegrees: 137)) - 137) < 1e-9)
    }

    @Test("A number that is not a number turns nothing")
    func nonFiniteIsStraight() {
        #expect(LayerAngle.degrees(fromRadians: .nan) == 0)
        #expect(LayerAngle.radians(fromDegrees: .infinity) == 0)
        #expect(LayerAngle.normalized(.nan) == 0)
    }

    // MARK: Saying the turn the shortest way

    @Test("Swinging the knob round twice still reads as where the layer ended up")
    func wrapsWholeTurns() {
        #expect(LayerAngle.normalized(370) == 10)
        #expect(LayerAngle.normalized(730) == 10)
        #expect(LayerAngle.normalized(-370) == -10)
        #expect(LayerAngle.normalized(190) == -170)
        #expect(LayerAngle.normalized(-190) == 170)
    }

    @Test("Half a turn is 180, the way people say it, not -180")
    func halfATurnIsPositive() {
        #expect(LayerAngle.normalized(180) == 180)
        #expect(LayerAngle.normalized(-180) == 180)
        #expect(LayerAngle.display(-179.6) == 180)
    }

    @Test("Straight is 0, never -0")
    func straightHasNoSign() {
        #expect(LayerAngle.normalized(0) == 0)
        #expect(LayerAngle.display(-0.2) == 0)
        #expect(String(Int(LayerAngle.display(-0.2))) == "0")
    }

    @Test("The field shows whole degrees, so what you read is what an arrow key steps from")
    func displayIsWhole() {
        #expect(LayerAngle.display(44.6) == 45)
        #expect(LayerAngle.display(45.4) == 45)
        #expect(LayerAngle.display(-44.6) == -45)
    }

    @Test("45 and 405 are the same turn, so typing one over the other changes nothing")
    func sameTurn() {
        #expect(LayerAngle.isSameTurn(45, 405))
        #expect(LayerAngle.isSameTurn(-180, 180))
        #expect(!LayerAngle.isSameTurn(45, 46))
    }
}
