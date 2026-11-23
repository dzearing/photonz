import Foundation
import Observation
import PhotonzCore

/// Whether a video's time reads in seconds or in timecode (View > Timecode).
///
/// One switch for the whole app, remembered across launches: it is how this
/// person reads time, not anything a document carries, so every open window
/// changes with it. Off by default (settled 2026-10-20).
@MainActor @Observable
final class VideoTimeDisplaySetting {
    static let shared = VideoTimeDisplaySetting()

    static let defaultsKey = "video.timeDisplay"

    private(set) var display: VideoTimeDisplay

    private init() {
        display = Self.remembered
    }

    private static var remembered: VideoTimeDisplay {
        UserDefaults.standard.string(forKey: defaultsKey)
            .flatMap(VideoTimeDisplay.init(rawValue:)) ?? .defaultValue
    }

    var isTimecode: Bool { display.isTimecode }

    func setTimecode(_ on: Bool) {
        display = on ? .timecode : .seconds
        UserDefaults.standard.set(display.rawValue, forKey: Self.defaultsKey)
    }

    /// Read the setting afresh, after a walk forgot it or put it back.
    func reload() {
        let now = Self.remembered
        if display != now { display = now }
    }
}
