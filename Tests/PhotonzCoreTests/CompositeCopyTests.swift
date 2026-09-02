import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Copy Image's clipboard payload (`next-measure-panel`): the picture always,
/// and the spec list as text beside it when the document has something to
/// list. The type order is pinned because it is what image-aware apps read.
@Suite("Composite copy")
struct CompositeCopyTests {

    private func caliper(from start: CGPoint, to end: CGPoint, visible: Bool = true) -> Layer {
        var content = MeasureContent(role: .size)
        content.mode = MeasureContent.dominantAxis(from: start, to: end)
        var layer = MeasureBuilder.layer(content: content, from: start, to: end)
        layer.isVisible = visible
        return layer
    }

    @Test func aDocumentWithNoMeasurementsCarriesNoText() {
        // Exactly what Copy Image copied before: PNG then TIFF, nothing else.
        let doc = PhotonzDocument(canvasSize: CGSize(width: 640, height: 480))
        #expect(CompositeCopy.specListText(document: doc, name: "Shot") == nil)
        #expect(CompositeCopy.representations(specList: nil) == [.png, .tiff])
        #expect(CompositeCopy.visibleMeasurementCount(in: doc) == 0)
    }

    @Test func measurementsPutTheSpecListBesideThePictureAfterTheImageTypes() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1280, height: 800))
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 128, y: 10)))
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 40), to: CGPoint(x: 64, y: 40)))

        let text = CompositeCopy.specListText(document: doc, name: "Capture")
        #expect(text == MeasureSpecList.render(document: doc, name: "Capture"))
        #expect(text?.hasPrefix("Capture · 1280 × 800 px\n") == true)
        // Image types first so image-aware apps take the picture; the string
        // last so only text-only fields fall through to it.
        #expect(CompositeCopy.representations(specList: text) == [.png, .tiff, .text(text ?? "")])
        #expect(CompositeCopy.visibleMeasurementCount(in: doc) == 2)
    }

    @Test func hiddenMeasurementsDoNotEarnAHeaderOnlyList() {
        // A list that would be just the header line says nothing the picture
        // does not, so the clipboard stays picture-only.
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 100))
        doc.addLayer(caliper(from: CGPoint(x: 0, y: 40), to: CGPoint(x: 64, y: 40), visible: false))
        #expect(CompositeCopy.specListText(document: doc, name: "Shot") == nil)
        #expect(CompositeCopy.visibleMeasurementCount(in: doc) == 0)
    }

    @Test func theNoticeSaysWhatLanded() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(CopyConfirmation(subject: .image(measurements: 0), shownAt: t0).detail == "Image")
        #expect(CopyConfirmation(subject: .image(measurements: 1), shownAt: t0).detail
                == "Image and spec list with 1 measurement")
        #expect(CopyConfirmation(subject: .image(measurements: 3), shownAt: t0).detail
                == "Image and spec list with 3 measurements")
        #expect(CopyConfirmation(subject: .image(measurements: 3), shownAt: t0).title == "Copied")
    }
}
