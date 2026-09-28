import CoreGraphics
import Foundation

/// **How loud you are listening**: the speaker and the short slider at the
/// left of the transport, the way QuickTime has them.
///
/// This is the listener's level, not the document's. It is not saved into a
/// document, not an undo step, never reaches an export, and it is one level
/// for the person across every recording they open; a clip's own Volume is a
/// different thing and lives in the panel (`AudioLevel`).
///
/// Mute is kept apart from the level so turning the sound back on returns to
/// where it was. While muted the slider reads empty, and touching the level at
/// all (a click, a drag, the wheel turned up) turns the sound back on there.
public struct PlayerVolume: Hashable, Sendable, Codable {
    /// Where the slider sits while sounding, nought to one.
    public private(set) var level: Double
    public private(set) var isMuted: Bool

    /// Where the speaker button brings the sound back to when the slider had
    /// been pulled all the way down: a mute you cannot undo is not a button.
    public static let comeBackLevel = 0.5

    public init(level: Double = 1, isMuted: Bool = false) {
        self.level = Self.held(level, otherwise: 1)
        self.isMuted = isMuted
    }

    /// What the slider draws: empty while muted.
    public var sliderFraction: Double { isMuted ? 0 : level }

    /// What reaches the speakers, as a gain. The level squared, so the slider
    /// is a loudness control rather than an amplitude one: half way reads as
    /// clearly quieter, rather than every audible change being in the bottom
    /// fifth.
    public var outputGain: Double { isMuted ? 0 : level * level }

    public var isSilent: Bool { outputGain <= 0 }

    /// The speaker's waves.
    public enum Tier: String, Hashable, Sendable, Codable { case off, low, medium, high }

    public var tier: Tier {
        if isSilent { return .off }
        if level < 0.34 { return .low }
        if level < 0.67 { return .medium }
        return .high
    }

    /// The slider's reading, as a whole percentage.
    public var percent: Int { Int((sliderFraction * 100).rounded()) }

    /// A click or a drag on the slider. Any level above nothing turns a muted
    /// sound back on at that level; nothing leaves a mute where it is.
    public mutating func setLevel(_ value: Double) {
        let held = Self.held(value, otherwise: level)
        if isMuted {
            guard held > 0 else { return }
            isMuted = false
        }
        level = held
    }

    /// The speaker button.
    public mutating func toggleMute() {
        if isSilent {
            isMuted = false
            if level <= 0 { level = Self.comeBackLevel }
        } else {
            isMuted = true
        }
    }

    /// The wheel: move the slider by `delta` from where it is drawn.
    public mutating func nudge(by delta: Double) {
        guard delta.isFinite, delta != 0 else { return }
        setLevel(sliderFraction + delta)
    }

    // MARK: - The slider's geometry

    /// The level a click at `x` asks for on a track `width` wide whose knob is
    /// `knob` wide: the knob's centre lands under the pointer, and it travels
    /// an inset span so it never hangs off either end.
    public static func fraction(atX x: CGFloat, width: CGFloat, knob: CGFloat) -> Double {
        let usable = width - knob
        guard usable > 0 else { return 0 }
        return held(Double((x - knob / 2) / usable), otherwise: 0)
    }

    /// Where the knob's centre sits for a level: the inverse of `fraction`.
    public static func knobCentre(forFraction fraction: Double, width: CGFloat, knob: CGFloat) -> CGFloat {
        let usable = max(0, width - knob)
        return knob / 2 + CGFloat(held(fraction, otherwise: 0)) * usable
    }

    /// How far a turn of the wheel moves the slider. `dx` and `dy` are the
    /// wheel's travel with the direction already made physical (up and right
    /// are positive, however the Mac is set to scroll). A mouse wheel counts
    /// lines, a twentieth of the slider each; a trackpad counts points, two
    /// hundred of them the whole slider.
    public static func wheelStep(dx: Double, dy: Double, precise: Bool) -> Double {
        let travel = abs(dx) > abs(dy) ? dx : dy
        guard travel.isFinite else { return 0 }
        return travel * (precise ? 1.0 / 200 : 0.05)
    }

    private static func held(_ value: Double, otherwise fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(0, value), 1)
    }
}
