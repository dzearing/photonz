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

    /// Renders `text` top-left aligned, word-wrapped inside `size` (in pixels).
    public static func rasterize(_ text: TextContent, size: CGSize) -> CGImage? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width >= 1, height >= 1 else { return nil }

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString(text))
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
                          transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)

        return context.makeImage()
    }

    /// The size a frame must be for `text` to lay out without wrapping beyond
    /// `maxWidth` or clipping (the result includes `frameInset` on all sides).
    /// An empty string still measures one line tall so the inline editor has a
    /// caret-height frame before any typing.
    public static func naturalSize(_ text: TextContent, maxWidth: CGFloat = .greatestFiniteMagnitude) -> CGSize {
        let font = font(for: text)
        let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        guard !text.string.isEmpty else {
            return CGSize(width: ceil(text.fontSize / 2) + frameInset * 2,
                          height: ceil(lineHeight) + frameInset * 2)
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString(text, font: font))
        let constraint = maxWidth.isFinite ? max(maxWidth - frameInset * 2, 1) : .greatestFiniteMagnitude
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: constraint, height: .greatestFiniteMagnitude), nil)
        return CGSize(width: ceil(suggested.width) + frameInset * 2,
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
            descriptor = bestFaceDescriptor(fontName: text.fontName, target: text.weight.fontWeightTrait)
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

    private static func attributedString(_ text: TextContent, font: CTFont? = nil) -> NSAttributedString {
        let rgba = RGBA(hex: text.colorHex) ?? RGBA(r: 1, g: 1, b: 1)
        let color = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        return NSAttributedString(string: text.string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font ?? self.font(for: text),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
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
