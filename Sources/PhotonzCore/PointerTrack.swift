import CoreGraphics
import Foundation

// Where the pointer went in a recording, and every click.
//
// Photonz makes its recordings itself, so rather than finding clicks in the
// pixels afterwards it writes them down while it records, the way Screen
// Studio does. What it writes is a small record beside the video file (a
// `.photonzpointer` sidecar): never pixels, and never in the document. A
// document holds the recording by identity (`MovieRef`) and the app finds the
// record by the file, the same bargain pictures strike with `ImageStore`.
//
// Everything is in the RECORDING's own terms: milliseconds from its first
// frame, and its own pixels counted from the top-left. That is what lets a
// click ring or a zoom that follows the mouse land on the frame and the spot
// the click was made, whatever the clip is later moved, cut or scaled to.

/// Which button went down.
public enum PointerButton: String, Codable, Sendable, Hashable {
    case left, right, other
}

/// Where the pointer was at one moment of a recording.
public struct PointerSample: Hashable, Sendable {
    /// Milliseconds from the recording's first frame.
    public var ms: Int
    /// Recording pixels, from the top-left.
    public var x: Double
    public var y: Double

    public init(ms: Int, x: Double, y: Double) {
        self.ms = ms
        self.x = x
        self.y = y
    }

    public var point: CGPoint { CGPoint(x: x, y: y) }
}

/// One click: when the button went down, when it came back up, where, and
/// which button.
public struct PointerClick: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Milliseconds from the recording's first frame to the press.
    public var downMS: Int
    /// ...and to the release. Nil for a button still held when the recording
    /// stopped, and for a click added by hand, which has no release to know.
    public var upMS: Int?
    /// Where it was pressed, in recording pixels from the top-left.
    public var point: CGPoint
    public var button: PointerButton

    public init(id: UUID = UUID(), downMS: Int, upMS: Int?, point: CGPoint, button: PointerButton) {
        self.id = id
        self.downMS = downMS
        self.upMS = upMS
        self.point = point
        self.button = button
    }

    /// Every click a clip has, the recorded ones and the ones added by hand,
    /// as one list in the order they happen.
    public static func all(recorded: PointerTrack?, added: [PointerClick]?) -> [PointerClick] {
        ((recorded?.clicks ?? []) + (added ?? [])).sorted { $0.downMS < $1.downMS }
    }
}

/// Everything the pointer did while a recording was made.
public struct PointerTrack: Hashable, Sendable {
    /// The recording's own picture size, in pixels, which every point here is in.
    public var pixelSize: CGSize
    /// Where the pointer was, in time order, written only when it moved.
    public var samples: [PointerSample]
    /// Every click, in the order they were pressed.
    public var clicks: [PointerClick]

    public init(pixelSize: CGSize, samples: [PointerSample], clicks: [PointerClick]) {
        self.pixelSize = pixelSize
        self.samples = samples
        self.clicks = clicks
    }

    /// Where the pointer was at a moment of the recording: in between two
    /// samples it is in between them, past the last it stays where it stopped.
    /// Nil when nothing was ever taken down.
    public func position(atMS ms: Int) -> CGPoint? {
        guard let first = samples.first else { return nil }
        if ms <= first.ms { return first.point }
        // The last sample at or before `ms`.
        var lo = 0
        var hi = samples.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if samples[mid].ms <= ms { lo = mid } else { hi = mid - 1 }
        }
        let before = samples[lo]
        guard lo + 1 < samples.count else { return before.point }
        let after = samples[lo + 1]
        let span = Double(after.ms - before.ms)
        guard span > 0 else { return after.point }
        let t = Double(ms - before.ms) / span
        return CGPoint(x: before.x + (after.x - before.x) * t,
                       y: before.y + (after.y - before.y) * t)
    }
}

extension PointerTrack: Codable {
    /// Bumped if the shape of the file ever changes.
    public static let version = 1

    private enum CodingKeys: String, CodingKey { case version, width, height, samples, clicks }

