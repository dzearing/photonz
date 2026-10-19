import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// What an agent reads when it asks what is open: the document as plain
/// structured data, small enough to read in one go (`docs/design/agent-mcp.md`).
@Suite("Agent read: the document as structured data")
struct AgentDocumentReadTests {

    static let context = AgentDocumentRead.Context(id: "d1", title: "shot.png", file: "/tmp/shot.png",
                                                   playheadMS: 0, canUndo: true, canRedo: false)

    static func picture() -> PhotonzDocument {
        let background = Layer(name: "Background", content: .image(ImageRef(pixelSize: CGSize(width: 800, height: 600))),
                               frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        var title = Layer(name: "Title", content: .text(TextContent(string: "Hello there", fontName: "SF Pro",
                                                                    fontSize: 48, colorHex: "#FF0000",
                                                                    weight: .bold)),
                          frame: CGRect(x: 40.04, y: 50, width: 300, height: 60))
        title.style.opacity = 0.5
        var box = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 4,
                                                                            colorHex: "#00FF00")),
                        frame: CGRect(x: 100, y: 200, width: 120, height: 80))
        box.isVisible = false
        let group = Layer(name: "Group", content: .group(GroupContent(children: [box])),
                          frame: CGRect(x: 100, y: 200, width: 120, height: 80))
        return PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                               layers: [background, title, group], pixelScale: 2)
    }

    @Test("A picture reads as its canvas and its layers, top of the stack first, groups nested")
    func picture() throws {
        let read = AgentDocumentRead.make(Self.picture(), context: Self.context)
        #expect(read.kind == "picture")
        #expect(read.canvas == .init(width: 800, height: 600))
        #expect(read.pixelScale == 2)
        #expect(read.layers.map(\.name) == ["Group", "Title", "Background"])
        #expect(read.layers[0].children?.first?.name == "Box")
        #expect(read.layers[0].children?.first?.hidden == true)
        #expect(read.layers[0].children?.first?.shape?.shape == "rectangle")
        #expect(read.layers[0].children?.first?.shape?.stroke == "#00FF00")
        let title = read.layers[1]
        #expect(title.kind == "text")
        #expect(title.text?.string == "Hello there")
        #expect(title.text?.size == 48)
        #expect(title.text?.color == "#FF0000")
        #expect(title.text?.weight == "bold")
        #expect(title.opacity == 0.5)
        #expect(title.frame == .init(x: 40, y: 50, width: 300, height: 60))
        #expect(read.layers[2].kind == "image")
        #expect(read.tracks == nil)
        #expect(read.durationSeconds == nil)
        #expect(read.canUndo == true && read.canRedo == false)
    }

    @Test("Defaults are left out, so a plain layer is a few short lines")
    func defaultsLeftOut() throws {
        let read = AgentDocumentRead.make(Self.picture(), context: Self.context)
        let json = String(decoding: try read.encoded(), as: UTF8.self)
        #expect(!json.contains(#""hidden":false"#))
        #expect(!json.contains(#""locked":false"#))
        #expect(!json.contains(#""opacity":1"#))
        #expect(read.layers[2].opacity == nil)
        #expect(read.layers[2].hidden == nil)
    }

    @Test("Long text is cut, and a huge stack is counted instead of listed")
    func bounded() {
        var document = Self.picture()
        let long = String(repeating: "word ", count: 200)
        for i in 0..<500 {
            document.layers.append(Layer(name: "T\(i)", content: .text(TextContent(string: long)),
                                         frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        }
        let read = AgentDocumentRead.make(document, context: Self.context)
        #expect(read.layerCount == 504)
        #expect(read.layersNotListed == 504 - AgentDocumentRead.mostLayersListed)
        #expect((read.layers.first?.text?.string.count ?? 0) <= AgentDocumentRead.longestText + 1)
        #expect(read.layers.first?.text?.string.hasSuffix("…") == true)
    }

    static func video() -> (PhotonzDocument, Layer, Layer) {
        let movie = MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 20_000)
        func clip(_ name: String, at inMS: Int, length: Int) -> Layer {
            var layer = Layer(name: name, content: .image(movie.frameRef(atSourceMS: 0)),
                              frame: CGRect(origin: .zero, size: movie.pixelSize))
            layer.movie = movie
            layer.time = LayerTime(inMS: inMS, outMS: inMS + length, sourceInMS: 0, sourceLengthMS: 20_000)
            return layer
        }
        var first = clip("Case 1", at: 0, length: 10_000)
        var pieces = first.clipPieces ?? ClipPieces(single: first.time ?? LayerTime(inMS: 0, outMS: 10_000))
        _ = pieces.split(atMS: 4000)
        _ = pieces.setTransition(ClipTransition(kind: .dissolve, lengthMS: 500), atCut: 1)
        first.setClipPieces(pieces)
        let second = clip("Case 2", at: 10_000, length: 5000)
        var document = PhotonzDocument(canvasSize: movie.pixelSize, layers: [first, second])
        document.durationMS = 15_000
        _ = document.addMarker(atMS: 2500)
        return (document, first, second)
    }

    @Test("A video reads as its length, tracks with clips in and out, and its cuts with their transitions")
    func video() throws {
        let (document, first, second) = Self.video()
        var context = Self.context
        context.playheadMS = 10_000
        let read = AgentDocumentRead.make(document, context: context)
        #expect(read.kind == "video")
        #expect(read.durationSeconds == 15)
        #expect(read.playheadSeconds == 10)
        let clips = (read.tracks ?? []).flatMap(\.clips)
        #expect(Set(clips.map(\.name)) == ["Case 1", "Case 2"])
        let one = try #require(clips.first { $0.layer == first.id.uuidString })
        #expect(one.inSeconds == 0 && one.outSeconds == 10)
        #expect(one.pieces == 2)
        let two = try #require(clips.first { $0.layer == second.id.uuidString })
        #expect(two.inSeconds == 10 && two.outSeconds == 15)
        #expect(read.tracks?.first?.kind == "video")
        let dissolve = try #require(read.cuts?.first { $0.transition != nil })
        #expect(dissolve.atSeconds == 4)
        #expect(dissolve.transition?.kind == "dissolve")
        #expect(dissolve.transition?.seconds == 0.5)
        #expect(read.markers == [2.5])
        let layer = try #require(read.layers.first { $0.id == first.id.uuidString })
        #expect(layer.time == .init(inSeconds: 0, outSeconds: 10))
        #expect(layer.kind == "clip")
    }
}

