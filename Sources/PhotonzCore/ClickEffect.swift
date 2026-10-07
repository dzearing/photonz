import CoreGraphics
import Foundation

// An effect at each click of a recording: a ring that spreads, a soft dot, or
// the picture dimmed round the spot, for a moment as the click lands.
//
// The user, 2026-09-30: "I'd love to have an option to have some UI effect on
// the cursor when the click happens." Screen Studio and ScreenFlow are the
// grown-up tools, and their shape is the one kept: one switch on the clip, a
// few good looks, a colour and a size, and nothing to set per click unless a
// click is wrong (hide it, or slide it to when it really happened).
//
// The clicks themselves are the ones the recorder took down beside the file
// (`PointerTrack.swift`) and the ones added by hand (`Layer.addedClicks`).
// Turning the effect on keeps a copy of the recorded ones here, the way Follow
// Cursor keeps its stretch of path (`ClipZoom.bakeCursor`), so an export, a
// copy of the document and a machine without the record all draw the same.
//
// Each click is drawn as an ordinary shape over the clip on the drawn document
// only (`PhotonzDocument.drawn(atTimeMS:)`), so playback, scrubbing, stills and
// every export read one answer and the renderer learns nothing new. Its timing
// is on the DOCUMENT's clock from the moment the click's frame plays, so a
// sped-up stretch still shows the whole effect, and a click in a stretch cut
// out shows nothing.

/// How a click looks.
public enum ClickEffectStyle: String, Codable, CaseIterable, Hashable, Sendable {
    /// A ring that spreads from the click and fades.
    case ripple
    /// A soft filled dot that swells and fades.
    case pulse
    /// Everything but the spot round the click dimmed for a moment.
    case spotlight

    public var title: String {
        switch self {
        case .ripple: return "Ripple"
        case .pulse: return "Pulse"
        case .spotlight: return "Spotlight"
        }
    }

    /// Whether the colour row means anything: a spotlight dims with black.
    public var takesAColour: Bool { self != .spotlight }
}

/// How big a click's effect is drawn.
public enum ClickEffectSize: String, Codable, CaseIterable, Hashable, Sendable {
    case small, medium, large

    public var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// How wide the effect grows, as a share of the recording's shorter side.
    /// Medium is about twice a pointer on a Retina recording, so the ring is
    /// read as being round the pointer rather than somewhere near it.
    public var share: CGFloat {
        switch self {
        case .small: return 0.04
        case .medium: return 0.065
        case .large: return 0.10
        }
    }
}

/// The effect on one clip, and what a person has changed about its clicks.
public struct ClickEffect: Codable, Hashable, Sendable {
    public var isOn: Bool
    public var style: ClickEffectStyle
    /// `#RRGGBB`, for a ripple's ring and a pulse's dot.
    public var colorHex: String
    public var size: ClickEffectSize
    /// The recorder's clicks, kept when the effect was turned on, so nothing
    /// that draws this clip needs the record beside the file. Nil until then.
    public var recorded: [PointerClick]?
    /// Clicks a person hid, by id: still marked on the clip, drawn as nothing.
    public var hiddenIDs: [UUID]?
    /// Clicks a person slid to another moment, by id, on the recording's own
    /// clock. Keyed by the id's string so the file reads plainly.
    public var movedMS: [String: Int]?

    /// The system accent: reads on light and dark screenshots alike.
    public static let defaultColorHex = "#0A84FF"
    /// How long each click's effect plays, on the document's clock.
    public static let lengthMS = 400

    public init(isOn: Bool = false, style: ClickEffectStyle = .ripple,
                colorHex: String = ClickEffect.defaultColorHex, size: ClickEffectSize = .medium) {
        self.isOn = isOn
        self.style = style
        self.colorHex = colorHex
        self.size = size
    }

    public func isHidden(_ id: UUID) -> Bool { hiddenIDs?.contains(id) == true }

    public func movedMS(of id: UUID) -> Int? { movedMS?[id.uuidString] }
}

/// One click as the clip shows it: at the moment it now happens, and whether
/// it was hidden.
public struct ClickMark: Hashable, Sendable, Identifiable {
    public var click: PointerClick
    public var isHidden: Bool
    public var id: UUID { click.id }

    public init(click: PointerClick, isHidden: Bool) {
        self.click = click
        self.isHidden = isHidden
    }
}

// MARK: - On the clip

extension Layer {

    /// Every click this clip has, with what a person changed applied, in the
    /// order they now happen. `recorded` is the record beside the file, used
    /// only while the effect has not kept a copy of its own.
    public func clickMarks(recorded fallback: [PointerClick]?) -> [ClickMark] {
        let effect = clickEffect
        let all = (effect?.recorded ?? fallback ?? []) + (addedClicks ?? [])
        return all.map { click in
            var moved = click
            if let ms = effect?.movedMS(of: click.id) { moved.downMS = ms }
            return ClickMark(click: moved, isHidden: effect?.isHidden(click.id) ?? false)
        }
        .sorted { $0.click.downMS < $1.click.downMS }
    }

