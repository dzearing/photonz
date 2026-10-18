import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Putting a picked text on a picked path, reshaping the curve after, and
/// keying where along it the words start (`TextOnPathEditing.swift`).
@Suite("Text on a path in a document")
struct TextOnPathDocumentTests {

    private func textLayer(_ string: String = "Follow the curve") -> Layer {
        Layer(name: "Title", content: .text(TextContent(string: string, fontSize: 40)),
              frame: CGRect(x: 600, y: 600, width: 300, height: 50))
    }

    /// The quarter circle from the core tests, standing at (100, 100).
    private func pathLayer() -> Layer {
        let guide = TextOnPathTests.quarterCircle(300)
        let box = guide.bounds
        var layer = Layer(name: "Path", content: .path(guide.offsetBy(dx: -box.minX, dy: -box.minY)),
                          frame: CGRect(x: 100, y: 100, width: box.width, height: box.height))
        layer.name = "Path"
        return layer
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        document.layers = layers
        return document
    }

    // MARK: - Which pick can be put together

    @Test func oneTextAndOnePathArePutTogether() throws {
        let text = textLayer(), path = pathLayer()
        let doc = document([text, path])
        let pair = try #require(doc.textAndPath(in: [text.id, path.id]))
        #expect(pair.text == text.id)
        #expect(pair.path == path.id)
    }

    @Test func anythingElsePickedIsNotAPair() {
        let text = textLayer(), path = pathLayer(), other = textLayer("Other")
        let doc = document([text, path, other])
        #expect(doc.textAndPath(in: [text.id]) == nil)
        #expect(doc.textAndPath(in: [path.id]) == nil)
        #expect(doc.textAndPath(in: [text.id, other.id]) == nil)
        #expect(doc.textAndPath(in: [text.id, path.id, other.id]) == nil)
    }

    @Test func aLockedLayerIsNotPutOnAPath() {
        var text = textLayer()
        text.isLocked = true
        let path = pathLayer()
        #expect(document([text, path]).textAndPath(in: [text.id, path.id]) == nil)
    }

    // MARK: - Putting it on

    @Test func theWordsTakeTheCurveAndThePathLayerGoes() throws {
        let text = textLayer(), path = pathLayer()
        var doc = document([text, path])
        let didPut = doc.putTextOnPath(textID: text.id, pathID: path.id)
        #expect(didPut)
        #expect(doc.layers.count == 1)
        let placed = try #require(doc.layer(id: text.id))
        let words = try #require(placed.text)
        let onPath = try #require(words.onPath)
        // The words keep everything they were.
        #expect(words.string == "Follow the curve")
        #expect(words.fontSize == 40)
        // The curve is where the path was on the canvas: its first point at
        // (400, 100) and its last at (100, 400).
        let first = try #require(onPath.guide.anchors.first?.point)
        let last = try #require(onPath.guide.anchors.last?.point)
        #expect(abs(placed.frame.minX + first.x - 400) < 0.01)
        #expect(abs(placed.frame.minY + first.y - 100) < 0.01)
        #expect(abs(placed.frame.minX + last.x - 100) < 0.01)
        #expect(abs(placed.frame.minY + last.y - 400) < 0.01)
        // The box is the curve's box, so the selection sits round the curve.
        #expect(abs(placed.frame.width - 300) < 0.5)
        #expect(abs(placed.frame.height - 300) < 0.5)
        #expect(onPath.startPercent == 0)
    }

    @Test func aTurnedPathIsPutOnAsItLooks() throws {
        let text = textLayer()
        var path = pathLayer()
        path.transform.rotation = 90
        let content = try #require(path.path)
        let before = content.offsetBy(dx: path.frame.minX, dy: path.frame.minY)
            .transformed(by: path.transform.affineTransform(
                around: CGPoint(x: path.frame.midX, y: path.frame.midY)))
        // Turned a quarter about the middle of its box, the curve's first
        // point is no longer where its numbers say.
        #expect(abs(before.anchors[0].point.x - 400) > 1 || abs(before.anchors[0].point.y - 100) > 1)
        var doc = document([text, path])
        let didPut = doc.putTextOnPath(textID: text.id, pathID: path.id)
        #expect(didPut)
        let placed = try #require(doc.layer(id: text.id))
        #expect(placed.transform.isIdentity)
        let guide = try #require(placed.text?.onPath?.guide)
        for (a, b) in zip(guide.anchors, before.anchors) {
            #expect(abs(placed.frame.minX + a.point.x - b.point.x) < 0.01)
            #expect(abs(placed.frame.minY + a.point.y - b.point.y) < 0.01)
        }
    }

    // MARK: - Reshaping

