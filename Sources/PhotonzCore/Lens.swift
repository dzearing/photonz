import CoreGraphics
import Foundation

/// What a lens layer DOES to the picture underneath it.
///
/// These are not entries in the Effects list and they are deliberately not
/// modelled as ones. An effect is something you added to a layer, and it acts
/// on the layer's own pixels: a blur in the Effects list softens the box you
/// drew. A lens acts on the opposite input — whatever is composited BELOW it —
/// so it is what the layer IS, not what it has. One list, one meaning.
public enum LensAdjustment: String, CaseIterable, Hashable, Codable, Sendable {
    /// Softens what is underneath, so an address stops being readable.
    case blur
    /// Replaces what is underneath with square blocks of its average colour.
    case pixelate
    /// Drains the colour out of what is underneath.
    case greyscale
    /// Flips what is underneath to its opposite colour.
    case invert
    /// Lifts what is underneath towards white, or pushes it towards black.
    case brightness

    /// The word on the adjustment, in the tool's capsule and in the panel.
    public var title: String {
        switch self {
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        case .greyscale: "Greyscale"
        case .invert: "Invert"
        case .brightness: "Brightness"
        }
    }

    /// The word on this adjustment's one number, or nil for the one that has
    /// no number at all. The panel ASKS rather than knowing, so a slider with
    /// nothing to set is never drawn beside Invert.
    public var settingTitle: String? {
        switch self {
        case .blur: "Strength"
        case .pixelate: "Block size"
        case .greyscale: "Amount"
        case .invert: nil
        case .brightness: "Amount"
        }
    }

    /// What the slider offers.
    ///
    /// Blur stops at 60pt and pixelate at 80pt because past that a lens over a
    /// name is a lens over half the screenshot. Brightness runs both ways from
    /// nought, which is what makes one adjustment cover Brighten and Darken
    /// rather than two that behave identically in opposite directions.
    public var range: ClosedRange<CGFloat> {
        switch self {
        case .blur: 1...60
        case .pixelate: 2...80
        case .greyscale: 0...1
        case .invert: 0...0
        case .brightness: -1...1
        }
    }

    /// Where a fresh lens starts. Blur and pixelate start strong enough to
    /// actually hide a word — the commonest reason anyone reaches for either —
    /// rather than at a polite setting that still reads.
    public var defaultAmount: CGFloat {
        switch self {
        case .blur: 8
        case .pixelate: 12
        case .greyscale: 1
        case .invert: 0
        case .brightness: 0.35
        }
    }

    /// Whether this number is a LENGTH measured in document points, and so has
    /// to grow with the picture on a magnified render. A blur's sigma and a
    /// block's side are lengths; a greyscale mix and a brightness shift are
    /// not, and mean the same thing at any zoom (`Layer.magnified(by:)`).
    public var isLength: Bool {
        switch self {
        case .blur, .pixelate: true
        case .greyscale, .invert, .brightness: false
        }
    }

    /// The readout beside the slider: points for the two lengths, a percentage
    /// for the two mixes, and nothing at all for the adjustment with no
    /// number. Brightness keeps its sign, since which way it went is the whole
    /// difference between brightening and darkening.
    public func label(_ amount: CGFloat) -> String {
        guard amount.isFinite else { return label(defaultAmount) }
        switch self {
        case .blur, .pixelate:
            return "\(Int(amount.rounded())) pt"
        case .greyscale:
            return "\(Int((amount * 100).rounded()))%"
        case .invert:
            return ""
        case .brightness:
            let percent = Int((amount * 100).rounded())
            return percent > 0 ? "+\(percent)%" : "\(percent)%"
        }
    }
}

/// A layer whose picture is whatever is composited beneath it, drawn through
/// one adjustment. Its frame is the region it covers; its corner radii, border,
/// shadow and opacity are the layer's own, like any other.
///
/// Every adjustment keeps its OWN number rather than sharing one, so switching
/// a lens to Pixelate and back hands your blur strength back instead of a block
/// size standing in for it. That costs four stored numbers and buys the thing
/// people actually do: try the other one, then change their mind.
public struct LensContent: Hashable, Codable, Sendable {
    public var adjustment: LensAdjustment
    /// Gaussian sigma, in document points.
    public var blurRadius: CGFloat
    /// The side of one block, in document points.
    public var blockSize: CGFloat
    /// How much of the colour is drained, 0 to 1.
    public var greyscaleAmount: CGFloat
    /// How far the picture is lifted or pushed, -1 to 1.
    public var brightness: CGFloat

