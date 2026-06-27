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
    public static let minimumTextWidth: CGFloat = 80

    /// Renders `text` top-left aligned, word-wrapped inside `size` (in pixels).
    /// A `borderWidth > 0` strokes the glyph OUTLINES in `borderColorHex` (a text
    /// outline), not a box — the layer's box border is suppressed for text.
    public static func rasterize(_ text: TextContent, size: CGSize,
                                 borderWidth: CGFloat = 0,
                                 borderColorHex: String = "#000000") -> CGImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width >= 1, height >= 1 else { return nil }

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        let path = CGPath(rect: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
                          transform: nil)
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