    /// Whether this clip has any click an effect could be drawn at.
    public func hasClicksToShow(recorded: [PointerClick]?) -> Bool {
        movie != nil && !clickMarks(recorded: recorded).isEmpty
    }

    /// Where a moment of the recording first plays on the DOCUMENT's
    /// timeline, or nil where the clip never plays it (cut out, or held).
    public func timelineMS(ofClickAtSourceMS source: Int) -> Int? {
        guard let time, let pieces = clipPieces,
              let offset = pieces.playingOffsetMS(ofSourceMS: source) else { return nil }
        return time.inMS + offset
    }

    /// The moment of the recording playing at a moment of the document, for
    /// a click slid along the clip. Nil off the clip.
    public func sourceMS(ofClickAtTimelineMS ms: Int) -> Int? {
        guard let time, time.contains(ms: ms), let pieces = clipPieces else { return nil }
        return pieces.sourceMS(atMS: ms - time.inMS)
    }

    /// Derived the way a transition's second picture is
    /// (`transitionPartnerID`), so a click's mark is the same id in every
    /// render of the same moment and never the id of a real layer.
    static func clickMarkID(of id: UUID) -> UUID {
        var bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        bytes[0] ^= 0x3C
        bytes[15] ^= 0xC3
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// This layer, with the effect of every click playing at a moment of the
    /// document drawn over it. A layer drawn by `drawn(atTimeMS:)`: its frame
    /// is where it is at that moment and its zoom window is set.
    func withClickEffectsDrawn(atDocumentTimeMS ms: Int) -> [Layer] {
        var drawn = self
        if isGroup {
            drawn.children = children.flatMap { $0.withClickEffectsDrawn(atDocumentTimeMS: ms) }
        }
        guard isVisible, let effect = clickEffect, effect.isOn, let movie,
              let time, time.contains(ms: ms),
              movie.pixelSize.width > 0, movie.pixelSize.height > 0 else { return [drawn] }
        var marks: [Layer] = []
        for mark in clickMarks(recorded: nil) where !mark.isHidden {
            guard let at = timelineMS(ofClickAtSourceMS: mark.click.downMS) else { continue }
            let elapsed = ms - at
            guard elapsed >= 0, elapsed < ClickEffect.lengthMS else { continue }
            let progress = Double(elapsed) / Double(ClickEffect.lengthMS)
            if let drawnMark = clickEffectMark(effect, click: mark.click, movie: movie, progress: progress) {
                marks.append(drawnMark)
            }
        }
        return [drawn] + marks
    }

    /// One click's effect `progress` of the way through, as a shape over this
    /// clip, or nil where the click is not in the part of the picture shown.
    func clickEffectMark(_ effect: ClickEffect, click: PointerClick, movie: MovieRef,
                         progress t: Double) -> Layer? {
        let box = frame.standardized
        guard box.width > 0, box.height > 0 else { return nil }
        let picture = movie.pixelSize
        let window = zoomWindow ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        // The part of the recording the clip's picture holds: all of it, or
        // what its crop kept.
        let kept = pictureInRecording
        guard window.width > 0, window.height > 0, kept.width > 0, kept.height > 0 else { return nil }
        // Where the click is in the part of the picture shown, as fractions.
        let inPicture = CGPoint(x: (click.point.x / picture.width - kept.minX) / kept.width,
                                y: (click.point.y / picture.height - kept.minY) / kept.height)
        let shown = CGPoint(x: (inPicture.x - window.minX) / window.width,
                            y: (inPicture.y - window.minY) / window.height)
        guard shown.x >= 0, shown.x <= 1, shown.y >= 0, shown.y <= 1 else { return nil }
        let centre = CGPoint(x: box.minX + shown.x * box.width, y: box.minY + shown.y * box.height)
        // How wide it grows: a share of the recording, in the clip's points,
        // and bigger in a zoom, since it marks the picture.
        let reach = effect.size.share * min(picture.width, picture.height)
            * (box.width / (picture.width * kept.width)) / window.width
        guard reach > 0 else { return nil }
        let id = Self.clickMarkID(of: click.id)
        let spread = 1 - pow(1 - t, 3)
        switch effect.style {
        case .ripple:
            let width = reach * (0.3 + 0.7 * spread)
            let edge = max(2, reach * 0.09)
            var ring = Layer(id: id, name: "\(name) click",
                             content: .annotation(AnnotationContent(
                                shape: .ellipse, strokeWidth: edge, colorHex: effect.colorHex,
                                start: .zero, end: CGPoint(x: width, y: width))),
                             frame: CGRect(x: centre.x - width / 2, y: centre.y - width / 2,
                                           width: width, height: width),
                             isLocked: true)
            ring.style.opacity = pow(1 - t, 1.3)
            return ring
        case .pulse:
            let width = reach * (0.5 + 0.35 * spread)
            var dot = Layer(id: id, name: "\(name) click",
                            content: .annotation(AnnotationContent(
                                shape: .ellipse, strokeWidth: 0, colorHex: effect.colorHex,
                                start: .zero, end: CGPoint(x: width, y: width),
                                fillColorHex: effect.colorHex)),
                            frame: CGRect(x: centre.x - width / 2, y: centre.y - width / 2,
                                          width: width, height: width),
                            isLocked: true)
            dot.style.opacity = 0.6 * Self.envelope(t, rise: 0.15, fall: 0.85)
            return dot
        case .spotlight:
            var paint = Paint(hex: "#000000", kind: .radial,
                              center: CGPoint(x: (centre.x - box.minX) / box.width,
                                              y: (centre.y - box.minY) / box.height))
            let far = max(1, paint.radialRadius(in: CGRect(origin: .zero, size: box.size)))
            let clear = reach * 0.8
            let soft = reach * 0.5
            paint.stops = [GradientStop(hex: "#00000000", position: Double(clear / far)),
                           GradientStop(hex: "#000000", position: Double(min(far, clear + soft) / far))]
            var dim = AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                        start: .zero, end: CGPoint(x: box.width, y: box.height))
            dim.fill = paint
            var panel = Layer(id: id, name: "\(name) click", content: .annotation(dim),
                              frame: box, isLocked: true)
            panel.style.opacity = 0.5 * Self.envelope(t, rise: 0.2, fall: 0.3)
            return panel
        }
    }

