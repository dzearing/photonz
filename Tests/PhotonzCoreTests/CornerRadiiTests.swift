import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The four corners of a box, and the one number that is still the way in.
///
/// A card with a rounded top and a square bottom, a segmented control with
/// round ends and a square middle, a speech bubble: none of them could be drawn
/// while a shape carried one radius for all four corners.
@Suite("Corner radii")
struct CornerRadiiTests {

    @Test("One number is all four")
    func oneNumber() {
        let radii = CornerRadii(12)
        #expect(radii.topLeft == 12)
        #expect(radii.topRight == 12)
        #expect(radii.bottomRight == 12)
        #expect(radii.bottomLeft == 12)
        #expect(radii.uniform == 12)
        #expect(radii.isUniform)
    }

    @Test("Four that disagree have no one number")
    func mixed() {
        let radii = CornerRadii(topLeft: 12, topRight: 12, bottomRight: 0, bottomLeft: 0)
        #expect(radii.uniform == nil)
        #expect(!radii.isUniform)
        #expect(radii.largest == 12)
        #expect(radii.isRound)
    }

    @Test("Nothing rounded at all")
    func square() {
        #expect(!CornerRadii.none.isRound)
        #expect(CornerRadii.none.uniform == 0)
    }

    @Test("Corners are read and written by name, clockwise from the top left")
    func subscripts() {
        var radii = CornerRadii.none
        radii[.topRight] = 8
        #expect(radii[.topRight] == 8)
        #expect(radii[.topLeft] == 0)
        #expect(CornerRadii.Corner.allCases.map(\.rawValue)
            == ["topLeft", "topRight", "bottomRight", "bottomLeft"])
    }

    @Test("Negative rounding is no rounding")
    func floor() {
        let used = CornerRadii(topLeft: -4, topRight: .nan, bottomRight: 6, bottomLeft: 0).used
        #expect(used.topLeft == 0)
        #expect(used.topRight == 0)
        #expect(used.bottomRight == 6)
    }

    // MARK: - Fitting in the box

    @Test("Four that agree clamp exactly the way one number always did")
    func uniformClampIsUnchanged() {
        let box = CGSize(width: 120, height: 80)
        #expect(CornerRadii(999).fitted(in: box).uniform == 40)
        #expect(CornerRadii(10).fitted(in: box).uniform == 10)
        #expect(CornerRadii(40).fitted(in: box).uniform == 40)
    }

    @Test("Two corners that would meet in the middle of an edge are scaled down together")
    func adjacentOverlap() {
        // 60 + 60 on a 100 point edge is not a shape: both come back at 50.
        let fitted = CornerRadii(topLeft: 60, topRight: 60, bottomRight: 0, bottomLeft: 0)
            .fitted(in: CGSize(width: 100, height: 100))
        #expect(fitted.topLeft == 50)
        #expect(fitted.topRight == 50)
    }

    @Test("One big corner never shrinks the small one beside it more than it must")
    func proportionalScale() {
        // Top edge wants 80 + 20 = 100 out of 50: everything halves.
        let fitted = CornerRadii(topLeft: 80, topRight: 20, bottomRight: 0, bottomLeft: 0)
            .fitted(in: CGSize(width: 50, height: 200))
        #expect(fitted.topLeft == 40)
        #expect(fitted.topRight == 10)
        #expect(fitted.bottomRight == 0)
    }

    @Test("A rounded top over a square bottom survives the fit")
    func roundedTopSquareBottom() {
        let fitted = CornerRadii(topLeft: 16, topRight: 16, bottomRight: 0, bottomLeft: 0)
            .fitted(in: CGSize(width: 320, height: 200))
        #expect(fitted == CornerRadii(topLeft: 16, topRight: 16, bottomRight: 0, bottomLeft: 0))
    }

    @Test("An empty box rounds nothing")
    func emptyBox() {
        #expect(!CornerRadii(20).fitted(in: .zero).isRound)
    }

    // MARK: - Growing and shrinking with a ring

    @Test("A ring pushed out grows every rounded corner and leaves the square ones square")
    func outset() {
        let grown = CornerRadii(topLeft: 10, topRight: 0, bottomRight: 0, bottomLeft: 4).grown(by: 6)
        #expect(grown.topLeft == 16)
        #expect(grown.topRight == 0)
        #expect(grown.bottomLeft == 10)
    }

    @Test("Scaling for magnification takes all four")
    func scaled() {
        let big = CornerRadii(topLeft: 4, topRight: 8, bottomRight: 0, bottomLeft: 2).scaled(by: 2)
        #expect(big == CornerRadii(topLeft: 8, topRight: 16, bottomRight: 0, bottomLeft: 4))
    }

    // MARK: - What the panel reads

    @Test("The four numbers read as a shorthand and in words")
    func readouts() {
        let radii = CornerRadii(topLeft: 16, topRight: 16, bottomRight: 0, bottomLeft: 0)
        #expect(radii.shorthand == "16/16/0/0")
        #expect(radii.inWords == "16 top left, 16 top right, 0 bottom right, 0 bottom left")
    }

    // MARK: - On disk

    @Test("Four that agree save as the single number every older document holds")
    func encodesAsOneNumber() throws {
        let data = try JSONEncoder().encode(CornerRadii(18))
        #expect(String(data: data, encoding: .utf8) == "18")
    }

    @Test("A document written before there were four corners opens unchanged")
    func decodesOneNumber() throws {
        let radii = try JSONDecoder().decode(CornerRadii.self, from: Data("18".utf8))
        #expect(radii == CornerRadii(18))
    }

    @Test("Four that disagree save as four and come back as four")
    func roundTripsFour() throws {
        let radii = CornerRadii(topLeft: 16, topRight: 4, bottomRight: 0, bottomLeft: 9)
        let back = try JSONDecoder().decode(CornerRadii.self,
                                            from: try JSONEncoder().encode(radii))
        #expect(back == radii)
    }

    @Test("A corner left out of the file is a square corner")
    func decodesPartial() throws {
        let radii = try JSONDecoder().decode(CornerRadii.self,
                                             from: Data(#"{"topLeft":12}"#.utf8))
        #expect(radii == CornerRadii(topLeft: 12, topRight: 0, bottomRight: 0, bottomLeft: 0))
    }

    // MARK: - The path everything follows

    @Test("A square box is a plain rectangle")
    func squarePath() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 60)
        #expect(CornerRadii.none.path(in: box).boundingBoxOfPath == box)
    }

    @Test("A rounded path stays inside the box it was asked for")
    func pathStaysInside() {
        let box = CGRect(x: 10, y: 20, width: 100, height: 60)
        let path = CornerRadii(topLeft: 30, topRight: 0, bottomRight: 12, bottomLeft: 0).path(in: box)
        let bounds = path.boundingBoxOfPath
        #expect(abs(bounds.minX - box.minX) < 0.01)
        #expect(abs(bounds.maxY - box.maxY) < 0.01)
        #expect(box.insetBy(dx: -0.01, dy: -0.01).contains(bounds))
    }

    @Test("A corner that is round is not on the box's own corner, and a square one is")
    func pathCorners() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = CornerRadii(topLeft: 40, topRight: 0, bottomRight: 0, bottomLeft: 0).path(in: box)
        #expect(!path.contains(CGPoint(x: 2, y: 2)))       // rounded away
        #expect(path.contains(CGPoint(x: 98, y: 2)))       // still square
        #expect(path.contains(CGPoint(x: 98, y: 98)))
        #expect(path.contains(CGPoint(x: 2, y: 98)))
    }
}
