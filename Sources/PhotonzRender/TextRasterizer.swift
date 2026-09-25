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
        rasterize(text, size: size,
                  outlines: borderWidth > 0
                      ? [TextOutline(width: borderWidth, colorHex: borderColorHex)] : [],
                  scale: scale)
    }

    /// One outline round the letters: how thick, and what colour.
    public struct TextOutline: Hashable, Sendable {
        public var width: CGFloat
        public var colorHex: String
        public init(width: CGFloat, colorHex: String) {
            self.width = width
            self.colorHex = colorHex
        }
    }

    /// The same words, with as many outlines round the letters as the layer's
    /// Effects list holds borders.
    ///
    /// A label's edge is a Border like every other layer's since the Outline
    /// row left Appearance (`OutlineRetirement.swift`), and a border is
    /// countable, so a label can wear a fat pale halo AND a thin dark line the
    /// way a box can. They are drawn widest first so the narrow one lands on
    /// top of the fat one, which is the order the list itself paints in.
    public static func rasterize(_ text: TextContent, size: CGSize,
                                 outlines: [TextOutline],
                                 scale: CGFloat = 1) -> CGImage? {
        guard scale > 0, scale.isFinite else { return nil }
        // Words that stay on one line give way here, before anything is laid
        // out, so everything below — the box, the alignment, the halo — is
        // working on the string that actually fits.
        let text = truncating(text, toFit: size.width)
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

        // Outer border: draw fat border-colored glyphs underneath, then the
        // normal fill on top, so the stroke shows only OUTSIDE the letters —
        // it grows outward with the fill intact. (A single centered stroke
        // would eat into the glyphs.) The underlay stroke is doubled because a
        // centered stroke extends half its width outward.
        if text.fontSize > 0 {
            for outline in outlines.filter({ $0.width > 0 }).sorted(by: { $0.width > $1.width }) {
                var underlay = text
                underlay.colorHex = outline.colorHex
                draw(attributedString(underlay, borderWidth: outline.width * 2,
                                      borderColorHex: outline.colorHex))
            }
        }
        // A caption's plate goes under everything, hugging the lines
        // (`CaptionLook.swift`).
        if let plateHex = text.plateHex {
            drawPlate(for: text, hex: plateHex, laidOutIn: path, bounds: box, in: context)
        }
        draw(lit(attributedString(text), text))

        return context.makeImage()
    }

    /// One rounded plate behind all the lines, as wide as the widest of them
    /// plus a little air, the way the mock's caption box hugs its words.
    private static func drawPlate(for text: TextContent, hex: String, laidOutIn path: CGPath,
                                  bounds box: CGRect, in context: CGContext) {
        guard text.fontSize > 0, !text.string.isEmpty,
              let rgba = RGBA(hex: hex) else { return }
        let frame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(attributedString(text)),
            CFRange(location: 0, length: 0), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let base = path.boundingBox.origin
        var union = CGRect.null
        for (line, origin) in zip(lines, origins) {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let full = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let width = full - CGFloat(CTLineGetTrailingWhitespaceWidth(line))
            guard width > 0 else { continue }
            // A centred or right-aligned line is pushed along by the frame; the
            // pen offset is how far, for the width it actually inks.
            let flush: CGFloat = switch text.alignment ?? .left {
            case .left: 0
            case .center: 0.5
            case .right: 1
            }
            let pen = CGFloat(CTLineGetPenOffsetForFlush(line, flush, Double(path.boundingBox.width)))
            let x = base.x + (text.alignment == nil || text.alignment == .left ? origin.x : pen)
            let rect = CGRect(x: x, y: base.y + origin.y - descent, width: width, height: ascent + descent)
            union = union.union(rect)
        }
        guard !union.isNull else { return }
        let plate = union.insetBy(dx: -text.fontSize * 0.45, dy: -text.fontSize * 0.2)
            .intersection(box)
        guard !plate.isEmpty else { return }
        let radius = min(text.fontSize * 0.28, plate.height / 2)
        context.saveGState()
        context.setFillColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a))
        context.addPath(CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        context.restoreGState()
    }

    /// The words with the lit stretch drawn in its own colour. A stretch that
    /// runs past the words (a line retyped shorter) is cut to them.
    private static func lit(_ attributed: NSAttributedString, _ text: TextContent) -> NSAttributedString {
        guard let highlight = text.highlight, let rgba = RGBA(hex: highlight.colorHex) else { return attributed }
        let length = attributed.length
        let start = min(max(0, highlight.location), length)
        let end = min(max(start, highlight.location + highlight.length), length)
        guard end > start else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        mutable.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String),
                             value: CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a),
                             range: NSRange(location: start, length: end - start))
        return mutable
    }

    /// The words as ONE outline, in the layer's own top-left coordinates.
    ///
    /// What SVG export writes instead of a `<text>` element: a `<text>` renders
    /// in whatever face the machine opening the file happens to have, so an
    /// icon handed to somebody without the font comes out wrong, and an outline
    /// looks the same everywhere (`docs/design/svg-export.md`).
    ///
    /// Laid out through exactly the same framesetter the rasterizer draws
    /// with — the same truncation, the same box, the same alignment — so the
    /// letters land where the canvas puts them. CoreText lays out with y
    /// running up the box and the document counts y from the top, so every
    /// glyph is flipped about the box on the way out.
    public static func outlinePath(_ text: TextContent, size: CGSize) -> CGPath? {
        guard size.width > 0, size.height > 0, text.fontSize > 0 else { return nil }
        let text = truncating(text, toFit: size.width)
        let box = CGRect(origin: .zero, size: size)
        let frame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(attributedString(text)),
            CFRange(location: 0, length: 0),
            CGPath(rect: laidOutBox(text, in: box), transform: nil), nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return nil }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        let outline = CGMutablePath()
        for (line, lineOrigin) in zip(lines, origins) {
            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { continue }
            for run in runs {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let font = attributes[kCTFontAttributeName as String] else { continue }
                let ctFont = font as! CTFont
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                for index in 0..<count {
                    guard let glyph = CTFontCreatePathForGlyph(ctFont, glyphs[index], nil)
                    else { continue }
                    let x = lineOrigin.x + positions[index].x
                    let y = lineOrigin.y + positions[index].y
                    let place = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                                  tx: x, ty: size.height - y)
                    outline.addPath(glyph, transform: place)
                }
            }
        }
        return outline.isEmpty ? nil : outline
    }

    /// Where each word of `text` is drawn in a box of `size`: one rect per run
    /// of non-space characters, in document points with the origin top left,
    /// or nil for a word that was cut off. A word broken across two lines is
    /// the union of both pieces.
    ///
    /// Laid out exactly as `rasterize` lays it out — the same truncation, box
    /// and alignment — so a double click on a word of a caption lands on the
    /// word the picture shows there.
    public static func wordRects(_ text: TextContent, size: CGSize) -> [CGRect?] {
        let spans = CaptionActiveWord.tokenSpans(in: text.string)
        guard size.width > 0, size.height > 0, text.fontSize > 0, !spans.isEmpty else {
            return spans.map { _ in nil }
        }
        let shown = truncating(text, toFit: size.width)
        let path = CGPath(rect: laidOutBox(shown, in: CGRect(origin: .zero, size: size)), transform: nil)
        let frame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(attributedString(shown)),
            CFRange(location: 0, length: 0), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else {
            return spans.map { _ in nil }
        }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let base = path.boundingBox.origin
        let visible = shown.string == text.string ? (text.string as NSString).length
            : max(0, (shown.string as NSString).length - 1)
        return spans.map { span in
            let start = span.location
            let end = min(span.location + span.length, visible)
            guard end > start else { return nil }
            var union = CGRect.null
            for (line, origin) in zip(lines, origins) {
                let range = CTLineGetStringRange(line)
                let from = max(start, range.location), to = min(end, range.location + range.length)
                guard to > from else { continue }
                var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
                let x0 = CTLineGetOffsetForStringIndex(line, from, nil)
                let x1 = CTLineGetOffsetForStringIndex(line, to, nil)
                let top = size.height - (base.y + origin.y + ascent)
                union = union.union(CGRect(x: base.x + origin.x + min(x0, x1), y: top,
                                           width: abs(x1 - x0), height: ascent + descent))
            }
            return union.isNull ? nil : union
        }
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

    /// `text` cut down to what fits `width`, with an ellipsis where the rest
    /// was — the answer a bar title gives when it is longer than the bar has
    /// room for.
    ///
    /// Only words told to stay on one line are ever cut: everything else wraps,
    /// and cutting a paragraph short would lose words nobody asked to lose. A
    /// string that already fits comes straight back, unchanged, so a label with
    /// room to spare is byte for byte what it was before any of this existed.
    ///
    /// The cut lands on a cluster boundary rather than a byte one, so an emoji
    /// or an accented letter is never split down the middle, and any spaces
    /// left dangling before the ellipsis go with it.
    static func truncating(_ text: TextContent, toFit width: CGFloat) -> TextContent {
        guard text.staysOnOneLine == true, !text.string.isEmpty else { return text }
        // The words lay out in the width they were measured against, which is
        // the box less the inset it carries on each side.
        let room = max(1, width - frameInset * 2)
        guard naturalSize(text).width - frameInset * 2 > room + truncationSlack
        else { return text }
        var token = text
        token.string = ellipsis
        let tokenWidth = CTLineGetTypographicBounds(
            CTLineCreateWithAttributedString(attributedString(token)), nil, nil, nil)
        let typesetter = CTTypesetterCreateWithAttributedString(attributedString(text))
        let fits = CTTypesetterSuggestClusterBreak(typesetter, 0, max(1, room - tokenWidth))
        let string = text.string as NSString
        let head = string.substring(to: min(max(0, fits), string.length))
        var out = text
        out.string = head.trimmingCharacters(in: .whitespacesAndNewlines) + ellipsis
        return out
    }

    /// How much narrower than its words a box may be before they are cut.
    ///
    /// A hairsbreadth, and it is here because a box is MEASURED in document
    /// points and DRAWN through a zoom. A label whose box was measured for its
    /// own words is exactly as wide as they are, the canvas states that box in
    /// output pixels, and the rasterizer divides it back: `w * zoom / zoom` is
    /// not always `w` in binary floating point, so at some zooms the box
    /// arrives one ulp short of the words it was measured for. One ulp used to
    /// cost three characters and an ellipsis — a label read out of a screenshot
    /// came back "Show in menu b…" on the canvas at 151% and read whole at
    /// 150%.
    ///
    /// A hundredth of a point is far more than any round trip can lose and far
    /// less than anybody can see, so a box that really is too narrow is still
    /// cut exactly as it was.
    static let truncationSlack: CGFloat = 0.01

    /// What stands in for the words that did not fit. One character, not three
    /// dots, so it is one glyph wide and reads as a cut rather than a pause.
    private static let ellipsis = "…"

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
        // Words that stay on one line have nothing to wrap at, so the room
        // they are measured against says nothing about how big they are. Same
        // answer `TextMeasurement` gives, which is the point: the model and
        // the drawing must not disagree about how tall a title is.
        let maxWidth = text.staysOnOneLine == true ? CGFloat.greatestFiniteMagnitude : maxWidth
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
        guard !text.string.isEmpty else { return 0 }
        // More than one line: each line sits differently, so there is no single
        // ink to centre — but the LINES are laid out in the measured width
        // (`alignedWidth` takes the frame inset back off), so centred rows come
        // out one inset left of the middle of the box. Say so, and a pill that
        // centres this box puts the rows in its middle. Rows that are not
        // centred are drawn from the left edge and have nothing to correct.
        if text.string.contains(where: \.isNewline) {
            return text.usedAlignment == .center ? -frameInset : 0
        }
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
