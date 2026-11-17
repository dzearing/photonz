// Writes the reference edit (`ReferenceEdit`, task
// `a-long-reference-edit-opens-in-the-probe-in-one`) as a project the app opens:
// its recordings and music first, once per machine, then the project itself,
// fresh every time so an edit saved into it last run never carries over.
//
//   swift run ReferenceEditTool 6|20|60 [--folder <dir>] [--seed <n>] [--sheet <png>]
//
// `--sheet` also draws a contact sheet of twelve moments of the edit
// (`ReferenceEdit.sheetMoments`) through the app's own renderer, each frame
// read from the recordings, for an audit.
//
// Prints the project's path on its last line. `Scripts/perf/reference-edit.sh`
// runs this and opens the result in the probe.
import AVFoundation
import Foundation
import PhotonzCore
import PhotonzMedia
import PhotonzRender
import CoreText

var arguments = Array(CommandLine.arguments.dropFirst())

// `envelope <out.json> <run.json>...`: the worst of several speed walk runs,
// number by number, as one baseline (`SpeedRun.envelope`), for
// `Scripts/perf/speed-walk.sh --baseline`.
if arguments.first == "envelope", arguments.count >= 3 {
    let runs = arguments.dropFirst(2).compactMap { file in
        try? JSONDecoder().decode(SpeedRun.self, from: Data(contentsOf: URL(fileURLWithPath: file)))
    }
    guard runs.count == arguments.count - 2, var both = SpeedRun.envelope(of: runs) else {
        FileHandle.standardError.write(Data("every run must read as a speed walk run\n".utf8))
        exit(2)
    }
    both.head = Set(runs.map(\.head)).sorted().joined(separator: ",") + " (worst of \(runs.count))"
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        try encoder.encode(both).write(to: URL(fileURLWithPath: arguments[1]))
    } catch {
        FileHandle.standardError.write(Data("could not write \(arguments[1]): \(error)\n".utf8))
        exit(1)
    }
    print("==> \(arguments[1]): the worst of \(runs.count) runs")
    exit(0)
}

