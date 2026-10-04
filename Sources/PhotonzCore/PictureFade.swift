import Foundation

// A picture fade: a clip, a title, a shape or a picture on the timeline rising
// out of black at the start of its bar and sinking back into it at the end.
//
// Fading a video in and out is the most basic edit there is, and until
// 2026-10-03 the only fades a video had were its sound's. The user: "It's also
// unintuitive on how to fade the video out or in." Final Cut puts a fade handle
// on each top corner of a clip; Premiere dips the head and tail to black. Both
// are a length at each END of the clip, not keys at moments, and that is the
// model here:
//
//  - **Measured from the bar's ends on the document's clock.** A trim, a move,
//    a ripple or a cut inside the clip never strands a fade in the middle,
//    because the fade has no moment of its own to be stranded at. That is the
//    reason it is not an Opacity motion, the way a title's Fade used to be: a
//    motion is written on the clip's own source clock (`motionClockMS`), which
//    is exactly the clock that slides when the clip is trimmed.
//  - **It multiplies whatever opacity the layer has at that moment**, keys
//    included, so a fade over a layer at half opacity goes from nought to half.
//  - **To black, or to whatever is underneath.** The fade is the layer's
//    opacity and nothing else, so over a title page it reveals the page and
//    over nothing it reveals the black every document with time is drawn on
//    (`CanvasDisplay`, `DocumentMovieWriter`).
//  - **One fade for everything.** A title's old Fade was an Opacity motion in
//    the shape `TitleTime.fade` writes; it reads as this fade at both ends, and
//    the first edit turns it into one.
//
// Applied at the moment a frame is drawn (`PhotonzDocument.drawn(atTimeMS:)`),
// so playing, scrubbing, a still and an export all read the same answer.

/// The two ends of a bar a fade can be on.
public enum FadeEnd: String, Hashable, Codable, Sendable, CaseIterable {
    /// Rising out of black where the bar starts.
    case `in`
    /// Sinking into black where the bar ends.
    case out

    /// What the menu calls a fade at this end.
    public var title: String { self == .in ? "Fade In" : "Fade Out" }
}

/// How long a layer's picture takes to come up at the start of its bar and to
/// go down at the end, in milliseconds. Nought at an end cuts.
public struct PictureFade: Hashable, Codable, Sendable {
    public var inMS: Int
    public var outMS: Int

    public init(inMS: Int, outMS: Int) {
        self.inMS = max(0, inMS)
        self.outMS = max(0, outMS)
    }

    /// The lengths offered in one click, nought meaning it simply cuts. A short
    /// list rather than a number to type: how long a fade should take is
    /// judged by watching it, and the handle on the bar is there for any other
    /// length.
    public static let stopsMS = [0, 250, 500, 1000, 2000]

    /// What a fade length is called where it is offered: `None`, `0.25s`,
    /// `0.5s`, `1s`.
    public static func title(_ ms: Int) -> String {
        guard ms > 0 else { return "None" }
        let seconds = Double(ms) / 1000
        var text = String(format: "%.2f", seconds)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "s"
    }

    public func ms(_ end: FadeEnd) -> Int { end == .in ? inMS : outMS }

    public var isNone: Bool { inMS == 0 && outMS == 0 }

    /// The two lengths on a bar this long. Fades that together run longer than
    /// the bar share it in proportion rather than overlapping, which is what
    /// keeps a clip trimmed shorter than its fades fully up at one moment.
    public func fitted(lengthMS: Int) -> PictureFade {
        let length = max(0, lengthMS)
        let total = inMS + outMS
        guard total > length, total > 0 else { return self }
        let fittedIn = Int((Double(inMS) * Double(length) / Double(total)).rounded())
        return PictureFade(inMS: fittedIn, outMS: length - fittedIn)
    }

    /// How far up the picture is, nought to one, `offsetMS` into a bar
    /// `lengthMS` long. A straight line, the way a video fade handle draws.
    public func level(atOffsetMS offset: Int, lengthMS: Int) -> Double {
        let fade = fitted(lengthMS: lengthMS)
        var level = 1.0
        if fade.inMS > 0, offset < fade.inMS {
            level = min(level, max(0, Double(offset) / Double(fade.inMS)))
        }
        if fade.outMS > 0, offset > lengthMS - fade.outMS {
            level = min(level, max(0, Double(lengthMS - offset) / Double(fade.outMS)))
        }
        return level
    }
}