    /// Samples are written as `[ms, x, y]` triples to a tenth of a pixel: a
    /// pointer moving every frame for three minutes is about ten thousand of
    /// them, and a keyed object each would be most of a megabyte of names.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.version, forKey: .version)
        try c.encode(Double(pixelSize.width), forKey: .width)
        try c.encode(Double(pixelSize.height), forKey: .height)
        try c.encode(samples.map { [Double($0.ms), Self.tenth($0.x), Self.tenth($0.y)] }, forKey: .samples)
        try c.encode(clicks, forKey: .clicks)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let triples = try c.decode([[Double]].self, forKey: .samples)
        self.init(pixelSize: CGSize(width: try c.decode(Double.self, forKey: .width),
                                    height: try c.decode(Double.self, forKey: .height)),
                  samples: triples.compactMap { t in
                      t.count == 3 ? PointerSample(ms: Int(t[0]), x: t[1], y: t[2]) : nil
                  },
                  clicks: try c.decode([PointerClick].self, forKey: .clicks))
    }

    static func tenth(_ v: Double) -> Double { (v * 10).rounded() / 10 }
}

// MARK: - From the screen to the recording's pixels

/// How a point on the screen lands in a recording's picture.
///
/// AppKit hands the pointer over in the global space: points, counted up from
/// the bottom-left of the main display. A recording is pixels counted down
/// from the top-left of what it captured, which is a whole display or a region
/// of one, at that display's backing scale.
public struct PointerSpace: Hashable, Sendable, Codable {
    /// The recorded display's frame in the global space (bottom-left origin).
    public var displayFrame: CGRect
    /// What was captured, in points within the display, from its top-left
    /// (`RecordingSource.sourceRect`).
    public var sourceRect: CGRect
    /// The recording's picture size in pixels.
    public var pixelSize: CGSize

    public init(displayFrame: CGRect, sourceRect: CGRect, pixelSize: CGSize) {
        self.displayFrame = displayFrame
        self.sourceRect = sourceRect
        self.pixelSize = pixelSize
    }

    /// A global screen point, in the recording's pixels. Scaled by the size
    /// the picture really came out at, so a recorder that rounded an odd
    /// backing size down still lands the far edge on the far edge.
    public func pixelPoint(forScreen p: CGPoint) -> CGPoint {
        let sx = sourceRect.width > 0 ? pixelSize.width / sourceRect.width : 1
        let sy = sourceRect.height > 0 ? pixelSize.height / sourceRect.height : 1
        let localX = p.x - displayFrame.minX
        let localYFromTop = displayFrame.maxY - p.y
        return CGPoint(x: (localX - sourceRect.minX) * sx,
                       y: (localYFromTop - sourceRect.minY) * sy)
    }

    /// Whether a recording pixel is inside the picture.
    public func contains(pixel p: CGPoint) -> Bool {
        p.x >= 0 && p.y >= 0 && p.x <= pixelSize.width && p.y <= pixelSize.height
    }
}

// MARK: - Taking it down

/// What the recorder writes into while it records: moves and presses as they
/// arrive, on the host clock (the clock both `NSEvent` timestamps and a screen
/// stream's frames are stamped with), turned into a `PointerTrack` counted
/// from the first frame once recording stops.
public struct PointerTrackRecording: Sendable {
    public let space: PointerSpace

    private var moves: [(host: Double, point: CGPoint)] = []
    private var presses: [(host: Double, point: CGPoint, button: PointerButton, upHost: Double?)] = []

    public init(space: PointerSpace) {
        self.space = space
    }

    /// The pointer was at a global screen point. A sample that has not moved
    /// from the last one is not kept.
    public mutating func move(to screenPoint: CGPoint, atHostSeconds host: Double) {
        let p = space.pixelPoint(forScreen: screenPoint)
        if let last = moves.last, abs(last.point.x - p.x) < 0.25, abs(last.point.y - p.y) < 0.25 { return }
        moves.append((host, p))
    }

    public mutating func press(_ button: PointerButton, at screenPoint: CGPoint, atHostSeconds host: Double) {
        presses.append((host, space.pixelPoint(forScreen: screenPoint), button, nil))
    }

    /// Closes the latest press of the same button still held.
    public mutating func release(_ button: PointerButton, at screenPoint: CGPoint, atHostSeconds host: Double) {
        guard let i = presses.lastIndex(where: { $0.button == button && $0.upHost == nil }) else { return }
        presses[i].upHost = host
    }