    public init(adjustment: LensAdjustment = .blur,
                blurRadius: CGFloat = LensAdjustment.blur.defaultAmount,
                blockSize: CGFloat = LensAdjustment.pixelate.defaultAmount,
                greyscaleAmount: CGFloat = LensAdjustment.greyscale.defaultAmount,
                brightness: CGFloat = LensAdjustment.brightness.defaultAmount) {
        self.adjustment = adjustment
        self.blurRadius = blurRadius
        self.blockSize = blockSize
        self.greyscaleAmount = greyscaleAmount
        self.brightness = brightness
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        adjustment = try c.decodeIfPresent(LensAdjustment.self, forKey: .adjustment) ?? .blur
        // Each number defaults on its own, so a lens saved by a build that had
        // fewer adjustments than this one opens as a working lens rather than
        // throwing.
        blurRadius = try c.decodeIfPresent(CGFloat.self, forKey: .blurRadius)
            ?? LensAdjustment.blur.defaultAmount
        blockSize = try c.decodeIfPresent(CGFloat.self, forKey: .blockSize)
            ?? LensAdjustment.pixelate.defaultAmount
        greyscaleAmount = try c.decodeIfPresent(CGFloat.self, forKey: .greyscaleAmount)
            ?? LensAdjustment.greyscale.defaultAmount
        brightness = try c.decodeIfPresent(CGFloat.self, forKey: .brightness)
            ?? LensAdjustment.brightness.defaultAmount
    }

    /// The number the adjustment in force is using. Reading and writing this
    /// is what every slider in the product does; writing pulls the value
    /// inside what that adjustment offers.
    public var amount: CGFloat {
        get { amount(for: adjustment) }
        set { setAmount(newValue, for: adjustment) }
    }

    public func amount(for adjustment: LensAdjustment) -> CGFloat {
        switch adjustment {
        case .blur: blurRadius
        case .pixelate: blockSize
        case .greyscale: greyscaleAmount
        case .invert: 0
        case .brightness: brightness
        }
    }

    /// Sets one adjustment's number, held inside the range that adjustment
    /// offers. A value that is not a number at all falls back to the default:
    /// a lens you can still see beats a lens that vanished.
    public mutating func setAmount(_ value: CGFloat, for adjustment: LensAdjustment) {
        let range = adjustment.range
        let clamped = value.isFinite
            ? min(max(value, range.lowerBound), range.upperBound)
            : adjustment.defaultAmount
        switch adjustment {
        case .blur: blurRadius = clamped
        case .pixelate: blockSize = clamped
        case .greyscale: greyscaleAmount = clamped
        case .invert: break
        case .brightness: brightness = clamped
        }
    }

    /// How far OUTSIDE its own box the renderer has to sample before it
    /// filters, in the same unit the box is stated in.
    ///
    /// Blur and pixelate are neighbourhood operations: they mix a pixel with
    /// its neighbours, so cutting the picture to the box first leaves the edge
    /// mixed with the transparency beyond it, which reads as a dark rim.
    /// Sample wider, filter, then cut. Three sigma covers a gaussian's visible
    /// tail, the same reach `blurred` already reserves everywhere else.
    public var sampleReach: CGFloat {
        switch adjustment {
        case .blur: (blurRadius * 3).rounded(.up)
        case .pixelate: blockSize.rounded(.up)
        case .greyscale, .invert, .brightness: 0
        }
    }

    /// Whether this lens changes nothing at all, so the renderer can hand the
    /// backdrop straight back instead of paying for a filter.
    public var isIdentity: Bool {
        switch adjustment {
        case .blur: blurRadius <= 0
        case .pixelate: blockSize <= 1
        case .greyscale: greyscaleAmount <= 0
        case .invert: false
        case .brightness: brightness == 0
        }
    }

    /// The two lengths restated in a bigger unit, for a render at `scale`
    /// output pixels per document point. The mixes are left alone: a
    /// half-drained colour is half drained at any zoom.
    func magnified(by scale: CGFloat) -> LensContent {
        guard scale > 0, scale != 1, scale.isFinite else { return self }
        var out = self
        // Deliberately NOT clamped to the slider's range: a 60pt blur exported
        // at 4x is a 240pt blur, and pulling it back to 60 would quietly
        // sharpen the very thing somebody hid.
        out.blurRadius = blurRadius * scale
        out.blockSize = blockSize * scale
        return out
    }
}

