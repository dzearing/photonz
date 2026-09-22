import Foundation

// A title: text that knows when it is on screen
// (`docs/design/mocks/pages/video-title-wt.html`).
//
// **A title is a text layer that happens to live in a document with time, so
// it gets an in and an out. Nothing else about it is special.** That sentence
// is the whole specification, and this file is the smallest amount of model
// that makes it true. There is no Title object, no title preset, no titles
// panel and no fade property: a title is a `Layer` with `content: .text` and a
// `LayerTime` on it, which is the same pair a clip, a mark on a held frame and
// a piece of clip art are made of.
//
// What IS here is the one distinction the timeline could not do without:
//
//   **A layer PLACED in time is not a layer that PLAYS.**
//
// A clip has frames behind both its ends, so its left end is a trim into them
// and the clip itself stays where it was put. A title has nothing behind it, so
// its left end is simply the moment it arrives, and dragging it earlier makes
// the title start earlier. Told apart by whether the layer plays any media at
// all, which is a question the layer can already answer about itself.
//
// Two consequences that were already wrong before titles existed and are fixed
// here: nothing that belongs to media — a speed, a held frame, a split — may
// be offered for a layer that plays nothing (a mark drawn on a held frame was
// offered all three), and a fade written in absolute milliseconds has to be
// refitted when the stretch it is on changes length, or the words go out early
// and never come back.

/// The numbers a title is placed with, and the words the panel says about them.
public enum TitleTime {

    /// How long a title is on screen for when nobody has said: three seconds.
    ///
    /// Long enough to read a line of words twice and short enough that the
    /// commonest edit is making it longer rather than shorter, which is the
    /// drag with the whole rest of the document to move into rather than the
    /// one that has to be aimed between two other bars.
    public static let defaultLengthMS = 3000

    /// The fade lengths offered in one click, nought meaning it simply cuts on.
    ///
    /// A short list rather than a number to type, for the same reason the hold
    /// lengths are one (`ClipPieces.holdStopsMS`): how long a title should take
    /// to arrive is a judgment made by watching it, and the judgment is
    /// "softer" long before it is "four hundred milliseconds". Anything else is
    /// the Opacity motion itself, in the Motion section, because that is all a
    /// fade is here.
    public static let fadeStopsMS = [0, 250, 500, 1000]

    /// What a fade length is called where it is offered.
    public static func fadeTitle(_ ms: Int) -> String {
        ms <= 0 ? "None" : String(format: "%.2fs", Double(ms) / 1000)
    }

    /// `0:02 to 0:05 · 3.0s`: when the words arrive, when they go, and how long
    /// that is. One place, so the panel and a walk reading it cannot drift.
    public static func reading(_ time: LayerTime) -> String {
        "\(MotionStripRuler.timecode(Double(time.inMS))) to "
            + "\(MotionStripRuler.timecode(Double(time.outMS))) · "
            + ClipBarCopy.length(time.lengthMS)
    }

    /// The sentence the Time section says about a layer that is placed in time
    /// rather than played. It is the thesis, said where somebody is looking at
    /// the thing it is about.
    public static let sentence = "A title is a text layer that happens to live in a document "
        + "with time, so it gets an in and an out. Nothing else about it is special."

    /// The same thesis about a component somebody built and put on the
    /// timeline (`ComponentsInTime.swift`). Said about a component because
    /// that is the claim: the badge in the film is the badge in the design
    /// file, not a picture of it.
    public static let componentSentence = "A component is the thing you built, living in a "
        + "document with time, so it gets an in and an out. Edit the original and it "
        + "changes here too."

    /// ...and about anything else simply placed: a shape, an arrow, a picture.
    public static let placedSentence = "Anything placed on a document with time gets an in "
        + "and an out. Nothing else about it is special."

    /// Which of the three the Time section says, for the thing in your hand.
    public static func sentence(for layer: Layer) -> String {
        if case .text = layer.content { return sentence }
        if layer.isComponentInstance || layer.isMainComponent { return componentSentence }
        return placedSentence
    }

    /// What the two buttons promise, named after the thing they are about:
    /// words for words, and "it" for everything else, because "bring the
    /// words on" over a badge is a sentence about somebody else's layer.
    public static func startHelp(for layer: Layer) -> String {
        if case .text = layer.content {
            return "Bring the words on at the playhead. Where they go is untouched."
        }
        return "Bring it on at the playhead. Where it goes is untouched."
    }