// MARK: - What a layer says about its fade

extension Layer {

    /// Whether this layer's picture can fade: it has a bar on the timeline and
    /// a picture to fade. A sound has no picture, and a caption's words come
    /// and go cue by cue.
    public var canFadePicture: Bool {
        guard time != nil, !isSoundOnly, !isCaption else { return false }
        return merged?.isSoundOnly != true
    }

    /// The fade this layer has, as long as its bar lets it be: its own, or a
    /// title's old Fade read as one at both ends.
    public var shownPictureFade: PictureFade? {
        guard let time else { return nil }
        if let pictureFade { return pictureFade.fitted(lengthMS: time.lengthMS) }
        if let old = titleFadeMS { return PictureFade(inMS: old, outMS: old) }
        return nil
    }

    /// How long the fade at one end is, nought where it cuts.
    public func pictureFadeMS(_ end: FadeEnd) -> Int {
        shownPictureFade?.ms(end) ?? 0
    }

    /// Whether a fade of this length at this end is one to offer: not the one
    /// it has, and leaving the fade at the other end its room. Nought is
    /// always the way back.
    public func canSetPictureFade(_ end: FadeEnd, toMS ms: Int) -> Bool {
        guard canFadePicture, let time, ms >= 0, ms != pictureFadeMS(end) else { return false }
        let other = pictureFadeMS(end == .in ? .out : .in)
        return ms == 0 || ms + other <= time.lengthMS
    }

    /// How far up this layer's picture is at a moment of the document, from
    /// its fade alone.
    public func pictureFadeLevel(atDocumentTimeMS ms: Int) -> Double {
        guard let pictureFade, let time else { return 1 }
        return pictureFade.level(atOffsetMS: ms - time.inMS, lengthMS: time.lengthMS)
    }

    /// This layer and everything inside it with each fade drawn at a moment of
    /// the document: its opacity multiplied by how far up the fade is.
    func withPictureFadeShown(atDocumentTimeMS ms: Int) -> Layer {
        var shown = self
        if pictureFade != nil {
            shown.style.opacity *= pictureFadeLevel(atDocumentTimeMS: ms)
        }
        if shown.isGroup {
            shown.children = shown.children.map { $0.withPictureFadeShown(atDocumentTimeMS: ms) }
        }
        return shown
    }
}

// MARK: - Writing it

extension PhotonzDocument {

    /// Whether anything in this document fades its picture.
    var hasPictureFades: Bool {
        allLayers.contains { $0.pictureFade != nil }
    }

    /// Fade a layer's picture in or out over this many milliseconds, or stop
    /// with nought. The other end keeps the length it is shown with. A title's
    /// old Fade becomes this fade here, so there is only ever one.
    ///
    /// A page that opened the recording keeps its dissolve over the
    /// recording's start when its fade out changes (`keepOpeningDissolve`).
    @discardableResult
    public mutating func setPictureFade(_ id: UUID, _ end: FadeEnd, toMS ms: Int) -> Bool {
        let opening = end == .out ? openingDissolveStartMS(id) : nil
        guard fadePicture(id, end, toMS: ms) else { return false }
        if let opening { keepOpeningDissolve(id, from: opening) }
        return true
    }

    /// The fade alone, nothing around it moved.
    @discardableResult
    mutating func fadePicture(_ id: UUID, _ end: FadeEnd, toMS ms: Int) -> Bool {
        guard let layer = layer(id: id), layer.canSetPictureFade(end, toMS: ms) else { return false }
        var fade = layer.shownPictureFade ?? PictureFade(inMS: 0, outMS: 0)
        if end == .in { fade.inMS = ms } else { fade.outMS = ms }
        let oldTitleFade = layer.pictureFade == nil && layer.titleFadeMS != nil
        updateLayer(id: id) { found in
            if oldTitleFade {
                let motions = (found.motions ?? []).filter { $0.property != .opacity }
                found.motions = motions.isEmpty ? nil : motions
            }
            found.pictureFade = fade.isNone ? nil : fade
        }
        return true
    }
}
