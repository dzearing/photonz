import CoreGraphics
import Foundation

// **The next thing you draw keeps the last one's look, fades included.**
//
// The user, 2026-10-19: "Today i wanted to make a video pause at sections have
// some arrows fade in and out. It was annoying to make it do that. I had to
// select each one, add a fade in, then add a fade out", and then "at minimum i
// wish it remembered the transitions from the previous object ... so then if i
// make another arrow, it retains the styling. Same goes for other things."
//
// A shape's colour, line, ending and effects have long been remembered per
// shape (`AnnotationStyles`). This is the rest of it:
//
//  - **the fade**, per kind of thing drawn, so the next arrow on a video comes
//    out fading in and out exactly as the last one was set to. It is only ever
//    handed to something that has a bar on the timeline, and it never moves
//    either end of that bar: an arrow drawn on a freeze still takes the hold,
//    and fades longer than the hold share it (`PictureFade.fitted`);
//  - **the effects of the kinds the shape tools never covered**: words and a
//    Pen path. Shadow, opacity, blur and the rest go to the next one as they do
//    for a box.
//
// A recording is not something drawn and has no kind, so fading one never
// teaches the next clip anything: Premiere does not fade a clip you drop just
// because you faded the one before it.

/// What kind of drawn thing a layer is: the bucket its look is remembered in.
public enum DrawnKind: String, Codable, CaseIterable, Sendable {
    case arrow, line, rectangle, ellipse, highlight
    case text, path, picture, measurement, callout, lens
    /// Words on a video, which start with the title look rather than the
    /// still-picture one. Never read off a layer: the app says which.
    case title

    /// The kind `layer` is, or nil for anything that is not drawn: a
    /// recording, a sound, a group, a caption.
    public init?(_ layer: Layer) {
        guard !layer.hasMediaBehindIt, !layer.isCaption else { return nil }
        switch layer.content {
        case .annotation(let shape):
            switch shape.shape {
            case .arrow: self = .arrow
            case .line: self = .line
            case .rectangle: self = .rectangle
            case .ellipse: self = .ellipse
            case .highlight: self = .highlight
            }
        case .text: self = .text
        case .path: self = .path
        case .image: self = .picture
        case .measure: self = .measurement
        case .zoomCallout: self = .callout
        case .lens: self = .lens
        default: return nil
        }
    }

    /// The kinds whose effects are remembered here. A shape keeps its own in
    /// `AnnotationStyles` (edge and all), and a measurement in its own styles.
    public var remembersItsEffectsHere: Bool { self == .text || self == .title || self == .path }
}

