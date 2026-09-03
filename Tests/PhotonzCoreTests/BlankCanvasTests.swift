import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Blank canvas presets")
struct BlankCanvasTests {

    @Test("There are a few presets, not a catalog")
    func presetCount() {
        #expect(BlankCanvas.presets.count >= 3)
        #expect(BlankCanvas.presets.count <= 6)
    }

    @Test("Preset ids are unique, so the picker can key on them")
    func uniqueIDs() {
        let ids = BlankCanvas.presets.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every preset is a usable size")
    func presetsAreValid() {
        for preset in BlankCanvas.presets {
            #expect(preset.size.width >= BlankCanvas.minimumSide)
            #expect(preset.size.height >= BlankCanvas.minimumSide)
            #expect(preset.size.width <= BlankCanvas.maximumSide)
            #expect(preset.size.height <= BlankCanvas.maximumSide)
            #expect(!preset.title.isEmpty)
        }
    }

    @Test("The default preset is one of the presets, so the sheet opens preselected")
    func defaultIsAPreset() {
        #expect(BlankCanvas.presets.contains(BlankCanvas.defaultPreset))
    }

    @Test("A sensible custom size passes through untouched")
    func normalizeKeepsGoodSizes() {
        #expect(BlankCanvas.normalized(CGSize(width: 800, height: 600))
                == CGSize(width: 800, height: 600))
    }

    @Test("Fractional sizes round to whole pixels")
    func normalizeRounds() {
        #expect(BlankCanvas.normalized(CGSize(width: 800.4, height: 600.6))
                == CGSize(width: 800, height: 601))
    }

    @Test("Zero, negative and NaN sides come back as the smallest legal canvas")
    func normalizeFloors() {
        #expect(BlankCanvas.normalized(CGSize(width: 0, height: 0))
                == CGSize(width: BlankCanvas.minimumSide, height: BlankCanvas.minimumSide))
        #expect(BlankCanvas.normalized(CGSize(width: -40, height: 600))
                == CGSize(width: BlankCanvas.minimumSide, height: 600))
        #expect(BlankCanvas.normalized(CGSize(width: CGFloat.nan, height: CGFloat.nan))
                == CGSize(width: BlankCanvas.minimumSide, height: BlankCanvas.minimumSide))
    }

    @Test("An enormous side is capped rather than allocating a gigabyte")
    func normalizeCaps() {
        let huge = BlankCanvas.normalized(CGSize(width: 999_999, height: 999_999))
        #expect(huge == CGSize(width: BlankCanvas.maximumSide, height: BlankCanvas.maximumSide))
    }

    @Test("A size is acceptable exactly when it survives normalizing unchanged")
    func validityMatchesNormalizing() {
        #expect(BlankCanvas.isValid(CGSize(width: 800, height: 600)))
        #expect(!BlankCanvas.isValid(CGSize(width: 0, height: 600)))
        #expect(!BlankCanvas.isValid(CGSize(width: 800, height: 99_999)))
    }
}
