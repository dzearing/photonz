import CoreGraphics
import Testing
@testable import PhotonzCore

/// The ring a picked thing wears on the canvas. Every mock draws it as one
/// solid accent stroke (selection.css `.sel-ring`, 1.5px; a member of a
/// multi-selection `.mem-ring`, 1px at 70%). The app drew a faint dotted blue
/// line instead until 2026-10-14, which is what Current keeps.
@Suite("The ring a picked layer wears")
struct PickedRingTests {

    @Test("A picked layer wears the mock's solid accent ring at full strength")
    func pickedIsTheMockRing() {
        let ring = PickedRing.picked(solid: true)
        #expect(ring.width == 1.5)
        #expect(ring.opacity == 1)
        #expect(ring.dash == nil)
        #expect(ring.ink == .accent)
    }

    @Test("A member of a multi-selection wears the finer ring at 70%")
    func memberIsTheMockMemberRing() {
        let ring = PickedRing.member(solid: true)
        #expect(ring.width == 1)
        #expect(ring.opacity == 0.7)
        #expect(ring.dash == nil)
        #expect(ring.ink == .accent)
    }

    @Test("A solid ring is cased in a light halo wider than itself, so it reads on a blue screenshot")
    func solidRingsAreCased() throws {
        for ring in [PickedRing.picked(solid: true), PickedRing.member(solid: true)] {
            let casing = try #require(ring.casing)
            // Wide enough to show past the ink on both sides...
            #expect(casing.width >= ring.width + 1)
            // ...and no wider than a hairline on each side, so the ring still
            // reads as the mock's single line rather than as a double one.
            #expect(casing.width <= ring.width + 2)
            #expect(casing.white == 1)
            #expect(casing.opacity > 0.4 && casing.opacity < 0.8)
        }
    }

    @Test("With the switch off the ring is the dotted blue line Current has always drawn")
    func offIsTheOldDottedLine() {
        for ring in [PickedRing.picked(solid: false), PickedRing.member(solid: false)] {
            #expect(ring.width == 2)
            #expect(ring.opacity == 0.6)
            #expect(ring.dash == [2, 4])
            #expect(ring.ink == .systemBlue)
            #expect(ring.casing == nil)
        }
    }
}
