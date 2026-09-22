import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import PhotonzRender
import Testing

/// **What plays is what leaves**, for a component placed on a recording
/// (`components-on-the-timeline-animated-the-way-ever`).
///
/// The claim this suite exists to check cannot be checked by reading code: a
/// badge you built in a design file, dropped on a recording, has to be in the
/// FILE — at the moments it is on screen and at no other, moving the way it
/// moves on the canvas, composited over the shot the way the panel says. So
/// every test here writes a real movie through the ordinary renderer and then
/// opens it again and looks at the pixels.
@Suite("A component placed on a recording reaches the file", .serialized)
struct ComponentOnTheTimelineExportTests {

    static let folder = TestTone.scratch()
    static let canvas = CGSize(width: 160, height: 120)

    /// The colour the recording under everything is: nothing else in these
    /// tests is green, so green means "the shot, with nothing over it".
    static let shotHex = "#00C000"

    static func rectangle(_ name: String, _ rect: CGRect, hex: String) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                     colorHex: hex,
                                                     start: .zero,
                                                     end: CGPoint(x: rect.width, y: rect.height),
                                                     fillColorHex: hex)),
              frame: rect)
    }

    /// A four second recording as one clip, and a two part badge made into a
    /// component off to one side of it, its original hidden so only the copy
    /// that gets placed is in the picture.
    static func recordingWithABadge() throws -> (document: PhotonzDocument, store: ImageStore,
                                                 componentID: UUID) {
        let store = ImageStore()
        let movie = MovieRef(pixelSize: canvas, durationMS: 4000)
        var clip = Layer(name: "Recording", content: .image(movie.frameRef(atSourceMS: 0)),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.movie = movie
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0, sourceLengthMS: 4000)
        var document = PhotonzDocument(canvasSize: canvas, layers: [clip])
        document.durationMS = 4000
        document.addLayer(rectangle("Dot", CGRect(x: 0, y: 0, width: 20, height: 20),
                                    hex: "#FF0000"))
        document.addLayer(rectangle("Bar", CGRect(x: 30, y: 0, width: 20, height: 20),
                                    hex: "#0000FF"))
        let parts = Set(document.layers.suffix(2).map(\.id))
        let grouped = document.groupLayers(ids: parts, name: "Badge")
        let group = try #require(grouped)
        let made = document.makeComponent(id: group.id)
        let componentID = try #require(made)
        document.updateLayer(id: group.id) { $0.isVisible = false }
        return (document, store, componentID)
    }

    /// The frames the app's own fetcher would have filed: every frame of the
    /// recording the one flat colour.
    static func fillFrames(_ document: PhotonzDocument, store: ImageStore, atMS ms: Int) throws {
        for request in document.movieFrames(atTimeMS: ms) {
            store.register(try #require(SolidImage.make(size: canvas, hex: shotHex)),
                           as: request.ref)
        }
    }

    /// Exactly what the app hands the writer: the document drawn at a moment,
    /// through the ordinary renderer.
    static func frames(_ document: PhotonzDocument,
                       store: ImageStore) -> @Sendable (Int) async -> CGImage? {
        { ms in
            try? fillFrames(document, store: store, atMS: ms)
            return DocumentRenderer().render(document.drawn(atTimeMS: ms), store: store)
        }
    }

    static func write(_ document: PhotonzDocument, store: ImageStore,
                      named name: String) async throws -> URL {
        let plan = DocumentVideoExport.plan(durationMS: document.documentDurationMS,
                                            canvasSize: document.canvasSize,
                                            format: .mp4, quality: .standard)
        let out = folder.appendingPathComponent(name)
        try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: out,
                                            frames: frames(document, store: store))
        return out
    }

    /// What the written file shows at one POINT of one frame, in the
    /// document's own top-left coordinates.
    static func colour(of url: URL, atSeconds seconds: Double,
                       at point: CGPoint) async throws -> (r: Int, g: Int, b: Int) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: seconds,
                                                         preferredTimescale: 600)).image
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(pixel.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                      bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        })
        // The frame drawn so that the point asked about is the one pixel the
        // context holds: no scaling, no interpolation, no averaging.
        context.interpolationQuality = .none
        context.draw(frame, in: CGRect(x: -point.x, y: point.y - CGFloat(frame.height) + 1,
                                       width: CGFloat(frame.width),
                                       height: CGFloat(frame.height)))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    static func isRed(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.r > 150 && c.g < 110 }
    static func isBlue(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.b > 150 && c.r < 110 }
    static func isShot(_ c: (r: Int, g: Int, b: Int)) -> Bool { c.g > 120 && c.r < 110 && c.b < 110 }

    /// Where a part of the placed copy sits on the canvas, in the document's
    /// coordinates: the middle of it, which is the pixel worth asking about.
    static func middle(of document: PhotonzDocument, copy: UUID, part: Int) throws -> CGPoint {
        let placed = try #require(document.layer(id: copy))
        let child = placed.children[part]
        return CGPoint(x: placed.frame.origin.x + child.frame.midX,
                       y: placed.frame.origin.y + child.frame.midY)
    }


    /// One copy placed at a moment, unwrapped: a mutating call cannot live
    /// inside `#require`.
    static func place(_ document: inout PhotonzDocument, _ componentID: UUID,
                      at point: CGPoint, atMS ms: Int) throws -> UUID {
        let placed = document.insertComponentInstance(of: componentID, at: point, atTimeMS: ms)
        return try #require(placed)
    }

    // MARK: - It is in the file, and only while it is on screen

    @Test("A component placed on a recording is in the file, at the moments it is on screen")
    func itIsInTheFileWhileItIsOnScreen() async throws {
        var (document, store, componentID) = try Self.recordingWithABadge()
        let placed = document.insertComponentInstance(of: componentID,
                                                      at: CGPoint(x: 80, y: 60), atTimeMS: 500)
        let copy = try #require(placed)
        let time = try #require(document.layer(id: copy)?.time)
        #expect(time.inMS == 500 && time.outMS == 3500)
        let dot = try Self.middle(of: document, copy: copy, part: 0)
        let out = try await Self.write(document, store: store, named: "component-in-time.mp4")
        // Before it arrives: the shot, with nothing over it.
        #expect(Self.isShot(try await Self.colour(of: out, atSeconds: 0.2, at: dot)))
        // While it is on: the badge, over the shot.
        #expect(Self.isRed(try await Self.colour(of: out, atSeconds: 1.5, at: dot)))
        // After it goes: the shot again.
        #expect(Self.isShot(try await Self.colour(of: out, atSeconds: 3.8, at: dot)))
    }

    // MARK: - It moves in the file, and its parts move out of phase

    @Test("Two parts of the placed component move out of phase in the file")
    func itsPartsMoveOutOfPhaseInTheFile() async throws {
        var (document, store, componentID) = try Self.recordingWithABadge()
        let main = try #require(document.mainComponent(componentID: componentID))
        let dotPart = try #require(main.children.first)
        let barPart = try #require(main.children.last)
        // Each part slides 40 points down, a second apart, in the component's
        // own clock: nought is the moment the copy arrives.
        func slide(_ layer: Layer, startMS: Int) -> LayerMotion {
            LayerMotion(property: .position, from: .point(layer.frame.origin),
                        to: .point(CGPoint(x: layer.frame.origin.x,
                                           y: layer.frame.origin.y + 40)),
                        timing: MotionTiming(startMS: startMS, durationMS: 400),
                        curve: .linear, repeats: .once)
        }
        document.updateLayer(id: dotPart.id) { $0.motions = [slide(dotPart, startMS: 0)] }
        document.updateLayer(id: barPart.id) { $0.motions = [slide(barPart, startMS: 1000)] }
        let copy = try Self.place(&document, componentID, at: CGPoint(x: 80, y: 40), atMS: 500)
        let dotHome = try Self.middle(of: document, copy: copy, part: 0)
        let barHome = try Self.middle(of: document, copy: copy, part: 1)
        let dotAway = CGPoint(x: dotHome.x, y: dotHome.y + 40)
        let barAway = CGPoint(x: barHome.x, y: barHome.y + 40)
        let out = try await Self.write(document, store: store, named: "component-out-of-phase.mp4")
        // A second after it arrives the first part has finished its move and
        // the second has not started: the whole test the animation model was
        // chosen against, read off the file.
        #expect(Self.isRed(try await Self.colour(of: out, atSeconds: 1.4, at: dotAway)))
        #expect(Self.isShot(try await Self.colour(of: out, atSeconds: 1.4, at: dotHome)))
        #expect(Self.isBlue(try await Self.colour(of: out, atSeconds: 1.4, at: barHome)))
        // ...and a second later the second part has moved too.
        #expect(Self.isBlue(try await Self.colour(of: out, atSeconds: 2.4, at: barAway)))
    }

    // MARK: - It composites over the shot under it

    @Test("A matte borrowed from the layer below cuts the placed component in the file")
    func aMatteReachesTheFile() async throws {
        var (document, store, componentID) = try Self.recordingWithABadge()
        let copy = try Self.place(&document, componentID, at: CGPoint(x: 80, y: 60), atMS: 0)
        let dot = try Self.middle(of: document, copy: copy, part: 0)
        let bar = try Self.middle(of: document, copy: copy, part: 1)
        // A small square directly under the badge, over the first part only:
        // the badge is allowed to be that square's shape and nothing else.
        var window = Self.rectangle("Window",
                                    CGRect(x: dot.x - 10, y: dot.y - 10, width: 20, height: 20),
                                    hex: "#FFFFFF")
        window.time = LayerTime(inMS: 0, outMS: 4000)
        let above = try #require(document.layers.firstIndex { $0.id == copy })
        document.layers.insert(window, at: above)
        document.updateLayer(id: copy) { $0.style.matte = .shape }
        let out = try await Self.write(document, store: store, named: "component-matte.mp4")
        // Inside the square the badge draws, and the square itself is spent as
        // the mask so it paints nothing white of its own.
        #expect(Self.isRed(try await Self.colour(of: out, atSeconds: 1.5, at: dot)))
        // ...and where the badge is but the square is not, the shot is
        // untouched: the second part of the badge has been cut away.
        #expect(Self.isShot(try await Self.colour(of: out, atSeconds: 1.5, at: bar)))
    }
}
