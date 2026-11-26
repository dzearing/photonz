import Foundation

/// **The player's controls fade away** while a video is watched in View, the
/// way QuickTime's do: about two seconds after the last thing a person did
/// while it plays, about five while it sits paused. A mouse move over the
/// window, a key, a click on the picture or play starting or stopping brings
/// them straight back and starts the wait again. Asked for on 2026-11-25:
/// "when in playback mode, and we start a video, i'd like the controls to fade
/// out and only show up on mouse move or spacebar to pause", "when we're
/// paused, they can also fade out after some time (5s?)" and "if themouse is
/// over the controls they stay visible".
///
/// The same rule in a window and full screen. Every time here is the one
/// place to tune them.
public enum PlayerControlsFade {

    /// How long after the last thing a person did, while it plays, the
    /// controls start to go.
    public static let secondsBeforeFadeWhilePlaying: Double = 2

    /// ...and while it sits paused.
    public static let secondsBeforeFadeWhilePaused: Double = 5

    /// The ease out of sight: short, never a cut.
    public static let fadeOutSeconds: Double = 0.35

    /// The way back is quicker, so a move feels answered at once.
    public static let fadeInSeconds: Double = 0.15

    /// How often the pointer is looked at while a window is a player: often
    /// enough that a move brings the controls back at once.
    public static let pointerLookSeconds: Double = 0.2

    /// What the controls' fate depends on, at one look.
    public struct Moment: Equatable, Sendable {
        /// The window is a player (View) on a document with time.
        public var watching: Bool
        /// The video is playing.
        public var playing: Bool
        /// Seconds since the pointer last moved over the window, a key, a
        /// click on the picture, or play starting or stopping.
        public var secondsIdle: Double
        /// The pointer rests on the controls themselves.
        public var pointerOverControls: Bool
        /// Something is open off them or a hand is on them: a menu, a
        /// popover, a guide's card, a drag on the play bar.
        public var held: Bool

        public init(watching: Bool, playing: Bool, secondsIdle: Double,
                    pointerOverControls: Bool, held: Bool) {
            self.watching = watching
            self.playing = playing
            self.secondsIdle = secondsIdle
            self.pointerOverControls = pointerOverControls
            self.held = held
        }
    }

    /// The wait before they go, playing or paused.
    public static func secondsBeforeFade(playing: Bool) -> Double {
        playing ? secondsBeforeFadeWhilePlaying : secondsBeforeFadeWhilePaused
    }

    /// Whether the controls are faded (and the pointer hidden over the
    /// picture) right now. The editor never fades anything.
    public static func faded(_ moment: Moment) -> Bool {
        moment.watching && !moment.pointerOverControls && !moment.held
            && moment.secondsIdle >= secondsBeforeFade(playing: moment.playing)
    }

    /// The longest it takes from the last move to fully faded: the wait, one
    /// look at the pointer late at most, and the fade itself.
    public static func secondsToFullyFaded(playing: Bool) -> Double {
        secondsBeforeFade(playing: playing) + pointerLookSeconds + fadeOutSeconds
    }
}
