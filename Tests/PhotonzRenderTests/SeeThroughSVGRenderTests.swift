import AppKit
import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// A see-through drawing looks on the canvas as macOS draws its file, when the
/// canvas mixes the way a browser does (Next's `next-web-compositing`).
///
/// On 2026-11-07 a 30 percent black square read 218 on a canvas mixing in
/// light where macOS drew 178. Mixing like a browser put the plain cases
/// right; what was left was the reading of the file: a line's own
/// `stroke-opacity` beside a fill came out solid, an `rgba()` colour lost its
/// see-through part, and a see-through group of overlapping shapes was faded
/// shape by shape, so the lower one showed through where they met.
@Suite("A see-through drawing looks as macOS draws its file")
struct SeeThroughSVGRenderTests {

    /// Each file with what it is about. Small on purpose: the icon grid opens
    /// a square file at 512 points.
    static let files: [(name: String, svg: String)] = [
        ("thirty percent black", ##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100"><rect width="100" height="100" fill="#000000" fill-opacity="0.3"/></svg>"##),
        ("a dot with a faint halo", ##"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6" fill="red"/><circle cx="8" cy="8" r="8" fill="red" fill-opacity="0.2"/></svg>"##),
        ("a faded group of one outline", ##"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40"><g opacity="0.3"><path fill="black" fill-rule="evenodd" d="M4 4H36V36H4ZM12 12V28H28V12Z"/></g></svg>"##),
        ("a faded group of overlapping shapes", ##"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40"><g opacity="0.3"><rect x="4" y="4" width="22" height="22" fill="#000"/><rect x="14" y="14" width="22" height="22" fill="#0A84FF"/></g></svg>"##),
        ("a see-through line beside a solid fill", ##"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40"><circle cx="20" cy="20" r="12" fill="#34C759" stroke="#000" stroke-width="6" stroke-opacity="0.4"/></svg>"##),
        ("colours with their own see-through amount", ##"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40"><rect x="2" y="2" width="36" height="20" fill="rgba(255,59,48,0.5)"/><rect x="2" y="18" width="36" height="20" fill="#5856D6" opacity="0.45"/></svg>"##),
        ("a fill fading to nothing", ##"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#000" stop-opacity="0.8"/><stop offset="1" stop-color="#000" stop-opacity="0"/></linearGradient></defs><rect width="40" height="40" fill="url(#g)"/></svg>"##),
        ("a faded group around a faded fill", ##"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40"><g opacity="0.5"><path d="M4 4H36V36H4Z" fill="#FF9500" fill-opacity="0.6"/></g></svg>"##),
    ]

    /// `url`'s drawing as macOS draws it, on white, at exactly `size`.
    static func macOSDrawing(of url: URL, size: CGSize) -> [UInt8]? {
        guard let image = NSImage(contentsOf: url),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current = previous
        guard let drawn = context.makeImage() else { return nil }
        return SVGExportRenderTests.pixels(of: drawn, size: size)
    }

    /// The widest difference, in levels of 255, over pixels away from any
    /// edge in macOS's drawing (a pixel and its eight neighbours alike), so
    /// antialiasing is left out and only the shade of what is drawn is read.
    static func widestAwayFromEdges(_ mine: [UInt8], _ theirs: [UInt8], width: Int, height: Int) -> Int {
        var widest = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = (y * width + x) * 4
                var flat = true
                for dy in -1...1 where flat {
                    for dx in -1...1 where flat {
                        let j = ((y + dy) * width + x + dx) * 4
                        flat = theirs[j] == theirs[i] && theirs[j + 1] == theirs[i + 1] && theirs[j + 2] == theirs[i + 2]
                    }
                }
                guard flat else { continue }
                for c in 0..<3 { widest = max(widest, abs(Int(mine[i + c]) - Int(theirs[i + c]))) }
            }
        }
        return widest
    }

    @Test("Each see-through file opens the shade macOS draws it", arguments: files.indices)
    func opensTheShadeMacOSDraws(_ index: Int) throws {
        let (name, svg) = Self.files[index]
        let opening = try SVGOpening.read(Data(svg.utf8), named: "drawing").get()
        #expect(opening.leftOut.isEmpty, "\(name) opened only in part: \(opening.leftOut)")
        let store = ImageStore()
        let white = try #require(SolidImage.make(size: opening.canvasSize, hex: "#FFFFFF"))
        let document = opening.document(on: store.register(white))
        let mine = try #require(DocumentRenderer(compositing: .sRGB).render(document, store: store))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-see-through-\(UUID().uuidString).svg")
        try svg.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let theirs = try #require(Self.macOSDrawing(of: url, size: opening.canvasSize))

        let width = Int(opening.canvasSize.width), height = Int(opening.canvasSize.height)
        let pixels = SVGExportRenderTests.pixels(of: mine, size: opening.canvasSize)
        let widest = Self.widestAwayFromEdges(pixels, theirs, width: width, height: height)
        #expect(widest <= 3, "\(name): the canvas is \(widest) levels of 255 off macOS's drawing")
        let mean = SVGExportRenderTests.meanDifference(between: pixels, and: theirs)
        #expect(mean <= 1, "\(name): the canvas is \(mean) off macOS's drawing on average")
    }

    @Test("A shape drawn at 30 percent is the shade macOS draws its exported file", arguments: ["#000000", "#FF3B30", "#0A84FF"])
    func aDrawnShapeAtThirtyPercent(_ hex: String) throws {
        let store = ImageStore()
        let size = CGSize(width: 120, height: 120)
        let white = try #require(SolidImage.make(size: size, hex: "#FFFFFF"))
        var document = PhotonzDocument.withBaseImage(store.register(white))
        var box = Layer(name: "Box",
                        content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: hex,
                                                               start: .zero, end: CGPoint(x: 80, y: 80),
                                                               fillColorHex: hex)),
                        frame: CGRect(x: 20, y: 20, width: 80, height: 80))
        box.style.opacity = 0.3
        document.layers.append(box)
        let renderer = DocumentRenderer(compositing: .sRGB)
        let mine = try #require(renderer.render(document, store: store))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-see-through-box-\(UUID().uuidString).svg")
        try SVGExporter.export(document, store: store, renderer: renderer).text
            .write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let theirs = try #require(Self.macOSDrawing(of: url, size: size))
        let widest = Self.widestAwayFromEdges(SVGExportRenderTests.pixels(of: mine, size: size), theirs,
                                              width: 120, height: 120)
        #expect(widest <= 3, "\(hex) at 30 percent: the canvas is \(widest) levels of 255 off macOS's drawing")
    }
}
