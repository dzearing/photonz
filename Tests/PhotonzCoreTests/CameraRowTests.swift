import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The camera's keys on a thin row at the top of the timeline
/// (`show-the-camera-s-keys-on-a-thin-row-at-the-top`, `CameraRow.swift`,
/// mock `video-depth.html`, "Camera A · a setting of the frame").
@Suite("The Camera row on the timeline")
struct CameraRowTests {

    /// Ten seconds and nothing keyed.
    static func video() -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        doc.layers = [Layer(name: "Title", content: .text(TextContent(string: "Hi", fontSize: 48)),
                            frame: CGRect(x: 100, y: 100, width: 400, height: 80))]
        doc.durationMS = 10_000
        return doc
    }

    /// A push in over two seconds: Camera depth keyed 0 at 1s and 400 at 3s.
    static func pushIn() -> PhotonzDocument {
        var doc = video()
        doc.toggleCameraKey(.cameraDepth, atDocumentTimeMS: 1000)
        doc.setCameraValue(.cameraDepth, 400, atDocumentTimeMS: 3000)
        return doc
    }

    @Test("No camera keys, no row")
    func noKeysNoRow() {
        var doc = Self.video()
        #expect(doc.cameraKeyMoments.isEmpty)
        #expect(!doc.hasCameraKeys)
        // A camera moved without keys is still no row.
        doc.setCameraValue(.cameraDepth, 200, atDocumentTimeMS: 0)
        #expect(!doc.hasCameraKeys)
    }

    @Test("One diamond per key, in time order, saying what it holds")
    func onePerKey() {
        let doc = Self.pushIn()
        #expect(doc.hasCameraKeys)
        let moments = doc.cameraKeyMoments
        #expect(moments.map(\.ms) == [1000, 3000])
        #expect(moments.map(\.properties) == [[.cameraDepth], [.cameraDepth]])
        #expect(moments[1].reading == "Camera depth 400 px")
    }

    @Test("Keys on different camera values at one moment are one diamond")
    func oneMomentOneDiamond() {
        var doc = Self.pushIn()
        doc.toggleCameraKey(.cameraX, atDocumentTimeMS: 3005)
        doc.toggleCameraKey(.cameraPerspective, atDocumentTimeMS: 6000)
        let moments = doc.cameraKeyMoments
        #expect(moments.map(\.ms) == [1000, 3000, 6000])
        // In the panel's order.
        #expect(moments[1].properties == [.cameraDepth, .cameraX])
        #expect(moments[2].properties == [.cameraPerspective])
    }

    @Test("Dragging a diamond moves every camera key at that moment and keeps their values")
    func dragMoves() {
        var doc = Self.pushIn()
        doc.toggleCameraKey(.cameraX, atDocumentTimeMS: 3000)
        let landed = doc.moveCameraKeys(atMS: 3000, toMS: 5000)
        #expect(landed == 5000)
        #expect(doc.cameraKeyMoments.map(\.ms) == [1000, 5000])
        #expect(doc.cameraValue(.cameraDepth, atDocumentTimeMS: 5000) == 400)
        #expect(doc.cameraKeyCount(.cameraDepth) == 2)
        #expect(doc.cameraKeyCount(.cameraX) == 1)
        // The push now takes four seconds: half way is 3s.
        let middle = doc.cameraValue(.cameraDepth, atDocumentTimeMS: 3000) ?? 0
        #expect(middle > 0 && middle < 400)
    }

    @Test("A diamond dragged past another settles beside it, not over it, and both values stay")
    func dragPast() {
        var doc = Self.pushIn()
        let landed = doc.moveCameraKeys(atMS: 3000, toMS: 500)
        #expect(landed == 500)
        #expect(doc.cameraKeyMoments.map(\.ms) == [500, 1000])
        #expect(doc.cameraValue(.cameraDepth, atDocumentTimeMS: 500) == 400)
        #expect(doc.cameraValue(.cameraDepth, atDocumentTimeMS: 1000) == 0)
    }

    @Test("A diamond dropped on another takes its place")
    func dragOnto() {
        var doc = Self.pushIn()
        _ = doc.moveCameraKeys(atMS: 3000, toMS: 1010)
        #expect(doc.cameraKeyMoments.count == 1)
        #expect(doc.cameraValue(.cameraDepth, atDocumentTimeMS: 0) == 400)
    }

    @Test("A diamond stays on the document's own clock")
    func dragClamped() {
        var doc = Self.pushIn()
        let early = doc.moveCameraKeys(atMS: 1000, toMS: -800)
        let late = doc.moveCameraKeys(atMS: 3000, toMS: 99_000)
        #expect(early == 0)
        #expect(late == 10_000)
        #expect(doc.cameraKeyMoments.map(\.ms) == [0, 10_000])
    }

    @Test("Dragging where nothing is keyed changes nothing")
    func dragNothing() {
        var doc = Self.pushIn()
        let before = doc
        let landed = doc.moveCameraKeys(atMS: 7000, toMS: 8000)
        #expect(landed == nil)
        #expect(doc == before)
    }

    @Test("Deleting a diamond removes every camera key at that moment")
    func delete() {
        var doc = Self.pushIn()
        doc.toggleCameraKey(.cameraX, atDocumentTimeMS: 3000)
        let removed = doc.removeCameraKeys(atMS: 3000)
        #expect(removed)
        #expect(doc.cameraKeyMoments.map(\.ms) == [1000])
        #expect(doc.cameraKeyCount(.cameraX) == 0)
        let none = doc.removeCameraKeys(atMS: 7000)
        #expect(!none)
    }

    @Test("Deleting the last diamond leaves the camera where it stood, and the row goes")
    func deleteLast() {
        var doc = Self.video()
        doc.toggleCameraKey(.cameraDepth, atDocumentTimeMS: 2000)
        doc.setCameraValue(.cameraDepth, 250, atDocumentTimeMS: 2000)
        let removed = doc.removeCameraKeys(atMS: 2000)
        #expect(removed)
        #expect(!doc.hasCameraKeys)
        #expect(doc.camera?.motions == nil)
        #expect(doc.camera?.depth == 250)
    }
}
