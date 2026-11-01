import CoreGraphics
import Foundation

/// A measurement's readout wears the same chip as an arrow's label: the ten
/// styles, the one Color and the marker (`ChipStyle.swift`,
/// `docs/design/markup.md`). The user, 2026-10-31: every measurement wears the
/// same chip styles, colour and marker as an arrow label, so a redline is one
/// system.
///
/// The caliper's ink (`strokeColorHex`) is the mark's one colour. A styled
/// chip writes the colours its style derives from that ink onto the chip's
/// own three parts (`chipColorHex`, `chipBorderColorHex`, `textColorHex`), so
/// the parts list, the SVG writer and every other reader of those fields sees
/// what is drawn. A part painted by hand on its row keeps its colour until it
/// is reset, exactly as an arrow label's does.
///
/// Nil `chipStyle` is the pill every measurement wore before there were
/// styles, and it draws from its stored colours exactly as it always did.
extension MeasureContent {

    /// The chip this readout is drawn on, or nil for the pill from before
    /// styles.
    public var chipLook: ChipLook? {
        guard let chipStyle else { return nil }
        return ChipLook.resolve(style: chipStyle, ink: strokeColorHex,
                                fill: hasChipFill ? chipFillHexWithAlpha : nil,
                                edge: hasChipBorder ? chipBorderColorHex : nil,
                                text: textColorHex, marker: chipMarker)
    }

    /// The style a tile row shows as on: the pill from before styles is
    /// Today's look (a dark plate in the ink and an outline in it).
    public var shownChipStyle: ChipStyle { chipStyle ?? .today }

    /// Whether this readout's chip is frosted glass, which the renderer draws
    /// from the picture behind the layer.
    public var drawsFrostedChip: Bool { chipStyle == .glass && showLabel }

    /// How heavy the readout's words are: semibold on a styled chip, as the
    /// design system sets them; the pill from before styles keeps its regular
    /// ones.
    public var chipFontWeight: TextWeight { chipStyle == nil ? .regular : .semibold }

    /// How much wider semibold words run than regular ones, for the frame
    /// reservation, which is worked out from a count of characters rather than
    /// measured glyphs. One for the pill from before styles.
    var chipWeightWidening: CGFloat { chipStyle == nil ? 1 : 1.08 }

    /// The extra width a marker or accent takes at the chip's front.
    public var chipLeadWidth: CGFloat {
        chipLook?.leadWidth(padding: labelPadding, fontSize: labelPointSize) ?? 0
    }

    /// How round the chip's corners are for a chip of `size`: the style's own
    /// share of half its height, or a capsule for the pill from before styles.
    /// Everything that has to meet the chip's outline (the caliper's line, a
    /// leader) reads it from here.
    public func chipCornerRadius(for size: CGSize) -> CGFloat {
        let capsule = LabelCapsule.capsuleRadius(for: size)
        guard let chipStyle else { return capsule }
        return capsule * min(max(chipStyle.roundness, 0), 1)
    }

    /// Room kept round the chip for its drop shadow, so a style whose shadow
    /// reaches further than the ring never clips at the layer's edge.
    var chipShadowSlack: CGFloat {
        guard let look = chipLook else { return 0 }
        let u = ChipLook.unit(fontSize: labelPointSize)
        let reach = look.shadows.map { (abs($0.y) + $0.blur) * u + 2 }.max() ?? 0
        return reach.rounded(.up)
    }

    /// Puts the readout's chip in `style`: its plate, edge and words painted
    /// from the caliper's ink. Parts set by hand keep their colour.
    public mutating func applyChipStyle(_ style: ChipStyle) {
        chipStyle = style
        // The edge's thickness is the style's: Today's outline is the one the
        // pill always had, every other edge is the style's hairline.
        if style.parts(forInk: strokeColorHex).edge != nil, !chipPartsByHand.contains(.edge) {
            chipBorderWidth = style == .today
                ? (hasChipBorder ? chipBorderWidth : startingChipBorderWidth)
                : max(1, ChipLook.unit(fontSize: labelPointSize))
        }
        rederiveChipParts()
    }

