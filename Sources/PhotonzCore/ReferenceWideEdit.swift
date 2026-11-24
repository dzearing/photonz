import CoreGraphics
import Foundation

// The wide reference edit (task `an-edit-with-50-tracks-and-100-clips-scrolls-pla`).
//
// The reference edit (`ReferenceEdit.swift`) is long and three tracks tall.
// This one is short and TALL: fifty tracks or a hundred, a hundred clips or
// two hundred of the same recordings spread over them, most tracks holding one
// or two and up to ten playing at one moment, the way a person who drops
// recording after recording on a timeline ends up. It measures what the long
// one cannot: scrolling down through the tracks, a header and a lane built for
// every one of them, and a moment made of ten recordings at once.

extension ReferenceEdit {

    /// How many tracks the wide edit is kept at.
    public static let wideTracks = [50, 100]

    /// How long the wide edit runs.
    public static let wideLengthMS = 120_000

    /// The most recordings playing at any one moment of it, and the moment it
    /// is built to reach that at.
    public static let wideOverlap = 10
    public static let wideBusiestMS = 60_000..<66_000

    /// The file a wide project is written to.
    public static func wideProjectName(tracks: Int) -> String { "Reference Edit \(tracks) tracks.photonz" }

    /// The wide edit: `tracks` tracks and twice as many clips of recordings,
    /// with titles, transitions and sound. Same seed, same document.
    public static func buildWide(tracks: Int, seed: UInt64 = defaultSeed) -> PhotonzDocument {
        var builder = Builder(totalMS: wideLengthMS, seed: seed ^ UInt64(tracks))
        builder.layWide(tracks: tracks)
        return builder.finished()
    }

    /// How many recordings play at `ms`, transitions not counted.
    public static func recordingsPlaying(in doc: PhotonzDocument, atMS ms: Int) -> Int {
        doc.timelineClipLayers.count { layer in
            guard layer.movie != nil, let time = layer.time else { return false }
            return time.inMS <= ms && ms < time.outMS
        }
    }
}

extension ReferenceEdit.Builder {

    /// Where a clip above the bottom track sits: one cell of a three by three
    /// grid, a half of the frame, or the whole of it, covering everything
    /// under it.
    private enum Place {
        case cell(Int), half(Int), whole

        func frame(in size: CGSize) -> CGRect {
            switch self {
            case .cell(let n):
                let w = size.width * 0.28, h = size.height * 0.28
                return CGRect(x: size.width * (0.03 + 0.32 * CGFloat(n % 3)),
                              y: size.height * (0.03 + 0.32 * CGFloat(n / 3)), width: w, height: h)
            case .half(let n):
                return CGRect(x: n == 0 ? 0 : size.width / 2, y: 0, width: size.width / 2, height: size.height)
            case .whole:
                return CGRect(origin: .zero, size: size)
            }
        }
    }

    /// The tracks, bottom to top: the main cut, the recordings over it, the
    /// titles, and the music.
    mutating func layWide(tracks: Int) {
        mainTrack = doc.addTrack(.video)
        let over = (0..<max(0, tracks - 3)).map { _ in doc.addTrack(.video) }
        titleTrack = doc.addTrack(.video, named: DocumentTrack.titleTrackName)
        musicTrack = doc.addTrack(.audio, named: "Music")
        for footage in ReferenceEdit.footage {
            doc.rememberMedia(.recording(footage.movie), named: footage.fileName)
        }
        doc.rememberMedia(.sound(ReferenceEdit.music.sound), named: ReferenceEdit.music.fileName)

        insert(.softGlass, at: 0)
        insert(.pill, at: 20_000)
        insert(.chapterCard, at: 50_000)
        insert(.splitWipe, at: 80_000)
        insert(.endCard, at: totalMS - BuiltInTitle.endCard.kind.lengthMS)

        let main = layMainClips()
        layTransitions(main)
        layOver(over, count: tracks * 2 - main.count)
        layMusic()
        doc.restackByTracks()
    }

    /// `count` recordings over the main cut: ten playing at once across the
    /// busiest stretch, then one on every track, then the rest wherever there
    /// is room, never more than `wideOverlap` at a moment with the main cut
    /// under them.
    private mutating func layOver(_ tracks: [UUID], count: Int) {
        guard !tracks.isEmpty, count > 0 else { return }
        var spans: [UUID: [Range<Int>]] = [:]
        var all: [Range<Int>] = []
        var made = 0

        func room(_ span: Range<Int>, on track: UUID) -> Bool {
            !(spans[track] ?? []).contains { $0.overlaps(span) }
                // Checked at the ends of everything it meets, where a count
                // can only rise, with the main cut as one.
                && ([span.lowerBound] + all.map(\.lowerBound).filter(span.contains)).allSatisfy { at in
                    all.count { $0.contains(at) } + 1 < ReferenceEdit.wideOverlap
                }
        }
        func lay(_ span: Range<Int>, on track: UUID, at place: Place) {
            let footage = ReferenceEdit.footage[random.int(in: 0...(ReferenceEdit.footage.count - 1))]
            let sourceIn = random.int(in: 0...(ReferenceEdit.footageLengthMS - span.count), step: 100)
            made += 1
            var layer = clipLayer(footage, name: "\(ReferenceEdit.brollPrefix) \(made)", frame: place.frame(in: doc.canvasSize),
                                  inMS: span.lowerBound, lengthMS: span.count, sourceInMS: sourceIn)
            if case .whole = place {} else { layer.style.cornerRadius = 24 }
            // A third speak; the rest are silent, or ten voices talk at once.
            if made % 3 != 0 { layer.soundDetached = true }
            let id = self.place(layer, on: track)
            if made % 5 == 0 {
                _ = doc.fadePicture(id, .in, toMS: 400)
                _ = doc.fadePicture(id, .out, toMS: 400)
            }
            spans[track, default: []].append(span)
            all.append(span)
        }

        // The busiest stretch, one picture a cell and all nine over the main cut.
        let busy = ReferenceEdit.wideBusiestMS
        for n in 0..<min(ReferenceEdit.wideOverlap - 1, count, tracks.count) {
            lay(busy, on: tracks[n * (tracks.count - 1) / max(1, ReferenceEdit.wideOverlap - 2)], at: .cell(n))
        }
        var waiting = tracks.filter { spans[$0] == nil }
        var tries = 0
        while made < count, tries < count * 400 {
            tries += 1
            let track = waiting.first ?? tracks[random.int(in: 0...(tracks.count - 1))]
            let length = random.int(in: 2500...5500, step: 100)
            let start = random.int(in: 6000...(totalMS - 6000 - length), step: 100)
            guard room(start..<(start + length), on: track) else { continue }
            if !waiting.isEmpty { waiting.removeFirst() }
            let shape = random.int(in: 0...9)
            let place: Place = shape < 6 ? .cell(random.int(in: 0...8)) : shape < 8 ? .half(shape - 6) : .whole
            lay(start..<(start + length), on: track, at: place)
        }
    }
}