    @Test func aTextOnAPathOffersItsCurveToReshape() throws {
        let text = textLayer(), path = pathLayer()
        var doc = document([text, path])
        doc.putTextOnPath(textID: text.id, pathID: path.id)
        let placed = try #require(doc.layer(id: text.id))
        #expect(placed.reshapablePath == placed.text?.onPath?.guide)
        #expect(textLayer().reshapablePath == nil)
        #expect(pathLayer().reshapablePath == pathLayer().path)
    }

    @Test func reshapingTheCurveKeepsTheWordsAndMovesTheBox() throws {
        let text = textLayer(), path = pathLayer()
        var doc = document([text, path])
        doc.putTextOnPath(textID: text.id, pathID: path.id)
        let placed = try #require(doc.layer(id: text.id))
        var guide = try #require(placed.reshapablePath)
        // Pull the last point 100 further down.
        guide.anchors[guide.anchors.count - 1].point.y += 100
        let refit = PathBuilder.refit(placed, content: guide)
        #expect(refit.text?.string == "Follow the curve")
        #expect(refit.path == nil)
        let newGuide = try #require(refit.text?.onPath?.guide)
        let last = try #require(newGuide.anchors.last?.point)
        #expect(abs(refit.frame.minY + last.y - 500) < 0.01)
        #expect(abs(refit.frame.height - 400) < 0.5)
    }

    @Test func resizingTheBoxScalesTheCurveAndNotTheType() throws {
        let text = textLayer(), path = pathLayer()
        var doc = document([text, path])
        doc.putTextOnPath(textID: text.id, pathID: path.id)
        let placed = try #require(doc.layer(id: text.id))
        #expect(!placed.resizeWidthOnly)
        let grown = placed.resized(to: CGRect(x: 100, y: 100, width: 600, height: 300))
        #expect(grown.frame == CGRect(x: 100, y: 100, width: 600, height: 300))
        #expect(grown.text?.fontSize == 40)
        let first = try #require(grown.text?.onPath?.guide.anchors.first?.point)
        #expect(abs(first.x - 600) < 0.01)
    }

    // MARK: - Words stay on it

    @Test func reWordingKeepsTheWordsOnTheCurve() throws {
        let text = textLayer(), path = pathLayer()
        var doc = document([text, path])
        doc.putTextOnPath(textID: text.id, pathID: path.id)
        let before = try #require(doc.layer(id: text.id))
        doc.commitTextEdit(id: text.id, content: TextContent(string: "New words", fontSize: 40),
                           canvasFrame: CGRect(x: 0, y: 0, width: 200, height: 50))
        let after = try #require(doc.layer(id: text.id))
        #expect(after.text?.string == "New words")
        #expect(after.text?.onPath == before.text?.onPath)
        #expect(after.frame == before.frame)
    }

    @Test func keepingTheSettingKeepsTheCurve() {
        var old = TextContent(string: "a")
        old.onPath = TextOnPath(guide: TextOnPathTests.quarterCircle(), startPercent: 12)
        var new = TextContent(string: "b")
        new.keepSetting(of: old)
        #expect(new.onPath == old.onPath)
    }

    // MARK: - Start, and keying it

    @Test func startIsSetOnTheText() throws {
        let text = textLayer(), path = pathLayer()
        var doc = document([text, path])
        doc.putTextOnPath(textID: text.id, pathID: path.id)
        doc.setTextPathStart(30, layerIDs: [text.id], atDocumentTimeMS: 0)
        #expect(doc.layer(id: text.id)?.text?.onPath?.startPercent == 30)
        #expect(doc.textPathStart(layerID: text.id, atDocumentTimeMS: 0) == 30)
        // Clamped to the range a person may set.
        doc.setTextPathStart(500, layerIDs: [text.id], atDocumentTimeMS: 0)
        #expect(doc.textPathStart(layerID: text.id, atDocumentTimeMS: 0) == 100)
    }

    @Test func startIsOnlyOfferedOnTextOnAPath() {
        let text = textLayer()
        #expect(MotionProperty.pathStart.current(of: text) == nil)
        #expect(document([text]).textPathStart(layerID: text.id, atDocumentTimeMS: 0) == nil)
    }

    @Test func aKeyedStartMovesTheWordsAlongOverTime() throws {
        let text = textLayer(), path = pathLayer()
        var placed = document([text, path])
        placed.putTextOnPath(textID: text.id, pathID: path.id)
        var layer = try #require(placed.layer(id: text.id))
        #expect(MotionProperty.pathStart.current(of: layer) == .number(0))
        layer.motions = [LayerMotion(property: .pathStart, from: .number(0), to: .number(50),
                                     timing: MotionTiming(startMS: 0, durationMS: 1000), curve: .linear,
                                     repeats: .once)]
        let halfway = layer.moved(toMotionTimeMS: 500, cycleMS: 1000)
        let start = try #require(halfway.text?.onPath?.startPercent)
        #expect(abs(start - 25) < 0.01)
        // The value reads back as a percent.
        #expect(MotionProperty.pathStart.format(.number(25)) == "25%")
    }
}