/// Builds lens layers from completed drags.
public enum LensBuilder {

    /// Drags smaller than this (either axis, document points) are stray
    /// clicks, not a region anybody meant to cover.
    public static let minimumSide: CGFloat = 4

    /// What a new lens looks like: nothing. No border, no shadow, no rounding.
    ///
    /// A lens is the one layer whose whole job is to look like the picture it
    /// sits on, changed. Chrome round it would be a second thing to explain
    /// and a second thing to turn off, and everything needed to add a ring or
    /// a shadow is already in Appearance and Effects for the one case that
    /// wants it.
    public static var defaultStyle: LayerStyle { LayerStyle() }

    /// The layer a drag from `start` to `end` (document coordinates) creates:
    /// the box you drew, cut to the canvas. Nil when the box is a stray click
    /// or falls off the picture entirely.
    public static func layer(from start: CGPoint, to end: CGPoint, canvas: CGSize,
                             adjustment: LensAdjustment = .blur,
                             content: LensContent? = nil,
                             style: LayerStyle = LensBuilder.defaultStyle) -> Layer? {
        let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y))
        let frame = Geometry.pixelAligned(box.intersection(CGRect(origin: .zero, size: canvas)))
        guard frame.width >= minimumSide, frame.height >= minimumSide else { return nil }
        var lens = content ?? LensContent()
        lens.adjustment = adjustment
        return Layer(name: adjustment.title, content: .lens(lens), frame: frame, style: style)
    }
}

extension Layer {
    /// The layer's lens content, nil for other content kinds.
    public var lens: LensContent? {
        if case .lens(let lens) = content { return lens }
        return nil
    }

    /// Whether this layer's picture is not its own: it draws what is
    /// composited BELOW it. A zoom callout magnifies a region of it; a lens
    /// draws the part of it under its own box.
    ///
    /// Three places ask: the renderer (which has to hand it the backdrop), the
    /// drag preview (which cannot sprite a layer whose picture changes as it
    /// moves) and the dirty region (which has to redraw it when something
    /// under it changes).
    public var readsBackdrop: Bool { content.readsBackdrop }

    /// The canvas region this layer reads, so a change touching it means this
    /// layer must be drawn again. Nil for everything that draws itself.
    public var backdropSource: CGRect? {
        switch content {
        case .zoomCallout(let callout):
            return callout.sourceRect.standardized
        case .lens(let lens):
            let reach = lens.sampleReach
            // A TURNED lens shows the picture underneath the right way up, so
            // what it reads is the canvas its TURNED box covers, not the box
            // it was stored as. With the stored box, a change in a corner the
            // turn swung into view would never redraw it.
            let box = transform.isIdentity
                ? frame.standardized
                : frame.standardized.applying(transform.affineTransform(around: turnPivot))
            return box.insetBy(dx: -reach, dy: -reach)
        default:
            return nil
        }
    }
}

extension LayerContent {
    /// Whether this content draws what is composited below the layer rather
    /// than a picture of its own.
    public var readsBackdrop: Bool {
        switch self {
        // Sound draws nothing, so it reads nothing either.
        case .sound: false
        case .zoomCallout, .lens: true
        case .image, .text, .annotation, .measure, .collage, .group, .path: false
        }
    }
}

/// The six things the Lens tool can be set to do: the five adjustments, and
/// Magnify.
///
/// Magnify is not a sixth `LensAdjustment` and deliberately so. The five
/// adjustments all act on the picture under the layer's own box and carry one
/// number; Magnify's picture comes from somewhere ELSE on the canvas, so it
/// carries a source region, a magnification and a shape, and what it draws is a
/// zoom callout (`ZoomCalloutContent`). Putting it in `LensAdjustment` would
/// hang a magnification on every lens that never uses one and let `LensBuilder`
/// build a lens with no source. So the TOOL offers six kinds and the CONTENT
/// stays two shapes, which is the honest split.
///
/// Raw values match `LensAdjustment`'s, so a kind and an adjustment read off
/// disk can never drift apart.
public enum LensKind: String, CaseIterable, Hashable, Codable, Sendable {
    case blur
    case pixelate
    case greyscale
    case invert
    case brightness
    /// Draws a magnified copy of a region somewhere else on the picture, with
    /// a line back to where it came from. Last in the list because the five
    /// above it were there first: an order somebody has learned does not get
    /// reshuffled to make room.
    case magnify

