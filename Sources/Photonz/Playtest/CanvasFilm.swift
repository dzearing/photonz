// A film of the canvas's PICTURE through one brush stroke, frame by frame, so a
// walk can say whether anything already painted moved while the new stroke was
// drawn and landed (`filmCanvas`, `expectPaintStill`).
//
// The user, 2026-10-25: "when I draw, it seems like all of the previous strokes
// are recomputed because they change and then swap into this higher
// resolution". A held picture against a landed one (`landsAsHeld`) misses that:
// the swap happens between the two, for a tenth of a second. So every frame is
// kept, from before the press until the canvas has settled, and each is held
// against the settled picture outside the new stroke's reach.
//
// Probe builds only.
#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzRender

/// One picture of the canvas: its bytes (RGBA, premultiplied, one pixel a
/// point) and when it was taken.
struct CanvasFilmFrame {
    let at: TimeInterval
    let bytes: [UInt8]
}

@MainActor
final class CanvasFilm {
    let width: Int
    let height: Int
    private(set) var frames: [CanvasFilmFrame] = []
    /// When the drag the film is for let go, once it has, and the frame taken
    /// the moment it did: the stroke as the hand left it, before any render.
    private(set) var releasedAt: TimeInterval?
    private var releaseFrame: Int?

    /// The button has just come up: the picture now is the stroke as the hand
    /// left it, the last stretch and its end drawn, nothing rendered yet.
    func released(_ canvas: CanvasNSView) {
        releasedAt = ProcessInfo.processInfo.systemUptime
        lastKey = ""
        sample(canvas)
        releaseFrame = frames.count - 1
    }
    private var task: Task<Void, Never>?
    private var lastKey = ""

    /// Pixels per point.
    let scale: CGFloat

    init?(canvas: CanvasNSView, scale: CGFloat = 1) {
        self.scale = scale
        width = Int(canvas.bounds.width * scale)
        height = Int(canvas.bounds.height * scale)
        guard width >= 1, height >= 1 else { return nil }
        sample(canvas)
        task = Task { @MainActor [weak self, weak canvas] in
            while !Task.isCancelled {
                guard let self, let canvas else { return }
                self.sample(canvas)
                try? await Task.sleep(for: .milliseconds(4))
            }
        }
    }

    /// Takes a frame when the picture has changed since the last one.
    func sample(_ canvas: CanvasNSView) {
        let key = canvas.playtestPictureKey + "|" + canvas.playtestBrushKey
        guard key != lastKey || frames.isEmpty else { return }
        lastKey = key
        guard let bytes = canvas.playtestPictureBytes(width: width, height: height, scale: scale) else { return }
        frames.append(CanvasFilmFrame(at: ProcessInfo.processInfo.systemUptime, bytes: bytes))
    }

    func stop(_ canvas: CanvasNSView) {
        task?.cancel()
        task = nil
        // The settled picture, whatever the key says.
        lastKey = ""
        if let bytes = canvas.playtestPictureBytes(width: width, height: height, scale: scale) {
            frames.append(CanvasFilmFrame(at: ProcessInfo.processInfo.systemUptime, bytes: bytes))
        }
    }

    /// What the film shows, judged against the picture it settled on.
    struct Reading {
        var frames: Int
        /// Frames in which something outside the stroke's reach differs from
        /// the settled picture, and the most pixels any one of them differed by.
        var changedFrames: Int
        var worstChangedPixels: Int
        var outsidePixels: Int
        /// The share of the stroke's reach where the picture the moment the
        /// button came up differs from the settled one, 0 to 1.
        var liveVsLanded: Double
        /// The same for the last picture with the button down, one pointer
        /// sample behind the release.
        var heldVsLanded: Double
        var reachPixels: Int
        /// From the release until the last frame that differs from the settled
        /// picture anywhere.
        var settledMS: Double
        /// Each frame: ms from the release (negative before it) and the pixels
        /// outside the reach that differ from the settled picture.
        var timeline: [(ms: Double, outside: Int)]
    }

    /// A pixel counts as different past this many levels in any channel: a
    /// resampled edge wobbles by a level or two and nobody sees it.
    static let tolerance = 8

