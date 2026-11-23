import Foundation

// Duck Under Speech: music that dips under somebody talking, in one step
// (`docs/design/video-audio.md` §7, `pages/video-audio.html`, the Duck button
// and the Ducking section).
//
// The design note cut this on 2026-09-21 because the app could not tell which
// layer is a voice. The captions can: they wrote themselves off the recording,
// one timed word at a time, so the stretches somebody is talking are known to
// the millisecond. Nothing here listens to anything.
//
// A duck is not a new kind of thing. It is what dragging four dots on the
// music's bar makes, a point either side of each dip (`AudioMix.swift`), so the
// result plays, exports and drags exactly like a duck made by hand, and one
// undo takes it away. That is Premiere's auto ducking too: it writes volume
// keyframes onto the music and leaves them for you to drag.

/// The numbers a duck is made with.
public enum SpeechDuck {

    /// How far the music goes down under the voice: the mock's Amount.
    public static let amountDB: Double = -8
    /// How long it takes to go down and to come back up: the mock's Ramp. The
    /// fall finishes as the first word starts, so the word is never fought.
    public static let rampMS = 300
    /// A pause shorter than this stays ducked. Music that swells back up for a
    /// breath between two sentences pumps, which is the sound of an automatic
    /// duck done badly: back up for a moment only where it can stay up for
    /// half a second after rising and before falling again.
    public static let shortestGapMS = 2 * rampMS + 500

    /// The gain the dip goes down to, as the mix multiplies by it.
    public static var gain: Double { AudioLevel.gain(forDecibels: amountDB) }

    /// Words, or any stretches of sound, made into the stretches the music
    /// ducks under: in order, overlapping ones joined, and any two with a
    /// pause shorter than `shortestGapMS` between them run together.
    public static func stretches(_ spans: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        var joined: [ClosedRange<Int>] = []
        for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = joined.last, span.lowerBound - last.upperBound < shortestGapMS {
                joined[joined.count - 1] = last.lowerBound...max(last.upperBound, span.upperBound)
            } else {
                joined.append(span)
            }
        }
        return joined
    }

    /// Whether a sound can be ducked, and if not, what the dimmed row's tip
    /// says. The words are the menu's own.
    public enum Availability: Equatable, Sendable {
        case ready
        /// There are no captions anywhere, so nothing says when anybody talks.
        case needsCaptions
        /// This is the voice the captions were heard off: ducking it would
        /// turn the speech itself down.
        case isTheVoice
        /// Not a sound on the timeline.
        case notASound

        /// The tip on a dimmed row. Nil where the row is live.
        public var tip: String? {
            switch self {
            case .ready, .notASound: nil
            case .needsCaptions: "Needs captions: add captions first"
            case .isTheVoice: "This is the voice the captions came from"
            }
        }
    }
}

extension AudioLevel {

