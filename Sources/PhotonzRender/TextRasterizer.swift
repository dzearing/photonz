import CoreGraphics
import CoreText
import Foundation
import PhotonzCore

/// Rasterizes `TextContent` into a transparent-background CGImage via CoreText.
/// No AppKit: fonts come from CTFontDescriptor matching, colors from the
/// model's hex strings.
public enum TextRasterizer {

    /// Slack `naturalSize` adds beyond the measured text so rounding and
    /// antialiased glyph edges never clip at the frame boundary. Drawing stays
    /// flush to the frame's top-left (insetting the draw path would make
    /// CoreText drop lines in frames a hair shorter than the line height).
    public static let frameInset: CGFloat = 2

    /// The minimum width (document points) a text block floors at, so a short
    /// caption isn't a sliver and so the live editor and committed frame agree on
    /// a sensible minimum. Shared by the canvas inline editor and `naturalSize`.
    /// It is the model's floor (`TextMeasurement.minimumWidth`), not a second
    /// number: the width you type into the inspector stops in the same place
    /// the width you drag does.
    public static let minimumTextWidth: CGFloat = TextMeasurement.minimumWidth

    /// Renders `text` word-wrapped inside `size` (the layer's box, in document
    /// points), sitting where its `alignment` and `verticalAlignment` say — top
    /// left for text that has never been given a place, which is every document
    /// written before those existed. A `borderWidth > 0` strokes the glyph
    /// OUTLINES in `borderColorHex` (a text outline), not a box — the layer's
    /// box border is suppressed for text.
    ///
    /// `scale` is how many pixels the result gets per document point, so the
    /// canvas can bake a label at the resolution the zoom is about to show it
    /// at and the words stay sharp instead of being blown up afterwards. It
    /// scales the drawing, never the type: the point size, the line breaks and
    /// the box the words sit in are identical at every scale, so a label does
    /// not shift or re-wrap when a sharper copy of it arrives.
    public static func rasterize(_ text: TextContent, size: CGSize,
                                 borderWidth: CGFloat = 0,
                                 borderColorHex: String = "#000000",
                                 scale: CGFloat = 1) -> CGImage? {
        guard scale > 0, scale.isFinite else { return nil }
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width >= 1, height >= 1 else { return nil }

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        // Everything below lays out in document points; the context turns them
        // into however many pixels `scale` asked for.
        context.scaleBy(x: scale, y: scale)

        let box = CGRect(x: 0, y: 0,
                         width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        let path = CGPath(rect: laidOutBox(text, in: box), transform: nil)
        func draw(_ attributed: NSAttributedString) {
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            CTFrameDraw(frame, context)
        }

        if borderWidth > 0, text.fontSize > 0 {
            // Outer border: draw fat border-colored glyphs underneath, then the
            // normal fill on top, so the stroke shows only OUTSIDE the letters —
            // it grows outward with the fill intact. (A single centered stroke
            // would eat into the glyphs.) The underlay stroke is doubled because a
            // centered stroke extends half its width outward.
            var underlay = text
            underlay.colorHex = borderColorHex
            draw(attributedString(underlay, borderWidth: borderWidth * 2, borderColorHex: borderColorHex))
            draw(attributedString(text))
        } else {
            draw(attributedString(text))
        }

        return context.makeImage()
    }

    /// The part of `box` the lines are laid out in, so text that does not fill
    /// its box sits where `verticalAlignment` says.
    ///
    /// CoreText fills a frame from its TOP edge down, so "top" is the whole box
    /// — byte for byte what this drew before alignment existed — and the other
    /// two shrink the box to the height the lines actually need and slide it.
    /// Text that needs at least the box it has keeps the whole box: a rect even
    /// a hair short makes CoreText drop the last line, and losing a word is
    /// worse than a line of text hugging the top of a box too small for it.
    private static func laidOutBox(_ text: TextContent, in box: CGRect) -> CGRect {
        let box = alignedWidth(text, in: box)
        // `TextBlockMetrics` owns how far down the lines sit, so the field you
        // type a label in can offset its draft by exactly the same amount.
        let inset = TextBlockMetrics.topInset(for: text, in: box.size)
        guard inset > 0 else { return box }
        let needed = TextBlockMetrics.laidOutHeight(text, width: box.width)
        return CGRect(x: box.minX, y: box.maxY - inset - needed, width: box.width, height: needed)
    }

    /// The same box, as wide as the words were MEASURED to fit in.
    ///
    /// A text box carries `frameInset` on each side beyond the ink, which is
    /// what `naturalSize` adds and what every box a person sees has taken back
    /// off again. Words drawn from the left never touch it, so laying them out
    /// in the whole box was free. Centred words are not: half of that slack
    /// lands on their left and they sit two points right of the middle of the
    /// box they are centred in, which is the kind of wrongness nobody can name
    /// and everybody can see. So they line up in the width they were measured
    /// against — `naturalSize`'s own constraint — instead.
    private static func alignedWidth(_ text: TextContent, in box: CGRect) -> CGRect {
        guard text.usedAlignment != .left else { return box }
        return CGRect(x: box.minX, y: box.minY,
                      width: max(1, box.width - frameInset * 2), height: box.height)
    }

    /// The attributed string a piece of content lays out as: the ONE place the
    /// face, color and alignment get stamped on, so everything that measures
    /// text measures the string that actually gets drawn.
    static func measuringString(_ text: TextContent) -> NSAttributedString {
        attributedString(text)
    }

    /// The size a frame must be for `text` to lay out without wrapping beyond
    /// `maxWidth` or clipping (the result includes `frameInset` on all sides).
    /// An empty string still measures one line tall so the inline editor has a
    /// caret-height frame before any typing.
    public static func naturalSize(_ text: TextContent,
                                   maxWidth: CGFloat = .greatestFiniteMagnitude,
                                   minWidth: CGFloat = 0) -> CGSize {
        let font = font(for: text)
        let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        // The floor applies to the whole frame width, but never exceeds maxWidth
        // (a deliberately-narrow wrap width wins over the default minimum).
        let floor = maxWidth.isFinite ? min(minWidth, maxWidth) : minWidth
        guard !text.string.isEmpty else {
            return CGSize(width: max(ceil(text.fontSize / 2) + frameInset * 2, floor),
                          height: ceil(lineHeight) + frameInset * 2)
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString(text, font: font))
        let constraint = maxWidth.isFinite ? max(maxWidth - frameInset * 2, 1) : .greatestFiniteMagnitude
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: constraint, height: .greatestFiniteMagnitude), nil)
        return CGSize(width: max(ceil(suggested.width) + frameInset * 2, floor),
                      height: max(ceil(suggested.height), ceil(lineHeight)) + frameInset * 2)
    }

    /// How far the ink of a single line sits from the middle of the box
    /// `naturalSize` measures for it, in document points. Positive is to the
    /// right; an empty or multi-line string is nothing to centre and reports 0.
    ///
    /// Anything that centres words by centring that box needs this. The box is
    /// the measured advance width rounded UP and widened by `frameInset` on
    /// each side, and left-aligned glyphs are drawn flush to its left edge, so
    /// every point of that slack lands on their right and the ink sits about
    /// two points left of the middle. That is the error nobody can name and
    /// everybody can see in a badge, so a pill slides its glyphs back by this
    /// and centres what a person actually looks at.
    public static func inkOffset(_ text: TextContent) -> CGFloat {
        // One line only: a CTLine is one line by definition, and a wrapped
        // block's lines each sit differently, so a caller with more than one
        // line is centring boxes and this has nothing to tell it.
        guard !text.string.isEmpty, !text.string.contains(where: \.isNewline) else { return 0 }
        let line = CTLineCreateWithAttributedString(measuringString(text))
        let ink = CTLineGetImageBounds(line, nil)
        guard ink.width > 0, ink.width.isFinite, ink.midX.isFinite else { return 0 }
        return ink.midX - naturalSize(text).width / 2
    }

    /// The document-size face `text` is set in, as a descriptor.
    ///
    /// The inline editor builds its draft font from this with a scale transform
    /// for the zoom, rather than asking for the zoomed point size: SF spaces
    /// letters by point size, so a draft set at (size x zoom) is a few percent
    /// off the box the renderer bakes at the document size. Going through the
    /// descriptor also carries the WEIGHT across — asking AppKit for the
    /// resolved system face by PostScript name (".SFNS-Regular") returns
    /// nothing at all, which used to drop a bold label back to regular for as
    /// long as you were typing it.
    public static func faceDescriptor(for text: TextContent) -> CTFontDescriptor {
        CTFontCopyFontDescriptor(font(for: text))
    }

    /// The CTFont for a piece of content. Descriptor matching with a weight
    /// trait alone doesn't reliably pick a heavier face, so this enumerates the
    /// family's upright faces and takes the one whose weight is closest to the
    /// model's `TextWeight`.
    ///
    /// Enumerating a family's faces (`CTFontDescriptorCreateMatchingFontDescriptors`)
    /// round-trips to the font daemon (`fontd`) over XPC — expensive, and under
    /// parallel load the synchronous reply can deadlock. The chosen face depends
    /// only on (family, weight), never on point size, so we memoize the resolved
    /// descriptor per `FontFaceKey` and apply the size fresh on every call. That
    /// collapses repeated/concurrent lookups to a single XPC hit per family+weight.
    public static func font(for text: TextContent) -> CTFont {
        let key = FontFaceKey(fontName: text.fontName, weight: text.weight)
        let descriptor: CTFontDescriptor?
        if let cached = faceCache.resolved(key) {
            descriptor = cached
        } else {
            descriptor = resolveDescriptor(fontName: text.fontName, weight: text.weight)
            faceCache.store(key, descriptor)
        }
        if let descriptor {
            return CTFontCreateWithFontDescriptor(descriptor, text.fontSize, nil)
        }
        // Unknown family: name lookup, with the symbolic bold flag as the only
        // weight lever left.
        let target = text.weight.fontWeightTrait
        let font = CTFontCreateWithName(text.fontName as CFString, text.fontSize, nil)
        if target >= TextWeight.semibold.fontWeightTrait,
           let bold = CTFontCreateCopyWithSymbolicTraits(font, text.fontSize, nil, .traitBold, .traitBold) {
            return bold
        }
        return font
    }

    /// Resolve a font name to a face descriptor. The system display faces
    /// ("SF Pro"/"SF Mono") aren't matchable by family name — `CTFontCreateWithName`
    /// silently returns Helvetica for them — so build them from the UI font and
    /// stamp the requested weight. Everything else goes through family matching.
    private static func resolveDescriptor(fontName: String, weight: TextWeight) -> CTFontDescriptor? {
        if let uiType = systemUIFontType(for: fontName) {
            guard let base = CTFontCreateUIFontForLanguage(uiType, 0, nil) else { return nil }
            let descriptor = CTFontCopyFontDescriptor(base)
            return CTFontDescriptorCreateCopyWithAttributes(
                descriptor,
                [kCTFontTraitsAttribute: [kCTFontWeightTrait: weight.fontWeightTrait]] as CFDictionary)
        }
        return bestFaceDescriptor(fontName: fontName, target: weight.fontWeightTrait)
    }

    /// The CoreText UI-font type backing a system display name, or nil for a
    /// normal installed family.
    private static func systemUIFontType(for name: String) -> CTFontUIFontType? {
        switch name {
        case "SF Pro": return .system
        case "SF Mono": return .userFixedPitch
        default: return nil
        }
    }

    /// The upright face in `fontName`'s family whose weight is closest to
    /// `target`, or nil when the family isn't installed (caller falls back to a
    /// plain name lookup). This is the only path that touches `fontd`.
    private static func bestFaceDescriptor(fontName: String, target: CGFloat) -> CTFontDescriptor? {
        let family = CTFontDescriptorCreateWithAttributes(
            [kCTFontFamilyNameAttribute: fontName] as CFDictionary)
        let mandatory = Set([kCTFontFamilyNameAttribute as String]) as CFSet
        guard let faces = CTFontDescriptorCreateMatchingFontDescriptors(family, mandatory) as? [CTFontDescriptor] else {
            return nil
        }
        var best: (descriptor: CTFontDescriptor, distance: CGFloat)?
        for face in faces {
            guard let traits = CTFontDescriptorCopyAttribute(face, kCTFontTraitsAttribute) as? [String: Any] else { continue }
            let symbolic = (traits[kCTFontSymbolicTrait as String] as? NSNumber)?.uint32Value ?? 0
            guard symbolic & CTFontSymbolicTraits.traitItalic.rawValue == 0 else { continue }
            let weight = (traits[kCTFontWeightTrait as String] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
            let distance = abs(weight - target)
            if distance < (best?.distance ?? .infinity) {
                best = (face, distance)
            }
        }
        return best?.descriptor
    }

    private struct FontFaceKey: Hashable {
        let fontName: String
        let weight: TextWeight
    }

    /// A resolved (family, weight) → face descriptor cache. CTFontDescriptor is
    /// immutable and thread-safe, and every access here is serialized by `lock`,
    /// so the unchecked-Sendable box is safe under Swift 6 strict concurrency.
    /// A stored `nil` value records a known miss (family not installed) so the
    /// fallback path isn't re-derived either.
    private final class FontFaceCache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [FontFaceKey: CTFontDescriptor?] = [:]

        /// `.some(value)` = resolved (value may be nil for a known miss);
        /// `nil` = not yet resolved.
        func resolved(_ key: FontFaceKey) -> CTFontDescriptor?? {
            lock.lock(); defer { lock.unlock() }
            return entries[key]
        }

        func store(_ key: FontFaceKey, _ value: CTFontDescriptor?) {
            lock.lock(); defer { lock.unlock() }
            entries[key] = value
        }
    }

    private static let faceCache = FontFaceCache()

    private static func attributedString(_ text: TextContent, font: CTFont? = nil,
                                         borderWidth: CGFloat = 0,
                                         borderColorHex: String = "#000000") -> NSAttributedString {
        let rgba = RGBA(hex: text.colorHex) ?? RGBA(r: 1, g: 1, b: 1)
        let color = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        var attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font ?? self.font(for: text),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        // Where the words sit across the box. Left is CoreText's own default,
        // so text that has never been placed carries no paragraph style at all
        // and lays out exactly as it did before alignment existed.
        if let alignment = text.alignment, alignment != .left,
           let paragraph = paragraphStyle(alignment) {
            attrs[NSAttributedString.Key(kCTParagraphStyleAttributeName as String)] = paragraph
        }
        if borderWidth > 0, text.fontSize > 0 {
            let brgba = RGBA(hex: borderColorHex) ?? RGBA(r: 0, g: 0, b: 0)
            let strokeColor = CGColor(srgbRed: brgba.r, green: brgba.g, blue: brgba.b, alpha: brgba.a)
            // CoreText stroke width is a percentage of the font size; NEGATIVE
            // means fill AND stroke (a positive value would hollow the glyphs).
            // Expressing the point width as a percentage makes the outline scale
            // with the text.
            let percent = -(borderWidth / text.fontSize * 100)
            attrs[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = strokeColor
            attrs[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = percent
        }
        return NSAttributedString(string: text.string, attributes: attrs)
    }

    /// A paragraph style that says nothing but which edge the lines line up on.
    private static func paragraphStyle(_ alignment: TextAlign) -> CTParagraphStyle? {
        var value: CTTextAlignment = alignment == .center ? .center : .right
        return withUnsafeBytes(of: &value) { raw -> CTParagraphStyle? in
            guard let base = raw.baseAddress else { return nil }
            var setting = CTParagraphStyleSetting(spec: .alignment,
                                                  valueSize: MemoryLayout<CTTextAlignment>.size,
                                                  value: base)
            return CTParagraphStyleCreate(&setting, 1)
        }
    }
}

extension TextWeight {
    /// The `kCTFontWeightTrait` value for this weight (the NSFont.Weight scale).
    var fontWeightTrait: CGFloat {
        switch self {
        case .regular: 0
        case .medium: 0.23
        case .semibold: 0.3
        case .bold: 0.4
        }
    }
}
