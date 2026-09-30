import Foundation
@testable import PhotonzCore
import Testing

/// Where see-through paint is mixed into what is under it: in light, the way
/// Photonz always has, or in the numbers the colour was written in, the way a
/// browser, Figma and every SVG reader do (`docs/design/svg-export.md`,
/// "Where see-through paint is mixed").
@Suite("Where see-through paint is mixed")
struct CompositingSpaceTests {

    /// Half black over white. Mixed in light, half the light is left, which
    /// the file stores as 188. Mixed in the stored numbers it is 128, which is
    /// what a browser draws for `rgba(0,0,0,.5)` over white.
    @Test func halfBlackOverWhiteIsTheGreyEachSpaceSaysItIs() {
        func mixed(_ space: CompositingSpace) -> Int {
            let white = space.working(1), black = space.working(0)
            return Int((space.encoded(white * 0.5 + black * 0.5) * 255).rounded())
        }
        #expect(mixed(.linearLight) == 188)
        #expect(mixed(.sRGB) == 128)
    }

    @Test func theStoredNumbersAreMixedAsTheyAreInSRGB() {
        for c in stride(from: 0.0, through: 1.0, by: 0.125) {
            #expect(CompositingSpace.sRGB.working(c) == c)
            #expect(CompositingSpace.sRGB.encoded(c) == c)
            #expect(CompositingSpace.sRGB.slope(atWorking: c) == 1)
        }
    }

    /// Going into light and back is the identity, so a colour nobody made
    /// see-through comes out exactly the colour it went in as, in either space.
    @Test func anOpaqueColourComesBackAsItWentIn() {
        for level in 0...255 {
            let c = Double(level) / 255
            let back = CompositingSpace.linearLight.encoded(CompositingSpace.linearLight.working(c))
            #expect(Int((back * 255).rounded()) == level)
        }
    }

    /// The slope is how far the stored number moves per unit of the working
    /// value, which is what turns an error in working units into levels.
    @Test func theSlopeInLightIsTheDerivativeOfTheCurve() {
        let space = CompositingSpace.linearLight
        for w in [0.001, 0.05, 0.2, 0.5, 0.9] {
            let h = 1e-6
            let numeric = (space.encoded(w + h) - space.encoded(w - h)) / (2 * h)
            #expect(abs(space.slope(atWorking: w) - numeric) < 1e-4)
        }
    }

    /// Photonz as people have it today stays exactly as it draws: light.
    @Test func linearLightIsWhatNothingSaidMeans() {
        #expect(CompositingSpace.standard == .linearLight)
    }
}

/// Which space each release gets out of the box, read off the same switch
/// the Experiments window shows.
@Suite("Which release mixes where")
struct CompositingSpaceReleaseTests {
    @Test func nextMixesTheWayABrowserDoesOutOfTheBox() {
        #expect(CompositingSpace.chosen(by: FeatureCatalog.defaultSettings(for: .next)) == .sRGB)
    }

    @Test func currentMixesInLightAsItAlwaysHas() {
        #expect(CompositingSpace.chosen(by: FeatureCatalog.defaultSettings(for: .current))
            == .linearLight)
    }

    @Test func turningTheSwitchOffInNextPutsLightBack() {
        var settings = FeatureCatalog.defaultSettings(for: .next)
        settings.setEnabled(false, for: FeatureCatalog.webCompositingFlag)
        #expect(CompositingSpace.chosen(by: settings) == .linearLight)
    }
}
