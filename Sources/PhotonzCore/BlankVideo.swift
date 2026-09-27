import CoreGraphics
import Foundation

/// Starting a video from nothing (`video.html`, the New video on ramp, step 1
/// New, empty): a blank timeline of a chosen size and length, an empty V1 over
/// an empty Audio track, and nothing on either until the Library fills and a
/// first tile is dragged onto a track.
///
/// The sizes are the ones an editor's new sequence offers for screen work,
/// 1080p first because that is the mock's blank project.
public enum BlankVideo {

    /// One offered frame size.
    public struct Preset: Hashable, Sendable, Identifiable {
        public let id: String
        /// What the picker shows, without the dimensions (the picker prints
        /// those from `size`, so the two can never disagree).
        public let title: String
        public let size: CGSize

        public init(id: String, title: String, size: CGSize) {
            self.id = id
            self.title = title
            self.size = size
        }
    }

    /// Movies are written in whole pairs of pixels, so the smallest side is
    /// two. The largest is the blank canvas's own cap, which holds 4K.
    public static let minimumSide: CGFloat = 2
    public static let maximumSide: CGFloat = BlankCanvas.maximumSide

    public static let presets: [Preset] = [
        Preset(id: "hd1080", title: "HD 1080p", size: CGSize(width: 1920, height: 1080)),
        Preset(id: "uhd4k", title: "4K", size: CGSize(width: 3840, height: 2160)),
        Preset(id: "hd720", title: "HD 720p", size: CGSize(width: 1280, height: 720)),
        Preset(id: "vertical", title: "Vertical", size: CGSize(width: 1080, height: 1920)),
        Preset(id: "square", title: "Square", size: CGSize(width: 1080, height: 1080)),
    ]

    /// What the sheet opens on, so Return alone makes the mock's blank project.
    public static let defaultPreset = presets[0]

    /// The length the sheet opens on, in seconds.
    public static let defaultLengthSeconds: Double = 10
    public static let shortestLengthMS = 1_000
    public static let longestLengthMS = 3_600_000

    /// A typed size made safe to build: whole, even, inside the legal range,
    /// never NaN.
    public static func normalized(_ size: CGSize) -> CGSize {
        CGSize(width: evenSide(size.width), height: evenSide(size.height))
    }

    /// Whether a size can be used as typed: the Create button's enablement.
    public static func isValid(_ size: CGSize) -> Bool {
        normalized(size) == size
    }

    /// A typed length in milliseconds, kept between a second and an hour.
    public static func lengthMS(seconds: Double) -> Int {
        guard seconds.isFinite else { return shortestLengthMS }
        let ms = (seconds * 1000).rounded()
        return Int(min(max(ms, Double(shortestLengthMS)), Double(longestLengthMS)))
    }

    /// Whether a length can be used as typed.
    public static func isValidLength(seconds: Double) -> Bool {
        seconds.isFinite && Double(lengthMS(seconds: seconds)) == (seconds * 1000).rounded()
    }

    private static func evenSide(_ side: CGFloat) -> CGFloat {
        guard side.isFinite else { return minimumSide }
        let even = (side / 2).rounded(.up) * 2
        return min(max(even, minimumSide), maximumSide)
    }
}

extension PhotonzDocument {

    /// A new video with nothing on it: the chosen frame size, the chosen
    /// length, and an empty V1 over an empty Audio track.
    ///
    /// The two tracks are written down with ids of their own rather than a
    /// layer's, so they are the person's tracks the way a track added by hand
    /// is, and no edit ever tidies them away for being empty.
    public static func emptyVideo(size: CGSize, lengthMS: Int) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: BlankVideo.normalized(size))
        doc.durationMS = min(max(lengthMS, BlankVideo.shortestLengthMS), BlankVideo.longestLengthMS)
        doc.tracks = [
            DocumentTrack(name: freeTrackName(.video, used: []), kind: .video),
            DocumentTrack(name: freeTrackName(.audio, used: []), kind: .audio),
        ]
        return doc
    }
}
