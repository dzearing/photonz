import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// The study behind `docs/design/separate-reads-the-words.md`: what it would
/// cost, and what it would get wrong, if Separate into Layers read the words
/// itself instead of leaving that to Turn into Text.
///
/// It is OFF unless `PHOTONZ_STUDY=1`, because reading every run of three real
/// captures is a hundred and ninety Vision passes and that is two minutes of a
/// debug test run. It is kept rather than deleted so the numbers in the
/// recommendation can be re-derived, and re-derived on a better reader:
///
/// ```
/// PHOTONZ_STUDY=1 Scripts/test.sh -c release --filter SeparateAutoReadStudyTests
/// ```
///
/// It prints a table per capture and writes the pictures the audit ships into
/// `/tmp/photonz-study`.
@Suite("Separate reading the words itself: the study", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_STUDY"] == "1"))
struct SeparateAutoReadStudyTests {

    struct Capture { let name: String; let scale: CGFloat }
    static let captures = [
        Capture(name: "settings-pane-2x", scale: 2),
        Capture(name: "app-window-2x", scale: 2),
        Capture(name: "dense-page-1x", scale: 1),
    ]
    static let out = URL(fileURLWithPath: "/tmp/photonz-study")

    private func image(_ name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }

    private func write(_ image: CGImage, _ name: String) {
        try? FileManager.default.createDirectory(at: Self.out, withIntermediateDirectories: true)
        guard let data = ImageCodec.encode(image, format: .png) else { return }
        try? data.write(to: Self.out.appendingPathComponent(name))
        print("   wrote \(Self.out.appendingPathComponent(name).path)")
    }

    // MARK: - The numbers

    @Test func measure() throws {
        for capture in Self.captures {
            guard let img = image(capture.name) else { Issue.record("missing"); continue }
            let gap = Double(AlignmentScan.visibleGap * capture.scale)
            let minElement = Double(max(10, 10 * capture.scale))
            let luma = EdgeMapAnalyzer.analyzeFully(img).luma
            var t0 = Date()
            guard let sep = LayerSeparator.separate(img, luma: luma, gap: gap,
                                                    minElement: minElement) else {
                Issue.record("no separation"); continue
            }
            let sepMS = Date().timeIntervalSince(t0) * 1000
            let images = sep.runs.compactMap(\.image)

            t0 = Date()
            let reads = images.map { TextReader.read($0, captureScale: capture.scale) }
            let serialMS = Date().timeIntervalSince(t0) * 1000

            // The same work spread over the cores, which is the fairest number
            // to hold against the command: folded in, this is what it would do.
            t0 = Date()
            var spread = [TextReader.Read?](repeating: nil, count: images.count)
            spread.withUnsafeMutableBufferPointer { buffer in
                guard let raw = buffer.baseAddress else { return }
                DispatchQueue.concurrentPerform(iterations: images.count) { i in
                    (raw + i).pointee = TextReader.read(images[i], captureScale: capture.scale)
                }
            }
            let spreadMS = Date().timeIntervalSince(t0) * 1000

            var refusals: [String: Int] = [:]
            var matched = 0, fallback = 0
            var families: [String: Int] = [:], weights: [String: Int] = [:]
            for read in reads {
                if let r = read.outcome.reading {
                    if r.provenance == .matched { matched += 1 } else { fallback += 1 }
                    families[r.face.fontName, default: 0] += 1
                    weights[r.face.weight.rawValue, default: 0] += 1
                } else if let refusal = read.outcome.refusal {
                    refusals[refusal.rawValue, default: 0] += 1
                }
            }
            let readCount = matched + fallback
            let majority = families.max {
                $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value
            }?.key ?? "?"
            let strays = readCount - (families[majority] ?? 0)
            let confidentStrays = reads.filter {
                guard let r = $0.outcome.reading else { return false }
                return r.provenance == .matched && r.face.fontName != majority
            }.count

            func pct(_ n: Int) -> String {
                sep.runs.isEmpty ? "0%"
                    : String(format: "%.0f%%", Double(n) / Double(sep.runs.count) * 100)
            }
            print("""
            ==== \(capture.name) — \(img.width)x\(img.height) px
            runs \(sep.runs.count)  boxes \(sep.boxes.count)  left in the picture \(sep.left)
            separate \(Int(sepMS)) ms · read every run, one after another \(Int(serialMS)) ms \
            · read every run across the cores \(Int(spreadMS)) ms
            read \(readCount)/\(sep.runs.count) (\(pct(readCount)))  \
            an answer \(matched)  a fallback \(fallback)
            refused \(refusals.sorted { $0.key < $1.key }
                .map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            families \(families.sorted { $0.value > $1.value }
                .map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            weights \(weights.sorted { $0.value > $1.value }
                .map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            off the page's own family: \(strays), of which the app called \
            \(confidentStrays) an answer rather than a fallback
            """)
            for (i, read) in reads.enumerated() where capture.name != "dense-page-1x" {
                if let r = read.outcome.reading {
                    print(String(format: "   Text %-3d %-26@ %-22@ %.2f %@", i + 1,
                                 "\"\(r.string.prefix(24))\"" as NSString,
                                 r.face.displayName as NSString, r.agreement,
                                 r.provenance.rawValue as NSString))
                } else {
                    print(String(format: "   Text %-3d %-26@ refused: %@", i + 1, "" as NSString,
                                 (read.outcome.refusal?.rawValue ?? "?") as NSString))
                }
                // How far the page's own family was behind, for the runs that
                // came back in one the page does not contain.
                if let r = read.outcome.reading, r.face.fontName != majority {
                    var bestPerFamily: [String: TextReading.Scored] = [:]
                    for s in read.scores where (bestPerFamily[s.face.fontName]?.agreement ?? -1) < s.agreement {
                        bestPerFamily[s.face.fontName] = s
                    }
                    print("      families: " + bestPerFamily.values
                        .sorted { $0.agreement > $1.agreement }
                        .map { String(format: "%@ %.3f", $0.face.displayName, $0.agreement) }
                        .joined(separator: " | "))
                }
            }

            // And the same runs read as a PAGE: the family they vote for
            // settled first, and then every run set in it, with a run that
            // family cannot account for left as the picture it was. This is
            // what the app does now; the table above is what reading each run
            // on its own used to give.
            t0 = Date()
            let settled = TextReader.readPage(images, captureScale: capture.scale)
            let settledMS = Date().timeIntervalSince(t0) * 1000
            var settledFamilies: [String: Int] = [:]
            for read in settled {
                if let r = read.outcome.reading { settledFamilies[r.face.fontName, default: 0] += 1 }
            }
            let settledRead = settledFamilies.values.reduce(0, +)
            let settledMajority = TextReading
                .pageFamily(of: settled.compactMap(\.outcome.reading)) ?? "?"
            let settledStrays = settledRead - (settledFamilies[settledMajority] ?? 0)
            print("""
            ---- the same runs, with the page's own family settled first
            the page votes \(settledMajority) · \(Int(settledMS)) ms, one after another
            read \(readCount) before, \(settledRead) after
            off the page's own family: \(strays) before, \(settledStrays) after
            families \(settledFamilies.sorted { $0.value > $1.value }
                .map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            """)
            for (i, pair) in zip(reads, settled).enumerated()
            where pair.0.outcome.reading?.face.fontName != pair.1.outcome.reading?.face.fontName
                || (pair.0.outcome.reading == nil) != (pair.1.outcome.reading == nil) {
                func say(_ read: TextReader.Read) -> String {
                    read.outcome.reading.map { $0.face.displayName }
                        ?? "a picture (\(read.outcome.refusal?.rawValue ?? "?"))"
                }
                print("   Text \(i + 1) \(say(pair.0)) → \(say(pair.1))")
            }
            // Every run that reads comes back in ONE family, because the
            // capture only contains one. That is the whole fix.
            let stillStray = "\(capture.name) still has \(settledStrays) runs in a family "
                + "the page does not contain"
            #expect(settledStrays == 0, "\(stillStray)")
            // And the page does not go quiet to get there.
            let wentQuiet = "\(capture.name) dropped from \(readCount) readings "
                + "to \(settledRead)"
            #expect(settledRead >= readCount - max(1, readCount / 10), "\(wentQuiet)")

            // The page, both ways. Text only, so the one thing that differs
            // between the two pictures is the words.
            guard let textOnly = LayerSeparator.separateText(img, luma: luma, gap: gap,
                                                             minElement: minElement)
            else { continue }
            let runReads = textOnly.runs.compactMap(\.image)
                .map { TextReader.read($0, captureScale: capture.scale) }
            if let a = compose(textOnly, reads: runReads, readingTheWords: false) {
                write(a, "\(capture.name)-shape-a.png")
            }
            if let b = compose(textOnly, reads: runReads, readingTheWords: true) {
                write(b, "\(capture.name)-shape-b.png")
            }

            // And the runs that came back in a face the page does not contain,
            // side by side with the ink they were meant to match.
            let wrong = reads.enumerated().filter {
                $0.element.outcome.reading.map { $0.face.fontName != majority } ?? false
            }
            if !wrong.isEmpty, capture.name == "app-window-2x" {
                let pairs = wrong.prefix(4).compactMap { (i, read) -> (String, CGImage, CGImage)? in
                    guard let r = read.outcome.reading,
                          let ink = TextReader.ink(images[i])?.mask,
                          let set = TextReader.render(r.string, in: r.face, size: r.fontSize,
                                                      scale: 1)
                    else { return nil }
                    return ("Text \(i + 1): \(r.face.displayName)",
                            picture(ink), picture(set))
                }
                if let strip = strip(pairs) {
                    write(strip, "\(capture.name)-a-face-the-page-does-not-contain.png")
                }
            }
        }
    }

    // MARK: - Pictures

    /// The page rebuilt from a text-only separation: every run put back as the
    /// picture it is, or as the words the app read in it.
    private func compose(_ sep: LayerSeparator.Result, reads: [TextReader.Read],
                         readingTheWords: Bool) -> CGImage? {
        let w = sep.background.width, h = sep.background.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)
                                          ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Top-left origin, the same way the document model thinks.
        context.translateBy(x: 0, y: CGFloat(h))
        context.scaleBy(x: 1, y: -1)
        draw(sep.background, at: CGRect(x: 0, y: 0, width: w, height: h), in: context,
             height: h)
        for (piece, read) in zip(sep.runs, reads) {
            if readingTheWords, let r = read.outcome.reading, let ink = read.inkRect {
                var text = TextContent(string: r.string, fontName: r.face.fontName,
                                       fontSize: r.fontSize, colorHex: r.colorHex,
                                       weight: r.face.weight)
                text.staysOnOneLine = true
                let inkFrame = CGRect(x: piece.rect.minX + ink.minX,
                                      y: piece.rect.minY + ink.minY,
                                      width: ink.width, height: ink.height)
                let box = TextReader.frame(for: text, placingInkAt: inkFrame, scale: 1)
                if let set = TextRasterizer.rasterize(text, size: box.size, scale: 1) {
                    draw(set, at: box, in: context, height: h)
                    continue
                }
            }
            if let image = piece.image { draw(image, at: piece.rect, in: context, height: h) }
        }
        return context.makeImage()
    }

    /// One image into a top-left-origin rect of a flipped context.
    private func draw(_ image: CGImage, at rect: CGRect, in context: CGContext,
                      height: Int) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY + rect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// A coverage mask as black ink on white, which is what the matcher sees.
    private func picture(_ mask: TextReading.Mask) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: mask.width * mask.height * 4)
        for p in 0..<(mask.width * mask.height) {
            let value = UInt8((1 - min(max(mask.coverage[p], 0), 1)) * 255)
            bytes[p * 4] = value; bytes[p * 4 + 1] = value; bytes[p * 4 + 2] = value
        }
        let data = CFDataCreate(nil, bytes, bytes.count)!
        let provider = CGDataProvider(data: data)!
        return CGImage(width: mask.width, height: mask.height, bitsPerComponent: 8,
                       bitsPerPixel: 32, bytesPerRow: mask.width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)
                           ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    /// The picture's ink over the ink the app would set in its place, one
    /// column per run, blown up so the difference is something an eye can find.
    private func strip(_ pairs: [(String, CGImage, CGImage)]) -> CGImage? {
        guard !pairs.isEmpty else { return nil }
        let zoom = 3, pad = 16, caption = 26, gap = 10
        let columnWidth = pairs.map { max($0.1.width, $0.2.width) * zoom }.max()! + pad * 2
        let rowHeight = pairs.map { max($0.1.height, $0.2.height) * zoom }.max()!
        let height = pad + caption + rowHeight + gap + caption + rowHeight + pad
        let width = columnWidth * pairs.count
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)
                                          ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        for (column, pair) in pairs.enumerated() {
            let x = CGFloat(column * columnWidth + pad)
            label("in the picture — \(pair.0)", at: CGPoint(x: x, y: CGFloat(pad)),
                  in: context, height: height)
            draw(pair.1, at: CGRect(x: x, y: CGFloat(pad + caption),
                                    width: CGFloat(pair.1.width * zoom),
                                    height: CGFloat(pair.1.height * zoom)),
                 in: context, height: height)
            let second = pad + caption + rowHeight + gap
            label("what the app would set", at: CGPoint(x: x, y: CGFloat(second)),
                  in: context, height: height)
            draw(pair.2, at: CGRect(x: x, y: CGFloat(second + caption),
                                    width: CGFloat(pair.2.width * zoom),
                                    height: CGFloat(pair.2.height * zoom)),
                 in: context, height: height)
        }
        return context.makeImage()
    }

    private func label(_ string: String, at point: CGPoint, in context: CGContext,
                       height: Int) {
        var text = TextContent(string: string, fontName: "SF Pro", fontSize: 13,
                               colorHex: "#7A7A7A", weight: .medium)
        text.staysOnOneLine = true
        let size = TextRasterizer.naturalSize(text)
        guard let image = TextRasterizer.rasterize(text, size: size, scale: 2) else { return }
        draw(image, at: CGRect(origin: point, size: size), in: context, height: height)
    }
}