/// What the next thing of each kind starts with, beyond what `AnnotationStyles`
/// and `TextStyles` already carry. Codable so it survives launches.
public struct RememberedLooks: Equatable, Codable, Sendable {
    /// The fade each kind was last left with, keyed by `DrawnKind.rawValue`.
    private var fades: [String: PictureFade] = [:]
    /// The effects each kind was last styled with.
    private var styles: [String: LayerStyle] = [:]
    /// The style the layer those effects were read off STARTED with, so a
    /// shadow nobody touched is told from one somebody chose.
    private var standards: [String: LayerStyle] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fades = try c.decodeIfPresent([String: PictureFade].self, forKey: .fades) ?? [:]
        styles = try c.decodeIfPresent([String: LayerStyle].self, forKey: .styles) ?? [:]
        standards = try c.decodeIfPresent([String: LayerStyle].self, forKey: .standards) ?? [:]
    }

    // MARK: The fade

    /// The fade the next thing of this kind arrives with on a video, or nil.
    public func fade(for kind: DrawnKind) -> PictureFade? { fades[kind.rawValue] }

    /// The next of `layer`'s kind arrives faded the way it is now: both ends
    /// and the curve, or not at all where it fades at neither end. A layer
    /// that is not drawn, or has no bar, teaches nothing.
    public mutating func rememberFade(of layer: Layer) {
        guard let kind = DrawnKind(layer), layer.canFadePicture else { return }
        let fade = layer.pictureFade ?? layer.shownPictureFade
        if let fade, !fade.isNone {
            fades[kind.rawValue] = fade
        } else {
            fades[kind.rawValue] = nil
        }
    }

    /// What **Fade In and Out** sets on a thing of this kind: the remembered
    /// lengths, an end with none taking the other's, and a second each where
    /// nothing is remembered, the default transition length in both Premiere
    /// and Final Cut.
    public func bothEnds(for kind: DrawnKind?) -> PictureFade {
        let standard = RememberedLooks.standardFadeMS
        guard let kind, let fade = fade(for: kind) else { return PictureFade(inMS: standard, outMS: standard) }
        let inMS = fade.inMS > 0 ? fade.inMS : (fade.outMS > 0 ? fade.outMS : standard)
        let outMS = fade.outMS > 0 ? fade.outMS : inMS
        return PictureFade(inMS: inMS, outMS: outMS)
    }

    /// A second: the length a fade starts at when nothing is remembered.
    public static let standardFadeMS = 1000

    /// Whether every one of `layers` already fades at both ends, which is what
    /// puts the tick on Fade In and Out.
    public static func fadesAtBothEnds(_ layers: [Layer]) -> Bool {
        !layers.isEmpty && layers.allSatisfy { $0.pictureFadeMS(.in) > 0 && $0.pictureFadeMS(.out) > 0 }
    }

    // MARK: The effects

    /// The effects the next of this kind starts with, or nil for its own.
    public func style(for kind: DrawnKind) -> LayerStyle? { styles[kind.rawValue] }

    /// Remember `style` for the next of `kind`, read off a layer that started
    /// as `standard`: what its kind is always given before anybody styles it.
    public mutating func rememberStyle(_ style: LayerStyle, for kind: DrawnKind,
                                       startedWith standard: LayerStyle = LayerStyle()) {
        guard kind.remembersItsEffectsHere else { return }
        styles[kind.rawValue] = style
        standards[kind.rawValue] = standard
    }

    /// `layer` as it arrives: the remembered effects of `kind` (its own kind
    /// where nil), where it came with only `standard`, the style its kind is
    /// always given. A layer somebody already styled keeps its own.
    ///
    /// The shadow is the one exception. Words start with a shadow picked to
    /// stand out from their colour (`TextBuilder.autoContrastShadow`, and a
    /// title's `TitleLook.shadows`); where the remembered words still wore the
    /// one they started with, the new words keep the one that suits THEIR
    /// colour, so black words after white ones never arrive over a black
    /// shadow. A shadow somebody chose goes across as it is.
    public func wearing(_ layer: Layer, as kind: DrawnKind? = nil,
                        startsWith standard: LayerStyle = LayerStyle()) -> Layer {
        guard let kind = kind ?? DrawnKind(layer), let remembered = style(for: kind),
              layer.style == standard else { return layer }
        var style = remembered
        if let was = standards[kind.rawValue], remembered.shadows == was.shadows {
            style.shadows = standard.shadows
        }
        var worn = layer
        worn.style = style
        return worn
    }

    /// `layer`, just given a bar on the timeline some way other than
    /// `addLayerDrawn`, with the fade its kind was last left with, where it
    /// brought none of its own.
    public func fading(_ layer: Layer) -> Layer {
        guard let kind = DrawnKind(layer), let fade = fade(for: kind), layer.pictureFade == nil,
              layer.canFadePicture else { return layer }
        var faded = layer
        faded.pictureFade = fade
        return faded
    }
}

// MARK: - Several at once, both ends at once

extension PhotonzDocument {

    /// Fade every one of `ids` that can fade, at the ends given, leaving an
    /// end passed as nil as each one has it. Nought at an end takes that end
    /// off. Returns the layers that changed.
    ///
    /// Unlike one end set from a menu row, nothing is refused for want of
    /// room: fades longer than a bar share it in proportion when it is drawn
    /// (`PictureFade.fitted`), so three arrows on holds of different lengths
    /// all take the same command, and none of their bars moves.
    @discardableResult
    public mutating func setPictureFades(_ ids: [UUID], inMS: Int?, outMS: Int?) -> [UUID] {
        var changed: [UUID] = []
        for id in ids {
            guard let layer = layer(id: id), layer.canFadePicture else { continue }
            let was = layer.pictureFade ?? layer.shownPictureFade ?? PictureFade(inMS: 0, outMS: 0)
            var fade = was
            if let inMS { fade.inMS = max(0, inMS) }
            if let outMS { fade.outMS = max(0, outMS) }
            let next: PictureFade? = fade.isNone ? nil : fade
            guard next != layer.pictureFade || layer.titleFadeMS != nil else { continue }
            let opening = outMS != nil ? openingDissolveStartMS(id) : nil
            let oldTitleFade = layer.pictureFade == nil && layer.titleFadeMS != nil
            updateLayer(id: id) { found in
                if oldTitleFade {
                    let motions = (found.motions ?? []).filter { $0.property != .opacity }
                    found.motions = motions.isEmpty ? nil : motions
                }
                found.pictureFade = next
            }
            if let opening { keepOpeningDissolve(id, from: opening) }
            changed.append(id)
        }
        return changed
    }

    /// A layer drawn at a moment, placed in time where asked, and arriving
    /// with `fade` where that gave it a bar and it brought no fade of its own.
    /// The fade never moves either end of the bar.
    public mutating func addLayerDrawn(_ layer: Layer, atTimeMS ms: Int, placingInTime: Bool,
                                       fade: PictureFade?) {
        var drawn = layer
        if placingInTime, drawn.time == nil, let span = drawnSpan(atTimeMS: ms) {
            drawn.time = span
        }
        if let fade, !fade.isNone, drawn.pictureFade == nil, drawn.canFadePicture {
            drawn.pictureFade = fade
        }
        addLayerDrawn(drawn, atTimeMS: ms)
    }
}
