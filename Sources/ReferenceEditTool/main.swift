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
