import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PhotonzCore
@testable import PhotonzMedia
@testable import PhotonzRender
import Testing
import UniformTypeIdentifiers

/// The reel for the user to judge (task `3d-transitions-and-title-entrances-flip-cube-swi`):
/// every transition and title entrance that turns in depth, filmed by the real
/// renderer as a three second MP4 and GIF, a contact sheet of each at five
/// moments, and the measured numbers of the visible motion bar.
///
/// Not part of the suite: it writes files the audit carries. Run it with
///
///     PHOTONZ_REEL=1 PHOTONZ_REEL_DIR=queue/audits Scripts/test.sh --filter DepthReelStudy
@Suite("A reel of the moves that turn in depth", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_REEL"] == "1"))
struct DepthReelStudyTests {

    static let canvas = CGSize(width: 1280, height: 720)
    static let lengthMS = 3000
    /// Where each move sits in its three seconds.
    static let moveStartMS = 1000

    struct Item {
        let slug: String
        let name: String
        let moveMS: Int
        let frame: @Sendable (Int) -> PhotonzDocument
    }

    // MARK: - Two stand-in shots

    /// A screen recording's worth of picture: a backdrop, a window with a
    /// title bar and a few lines, and the clip's name on it.
    static func shot(_ name: String, colours: (CGColor, CGColor), accent: CGColor) -> CGImage? {
        let w = Int(canvas.width), h = Int(canvas.height)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: [colours.0, colours.1] as CFArray, locations: [0, 1])
        else { return nil }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: h), options: [])
        let window = CGRect(x: 160, y: 110, width: 960, height: 500)
        context.setFillColor(CGColor(gray: 0.97, alpha: 1))
        context.addPath(CGPath(roundedRect: window, cornerWidth: 18, cornerHeight: 18, transform: nil))
        context.fillPath()
        context.setFillColor(CGColor(gray: 0.88, alpha: 1))
        context.fill(CGRect(x: window.minX, y: window.maxY - 44, width: window.width, height: 44))
        for (i, width) in [700.0, 520, 760, 610].enumerated() {
            context.setFillColor(i == 2 ? accent : CGColor(gray: 0.78, alpha: 1))
            context.fill(CGRect(x: window.minX + 48, y: window.maxY - 120 - Double(i) * 70, width: width, height: 26))
        }
        draw(name, at: CGPoint(x: 60, y: 50), size: 44, in: context, colour: CGColor(gray: 1, alpha: 1))
        return context.makeImage()
    }

    static func draw(_ string: String, at point: CGPoint, size: CGFloat, in context: CGContext, colour: CGColor) {
        let font = CTFontCreateWithName("SF Pro Display Bold" as CFString, size, nil)
        let attributed = NSAttributedString(string: string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    static func picture(_ image: CGImage, _ store: ImageStore, name: String) -> Layer {
        Layer(name: name, content: .image(store.register(image)), frame: CGRect(origin: .zero, size: canvas))
    }

    static func ground() -> Layer {
        Layer(name: "Ground", content: .annotation(AnnotationContent(
            shape: .rectangle, strokeWidth: 0, colorHex: "#05060A", start: .zero,
            end: CGPoint(x: canvas.width, y: canvas.height), fillColorHex: "#05060A")),
              frame: CGRect(origin: .zero, size: canvas))
    }

    // MARK: - The items

    static func transitionItems(store: ImageStore) throws -> [Item] {
        let a = picture(try #require(shot("clip-01", colours: (CGColor(srgbRed: 0.07, green: 0.76, blue: 0.91, alpha: 1),
                                                                 CGColor(srgbRed: 0.49, green: 0.30, blue: 1, alpha: 1)),
                                          accent: CGColor(srgbRed: 0.49, green: 0.55, blue: 1, alpha: 1))),
                        store, name: "clip-01")
        let b = picture(try #require(shot("clip-02", colours: (CGColor(srgbRed: 1, green: 0.62, blue: 0.36, alpha: 1),
                                                                 CGColor(srgbRed: 1, green: 0.36, blue: 0.56, alpha: 1)),
                                          accent: CGColor(srgbRed: 1, green: 0.45, blue: 0.3, alpha: 1))),
                        store, name: "clip-02")
        return ClipTransitionKind.inDepth.map { kind in
            let transition = ClipTransition(kind: kind)
            return Item(slug: "transition-\(kind.rawValue)", name: kind.title, moveMS: transition.lengthMS) { ms in
                let t = Double(ms - moveStartMS) / Double(transition.lengthMS)
                let layers: [Layer]
                if t <= 0 {
                    layers = [a]
                } else if t >= 1 {
                    layers = [b]
                } else {
                    layers = Layer.depthTransitionDrawn(kind, direction: transition.direction,
                                                        progress: transition.curve.value(at: t),
                                                        outgoing: a, incoming: b)
                }
                return PhotonzDocument(canvasSize: canvas, layers: [ground()] + layers)
            }
        }
    }

    /// A title over the dark frame: "Ship it faster." coming in word by word,
    /// or letter by letter.
    static func entranceItems(by unit: TextRevealUnit = .word, fontSize: CGFloat = 112) -> [Item] {
        TitleBuildKind.inDepth.map { kind in
            let build = TitleBuild(kind, delayMS: moveStartMS, lengthMS: unit == .letter ? 700 : 900, by: unit,
                                   staggerMS: unit == .letter ? 45 : 140)
            var doc = PhotonzDocument(canvasSize: canvas)
            var back = Layer(name: "Back", content: .annotation(AnnotationContent(
                shape: .rectangle, strokeWidth: 0, colorHex: "#141826", start: .zero,
                end: CGPoint(x: canvas.width, y: canvas.height), fillColorHex: "#141826")),
                frame: CGRect(origin: .zero, size: canvas))
            back.time = LayerTime(inMS: 0, outMS: lengthMS, sourceInMS: 0, sourceLengthMS: lengthMS)
            let words = Layer(name: "Words", content: .text(TextContent(string: "Ship it faster.", fontSize: fontSize,
                                                                         colorHex: "#FFFFFF", weight: .bold)),
                              frame: CGRect(x: 140, y: 360 - fontSize * 0.72, width: 1000, height: fontSize * 1.44))
            var title = Layer(name: "Title", content: .group(GroupContent(children: [words])), frame: .zero)
            title.time = LayerTime(inMS: 0, outMS: lengthMS * 2)
            doc.layers = [back]
            doc.addLayer(title)
            doc.durationMS = lengthMS
            _ = doc.applyTitleDesign(TitleDesign(parts: [TitlePart(path: "Words", role: .headline, in: build)]),
                                     layerID: title.id)
            let reveal = doc.layer(id: title.id).flatMap { TitleDesign.find("Words", in: $0) }?.text?.reveal
            let count = unit == .letter ? 13 : 3
            let move = reveal.map { $0.lengthMS(count: count) } ?? 900
            let finished = doc
            return Item(slug: "entrance-\(kind.rawValue)\(unit == .letter ? "-by-letter" : "")",
                        name: "\(kind.title), by \(unit)", moveMS: move) { ms in
                finished.drawn(atTimeMS: ms)
            }
        }
    }

    // MARK: - The numbers

    static func numbers() -> [[String: Any]] {
        let size = CGSize(width: 1920, height: 1080)
        var rows: [[String: Any]] = []
        for kind in ClipTransitionKind.inDepth {
            let transition = ClipTransition(kind: kind)
            let length = Double(transition.lengthMS)
            // The most turned picture actually on screen at the midpoint:
            // drawn, not faded out, and not showing a back it hides.
            let mid = DepthTransition.quads(kind, direction: .left, progress: transition.curve.value(at: 0.5),
                                            size: size)
            let angle = mid.filter { $0.quad != nil && $0.part.opacity > 0.05 }
                .map { max(abs($0.part.turn.rotationX), abs($0.part.turn.rotationY)) }
                .map { $0 > 90 ? 180 - $0 : $0 }.max() ?? 0
            func quads(at t: Double) -> [[CGPoint]?] {
                DepthTransition.quads(kind, direction: .left, progress: transition.curve.value(at: t), size: size)
                    .map(\.quad)
            }
            var moved: Double = 0
            for (x, y) in zip(quads(at: (length / 2 - 50) / length), quads(at: (length / 2 + 50) / length)) {
                if let x, let y { for (p, q) in zip(x, y) { moved = max(moved, Double(hypot(p.x - q.x, p.y - q.y))) } }
            }
            rows.append(["move": kind.title, "kind": "transition", "lengthMS": transition.lengthMS,
                         "curve": transition.curve.title, "midpointAngleDegrees": (angle * 10).rounded() / 10,
                         "cornerTravelIn100msPoints": moved.rounded()])
        }
        for kind in TitleBuildKind.inDepth {
            let build = TitleBuild(kind, delayMS: 0, lengthMS: 600)
            let reveal = TextReveal(style: { switch kind {
            case .swingIn: .swingIn
            case .flipUp: .flipUp
            case .flyInFromDepth: .flyInFromDepth
            default: .tiltSettle
            } }(), unit: .word, lengthMS: 600)
            let pose = reveal.pose(rank: 0, atElapsedMS: 300)
            let later = reveal.pose(rank: 0, atElapsedMS: 350)
            let earlier = reveal.pose(rank: 0, atElapsedMS: 250)
            rows.append(["move": kind.title, "kind": "title entrance", "lengthMS": 600,
                         "curve": build.curve.title,
                         "midpointAngleDegrees": (max(abs(pose.turnX), abs(pose.turnY)) * 10).rounded() / 10,
                         "angleChangeIn100msDegrees": (abs(max(abs(later.turnX), abs(later.turnY))
                                                           - max(abs(earlier.turnX), abs(earlier.turnY))) * 10)
                             .rounded() / 10])
        }
        return rows
    }

    // MARK: - Filming

    @Test("Film every move, write the contact sheet and the numbers")
    func film() async throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PHOTONZ_REEL_DIR"]
                            ?? FileManager.default.temporaryDirectory.path)
        let prefix = "2026-10-11-depth-reel"
        let store = ImageStore()
        let items = try Self.transitionItems(store: store) + Self.entranceItems()
        var sheetRows: [(String, [CGImage])] = []
        for item in items {
            let mp4 = directory.appendingPathComponent("\(prefix)-\(item.slug).mp4")
            let gif = directory.appendingPathComponent("\(prefix)-\(item.slug).gif")
            try? FileManager.default.removeItem(at: mp4)
            try? FileManager.default.removeItem(at: gif)
            let frame = item.frame
            let moviePlan = DocumentVideoExport.plan(durationMS: Self.lengthMS, canvasSize: Self.canvas,
                                                     format: .mp4, quality: .high)
            try await DocumentMovieWriter.write(plan: moviePlan, mix: [], soundURLs: [:], to: mp4,
                                                frames: { ms in DocumentRenderer().render(frame(ms), store: store) })
            let gifPlan = DocumentVideoExport.plan(durationMS: Self.lengthMS, canvasSize: Self.canvas,
                                                   format: .gif, quality: .small)
            try await DocumentMovieWriter.writeAnimated(plan: gifPlan, format: .gif, to: gif,
                                                        frames: { ms in
                                                            DocumentRenderer().render(frame(ms), store: store)
                                                        })
            let stills = [0.0, 0.25, 0.5, 0.75, 1.0].compactMap { share -> CGImage? in
                let ms = Self.moveStartMS + Int(Double(item.moveMS) * share) - (share == 1 ? 1 : 0)
                return DocumentRenderer().render(frame(min(ms, Self.lengthMS - 1)), store: store)
            }
            sheetRows.append((item.name, stills))
            print("[reel] \(item.name): \(mp4.lastPathComponent), \(gif.lastPathComponent)")
        }
        let sheet = try #require(Self.contactSheet(sheetRows))
        let sheetURL = directory.appendingPathComponent("\(prefix)-contact.png")
        let destination = try #require(CGImageDestinationCreateWithURL(sheetURL as CFURL,
                                                                       UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, sheet, nil)
        #expect(CGImageDestinationFinalize(destination))
        let numbers = try JSONSerialization.data(withJSONObject: Self.numbers(), options: [.prettyPrinted, .sortedKeys])
        try numbers.write(to: directory.appendingPathComponent("\(prefix)-numbers.json"))
        print("[reel] contact sheet \(sheetURL.path)")
    }

    /// The near and far edges of the first word or letter half way through its
    /// own arrival, drawn through the reveal compositor at the 1080p
    /// document camera (task `text-that-swings-flips-or-flies-in-from-depth-is`).
    static func textNumbers() throws -> [[String: Any]] {
        let eye = Projection3D(camera: nil, canvas: CGSize(width: 1920, height: 1080)).eyeDistance
        var rows: [[String: Any]] = []
        for unit in [TextRevealUnit.word, .letter] {
            let pieces = try #require(TextRasterizer.revealPieces(
                TextContent(string: "Ship it faster.", fontSize: 112, colorHex: "#FFFFFF", weight: .bold),
                size: CGSize(width: 1000, height: 160), unit: unit))
            let piece = try #require(pieces.pieces.first)
            for kind in TitleBuildKind.inDepth {
                let style: TextRevealStyle = switch kind {
                case .swingIn: .swingIn
                case .flipUp: .flipUp
                case .flyInFromDepth: .flyInFromDepth
                default: .tiltSettle
                }
                let reveal = TextReveal(style: style, unit: unit)
                let mid = reveal.lengthMS / 2
                func corners(_ ms: Int) -> [CGPoint]? {
                    let pose = reveal.pose(rank: 0, atElapsedMS: ms)
                    return TextRevealCompositor.turnedQuad(piece, pose: pose, em: pieces.emPixels,
                                                           height: pieces.pixelSize.height, eyeDistance: eye,
                                                           ignoringBack: true)
                }
                let pose = reveal.pose(rank: 0, atElapsedMS: mid)
                let quad = try #require(corners(mid))
                func length(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x - b.x, a.y - b.y)) }
                // The line box inside the padded picture, mapped the same way.
                let h = pieces.pixelSize.height
                let rect = CGRect(x: piece.rect.minX, y: h - piece.rect.maxY, width: piece.rect.width,
                                  height: piece.rect.height)
                let map = try #require(Homography(box: rect, to: quad.map { CGPoint(x: $0.x, y: h - $0.y) }))
                let b = CGRect(x: piece.box.minX, y: h - piece.box.maxY, width: piece.box.width,
                               height: piece.box.height)
                let box = try [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                               CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)]
                    .map { try #require(map.apply($0)) }
                let swings = abs(pose.turnY) > abs(pose.turnX)
                let (one, two) = swings ? (length(box[0], box[3]), length(box[1], box[2]))
                    : (length(box[0], box[1]), length(box[3], box[2]))
                var moved = 0.0
                if let a = corners(mid - 50), let z = corners(mid + 50) {
                    moved = zip(a, z).map { length($0, $1) }.max() ?? 0
                }
                rows.append(["move": kind.title, "by": "\(unit)", "lengthMS": reveal.lengthMS,
                             "curve": reveal.curve.title, "startAngleDegrees": reveal.amount,
                             "midpointAngleDegrees": (max(abs(pose.turnX), abs(pose.turnY)) * 10).rounded() / 10,
                             "midpointNearToFarEdges": (max(one, two) / min(one, two) * 100).rounded() / 100,
                             "edgesMeasured": swings ? "left and right" : "top and bottom",
                             "cornerTravelIn100msPixels": moved.rounded()])
            }
        }
        return rows
    }

    @Test("Film the text entrances by word and by letter beside the clip Flip")
    func filmText() async throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PHOTONZ_REEL_DIR"]
                            ?? FileManager.default.temporaryDirectory.path)
        let prefix = "2026-10-11-text-depth"
        let store = ImageStore()
        let flip = try Self.transitionItems(store: store).filter { $0.slug == "transition-flip" }
        let items = flip + Self.entranceItems(by: .word, fontSize: 150) + Self.entranceItems(by: .letter, fontSize: 150)
        var sheetRows: [(String, [CGImage])] = []
        for item in items {
            let frame = item.frame
            if item.slug != "transition-flip" {
                let mp4 = directory.appendingPathComponent("\(prefix)-\(item.slug).mp4")
                let gif = directory.appendingPathComponent("\(prefix)-\(item.slug).gif")
                try? FileManager.default.removeItem(at: mp4)
                try? FileManager.default.removeItem(at: gif)
                let moviePlan = DocumentVideoExport.plan(durationMS: Self.lengthMS, canvasSize: Self.canvas,
                                                         format: .mp4, quality: .high)
                try await DocumentMovieWriter.write(plan: moviePlan, mix: [], soundURLs: [:], to: mp4,
                                                    frames: { ms in DocumentRenderer().render(frame(ms), store: store) })
                let gifPlan = DocumentVideoExport.plan(durationMS: Self.lengthMS, canvasSize: Self.canvas,
                                                       format: .gif, quality: .small)
                try await DocumentMovieWriter.writeAnimated(plan: gifPlan, format: .gif, to: gif,
                                                            frames: { ms in
                                                                DocumentRenderer().render(frame(ms), store: store)
                                                            })
                print("[reel] \(item.name): \(mp4.lastPathComponent), \(gif.lastPathComponent)")
            }
            let stills = [0.0, 0.25, 0.5, 0.75, 1.0].compactMap { share -> CGImage? in
                let ms = Self.moveStartMS + Int(Double(item.moveMS) * share) - (share == 1 ? 1 : 0)
                return DocumentRenderer().render(frame(min(ms, Self.lengthMS - 1)), store: store)
            }
            sheetRows.append((item.name, stills))
        }
        let sheet = try #require(Self.contactSheet(sheetRows, thumb: CGSize(width: 448, height: 252)))
        let sheetURL = directory.appendingPathComponent("\(prefix)-contact.png")
        let destination = try #require(CGImageDestinationCreateWithURL(sheetURL as CFURL,
                                                                       UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, sheet, nil)
        #expect(CGImageDestinationFinalize(destination))
        let numbers = try JSONSerialization.data(withJSONObject: try Self.textNumbers(),
                                                 options: [.prettyPrinted, .sortedKeys])
        try numbers.write(to: directory.appendingPathComponent("\(prefix)-numbers.json"))
        print("[reel] contact sheet \(sheetURL.path)")
    }

    /// One row per move: its name, then the move at 0, 25, 50, 75 and 100 per
    /// cent of the way through.
    static func contactSheet(_ rows: [(String, [CGImage])],
                             thumb: CGSize = CGSize(width: 320, height: 180)) -> CGImage? {
        let label: CGFloat = 230, gap: CGFloat = 10, header: CGFloat = 40
        let width = Int(label + (thumb.width + gap) * 5 + gap)
        let height = Int(header + (thumb.height + gap) * CGFloat(rows.count) + gap)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.09, green: 0.1, blue: 0.13, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let white = CGColor(gray: 1, alpha: 1), dim = CGColor(gray: 0.7, alpha: 1)
        for (column, title) in ["Start", "25%", "Midpoint", "75%", "End"].enumerated() {
            draw(title, at: CGPoint(x: label + gap + CGFloat(column) * (thumb.width + gap), y: CGFloat(height) - 28),
                 size: 15, in: context, colour: dim)
        }
        for (row, entry) in rows.enumerated() {
            let y = CGFloat(height) - header - CGFloat(row + 1) * (thumb.height + gap)
            draw(entry.0, at: CGPoint(x: 16, y: y + thumb.height / 2 - 6), size: 17, in: context, colour: white)
            for (column, image) in entry.1.enumerated() {
                context.draw(image, in: CGRect(x: label + gap + CGFloat(column) * (thumb.width + gap), y: y,
                                               width: thumb.width, height: thumb.height))
            }
        }
        return context.makeImage()
    }
}