    /// The one Color (markup.md section 2): the caliper takes `hex` exactly as
    /// picked and the chip derives its plate, edge and words from it. A pill
    /// from before styles first takes Today, the look it already wears, so
    /// the colour reaches the chip the same way it does on every other mark.
    public mutating func setInk(_ hex: String) {
        if chipStyle == nil { applyChipStyle(.today) }
        strokeColorHex = hex
    }

    /// Paints one chip part by hand: it keeps this colour through any style or
    /// colour change until it is reset.
    public mutating func setChipPartByHand(_ part: CaptionPart, hex: String) {
        switch part {
        case .fill: setChipFillHex(hex)
        case .edge:
            chipBorderColorHex = hex
            if !hasChipBorder { chipBorderWidth = startingChipBorderWidth }
        case .text: textColorHex = hex
        }
        noteChipPartByHand(part)
    }

    /// Marks a part as set by hand after its row painted it.
    mutating func noteChipPartByHand(_ part: CaptionPart) {
        if chipStyle != nil { chipPartsByHand.insert(part) }
    }

    /// Hands chip parts back to the style.
    public mutating func resetChipPartsByHand(_ parts: Set<CaptionPart> = Set(CaptionPart.allCases)) {
        chipPartsByHand.subtract(parts)
        rederiveChipParts()
    }

    /// Whether one step can hand the chip back to its automatic colours.
    public var canRestoreAutomaticChip: Bool {
        showLabel && (chipStyle == nil || !chipPartsByHand.isEmpty)
    }

    /// Puts the chip back on the colours its style derives from the ink, so
    /// the words read again. A pill from before styles takes Today.
    public mutating func restoreAutomaticChip() {
        guard showLabel else { return }
        if chipStyle == nil { applyChipStyle(.today) }
        resetChipPartsByHand()
    }

    /// The worst contrast the readout's words have on their chip as it is
    /// drawn, a see-through plate judged over a white and a black picture
    /// alike. Nil with nothing to judge: no readout, or no plate.
    public var chipWordContrast: Double? {
        guard showLabel else { return nil }
        if let look = chipLook {
            guard look.fillTop != nil else { return nil }
            return [RGBA(r: 1, g: 1, b: 1), RGBA(r: 0, g: 0, b: 0)]
                .map { look.wordContrast(over: $0) }.min()
        }
        guard hasChipFill, chipOpacity > 0.5, let back = RGBA(hex: chipColorHex),
              let ink = RGBA(hex: textColorHex) else { return nil }
        return InkPlate.contrast(ink, back)
    }

    /// Writes the style's colours for the caliper's ink onto every chip part
    /// not set by hand. Nothing for a pill from before styles.
    mutating func rederiveChipParts() {
        guard let chipStyle else { return }
        let parts = chipStyle.parts(forInk: strokeColorHex)
        let byHand = chipPartsByHand
        if !byHand.contains(.fill) {
            if let fill = parts.fill {
                chipColorHex = fill
                chipOpacity = 1
            } else {
                chipOpacity = 0
            }
        }
        if !byHand.contains(.edge) {
            if let edge = parts.edge {
                chipBorderColorHex = edge
                if !hasChipBorder { chipBorderWidth = startingChipBorderWidth }
            } else {
                chipBorderWidth = 0
            }
        }
        if !byHand.contains(.text) { textColorHex = parts.text }
    }
}

extension MeasureBuilder {
    /// A change to a measurement's chip (its style, marker, colour or parts),
    /// with the frame re-padded for the chip's new room and the feet left
    /// where they were in the document.
    public static func rechipped(_ layer: Layer, _ change: (inout MeasureContent) -> Void) -> Layer {
        guard var m = layer.measure,
              let start = layer.measureEndpoint(.start),
              let end = layer.measureEndpoint(.end) else { return layer }
        change(&m)
        var updated = layer
        updated.content = .measure(m)
        return updating(updated, start: start, end: end)
    }
}
