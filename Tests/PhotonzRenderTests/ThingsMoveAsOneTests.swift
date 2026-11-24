import CoreGraphics
import Foundation
import PhotonzCore
import Testing
@testable import PhotonzRender

/// Everything else that moves in a video, measured the same way the title is:
/// each mark's centre follows a straight line in what the motion is doing.
@Suite("Things that scale, drift and turn in a video move as one piece")
struct ThingsMoveAsOneTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static func black() -> Layer {
        Layer(name: "Black", content: .annotation(
            AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#000000", start: .zero,
                              end: CGPoint(x: canvas.width, y: canvas.height), fillColorHex: "#000000")),
              frame: CGRect(origin: .zero, size: canvas))
    }

    static func title(_ size: CGFloat = 80, x: CGFloat = 600, y: CGFloat = 480, string: String = "Hnmow",
                      font: String = "SF Pro") -> Layer {
        var words = TextContent(string: string, fontName: font, fontSize: size, colorHex: "#FFFFFF",
                                weight: .semibold, alignment: .center)
        words.tracking = 0.3
        let box = TextRasterizer.naturalSize(words)
        var layer = Layer(name: "Title", content: .text(words),
                          frame: CGRect(x: x, y: y, width: box.width, height: box.height))
        layer.style.shadows = []
        return layer
    }

    static func scaling(_ from: Double, _ to: Double) -> LayerMotion {
        LayerMotion(property: .scale, from: .number(from), to: .number(to),
                    timing: MotionTiming(startMS: 0, durationMS: 1000), curve: .linear, repeats: .once)
    }

    /// A video document of `layers` over black, all of it on screen.
    static func document(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: canvas, layers: [black()] + layers)
        doc.durationMS = 2000
        return doc
    }

    /// The marks' worst departure from a straight line in the progress of the
    /// motion, and how far a whole frame ever steps backwards.
    static func worst(_ doc: PhotonzDocument, frames: Int = 16, store: ImageStore = ImageStore(),
                      scale: CGFloat = 1, along: (Double) -> Double = { $0 }) throws -> (off: Double, marks: Int) {
        let renderer = DocumentRenderer(compositing: .sRGB)
        var at: [Double] = [], found: [[GlyphSteadiness.Letter]] = []
        for i in 0...frames {
            let ms = i * 1000 / frames
            let image = try #require(renderer.render(doc.drawn(atTimeMS: ms), store: store, scale: scale))
            at.append(along(Double(ms) / 1000))
            found.append(GlyphSteadiness.letters(image))
        }
        let marks = found[0].count
        guard found.allSatisfy({ $0.count == marks }), marks > 0 else { return (.infinity, 0) }
        var off = 0.0
        for mark in 0..<marks {
            off = max(off, GlyphSteadiness.offLine(found.map { $0[mark].x }, against: at))
            off = max(off, GlyphSteadiness.offLine(found.map { $0[mark].y }, against: at))
        }
        return (off, marks)
    }

    /// How far any mark's place against the others departs from its place in
    /// them over the whole move, with the whole's own scale and shift taken
    /// out of every frame: what is left is a mark slipping on its own.
    static func outOfShape(_ doc: PhotonzDocument, frames: Int = 16, store: ImageStore = ImageStore()) throws -> Double {
        let renderer = DocumentRenderer(compositing: .sRGB)
        var found: [[GlyphSteadiness.Letter]] = []
        for i in 0...frames {
            found.append(GlyphSteadiness.letters(try #require(
                renderer.render(doc.drawn(atTimeMS: i * 1000 / frames), store: store, scale: 1))))
        }
        let n = Double(found[0].count)
        var residuals: [[Double]] = []
        for frame in found {
            let rx = found[frames / 2].map(\.x), ry = found[frames / 2].map(\.y)
            let fx = frame.map(\.x), fy = frame.map(\.y)
            let mrx = rx.reduce(0, +) / n, mry = ry.reduce(0, +) / n
            let mfx = fx.reduce(0, +) / n, mfy = fy.reduce(0, +) / n
            var top = 0.0, bottom = 0.0
            for i in frame.indices {
                top += (rx[i] - mrx) * (fx[i] - mfx) + (ry[i] - mry) * (fy[i] - mfy)
                bottom += (rx[i] - mrx) * (rx[i] - mrx) + (ry[i] - mry) * (ry[i] - mry)
            }
            let s = top / bottom
            var off: [Double] = []
            for i in frame.indices {
                let dx: Double = fx[i] - mfx - s * (rx[i] - mrx)
                let dy: Double = fy[i] - mfy - s * (ry[i] - mry)
                off.append(dx); off.append(dy)
            }
            residuals.append(off)
        }
        var worst = 0.0
        for mark in residuals[0].indices {
            let track = residuals.map { $0[mark] }
            worst = max(worst, GlyphSteadiness.offLine(track, against: track.indices.map(Double.init)))
        }
        return worst
    }

    static func report(_ name: String, _ got: (off: Double, marks: Int)) {
        print("MOVES \(name): off \(String(format: "%.3f", got.off)) marks \(got.marks)")
    }

    @Test func wordsInAGroupThatScales() throws {
        var a = Self.title(80, x: 20, y: 10), b = Self.title(34, x: 120.5, y: 160.25)
        a.name = "a"; b.name = "b"
        for child in [a, b] {
            var group = Layer(name: "Group", content: .group(GroupContent(children: [child])),
                              frame: CGRect(x: 500, y: 400, width: 700, height: 250))
            group.motions = [Self.scaling(50, 100)]
            let got = try Self.worst(Self.document([group]))
            Self.report("group scale \(child.name)", got)
            #expect(got.marks == 5)
            #expect(got.off < 0.1)
        }
    }

    @Test func wordsThatDrift() throws {
        var layer = Self.title()
        layer.motions = [LayerMotion(property: .position, from: .point(CGPoint(x: 600, y: 480)),
                                     to: .point(CGPoint(x: 620, y: 487)),
                                     timing: MotionTiming(startMS: 0, durationMS: 1000), curve: .linear, repeats: .once)]
        let got = try Self.worst(Self.document([layer]))
        Self.report("drift 20px", got)
        #expect(got.off < 0.1)
    }

    @Test func wordsWhoseTextSizeGrows() throws {
        var layer = Self.title()
        layer.motions = [LayerMotion(property: .textSize, from: .number(40), to: .number(80),
                                     timing: MotionTiming(startMS: 0, durationMS: 1000), curve: .linear, repeats: .once)]
        let got = try Self.worst(Self.document([layer]))
        Self.report("text size", got)
        #expect(got.off < 0.1)
    }

    @Test func wordsUnderACameraThatPushesIn() throws {
        var doc = Self.document([Self.title()])
        var camera = SceneCamera()
        camera.motions = [LayerMotion(property: .cameraDepth, from: .number(0), to: .number(300),
                                      timing: MotionTiming(startMS: 0, durationMS: 1000), curve: .linear, repeats: .once)]
        doc.camera = camera
        // Closing on the canvas at a steady speed, things grow as one over
        // the distance left.
        let eye = doc.projection.eyeDistance
        let got = try Self.worst(doc, along: { 1 / (eye - 300 * $0) })
        Self.report("camera push", got)
        let shaped = try Self.outOfShape(doc)
        Self.report("camera push, letters against the word", (shaped, got.marks))
        #expect(got.off < 0.1)
    }

    /// Dots across a picture, so its scale is read the way the letters are.
    static func dots(width: Int = 640, height: Int = 320, near: Bool = false) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        for i in 0..<6 {
            context.fillEllipse(in: CGRect(x: 50 + i * (near ? 130 : 100),
                                           y: near ? height - 400 + (i * 53) % 180 : 60 + (i * 53) % 180,
                                           width: 24, height: 30))
        }
        return context.makeImage()!
    }

    @Test func aPictureThatScales() throws {
        let store = ImageStore()
        for (from, to) in [(50.0, 100.0), (100.0, 102.0), (100.0, 160.0)] {
            let ref = store.register(Self.dots())
            var layer = Layer(name: "Picture", content: .image(ref), frame: CGRect(x: 640, y: 380, width: 640, height: 320))
            layer.motions = [Self.scaling(from, to)]
            let got = try Self.worst(Self.document([layer]), store: store)
            Self.report("picture \(from)->\(to)", got)
            #expect(got.off < 0.1)
        }
    }

    static func shape(_ kind: AnnotationShape, in frame: CGRect, stroke: CGFloat = 0, fill: String? = "#FFFFFF") -> Layer {
        Layer(name: "Shape", content: .annotation(
            AnnotationContent(shape: kind, strokeWidth: stroke, colorHex: "#FFFFFF", start: .zero,
                              end: CGPoint(x: frame.width, y: frame.height), fillColorHex: fill)), frame: frame)
    }

    @Test func shapesThatScale() throws {
        for (from, to) in [(50.0, 100.0), (100.0, 102.0)] {
            for (name, layer) in [("box", Self.shape(.rectangle, in: CGRect(x: 700, y: 400, width: 333, height: 187))),
                                  ("oval", Self.shape(.ellipse, in: CGRect(x: 700, y: 400, width: 333, height: 187))),
                                  ("outline", Self.shape(.rectangle, in: CGRect(x: 700, y: 400, width: 333, height: 187),
                                                         stroke: 3, fill: nil))] {
                // Off centre in a group, so its own corner has to travel.
                var group = Layer(name: "Group", content: .group(GroupContent(children: [{
                    var l = layer; l.frame.origin = CGPoint(x: 30, y: 20); return l }()])),
                                  frame: CGRect(x: 500, y: 300, width: 700, height: 250))
                group.motions = [Self.scaling(from, to)]
                let got = try Self.worst(Self.document([group]))
                Self.report("\(name) \(from)->\(to)", got)
                #expect(got.off < 0.1)
            }
        }
    }

    @Test func aZoomOnARecording() throws {
        let store = ImageStore()
        for size in [CGSize(width: 1920, height: 1080), CGSize(width: 2880, height: 1620)] {
            let ref = store.register(Self.dots(width: Int(size.width), height: Int(size.height), near: true))
            let zoom = ClipZoom(startMS: 0, endMS: 4000, easeInMS: 1000, scale: 2,
                                center: CGPoint(x: 0.25, y: 0.25))
            let renderer = DocumentRenderer(compositing: .sRGB)
            var tracks: [[GlyphSteadiness.Letter]] = [], windows: [CGRect] = []
            for i in 1..<16 {
                var layer = Layer(name: "Clip", content: .image(ref), frame: CGRect(origin: .zero, size: Self.canvas))
                let window = try #require(zoom.window(atMS: i * 1000 / 16))
                layer.zoomWindow = window
                let doc = Self.document([layer])
                let image = try #require(renderer.render(doc, store: store, scale: 1))
                tracks.append(GlyphSteadiness.letters(image)); windows.append(window)
            }
            // Each dot belongs at (its place - the window's corner) over the
            // window's size: solved for one place, the rest is departure.
            var worst = 0.0
            let marks = tracks.map(\.count).min() ?? 0
            for mark in 0..<marks {
                let places = zip(tracks, windows).map { t, w in
                    (Double(w.minX) + t[mark].x / 1920 * Double(w.width), Double(w.width)) }
                let mean = places.map(\.0).reduce(0, +) / Double(places.count)
                for (place, width) in places { worst = max(worst, abs(place - mean) / width * 1920) }
            }
            Self.report("zoom on a recording \(Int(size.width))", (worst, marks))
            #expect(worst < 0.1)
        }
    }

    /// The words of every built-in title that grows or shrinks any, followed
    /// alone on black through its whole way in and out.
    @Test func theBuiltInTitlesThatGrow() throws {
        func only(_ layers: [Layer], words: UUID) -> [Layer] {
            layers.compactMap { layer in
                var layer = layer
                layer.style.opacity = 1
                layer.style.effects = []
                layer.turn3D = nil
                layer.motionSmear = nil
                if var group = layer.group {
                    group.children = only(group.children, words: words)
                    group.background = nil
                    layer.content = .group(group)
                    return group.children.isEmpty ? nil : layer
                }
                guard layer.id == words, var text = layer.text else { return nil }
                text.reveal = nil
                text.fill = nil
                text.plateHex = nil
                text.colorHex = "#FFFFFF"
                layer.content = .text(text)
                return layer
            }
        }
        var read = 0
        for preset in BuiltInTitle.allCases {
            var doc = PhotonzDocument(canvasSize: Self.canvas)
            doc.durationMS = 1000
            doc.insertTitle(preset, atTimeMS: 0)
            let moments = Array(stride(from: 0, to: doc.documentDurationMS, by: 66))
            var growing: [UUID: [Int]] = [:]
            for ms in moments {
                for layer in doc.drawn(atTimeMS: ms).allLayers where (layer.text?.drawnScale ?? 1) != 1 {
                    growing[layer.id, default: []].append(ms)
                }
            }
            for (id, times) in growing.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
                let renderer = DocumentRenderer(compositing: .sRGB)
                var pictures: [[LetterSteadiness.Mark]] = []
                for ms in times {
                    var shown = doc.drawn(atTimeMS: ms)
                    shown.layers = [Self.black()] + only(shown.layers, words: id)
                    shown.camera = nil
                    guard let image = renderer.render(shown, store: ImageStore(), scale: 1) else { continue }
                    pictures.append(GlyphSteadiness.letters(image))
                }
                // Only the pictures whose letters stand apart.
                let count = pictures.map(\.count).max() ?? 0
                let apart = pictures.filter { $0.count == count && count > 1 }
                guard apart.count >= 4 else { continue }
                let slip = LetterSteadiness(apart).slip
                read += 1
                print("MOVES title \(preset.name): slip \(String(format: "%.3f", slip)) over \(apart.count) of \(pictures.count)")
                #expect(slip < 0.1, "\(preset.name)")
            }
        }
        #expect(read >= 1)
    }

    @Test func wordsAndPicturesThatTurnSlowly() throws {
        let store = ImageStore()
        var words = Self.title()
        words.frame.origin = CGPoint(x: 600, y: 480)
        let picture = Layer(name: "Picture", content: .image(store.register(Self.dots())),
                            frame: CGRect(x: 640, y: 380, width: 640, height: 320))
        for var layer in [words, picture] {
            layer.motions = [LayerMotion(property: .rotation, from: .number(0.4), to: .number(3.4),
                                         timing: MotionTiming(startMS: 0, durationMS: 1000), curve: .linear,
                                         repeats: .once)]
            let doc = Self.document([layer])
            let renderer = DocumentRenderer(compositing: .sRGB)
            let middle = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
            // Every mark turned back by what the frame turned it, which is
            // one place if it turned as a solid thing does.
            var back: [[CGPoint]] = []
            for i in 0...16 {
                let ms = i * 1000 / 16
                let angle = -(0.4 + 3 * Double(ms) / 1000) * .pi / 180
                let image = try #require(renderer.render(doc.drawn(atTimeMS: ms), store: store, scale: 1))
                back.append(GlyphSteadiness.letters(image).map { mark in
                    let dx = mark.x - middle.x, dy = mark.y - middle.y
                    return CGPoint(x: dx * cos(angle) - dy * sin(angle), y: dx * sin(angle) + dy * cos(angle))
                })
            }
            let marks = back[0].count
            #expect(marks >= 5 && back.allSatisfy { $0.count == marks })
            var worst = 0.0
            for mark in 0..<marks {
                let x = back.map { Double($0[mark].x) }, y = back.map { Double($0[mark].y) }
                let mx = x.reduce(0, +) / Double(x.count), my = y.reduce(0, +) / Double(y.count)
                for (a, b) in zip(x, y) { worst = max(worst, abs(a - mx), abs(b - my)) }
            }
            Self.report("\(layer.name) turning", (worst, marks))
            #expect(worst < 0.1)
        }
    }
}
