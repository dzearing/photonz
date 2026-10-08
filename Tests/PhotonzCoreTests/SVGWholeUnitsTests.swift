import Foundation
import PhotonzCore
import Testing

/// The icon epic's promise that a file says every place in whole units, read
/// back out of the file itself (`SVGWholeUnits`).
@Suite("SVG whole units")
struct SVGWholeUnitsTests {

    @Test func anIconOnTheGridHasNothingToReport() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
          <g transform="translate(4 4)">
            <ellipse cx="8" cy="8" rx="8" ry="8" stroke-width="1.5" opacity="0.5"/>
            <path d="M0 0 L12 0 C14 2 16 4 18 6 Z"/>
          </g>
        </svg>
        """
        #expect(SVGWholeUnits.fractionalCoordinates(in: svg).isEmpty)
    }

    @Test func aPlaceOffTheGridIsNamedWithItsAttribute() {
        let svg = #"<svg viewBox="0 0 24 24"><rect x="2.5" y="3" width="10" height="7.25"/></svg>"#
        #expect(SVGWholeUnits.fractionalCoordinates(in: svg) == ["x=2.5", "height=7.25"])
    }

    @Test func pathDataAndMovesAreReadNumberByNumber() {
        let svg = #"<svg><path d="M0 0 L3.5 4 Z" transform="translate(1.25 2)"/></svg>"#
        #expect(SVGWholeUnits.fractionalCoordinates(in: svg) == ["d=3.5", "transform=1.25"])
    }

    @Test func weightsAndFadesAreNotPlaces() {
        // A 1.5 stroke is a weight, a half fade is a fade: neither is a point
        // on the grid, so neither is reported.
        let svg = #"<svg><line x1="0" y1="0" x2="8" y2="8" stroke-width="1.5" stroke-opacity="0.3"/></svg>"#
        #expect(SVGWholeUnits.fractionalCoordinates(in: svg).isEmpty)
    }

    @Test func aPictureRidingAlongIsNotReadAsNumbers() {
        // Base64 inside an embedded picture is letters and digits, not places.
        let svg = #"<svg><image x="0" y="0" width="4" height="4" href="data:image/png;base64,AQ1.5ID"/></svg>"#
        #expect(SVGWholeUnits.fractionalCoordinates(in: svg).isEmpty)
    }
}
