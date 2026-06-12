import CoreGraphics
import PhotonzCore
import Testing

@Suite("Resize dialog model")
struct ResizeModelTests {
    let model = ResizeModel(originalSize: CGSize(width: 1200, height: 800))

    // MARK: Defaults

    @Test func startsInPixelsAtTheOriginalSizeWithAspectLocked() {
        #expect(model.unit == .pixels)
        #expect(model.lockAspect)
        #expect(model.width == 1200)
        #expect(model.height == 800)
        #expect(model.targetSize == CGSize(width: 1200, height: 800))
        #expect(model.isIdentity)
    }

    // MARK: Aspect-locked edits

    @Test func lockedWidthEditDrivesHeight() {
        var m = model
        m.setWidth(600)
        #expect(m.height == 400)
        #expect(m.targetSize == CGSize(width: 600, height: 400))
        #expect(!m.isIdentity)
    }

    @Test func lockedHeightEditDrivesWidth() {
        var m = model
        m.setHeight(400)
        #expect(m.width == 600)
    }

    @Test func unlockedEditsAreIndependent() {
        var m = model
        m.setLockAspect(false)
        m.setWidth(600)
        #expect(m.height == 800)
        m.setHeight(100)
        #expect(m.width == 600)
        #expect(m.targetSize == CGSize(width: 600, height: 100))
    }

    @Test func relockingSnapsHeightBackToTheAspect() {
        var m = model
        m.setLockAspect(false)
        m.setHeight(100)
        m.setLockAspect(true)
        #expect(m.height == 800 * (m.width / 1200))
    }

    // MARK: Units

    @Test func switchingToPercentConvertsTheFields() {
        var m = model
        m.setWidth(600)
        m.setUnit(.percent)
        #expect(m.width == 50)
        #expect(m.height == 50)
        #expect(m.targetSize == CGSize(width: 600, height: 400))
    }

    @Test func percentEditsScaleFromTheOriginal() {
        var m = model
        m.setUnit(.percent)
        m.setWidth(25)
        #expect(m.height == 25)
        #expect(m.targetSize == CGSize(width: 300, height: 200))
    }

    @Test func switchingBackToPixelsRestoresPixelValues() {
        var m = model
        m.setUnit(.percent)
        m.setWidth(50)
        m.setUnit(.pixels)
        #expect(m.width == 600)
        #expect(m.height == 400)
    }

    @Test func unlockedPercentEditsAreIndependent() {
        var m = model
        m.setUnit(.percent)
        m.setLockAspect(false)
        m.setWidth(50)
        m.setHeight(200)
        #expect(m.targetSize == CGSize(width: 600, height: 1600))
    }

    // MARK: Presets

    @Test func percentPresetSetsBothFields() {
        var m = model
        m.setLockAspect(false) // presets are uniform regardless of the lock
        m.applyPercent(50)
        #expect(m.unit == .percent)
        #expect(m.width == 50)
        #expect(m.height == 50)
        #expect(m.targetSize == CGSize(width: 600, height: 400))
    }

    // MARK: Validation & rounding

    @Test func targetSizeRoundsToWholePixels() {
        var m = ResizeModel(originalSize: CGSize(width: 999, height: 333))
        m.setUnit(.percent)
        m.applyPercent(50)
        #expect(m.targetSize == CGSize(width: 500, height: 167))
    }

    @Test func zeroOrNegativeFieldsAreInvalid() {
        var m = model
        m.setLockAspect(false)
        m.setWidth(0)
        #expect(!m.isValid)
        m.setWidth(-5)
        #expect(!m.isValid)
        m.setWidth(600)
        #expect(m.isValid)
    }

    @Test func tinyPercentStillYieldsAtLeastOnePixel() {
        var m = ResizeModel(originalSize: CGSize(width: 10, height: 10))
        m.setUnit(.percent)
        m.applyPercent(1)
        #expect(m.targetSize == CGSize(width: 1, height: 1))
        #expect(m.isValid)
    }

    @Test func identityDetectionSurvivesUnitRoundTrips() {
        var m = model
        m.setUnit(.percent)
        m.setUnit(.pixels)
        #expect(m.isIdentity)
    }
}