    /// Up over the first `rise` of the way, held, and down over the last `fall`.
    static func envelope(_ t: Double, rise: Double, fall: Double) -> Double {
        if t < rise { return max(0, t / rise) }
        if t > 1 - fall { return max(0, (1 - t) / fall) }
        return 1
    }
}

extension ClipPieces {

    /// The first moment of the clip at which a moment of its recording plays,
    /// or nil where no piece plays it: cut out, or only ever held. Unlike
    /// `offsetMS(ofSourceMS:leaning:)` it never settles for the nearest.
    public func playingOffsetMS(ofSourceMS source: Int) -> Int? {
        var elapsed = 0
        for piece in pieces {
            defer { elapsed += piece.lengthMS }
            guard !piece.isHeld, piece.sourceLengthMS > 0,
                  source >= piece.sourceInMS, source < piece.sourceOutMS else { continue }
            let speed = Double(max(1, piece.speedPercent)) / 100
            return elapsed + min(Int((Double(source - piece.sourceInMS) / speed).rounded()), piece.lengthMS)
        }
        return nil
    }
}

// MARK: - Making and changing it

extension PhotonzDocument {

    /// Whether anything in this document draws its clicks.
    var hasClickEffects: Bool {
        allLayers.contains { $0.clickEffect?.isOn == true }
    }

    /// Change a clip's click effect, making it if it has none. Turned on with
    /// no copy of the recorded clicks yet, it keeps `recorded`.
    public mutating func setClickEffect(onClip id: UUID, recorded: [PointerClick]?,
                                        _ change: (inout ClickEffect) -> Void) {
        guard let layer = layer(id: id), layer.movie != nil else { return }
        var effect = layer.clickEffect ?? ClickEffect()
        change(&effect)
        if effect.isOn, effect.recorded == nil, let recorded, !recorded.isEmpty {
            effect.recorded = recorded
        }
        updateLayer(id: id) { $0.clickEffect = effect }
    }

    /// Hide one click, or show it again.
    public mutating func setClickHidden(onClip id: UUID, clickID: UUID, _ hidden: Bool) {
        guard let layer = layer(id: id), layer.movie != nil else { return }
        var effect = layer.clickEffect ?? ClickEffect()
        var ids = effect.hiddenIDs ?? []
        ids.removeAll { $0 == clickID }
        if hidden { ids.append(clickID) }
        effect.hiddenIDs = ids.isEmpty ? nil : ids
        updateLayer(id: id) { $0.clickEffect = effect }
    }

    /// Slide one click to another moment of the recording, kept inside the
    /// stretch the clip plays.
    public mutating func moveClick(onClip id: UUID, clickID: UUID, toSourceMS ms: Int) {
        guard let layer = layer(id: id), layer.movie != nil else { return }
        var effect = layer.clickEffect ?? ClickEffect()
        let range = layer.zoomSourceRange ?? 0...Int.max
        var moved = effect.movedMS ?? [:]
        moved[clickID.uuidString] = min(max(ms, range.lowerBound), range.upperBound)
        effect.movedMS = moved
        updateLayer(id: id) { $0.clickEffect = effect }
    }
}