    public static func endHelp(for layer: Layer) -> String {
        if case .text = layer.content {
            return "Take the words off at the playhead. Where they arrive is untouched."
        }
        return "Take it off at the playhead. Where it arrives is untouched."
    }

    /// One ordinary Opacity motion that brings a layer on and takes it off
    /// again, or nil where there is no room for one.
    ///
    /// Four keys on ONE motion rather than two motions, and that is not a
    /// detail: two motions on one property are two answers to one question, and
    /// the second would overwrite the first for the whole of the stretch
    /// between them. The two middle keys hold the words fully up, which is
    /// exactly the hold a punch-in makes between its two moves.
    public static func fade(overMS fade: Int, lengthMS length: Int) -> LayerMotion? {
        let span = max(0, length)
        let over = min(max(0, fade), span / 2)
        guard over > 0, span > 0 else { return nil }
        return LayerMotion(
            property: .opacity,
            from: .number(0), to: .number(0),
            timing: MotionTiming(startMS: 0, durationMS: span),
            curve: .easeInOut, repeats: .once,
            stops: [MotionStop(atMS: over, value: .number(100)),
                    MotionStop(atMS: span - over, value: .number(100))])
    }
}

// MARK: - Placed in time, rather than playing

extension Layer {

    /// Whether there is MEDIA behind the stretch this layer occupies: a
    /// recording, a sound, or a stretch that remembers how long its source runs
    /// for. That is what a trim trims into, and what a speed speeds up.
    public var hasMediaBehindIt: Bool {
        movie != nil || sound != nil || time?.sourceLengthMS != nil
    }

    /// Whether this layer is simply PLACED in time: it has an in and an out
    /// and there is no media behind them.
    ///
    /// A title, a piece of clip art, a mark drawn on a held frame. Everything
    /// about a clip that is really about the frames behind it — a speed, a
    /// held frame, a split, a trim — means nothing for one of these, and the
    /// surfaces that offer those read this to know it.
    public var isPlacedInTime: Bool { time != nil && !hasMediaBehindIt }

    /// Whether the left end of this layer's bar is free to go where the hand
    /// puts it.
    ///
    /// **A clip's is not**: there are frames behind its in point, so dragging
    /// it is a trim into them and the clip stays where it was put
    /// (`ClipBarDrag`). A title's is, because the only thing its in point says
    /// is when the words arrive.
    public var startIsFree: Bool { isPlacedInTime && cuts == nil }

    /// How far this layer's OWN clock sits along the document's.
    ///
    /// A motion is written in the clock of the thing it is on — nought is the
    /// layer's first frame, not the document's — which is what keeps a
    /// punch-in nailed to the frame it was made on (`motionClockMS`). The
    /// timeline is drawn in the DOCUMENT's clock, so a lane has to be moved
    /// along by this much to be drawn where it actually happens: a fade on a
    /// title that arrives at three seconds happens at three seconds, and drawn
    /// at nought it would say the words come on before they exist.
    ///
    /// Only a shift, so a clip cut into pieces that have been reordered is
    /// still only approximately placed. That is no worse than not moving it at
    /// all, which is what happened before, and the exact answer is piecewise
    /// rather than a number.
    public var motionShiftMS: Int {
        guard let time else { return 0 }
        return time.inMS - time.sourceInMS
    }

    /// How long this layer takes to come on and go off again, where it is
    /// doing that with the fade the Time section writes.
    ///
    /// Read back off the motion rather than stored beside it, so there is one
    /// truth about the fade and it is the animation everybody else can see. A
    /// motion edited by hand into some other shape stops being read as a fade,
    /// which is what makes their edit safe: nothing refits it and nothing
    /// overwrites it.
    public var titleFadeMS: Int? {
        guard let motion = (motions ?? []).first(where: { $0.property == .opacity }),
              motion.repeats == .once, motion.isOn,
              motion.from == .number(0), motion.to == .number(0),
              motion.timing.startMS == 0,
              let stops = motion.stops, stops.count == 2,
              stops.allSatisfy({ $0.value == .number(100) }) else { return nil }
        let sorted = stops.sorted { $0.atMS < $1.atMS }
        let over = sorted[0].atMS
        guard over > 0, sorted[1].atMS == motion.timing.durationMS - over else { return nil }
        return over
    }
}