    /// Whether anything at all was taken down.
    public var isEmpty: Bool { moves.isEmpty && presses.isEmpty }

    /// The record, counted from the recording's first frame. A press before
    /// that frame is not in the picture and is left out; the pointer's place
    /// at the first frame is the last place it was seen before it. Without a
    /// first frame (the stream never said), it counts from the first thing
    /// heard.
    public func finished(firstFrameHostSeconds: Double?) -> PointerTrack {
        let zero = firstFrameHostSeconds
            ?? [moves.first?.host, presses.first?.host].compactMap { $0 }.min()
            ?? 0
        func ms(_ host: Double) -> Int { Int(((host - zero) * 1000).rounded()) }

        var samples: [PointerSample] = []
        for (i, move) in moves.enumerated() {
            if move.host < zero {
                // Only the last one before the picture began is worth keeping,
                // and it is kept AT the first frame.
                let next = i + 1 < moves.count ? moves[i + 1].host : .infinity
                if next >= zero { samples.append(PointerSample(ms: 0, x: move.point.x, y: move.point.y)) }
                continue
            }
            samples.append(PointerSample(ms: ms(move.host), x: move.point.x, y: move.point.y))
        }
        let clicks = presses
            .filter { $0.host >= zero }
            .map { PointerClick(downMS: ms($0.host), upMS: $0.upHost.map(ms), point: $0.point, button: $0.button) }
        return PointerTrack(pixelSize: space.pixelSize, samples: samples, clicks: clicks)
    }
}

// MARK: - Beside the file

/// The record's file: same folder, same name as the recording,
/// `.photonzpointer` (not a media extension, so the capture folder never lists
/// it as history). Like `VideoEditsSidecar`, losing it loses the record and
/// never the recording.
public enum PointerTrackSidecar {
    public static let pathExtension = "photonzpointer"

    public static func url(for mediaURL: URL) -> URL {
        mediaURL.deletingPathExtension().appendingPathExtension(pathExtension)
    }

    /// The record for a recording, or nil when there is none, it will not
    /// read, or the file is no longer the one it was made against: a save in
    /// the old recording window rewrites the file with the trim baked in
    /// (`VideoOriginals`), and a click at the eighth second of the original is
    /// somewhere else in the rewritten one.
    public static func load(for mediaURL: URL) -> PointerTrack? {
        guard !VideoOriginals.exists(for: mediaURL),
              let data = try? Data(contentsOf: url(for: mediaURL)) else { return nil }
        return try? JSONDecoder().decode(PointerTrack.self, from: data)
    }

    public static func save(_ track: PointerTrack, for mediaURL: URL) throws {
        try JSONEncoder().encode(track).write(to: url(for: mediaURL), options: .atomic)
    }
}

// MARK: - A click added by hand

extension PhotonzDocument {

    /// Add a click to a recording's clip at a moment of the document, where
    /// the picture was clicked: for a recording made before clicks were kept,
    /// or one the pointer missed. Answers the click, or nil where there is no
    /// clip playing at that moment or the point is off its picture.
    ///
    /// The click is written in the recording's own terms, like a recorded one:
    /// which frame of the file is under the playhead, and which pixel of it is
    /// under the point. So it stays on that frame and that spot when the clip
    /// is moved, cut or scaled afterwards.
    @discardableResult
    public mutating func addClick(toClip id: UUID, atMS ms: Int, canvasPoint: CGPoint) -> PointerClick? {
        guard let layer = layer(id: id), let movie = layer.movie, let time = layer.time,
              time.contains(ms: ms), let pieces = layer.clipPieces,
              let sourceMS = pieces.sourceMS(atMS: ms - time.inMS) else { return nil }
        let frame = layer.frame.standardized
        guard frame.width > 0, frame.height > 0, frame.contains(canvasPoint) else { return nil }
        let point = CGPoint(x: (canvasPoint.x - frame.minX) * movie.pixelSize.width / frame.width,
                            y: (canvasPoint.y - frame.minY) * movie.pixelSize.height / frame.height)
        let click = PointerClick(downMS: sourceMS, upMS: nil, point: point, button: .left)
        updateLayer(id: id) { $0.addedClicks = ($0.addedClicks ?? []) + [click] }
        return click
    }
}