// `compare <before.json> <after.json> [--margin <percent>]`: two speed walk
// runs side by side (`SpeedCompare`), for `Scripts/perf/compare.sh`.
if arguments.first == "compare" {
    let rest = Array(arguments.dropFirst())
    var files: [String] = []
    var margin: Double?
    var index = 0
    while index < rest.count {
        if rest[index] == "--margin", index + 1 < rest.count {
            margin = Double(rest[index + 1])
            index += 2
        } else {
            files.append(rest[index])
            index += 1
        }
    }
    guard files.count == 2 else {
        FileHandle.standardError.write(Data("usage: ReferenceEditTool compare <before.json> <after.json> [--margin <percent>]\n".utf8))
        exit(2)
    }
    var runs: [SpeedRun] = []
    for file in files {
        do {
            runs.append(try JSONDecoder().decode(SpeedRun.self, from: Data(contentsOf: URL(fileURLWithPath: file))))
        } catch {
            FileHandle.standardError.write(Data("\(file) does not read as a speed walk run: \(error)\n".utf8))
            exit(2)
        }
    }
    print("before: \(files[0])\nafter:  \(files[1])\n")
    print(SpeedCompare.table(runs[0], runs[1], names: ("before", "after")))
    if let margin {
        let worse = SpeedCompare.regressions(baseline: runs[0], run: runs[1], marginPercent: margin)
        print(worse.isEmpty ? "\nNothing worse than before by more than \(Int(margin))% and its floor."
              : "\nWorse than before by more than \(Int(margin))% and its floor:\n  " + worse.joined(separator: "\n  "))
        exit(worse.isEmpty ? 0 : 1)
    }
    exit(0)
}
// `frames <minutes> <before.mp4> <after.mp4>`: two exports of the reference
// edit compared picture by picture at twenty moments: the twelve of its
// contact sheet (a title, a zoom, the b-roll, a push, a cube, a flip) and the
// middles of more transitions. Prints, per moment, how far apart the two
// frames are in 8-bit levels: the mean, the 99th percentile and the largest
// difference in any channel. For a change to the export that must not change
// the picture (`Scripts/perf/speed-walk.sh`, the export's `keep`).
if arguments.first == "frames", arguments.count == 4, let minutes = Int(arguments[1]) {
    let document = ReferenceEdit.build(minutes: minutes)
    var moments = ReferenceEdit.sheetMoments(of: document)
    let byID = Dictionary(document.timelineClipLayers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    var middles: [ReferenceEdit.Moment] = []
    for track in document.timelineTracks where track.kind == .video {
        for point in document.editPoints(onTrack: track.id) {
            guard let transition = byID[point.incoming]?.arrivalTransition else { continue }
            let half = transition.lengthMS / 2
            let mid: Int
            switch transition.alignment {
            case .before: mid = point.atMS - half
            case .across: mid = point.atMS
            case .after: mid = point.atMS + half
            }
            middles.append(ReferenceEdit.Moment(ms: mid, what: "mid-\(transition.kind.title.lowercased())"))
        }
    }
    middles.sort { $0.ms < $1.ms }
    // Middles spread over the whole edit, until there are twenty moments.
    var step = max(1, middles.count / max(1, 20 - moments.count))
    while moments.count < 20, step >= 1 {
        for moment in stride(from: 0, to: middles.count, by: step).map({ middles[$0] })
        where moments.count < 20 && !moments.contains(where: { abs($0.ms - moment.ms) < 500 }) {
            moments.append(moment)
        }
        step = step == 1 ? 0 : max(1, step / 2)
    }
    moments.sort { $0.ms < $1.ms }
    func generator(_ path: String) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return generator
    }
    /// The picture's bytes as 8-bit sRGB, four to a pixel.
    func bytes(_ image: CGImage) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
        out.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return out
    }
    let before = generator(arguments[2]), after = generator(arguments[3])
    var worstMean = 0.0, worstP99 = 0, worstMax = 0
    func padded(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
    func clock(_ ms: Int) -> String { String(format: "%d:%04.1f", ms / 60_000, Double(ms % 60_000) / 1000) }
    print(padded("moment", 9) + padded("what", 30) + "    mean   p99   max")
    for moment in moments {
        let at = CMTime(value: CMTimeValue(moment.ms), timescale: 1000)
        guard let a = try? await before.image(at: at).image, let b = try? await after.image(at: at).image,
              a.width == b.width, a.height == b.height else {
            print("\(moment.ms)ms: no frame to compare in one of them, or their sizes differ")
            exit(1)
        }
        let pa = bytes(a), pb = bytes(b)
        var histogram = [Int](repeating: 0, count: 256)
        var total = 0
        for index in stride(from: 0, to: pa.count, by: 4) {
            for channel in 0..<3 {
                let d = abs(Int(pa[index + channel]) - Int(pb[index + channel]))
                histogram[d] += 1
                total += d
            }
        }
        let count = pa.count / 4 * 3
        var seen = 0, p99 = 0
        for (level, n) in histogram.enumerated() {
            seen += n
            if seen >= count * 99 / 100 { p99 = level; break }
        }
        let largest = histogram.lastIndex(where: { $0 > 0 }) ?? 0
        let mean = Double(total) / Double(max(1, count))
        worstMean = max(worstMean, mean); worstP99 = max(worstP99, p99); worstMax = max(worstMax, largest)
        print(padded(clock(moment.ms), 9) + padded(moment.what, 30) + String(format: "%8.3f %5d %5d", mean, p99, largest))
    }
    print(String(format: "==> %d moments: worst mean %.3f levels, worst 99th percentile %d, largest %d",
                 moments.count, worstMean, worstP99, worstMax))
    exit(0)
}

var folder = ReferenceFootage.defaultFolder
var seed = ReferenceEdit.defaultSeed
var minutes: Int?
var sheet: URL?
while !arguments.isEmpty {
    let word = arguments.removeFirst()
    switch word {
    case "--folder":
        guard !arguments.isEmpty else { break }
        folder = URL(fileURLWithPath: arguments.removeFirst(), isDirectory: true)
    case "--sheet":
        guard !arguments.isEmpty else { break }
        sheet = URL(fileURLWithPath: arguments.removeFirst())
    case "--seed":
        guard !arguments.isEmpty, let n = UInt64(arguments.removeFirst()) else { break }
        seed = n
    default:
        minutes = Int(word)
    }
}
guard let minutes, ReferenceEdit.lengths.contains(minutes) else {
    FileHandle.standardError.write(Data("usage: ReferenceEditTool \(ReferenceEdit.lengths.map(String.init).joined(separator: "|")) [--folder <dir>] [--seed <n>]\n".utf8))
    exit(2)
}