// MARK: - Putting something in time

extension PhotonzDocument {

    /// The stretch something newly drawn at this moment should occupy, or nil
    /// in a document with no time in it — which is every screenshot and every
    /// drawing, where nothing about this appears at all.
    ///
    /// Two rules, in this order. **On a held frame it takes the hold**, which
    /// is the rule `HeldFrame` already set for a mark drawn on a frozen frame
    /// and is no different for words: what is there to be pointed at is there
    /// for exactly as long as the frame is. **Anywhere else it arrives at the
    /// playhead and runs for three seconds**, never past the last frame,
    /// because a title that outlives the picture is a title nobody can see.
    public func placedSpan(atTimeMS ms: Int) -> LayerTime? {
        guard hasTime else { return nil }
        if let held = heldFrame(atTimeMS: ms) { return held.span }
        let end = documentDurationMS
        let start = end > LayerTime.shortestMS
            ? min(max(0, ms), end - LayerTime.shortestMS)
            : max(0, ms)
        let wanted = start + TitleTime.defaultLengthMS
        return LayerTime(inMS: start, outMS: end > 0 ? min(wanted, end) : wanted)
    }

    /// Move the moment a placed layer ARRIVES, leaving where it goes alone.
    ///
    /// The left end of a title's bar, and the In the panel sets. Refused for
    /// anything with media behind it: that edge is a trim
    /// (`ClipPieces.trimStart`).
    @discardableResult
    public mutating func moveLayerStart(_ id: UUID, toMS ms: Int) -> Bool {
        guard let layer = layer(id: id), let time = layer.time, layer.startIsFree else {
            return false
        }
        let landing = min(max(0, ms), time.outMS - LayerTime.shortestMS)
        guard landing != time.inMS else { return false }
        updateLayer(id: id) { $0.time = LayerTime(inMS: landing, outMS: time.outMS) }
        refitFade(id)
        refreshDuration()
        return true
    }

    /// Move the moment a placed layer GOES, leaving where it arrives alone.
    @discardableResult
    public mutating func moveLayerEnd(_ id: UUID, toMS ms: Int) -> Bool {
        guard let layer = layer(id: id), let time = layer.time, layer.startIsFree else {
            return false
        }
        let landing = max(ms, time.inMS + LayerTime.shortestMS)
        guard landing != time.outMS else { return false }
        updateLayer(id: id) { $0.time = LayerTime(inMS: time.inMS, outMS: landing) }
        refitFade(id)
        refreshDuration()
        return true
    }

    /// Bring a placed layer on and take it off again over this many
    /// milliseconds, or stop doing that with nought.
    ///
    /// It writes an ORDINARY Opacity motion, which is the whole point: it turns
    /// up in the Motion list, gets a lane on the timing strip, takes a
    /// different curve, undoes, and reaches the export with nothing written for
    /// it. A fade that was a property of a title would have had to be given all
    /// of that again.
    @discardableResult
    public mutating func setTitleFade(_ id: UUID, toMS fade: Int) -> Bool {
        guard let layer = layer(id: id), let time = layer.time, layer.isPlacedInTime else {
            return false
        }
        let written = TitleTime.fade(overMS: fade, lengthMS: time.lengthMS)
        guard written != nil || layer.titleFadeMS != nil else { return false }
        updateLayer(id: id) { found in
            var motions = (found.motions ?? []).filter { $0.property != .opacity }
            if let written { motions.append(written) }
            found.motions = motions.isEmpty ? nil : motions
        }
        return true
    }

    /// The fade re-cut to the stretch it is now on.
    ///
    /// Without this, dragging a title longer leaves the last key where it was
    /// and the words fade out on the old end and stay gone: a motion is written
    /// in milliseconds and knows nothing about the bar being dragged. Only a
    /// fade in the shape the Fade row writes is touched, so a motion somebody
    /// has edited by hand is left exactly as they left it.
    mutating func refitFade(_ id: UUID) {
        guard let layer = layer(id: id), let time = layer.time,
              let fade = layer.titleFadeMS,
              let refitted = TitleTime.fade(overMS: fade, lengthMS: time.lengthMS) else { return }
        updateLayer(id: id) { found in
            var motions = (found.motions ?? []).filter { $0.property != .opacity }
            motions.append(refitted)
            found.motions = motions
        }
    }
}