    public init(_ adjustment: LensAdjustment) {
        self = LensKind(rawValue: adjustment.rawValue) ?? .blur
    }

    /// The adjustment this kind holds, nil for the one that is not an
    /// adjustment at all.
    public var adjustment: LensAdjustment? { LensAdjustment(rawValue: rawValue) }

    public var magnifies: Bool { self == .magnify }

    /// The word on the kind, in the tool's capsule and in the panel.
    public var title: String { adjustment?.title ?? "Magnify" }
}

extension Layer {
    /// What this layer does to the picture underneath it, nil when it does
    /// nothing to it at all. A lens says its adjustment; a zoom callout says
    /// Magnify, because that is what it is.
    public var lensKind: LensKind? {
        switch content {
        case .lens(let lens): LensKind(lens.adjustment)
        case .zoomCallout: .magnify
        default: nil
        }
    }
}

/// Switching a layer already on the picture from one lens kind to another.
///
/// The two directions are not symmetric, because a magnifier's picture comes
/// from somewhere else and a lens's does not:
///
/// - **Magnify to an adjustment** keeps the box exactly where it is. Somebody
///   switching their magnifier to Blur is looking AT that box, so it must not
///   move out from under them; it simply stops magnifying and starts blurring
///   what it sits on.
/// - **An adjustment to Magnify** takes the lens's box as the SOURCE — that is
///   the region it was covering, which is the region you meant — and places the
///   magnified box beside it the same way a freshly drawn callout is placed. The
///   box moves, which is what a magnifier IS, and it is one undo away.
public enum LensConversion {

    /// The names a layer wears because of its kind rather than because anybody
    /// typed them. "Zoom" is in the list: it is what every callout drawn before
    /// Magnify existed is called.
    static func isAutomaticName(_ name: String) -> Bool {
        name == "Zoom" || LensKind.allCases.contains { $0.title == name }
    }

    /// `layer` as `kind`. Returns it unchanged when it is that already, when it
    /// is neither a lens nor a callout, or when the change cannot be made —
    /// a box too small to magnify comes back as the lens it still is rather
    /// than as a callout nobody can see.
    ///
    /// `lensSettings` is the Lens tool's own numbers, so a lens made this way
    /// is the lens the tool would have drawn. `magnification`, `shape` and
    /// `avoiding` are the same three the callout tool hands `ZoomCalloutBuilder`.
    public static func layer(_ layer: Layer, becoming kind: LensKind, canvas: CGSize,
                             lensSettings: LensContent = LensContent(),
                             magnification: CGFloat = ZoomCalloutBuilder.defaultMagnification,
                             shape: ZoomCalloutShape = .rectangle,
                             avoiding occupied: [CGRect] = []) -> Layer {
        guard let was = layer.lensKind, was != kind else { return layer }
        var out = layer
        if let adjustment = kind.adjustment {
            var lens = layer.lens ?? lensSettings
            lens.adjustment = adjustment
            out.content = .lens(lens)
        } else {
            let source = Geometry.pixelAligned(
                layer.frame.standardized.intersection(CGRect(origin: .zero, size: canvas)))
            guard source.width >= ZoomCalloutBuilder.minimumSourceSide,
                  source.height >= ZoomCalloutBuilder.minimumSourceSide else { return layer }
            out.content = .zoomCallout(ZoomCalloutContent(sourceRect: source,
                                                          magnification: magnification,
                                                          shape: shape))
            out.frame = Geometry.zoomCalloutPlacement(source: source,
                                                      magnification: magnification,
                                                      canvas: canvas, avoiding: occupied)
            // A lens wears no ring on purpose — its whole job is to look like
            // the picture, changed — but a magnifier's source outline and its
            // leader lines are drawn in the RING's colour and weight
            // (`ZoomCalloutOverlayRasterizer`). With none, they come out a
            // one-point black hairline that disappears on a dark screenshot,
            // so a layer with no ring is given the one a freshly drawn
            // magnifier has. A ring somebody chose is left exactly as chosen.
            if out.style.borderWidth <= 0 {
                out.style.borderWidth = ZoomCalloutBuilder.defaultStyle.borderWidth
                out.style.borderColorHex = ZoomCalloutBuilder.defaultStyle.borderColorHex
            }
        }
        if isAutomaticName(layer.name) { out.name = kind.title }
        return out
    }
}