    func read() -> Reading? {
        guard let first = frames.first, let settled = frames.last, frames.count >= 2 else { return nil }
        let count = width * height
        // The stroke's reach: where the picture before the press and the
        // settled one differ, grown by a few pixels for its soft edge.
        var reach = [Bool](repeating: false, count: count)
        for i in 0..<count where Self.differs(first.bytes, settled.bytes, i) { reach[i] = true }
        reach = Self.grown(reach, width: width, height: height, by: 4)
        let reachPixels = reach.reduce(0) { $0 + ($1 ? 1 : 0) }
        let released = releasedAt ?? settled.at
        var timeline: [(ms: Double, outside: Int)] = []
        var changed = 0, worst = 0
        var settledAt = released
        var lastHeld: CanvasFilmFrame?
        for frame in frames.dropLast() {
            var outside = 0, anywhere = 0
            for i in 0..<count where Self.differs(frame.bytes, settled.bytes, i) {
                anywhere += 1
                if !reach[i] { outside += 1 }
            }
            // The picture before the press is not part of the stroke.
            if frame.at >= first.at, outside > 0, frame.at > first.at { changed += 1 }
            worst = max(worst, frame.at > first.at ? outside : 0)
            timeline.append(((frame.at - released) * 1000, outside))
            if frame.at < released { lastHeld = frame }
            if frame.at >= released, anywhere > 0 { settledAt = max(settledAt, frame.at) }
        }
        func apart(_ frame: CanvasFilmFrame?) -> Double {
            guard let frame, reachPixels > 0 else { return 0 }
            var differing = 0
            for i in 0..<count where reach[i] && Self.differs(frame.bytes, settled.bytes, i) { differing += 1 }
            return Double(differing) / Double(reachPixels)
        }
        let atRelease = releaseFrame.flatMap { $0 < frames.count - 1 ? frames[$0] : nil }
        return Reading(frames: frames.count, changedFrames: changed, worstChangedPixels: worst,
                       outsidePixels: count - reachPixels, liveVsLanded: apart(atRelease),
                       heldVsLanded: apart(lastHeld), reachPixels: reachPixels,
                       settledMS: (settledAt - released) * 1000, timeline: timeline)
    }

    /// Writes every frame as a picture, numbered in order, a contact sheet of
    /// them and the numbers.
    func write(to directory: URL, name: String, reading: Reading) {
        let folder = directory.appendingPathComponent("\(name)-film")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let released = releasedAt ?? 0
        for (n, frame) in frames.enumerated() {
            guard let image = Self.image(frame.bytes, width: width, height: height),
                  let data = ImageCodec.encode(image, format: .png) else { continue }
            let ms = Int(((frame.at - released) * 1000).rounded())
            try? data.write(to: folder.appendingPathComponent(String(format: "%03d_%+05dms.png", n, ms)))
        }
        let lines = reading.timeline.map { String(format: "%.1f\t%d", $0.ms, $0.outside) }
        try? ("ms_from_release\tpixels_outside_reach_differing\n" + lines.joined(separator: "\n") + "\n")
            .write(to: folder.appendingPathComponent("timeline.tsv"), atomically: true, encoding: .utf8)
    }

    private static func differs(_ a: [UInt8], _ b: [UInt8], _ i: Int) -> Bool {
        let o = i * 4
        return abs(Int(a[o]) - Int(b[o])) > tolerance || abs(Int(a[o + 1]) - Int(b[o + 1])) > tolerance
            || abs(Int(a[o + 2]) - Int(b[o + 2])) > tolerance || abs(Int(a[o + 3]) - Int(b[o + 3])) > tolerance
    }

    private static func grown(_ mask: [Bool], width: Int, height: Int, by r: Int) -> [Bool] {
        var rows = mask
        for y in 0..<height {
            var x = 0
            while x < width {
                if mask[y * width + x] {
                    for dx in max(0, x - r)...min(width - 1, x + r) { rows[y * width + dx] = true }
                }
                x += 1
            }
        }
        var out = rows
        for y in 0..<height {
            for x in 0..<width where rows[y * width + x] {
                for dy in max(0, y - r)...min(height - 1, y + r) { out[dy * width + x] = true }
            }
        }
        return out
    }

    static func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
#endif