/// The grid of frames an agent asks for to see a stretch of video at a glance.
@Suite("Agent contact sheet: which frames and where they go")
struct AgentContactSheetTests {

    @Test("Frames are spread evenly from the first moment to the last frame of the range")
    func times() {
        #expect(AgentContactSheet.times(fromMS: 0, toMS: 10_000, count: 5) == [0, 2492, 4984, 7475, 9967])
        #expect(AgentContactSheet.times(fromMS: 2000, toMS: 8000, count: 1) == [2000])
        #expect(AgentContactSheet.times(fromMS: 5000, toMS: 5000, count: 4) == [5000])
    }

    @Test("Cells keep the picture's shape, leave room for a time label, and the sheet fits them")
    func layout() {
        let layout = AgentContactSheet.layout(count: 7, columns: nil, cellWidth: 320,
                                              pictureSize: CGSize(width: 1920, height: 1080))
        #expect(layout.columns == 3)
        #expect(layout.rows == 3)
        #expect(layout.pictures.count == 7)
        #expect(layout.pictures[0].size == CGSize(width: 320, height: 180))
        #expect(layout.labels[0].minY == layout.pictures[0].maxY)
        let last = layout.pictures[6]
        #expect(last.minX == layout.pictures[0].minX)
        #expect(layout.size.width >= (layout.pictures.map(\.maxX).max() ?? 0))
        #expect(layout.size.height >= (layout.labels.map(\.maxY).max() ?? 0))
    }

    @Test("Asked for columns, it uses them, never more than there are frames")
    func columns() {
        #expect(AgentContactSheet.layout(count: 6, columns: 2, cellWidth: 200,
                                         pictureSize: CGSize(width: 100, height: 100)).columns == 2)
        #expect(AgentContactSheet.layout(count: 2, columns: 6, cellWidth: 200,
                                         pictureSize: CGSize(width: 100, height: 100)).columns == 2)
    }

    @Test("A time label reads like a timecode a person would say")
    func labels() {
        #expect(AgentContactSheet.label(ms: 0) == "0:00.0")
        #expect(AgentContactSheet.label(ms: 9967) == "0:09.9")
        #expect(AgentContactSheet.label(ms: 75_500) == "1:15.5")
    }
}