    /// This level with the music dipping under `stretches`, given in the
    /// layer's own milliseconds, for a layer `lengthMS` long.
    ///
    /// It REPLACES the points somebody had along the line, keeping the fade in
    /// and fade out, which is what Premiere's Generate Keyframes does too: run
    /// again after the captions change, it writes the new dips rather than
    /// stacking a second duck on the first. One undo puts the old line back.
    /// A dip that runs into a fade is folded into that fade's level rather than
    /// putting a point inside it, so the fade is still read as a fade.
    public func duckedUnder(_ stretches: [ClosedRange<Int>], lengthMS: Int,
                            gain duck: Double = SpeechDuck.gain,
                            rampMS ramp: Int = SpeechDuck.rampMS) -> AudioLevel {
        let length = max(0, lengthMS)
        let fadeIn = fadeInMS
        let fadeOut = fadeOutMS(lengthMS: length)
        let fadeOutStart = length - fadeOut
        // The line before the duck: flat, with its fades.
        var base = self
        base.clearPoints()
        if fadeIn > 0 { base.setFadeIn(fadeIn, lengthMS: length) }
        if fadeOut > 0 { base.setFadeOut(fadeOut, lengthMS: length) }

        let inside = stretches.compactMap { span -> ClosedRange<Int>? in
            let from = max(0, span.lowerBound), to = min(length, span.upperBound)
            return to > from ? from...to : nil
        }
        // How far down the duck has it at a moment: one outside every dip,
        // `duck` inside one, a straight slide across each ramp.
        func factor(_ ms: Int) -> Double {
            var lowest = 1.0
            for span in inside {
                let value: Double
                if ms >= span.lowerBound && ms <= span.upperBound {
                    value = duck
                } else if ms < span.lowerBound, ms > span.lowerBound - ramp {
                    value = 1 - (1 - duck) * Double(ms - (span.lowerBound - ramp)) / Double(ramp)
                } else if ms > span.upperBound, ms < span.upperBound + ramp {
                    value = duck + (1 - duck) * Double(ms - span.upperBound) / Double(ramp)
                } else {
                    continue
                }
                lowest = min(lowest, value)
            }
            return lowest
        }
        var corners = Set<Int>()
        for span in inside {
            for ms in [span.lowerBound - ramp, span.lowerBound, span.upperBound, span.upperBound + ramp] {
                corners.insert(min(length, max(0, ms)))
            }
        }
        var ducked = base
        // A corner inside a fade would make the fade read as something else;
        // the fade's own ends carry the duck's level instead.
        let fadeEnds = Set(base.points.map(\.atMS))
        for ms in corners.sorted() {
            if fadeIn > 0, ms < fadeIn { continue }
            if fadeOut > 0, ms > fadeOutStart { continue }
            ducked.setPoint(atMS: ms, gain: base.shape(atLayerMS: ms) * factor(ms))
        }
        for ms in fadeEnds {
            ducked.setPoint(atMS: ms, gain: base.shape(atLayerMS: ms) * factor(ms))
        }
        // A fade's foot is silence whatever the duck does, and must stay a point
        // of nought for the fade to be read as one.
        return ducked
    }
}

extension PhotonzDocument {

    /// When somebody is talking, on the document's clock: every word the
    /// captions heard, joined into stretches (`SpeechDuck.stretches`). A
    /// caption line typed by hand, with no timed words, counts as speech for
    /// as long as it is up. Empty where there are no captions.
    public var speechStretches: [ClosedRange<Int>] {
        var spans: [ClosedRange<Int>] = []
        for cue in captionLayers {
            guard let time = cue.time else { continue }
            if let words = captionWordsAsShown(of: cue.id), !words.isEmpty {
                spans += words.map { $0.startMS...max($0.startMS, $0.endMS) }
            } else {
                spans.append(time.inMS...time.outMS)
            }
        }
        return SpeechDuck.stretches(spans)
    }

    /// Whether Duck Under Speech can act on this layer.
    public func duckUnderSpeechAvailability(layerID id: UUID) -> SpeechDuck.Availability {
        guard let layer = layer(id: id), let sound = layer.sound, layer.time != nil else { return .notASound }
        guard !captionLayers.isEmpty else { return .needsCaptions }
        let heardOff = Set(captionsLayers.compactMap(\.captionsHeardOff))
        if heardOff.contains(sound.id) || layer.playedSound.map({ heardOff.contains($0.id) }) == true {
            return .isTheVoice
        }
        return .ready
    }

    /// The layer's level with it ducked under every stretch of speech it plays
    /// under, or nil where it cannot be (`duckUnderSpeechAvailability`).
    public func levelDuckedUnderSpeech(layerID id: UUID) -> AudioLevel? {
        guard duckUnderSpeechAvailability(layerID: id) == .ready,
              let layer = layer(id: id), let time = layer.time else { return nil }
        let length = layer.clipPieces?.totalLengthMS ?? time.lengthMS
        // Points are measured from the layer's own start.
        let stretches = speechStretches.map { ($0.lowerBound - time.inMS)...($0.upperBound - time.inMS) }
        return (layer.soundLevel ?? AudioLevel()).duckedUnder(stretches, lengthMS: length)
    }

    /// Duck the layer under the speech, as one change. False where it could
    /// not, or where it changed nothing.
    @discardableResult
    public mutating func duckUnderSpeech(layerID id: UUID) -> Bool {
        guard let level = levelDuckedUnderSpeech(layerID: id),
              level != (layer(id: id)?.soundLevel ?? AudioLevel()) else { return false }
        updateLayer(id: id) { $0.setSoundLevel(level) }
        return true
    }
}