let started = Date()
do {
    let project = try await ReferenceFootage.project(minutes: minutes, in: folder, seed: seed) { line in
        print("    \(line)")
    }
    try PackageIO.write(project.document, store: ImageStore(), media: project.media, to: project.url)
    let census = ReferenceEdit.census(of: project.document)
    let transitions = census.transitions.sorted { $0.key.rawValue < $1.key.rawValue }
        .map { "\($0.value) \($0.key.title.lowercased())" }.joined(separator: ", ")
    print("==> \(minutes) minutes, \(census.pictureTracks) picture tracks, \(census.clips) clips, \(census.cuts) cuts (\(transitions)), \(census.titles) titles, \(census.zooms) zooms, in \(Int(Date().timeIntervalSince(started)))s")
    let short = ReferenceEdit.shortfalls(census, minutes: minutes)
    if !short.isEmpty { print("!! Falls short of the objective's list: \(short.joined(separator: "; "))") }
    if let sheet {
        let files = Dictionary(project.media.map { ($0.id, URL(fileURLWithPath: $0.path)) },
                               uniquingKeysWith: { a, _ in a })
        try await drawSheet(project.document, files: files, to: sheet)
        print("    contact sheet: \(sheet.path)")
    }
    print(project.url.path)
} catch {
    FileHandle.standardError.write(Data("!! \(error)\n".utf8))
    exit(1)
}

/// Twelve moments of the edit, drawn the way the canvas and an export draw
/// them: every frame a moment needs read from its recording first.
func drawSheet(_ document: PhotonzDocument, files: [UUID: URL], to url: URL) async throws {
    let moments = ReferenceEdit.sheetMoments(of: document)
    let columns = 4
    let cell = CGSize(width: 864, height: 864 * document.canvasSize.height / document.canvasSize.width)
    let label: CGFloat = 44
    let rows = (moments.count + columns - 1) / columns
    let size = CGSize(width: CGFloat(columns) * cell.width + CGFloat(columns + 1) * 16,
                      height: CGFloat(rows) * (cell.height + label) + CGFloat(rows + 1) * 16)
    guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return }
    context.setFillColor(CGColor(gray: 0.12, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    let renderer = DocumentRenderer()
    let scale = cell.width / document.canvasSize.width
    var generators: [UUID: AVAssetImageGenerator] = [:]
    for (index, moment) in moments.enumerated() {
        let store = ImageStore()
        for request in document.movieFrames(atTimeMS: moment.ms) {
            guard let file = files[request.movie.id] else { continue }
            let generator = generators[request.movie.id] ?? {
                let made = AVAssetImageGenerator(asset: AVURLAsset(url: file))
                made.requestedTimeToleranceBefore = .zero
                made.requestedTimeToleranceAfter = .zero
                made.appliesPreferredTrackTransform = true
                return made
            }()
            generators[request.movie.id] = generator
            let time = CMTime(value: CMTimeValue(request.sourceMS), timescale: 1000)
            if let frame = try? await generator.image(at: time).image { store.register(frame, as: request.ref) }
        }
        let row = index / columns, column = index % columns
        let x = 16 + CGFloat(column) * (cell.width + 16)
        let top = 16 + CGFloat(row) * (cell.height + label + 16)
        let box = CGRect(x: x, y: size.height - top - cell.height, width: cell.width, height: cell.height)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(box)
        if let picture = renderer.render(document.drawn(atTimeMS: moment.ms), store: store, scale: scale) {
            context.draw(picture, in: box)
        }
        let seconds = moment.ms / 1000
        let words = String(format: "%d:%02d.%d  %@", seconds / 60, seconds % 60, (moment.ms % 1000) / 100, moment.what)
        let font = CTFontCreateWithName("Helvetica Neue" as CFString, 26, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: words, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.92, alpha: 1),
        ]))
        context.textPosition = CGPoint(x: x + 4, y: box.minY - 32)
        CTLineDraw(line, context)
    }
    guard let image = context.makeImage(), let data = ImageCodec.encode(image, format: .png) else { return }
    try data.write(to: url)
}
