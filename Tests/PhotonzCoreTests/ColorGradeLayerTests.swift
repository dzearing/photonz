import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A colour grade can be its own track over the clips below it
/// (`docs/design/mocks/pages/video-compositing.html`, the V4 colour grade
/// track; task `a-colour-grade-can-be-its-own-track-over-the-cli`).
///
/// The grade is a layer whose picture is whatever is under it, graded: a lens
/// that adjusts by the Color Grade in its own Effects list. So its Blending and
/// its Masked by are the ones every layer already has.
@Suite("A colour grade on its own track")
struct ColorGradeLayerTests {

    static let canvas = CGSize(width: 160, height: 90)

    /// An eight second video with one clip on V1.
    static func video(lengthMS: Int = 8000) -> PhotonzDocument {
        var clip = Layer(name: "beach.mov", content: .image(ImageRef(pixelSize: Self.canvas)),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: lengthMS)
        var document = PhotonzDocument(canvasSize: canvas, layers: [clip])
        document.durationMS = lengthMS
        return document
    }

    @Test func aGradeAddedAtTheStartCoversTheWholeVideoOnANewTopTrack() throws {
        var document = Self.video()
        let idAdded = document.addColorGrade(atMS: 0)
        let id = try #require(idAdded)
        let layer = try #require(document.layer(id: id))
        #expect(layer.name == "Color Grade")
        #expect(layer.isColorGrade)
        #expect(layer.frame == CGRect(origin: .zero, size: Self.canvas))
        #expect(layer.time == LayerTime(inMS: 0, outMS: 8000))
        // It arrives as the same Warm grade the per-clip effect arrives as, so
        // the press visibly did something.
        #expect(layer.style.colorGrade == .starting)
        #expect(layer.style.blendMode == .normal)
        // On top of the stack, on a track of its own at the top of the list.
        #expect(document.layers.last?.id == id)
        let top = try #require(document.timelineTracks.first)
        #expect(top.name == "Grade")
        #expect(top.kind == .video)
        #expect(layer.trackID == top.id)
    }

    @Test func aGradeAddedPartWayRunsFromThePlayheadToTheEnd() throws {
        var document = Self.video()
        let idAdded = document.addColorGrade(atMS: 3000)
        let id = try #require(idAdded)
        #expect(document.layer(id: id)?.time == LayerTime(inMS: 3000, outMS: 8000))
    }

    @Test func aGradeAddedAtTheVeryEndCoversTheWholeVideoInstead() throws {
        // A playhead parked on the last frame leaves no room for anything a
        // person could see; the whole video is what they meant.
        var document = Self.video()
        let idAdded = document.addColorGrade(atMS: 7900)
        let id = try #require(idAdded)
        #expect(document.layer(id: id)?.time == LayerTime(inMS: 0, outMS: 8000))
    }

    @Test func aSecondGradeGetsATrackOfItsOwn() throws {
        var document = Self.video()
        document.addColorGrade(atMS: 0)
        let secondAdded = document.addColorGrade(atMS: 0)
        let second = try #require(secondAdded)
        #expect(document.timelineTracks.first?.name == "Grade 2")
        #expect(document.layers.last?.id == second)
    }

    @Test func aGradeCanLandOnAFreeTrackItWasAskedFor() throws {
        var document = Self.video()
        let empty = document.addTrack(.video, named: "V9")
        let idAdded = document.addColorGrade(atMS: 0, onTrack: empty)
        let id = try #require(idAdded)
        #expect(document.layer(id: id)?.trackID == empty)
    }

    @Test func aPictureWithNoTimeTakesNoGradeTrack() {
        var document = PhotonzDocument(canvasSize: Self.canvas, layers: [])
        #expect(document.addColorGrade(atMS: 0) == nil)
        #expect(document.layers.isEmpty)
    }

    @Test func aGradeIsNotOneOfTheLensToolsKinds() {
        // The Lens tool's capsule and the Does dropdown offer the six lens
        // kinds; a grade layer's controls are its Color Grade effect, so it
        // has no Does row of its own.
        let layer = ColorGradeLayer.layer(canvas: Self.canvas, time: LayerTime(inMS: 0, outMS: 1000))
        #expect(layer.lensKind == nil)
        #expect(!LensKind.allCases.map(\.rawValue).contains(LensAdjustment.colorGrade.rawValue))
        #expect(LensAdjustment.colorGrade.settingTitle == nil)
        #expect(LensContent(adjustment: .colorGrade).isIdentity)
        #expect(LensContent(adjustment: .colorGrade).sampleReach == 0)
    }

    @Test func thePanelCallsAGradeAnAdjustment() {
        // `video-compositing.html`: the Properties chip reads Adjustment on
        // the grade, Clip on a clip.
        let layer = ColorGradeLayer.layer(canvas: Self.canvas, time: LayerTime(inMS: 0, outMS: 1000))
        #expect(ClipLine.kind(of: layer) == "Adjustment")
    }

    @Test func aGradeLayerSavesAndOpensAsAGrade() throws {
        var document = Self.video()
        let idAdded = document.addColorGrade(atMS: 0)
        let id = try #require(idAdded)
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        let layer = try #require(back.layer(id: id))
        #expect(layer.isColorGrade)
        #expect(layer.style.colorGrade == .starting)
    }

    @Test func theGradeCanBorrowItsShapeFromTheLayerUnderIt() throws {
        // The matte is the layer directly below, so a shape drawn first and
        // the grade added over it is the mock's V3 matte under its V4 grade.
        var document = Self.video()
        document.landPicture(ImageRef(pixelSize: Self.canvas), named: "Matte shape",
                             at: document.pictureLanding(atMS: 0, over: nil))
        let shapeID = try #require(document.layers.last?.id)
        let gradeIDAdded = document.addColorGrade(atMS: 0)
        let gradeID = try #require(gradeIDAdded)
        document.updateLayer(id: gradeID) { $0.style.matte = .shape }
        #expect(document.matteSource(for: gradeID)?.id == shapeID)
        #expect(document.isSpentAsAMatte(shapeID))
    }
}

/// Add, the mock's fourth blend swatch (`video-compositing.html`, Blend mode
/// reference: Normal, Screen, Multiply, Add).
@Suite("Add blending")
struct AddBlendModeTests {

    @Test func addIsOfferedAfterScreenWithAPlainSentence() {
        let modes = BlendMode.allCases
        let screen = modes.firstIndex(of: .screen) ?? 0
        #expect(modes.firstIndex(of: .add) == screen + 1)
        #expect(BlendMode.add.title == "Add")
        #expect(!BlendMode.add.explanation.isEmpty)
        #expect(!BlendMode.add.explanation.contains("\u{2014}"))
    }

    @Test func addSurvivesASaveAndAnUnknownModeIsStillNormal() throws {
        var style = LayerStyle()
        style.blendMode = .add
        let back = try JSONDecoder().decode(LayerStyle.self, from: JSONEncoder().encode(style))
        #expect(back.blendMode == .add)
        #expect(BlendMode.named("overlay") == .normal)
    }
}
