import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
import PhotonzRender
import Testing
import UniformTypeIdentifiers

/// Every built-in title photographed as it comes in, at 0, 25, 50, 75 and 100
/// percent of its in (task `titles-move-in-parts-not-as-one-block`).
///
/// Always run, so a preset that stops drawing anything at all is caught. The
/// pictures are written only when `PHOTONZ_TITLE_FRAMES` names a folder; with
/// `PHOTONZ_TITLE_FRAMES_LABEL=before` the sheets are kept aside, and a later
/// run labelled `after` stacks the two into one picture per preset for the
/// audit:
///
///     PHOTONZ_TITLE_FRAMES=/tmp/title-frames PHOTONZ_TITLE_FRAMES_LABEL=after \
///         Scripts/test.sh --filter TitleInFramesTests
@Suite("Every built-in title, photographed as it comes in")
struct TitleInFramesTests {

    static let canvas = CGSize(width: 960, height: 540)
    static let fractions: [Double] = [0, 0.25, 0.5, 0.75, 1]
    static let cell = CGSize(width: 384, height: 216)

    /// A stand-in recording to lay the title over: a name card is drawn over
    /// footage, and a page fades in from it.
    static func document() -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: canvas)
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#3A4556",
                                        start: .zero, end: CGPoint(x: canvas.width, y: canvas.height))
        content.fill = Paint(hex: "#3A4556", kind: .linear,
                             stops: [GradientStop(hex: "#2B3442", position: 0),
                                     GradientStop(hex: "#55657C", position: 1)],
                             angle: 120)
        var clip = Layer(name: "Recording", content: .annotation(content),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 8000)
        doc.layers = [clip]
        doc.durationMS = 8000
        return doc
    }

    /// How long a placed title takes to arrive: its fade in, or the last key
    /// anything inside it reaches in the front half of its stretch.
    static func inLengthMS(_ layer: Layer) -> Int {
        guard let time = layer.time else { return 0 }
        var last = layer.pictureFadeMS(.in)
        for piece in layer.selfAndDescendants {
            for motion in piece.motions ?? [] where motion.repeats == .once {
                for key in motion.keyframes {
                    let at = key.atMS - time.sourceInMS
                    if at < time.lengthMS / 2 { last = max(last, at) }
                }
            }
        }
        return last
    }

    @Test("Every built-in title draws something at each step of its in, and is whole at the end")
    func everyTitleIsPhotographedComingIn() throws {
        let folder = ProcessInfo.processInfo.environment["PHOTONZ_TITLE_FRAMES"]
        let label = ProcessInfo.processInfo.environment["PHOTONZ_TITLE_FRAMES_LABEL"] ?? "after"
        let start = 1000
        for preset in BuiltInTitle.allCases {
            var doc = Self.document()
            let placed = doc.insertTitle(preset, atTimeMS: start)
            let inserted = try #require(placed, "\(preset.name)")
            let layer = try #require(doc.layer(id: inserted.layerID))
            let length = Self.inLengthMS(layer)
            #expect(length > 0, "\(preset.name) arrives in no time at all")
            var frames: [CGImage] = []
            for fraction in Self.fractions {
                let ms = start + Int((Double(length) * fraction).rounded())
                let image = try #require(DocumentRenderer().render(doc.drawn(atTimeMS: ms), store: ImageStore()))
                // A card is a speck on the whole frame: its corner, at twice the size.
                let corner = CGRect(x: 0, y: image.height / 2, width: image.width / 2, height: image.height / 2)
                frames.append(preset.kind == .nameCard ? try #require(image.cropping(to: corner)) : image)
            }
            // At rest it differs from the frame before it began.
            #expect(Self.difference(frames[0], frames[4]) > 0.0005, "\(preset.name) never changes")
            guard let folder else { continue }
            let directory = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sheet = try #require(Self.sheet(frames, caption: "\(preset.name), \(label), in \(length) ms"))
            let file = directory.appendingPathComponent("\(preset.rawValue)-\(label).png")
            try Self.write(sheet, to: file)
            let before = directory.appendingPathComponent("\(preset.rawValue)-before.png")
            if label == "after", let old = Self.read(before),
               let both = Self.stacked([old, sheet]) {
                try Self.write(both, to: directory.appendingPathComponent("\(preset.rawValue)-before-after.png"))
            }
        }
    }

    // MARK: Pictures

    static func context(_ size: CGSize) -> CGContext? {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// The five frames in a row, with a strip under them saying which preset.
    static func sheet(_ frames: [CGImage], caption: String) -> CGImage? {
        let gap: CGFloat = 8, strip: CGFloat = 28
        let size = CGSize(width: cell.width * CGFloat(frames.count) + gap * CGFloat(frames.count + 1),
                          height: cell.height + gap * 2 + strip)
        guard let context = context(size) else { return nil }
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        for (index, frame) in frames.enumerated() {
            let x = gap + CGFloat(index) * (cell.width + gap)
            context.draw(frame, in: CGRect(x: x, y: strip + gap, width: cell.width, height: cell.height))
        }
        // A caption the eye can find: a bar per frame showing how far into
        // the in it is, under the frame, so the sheet needs no fonts.
        context.setFillColor(CGColor(gray: 0.85, alpha: 1))
        for (index, fraction) in fractions.enumerated() {
            let x = gap + CGFloat(index) * (cell.width + gap)
            context.fill(CGRect(x: x, y: 10, width: max(2, cell.width * CGFloat(fraction)), height: 6))
        }
        _ = caption
        return context.makeImage()
    }

    static func stacked(_ sheets: [CGImage]) -> CGImage? {
        let width = sheets.map(\.width).max() ?? 0
        let height = sheets.map(\.height).reduce(0, +)
        guard width > 0, let context = context(CGSize(width: width, height: height)) else { return nil }
        var y = height
        for sheet in sheets {
            y -= sheet.height
            context.draw(sheet, in: CGRect(x: 0, y: y, width: sheet.width, height: sheet.height))
        }
        return context.makeImage()
    }

    static func write(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    static func read(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The mean difference between two pictures of one size, 0 to 1.
    static func difference(_ a: CGImage, _ b: CGImage) -> Double {
        func bytes(_ image: CGImage) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
            out.withUnsafeMutableBytes { raw in
                let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                        bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return out
        }
        let x = bytes(a), y = bytes(b)
        guard x.count == y.count, !x.isEmpty else { return 1 }
        var total = 0
        for index in x.indices { total += abs(Int(x[index]) - Int(y[index])) }
        return Double(total) / Double(x.count * 255)
    }
}
