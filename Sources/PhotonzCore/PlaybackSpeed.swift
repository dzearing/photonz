import Foundation

/// **The speed a video plays at, picked from the transport** (the user,
/// 2026-11-12: ".25x .5x 1 1.5 2 4 8x something like that?").
///
/// QuickTime and every web player put a speed menu beside play; Premiere and
/// Final Cut reach the same speeds through J, K and L. Both live here: the
/// menu's seven speeds are the window's chosen speed, which Space and the Play
/// button play at, and J/K/L keep Premiere's own ladder (`TimelineShuttle`) and
/// show their speed in the same control while they run.
///
/// A speed is how the window plays, never part of the edit: it is not saved
/// into the document and an export never sees it.
public enum PlaybackSpeed {

    /// The menu, slowest first.
    public static let choices: [Double] = [0.25, 0.5, 1, 1.5, 2, 4, 8]

    /// What every new window plays at.
    public static let normal: Double = 1

    /// The fastest speed that still plays its sound. Faster than this an
    /// editor's sound goes quiet rather than chattering (Premiere mutes a
    /// shuttle above 2x by default, Final Cut above 2x too).
    public static let fastestWithSound: Double = 2

    /// `0.25x`, `1x`, `1.5x`, and `-2x` backwards: what the control shows.
    public static func label(_ rate: Double) -> String {
        let speed = abs(rate)
        var number = String(format: "%.2f", speed)
        while number.hasSuffix("0") { number.removeLast() }
        if number.hasSuffix(".") { number.removeLast() }
        return (rate < 0 ? "-" : "") + number + "x"
    }

    /// The next speed up the menu, or the fastest when already there. From a
    /// speed off the menu (a shuttle's), the first on it that is faster.
    public static func faster(than speed: Double) -> Double {
        choices.first { $0 > speed + 1e-9 } ?? choices[choices.count - 1]
    }

    /// The next speed down the menu, or the slowest when already there.
    public static func slower(than speed: Double) -> Double {
        choices.last { $0 < speed - 1e-9 } ?? choices[0]
    }

    /// Whether `speed` is one of the menu's.
    public static func isChoice(_ speed: Double) -> Bool {
        choices.contains { abs($0 - speed) < 1e-9 }
    }

    /// Whether sound plays at this rate: forwards, up to double speed.
    /// Backwards and faster than double it is silent.
    public static func playsSound(atRate rate: Double) -> Bool {
        rate > 0 && rate <= fastestWithSound + 1e-9
    }

    /// Whether the sound at this rate needs its pitch held: slower or faster
    /// than normal, and with sound at all.
    public static func holdsPitch(atRate rate: Double) -> Bool {
        playsSound(atRate: rate) && abs(rate - normal) > 1e-9
    }
}

/// **The pitch of a tone**, read from its samples: how a walk tells a sound
/// played at half speed with its pitch held from one that dropped an octave.
///
/// The lag at which the sound looks most like itself (its autocorrelation
/// peak), refined between samples, is one period. Meant for a steady tone, not
/// for speech or music.
public enum TonePitch {

    /// The tone's frequency in hertz, or nil for silence or a sound with no
    /// steady period between `lowest` and `highest` hertz.
    public static func hertz(of samples: [Float], sampleRate: Double,
                             lowest: Double = 60, highest: Double = 2000) -> Double? {
        guard sampleRate > 0, lowest > 0, highest > lowest else { return nil }
        let minLag = max(2, Int(sampleRate / highest))
        let maxLag = Int(sampleRate / lowest)
        // A window long enough to hold several of the longest periods.
        let window = min(samples.count - maxLag - 1, 4 * maxLag)
        guard window > minLag * 4 else { return nil }
        let energy = (0..<window).reduce(Float(0)) { $0 + samples[$1] * samples[$1] }
        guard energy / Float(window) > 1e-6 else { return nil }

        func correlation(_ lag: Int) -> Float {
            var sum: Float = 0
            for index in 0..<window { sum += samples[index] * samples[index + lag] }
            return sum
        }
        let scores = (minLag...maxLag).map(correlation)
        // The first peak that comes near the best one, so a tone does not read
        // at twice its period (the second peak is nearly as tall as the first).
        guard let best = scores.max(), best > 0.3 * energy else { return nil }
        var pick: Int?
        for index in 1..<(scores.count - 1)
        where scores[index] >= scores[index - 1] && scores[index] >= scores[index + 1]
            && scores[index] > 0.9 * best {
            pick = index
            break
        }
        guard let peak = pick else { return nil }
        // A parabola through the peak and its neighbours puts it between
        // samples.
        let left = Double(scores[peak - 1]), centre = Double(scores[peak]), right = Double(scores[peak + 1])
        let bend = left - 2 * centre + right
        let shift = bend == 0 ? 0 : 0.5 * (left - right) / bend
        let period = Double(peak + minLag) + shift
        guard period > 0 else { return nil }
        return sampleRate / period
    }
}
