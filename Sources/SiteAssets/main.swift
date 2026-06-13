// SiteAssets — generates the marketing-site hero image by compositing a
// showcase document through Photonz's *real* engine (PhotonzCore + PhotonzRender).
// Every pixel here is produced by the same renderer the app ships, so the hero
// is an honest demonstration of the zoom-callout, annotation, text, and
// layer-styling features — not a hand-drawn mockup.
//
//   swift run SiteAssets            # writes site/assets/*.png
//
// AppKit/CoreText are fine in this dev tool (it is not PhotonzCore).

import AppKit
import CoreGraphics
import CoreText
import Foundation
import PhotonzCore
import PhotonzRender

// MARK: - Base "screenshot" scene

/// Draws a believable editing subject: a brand gradient backdrop, soft glow
/// blobs, and a frosted info panel carrying a heading plus a line of fine print.
/// The fine print is the natural target for a zoom callout (magnify small text),
/// which is exactly the screenshot workflow Photonz is built for.
func makeBaseScene(size: CGSize, panelDoc: CGRect, fineBarDoc: CGRect) -> CGImage {
    let w = Int(size.width), h = Int(size.height)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // CoreGraphics is bottom-left origin; the document model is top-left. Convert
    // document rects to CG space so callout/annotation coords line up exactly.
    func cg(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height)
    }

    // Sky gradient.
    let grad = CGGradient(colorsSpace: cs,
                          colors: [CGColor(red: 0.10, green: 0.07, blue: 0.20, alpha: 1),
                                   CGColor(red: 0.17, green: 0.10, blue: 0.36, alpha: 1),
                                   CGColor(red: 0.30, green: 0.16, blue: 0.55, alpha: 1)] as CFArray,
                          locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size.height),
                           end: CGPoint(x: size.width, y: 0), options: [])

    // Soft glow blobs.
    func glow(_ center: CGPoint, _ radius: CGFloat, _ color: CGColor) {
        let g = CGGradient(colorsSpace: cs, colors: [color, color.copy(alpha: 0)!] as CFArray,
                           locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: radius, options: [])
    }
    glow(CGPoint(x: size.width * 0.78, y: size.height * 0.86), 420,
         CGColor(red: 0.72, green: 0.42, blue: 0.98, alpha: 0.55))
    glow(CGPoint(x: size.width * 0.16, y: size.height * 0.12), 360,
         CGColor(red: 0.35, green: 0.30, blue: 0.95, alpha: 0.45))

    // Frosted info panel (document coords → CG).
    let panel = cg(panelDoc)
    let panelPath = CGPath(roundedRect: panel, cornerWidth: 26, cornerHeight: 26, transform: nil)
    ctx.saveGState()
    ctx.addPath(panelPath); ctx.clip()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.fill(panel)
    ctx.restoreGState()
    ctx.addPath(panelPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
    ctx.setLineWidth(1.5)
    ctx.strokePath()

    // Text helper (CoreText). `y` is the baseline in CG bottom-left space.
    func drawText(_ string: String, font: NSFont, color: CGColor, x: CGFloat, baseline: CGFloat) {
        let attr = NSAttributedString(string: string, attributes: [
            .font: font, .foregroundColor: NSColor(cgColor: color)!,
        ])
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, ctx)
    }

    // Heading + subhead, positioned from the panel top (document coords).
    let headingBaseline = size.height - (panelDoc.minY + 60)
    drawText("Aurora Ridge — final cut",
             font: .systemFont(ofSize: 40, weight: .bold),
             color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.96),
             x: panelDoc.minX + 40, baseline: headingBaseline)
    drawText("Exported from Photonz",
             font: .systemFont(ofSize: 22, weight: .regular),
             color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.6),
             x: panelDoc.minX + 40, baseline: headingBaseline - 44)

    // Fine-print bar — a solid dark pill so the magnified callout shows crisp
    // white-on-dark text. This is the zoom-callout source region.
    let bar = cg(fineBarDoc)
    let barPath = CGPath(roundedRect: bar, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.addPath(barPath)
    ctx.setFillColor(CGColor(red: 0.05, green: 0.03, blue: 0.10, alpha: 0.78))
    ctx.fillPath()
    drawText("4096×3072 · ƒ/1.8 · ISO 100",
             font: .monospacedSystemFont(ofSize: 17, weight: .semibold),
             color: CGColor(red: 0.96, green: 0.98, blue: 1, alpha: 1),
             x: bar.minX + 14, baseline: bar.minY + 13)

    return ctx.makeImage()!
}

/// A small solid rounded chip used to show non-destructive layer styling
/// (corner radius + drop shadow applied at render time).
func makeChip(size: CGSize, color: CGColor) -> CGImage {
    let w = Int(size.width), h = Int(size.height)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(color)
    ctx.fill(CGRect(origin: .zero, size: size))
    return ctx.makeImage()!
}

// MARK: - Showcase document

let canvas = CGSize(width: 1440, height: 900)

// Everything below is in document (top-left) coordinates.
let panelDoc = CGRect(x: canvas.width * 0.11, y: canvas.height * 0.30,
                      width: canvas.width * 0.50, height: canvas.height * 0.40)
// Fine-print bar near the panel bottom — the zoom-callout source.
let fineRect = CGRect(x: panelDoc.minX + 28, y: panelDoc.maxY - 70, width: 330, height: 36)

let store = ImageStore()
let baseRef = store.register(makeBaseScene(size: canvas, panelDoc: panelDoc, fineBarDoc: fineRect))
var doc = PhotonzDocument.withBaseImage(baseRef)

// Zoom callout — the signature feature. Box = magnification × source so the whole
// magnified line fits crisply, with a glowing border and soft shadow.
let calloutMag: CGFloat = 2.0
doc.addLayer(Layer(
    name: "Zoom callout",
    content: .zoomCallout(ZoomCalloutContent(sourceRect: fineRect, magnification: calloutMag,
                                             shape: .rectangle)),
    frame: CGRect(x: canvas.width * 0.46, y: canvas.height * 0.14,
                  width: fineRect.width * calloutMag, height: fineRect.height * calloutMag),
    style: LayerStyle(cornerRadius: 16, borderWidth: 4, borderColorHex: "#C059F2",
                      shadow: ShadowStyle(radius: 26, offset: CGSize(width: 0, height: 10),
                                          colorHex: "#1A0B33", opacity: 0.55))
))

// A styled layer chip — shows corner radius + shadow are non-destructive.
let chipRef = store.register(makeChip(size: CGSize(width: 220, height: 220),
                                      color: CGColor(red: 0.55, green: 0.30, blue: 0.95, alpha: 1)))
doc.addLayer(Layer(
    name: "Styled layer",
    content: .image(chipRef),
    frame: CGRect(x: canvas.width * 0.70, y: canvas.height * 0.56, width: 220, height: 220),
    transform: LayerTransform(rotation: -0.12),
    style: LayerStyle(cornerRadius: 44, borderWidth: 3, borderColorHex: "#FFFFFFCC",
                      shadow: ShadowStyle(radius: 30, offset: CGSize(width: 0, height: 14),
                                          colorHex: "#000000", opacity: 0.45))
))

// Highlight over the heading words.
doc.addLayer(AnnotationBuilder.layer(
    content: AnnotationContent(shape: .highlight, strokeWidth: 4, colorHex: "#FFE45C"),
    from: CGPoint(x: panelDoc.minX + 34, y: panelDoc.minY + 22),
    to: CGPoint(x: panelDoc.minX + 332, y: panelDoc.minY + 74)))

// Arrow pointing from the callout box back to the source detail.
doc.addLayer(AnnotationBuilder.layer(
    content: AnnotationContent(shape: .arrow, strokeWidth: 7, colorHex: "#FF3B30"),
    from: CGPoint(x: canvas.width * 0.47, y: canvas.height * 0.24),
    to: CGPoint(x: fineRect.maxX - 24, y: fineRect.midY)))

// Text caption above the callout.
let caption = TextContent(string: "Magnify any detail", fontName: "SF Pro", fontSize: 30,
                          colorHex: "#FFFFFF", weight: .semibold)
doc.addLayer(Layer(
    name: "Caption",
    content: .text(caption),
    frame: CGRect(x: canvas.width * 0.46, y: canvas.height * 0.045, width: 360, height: 44),
    style: LayerStyle(shadow: ShadowStyle(radius: 6, offset: CGSize(width: 0, height: 2),
                                          colorHex: "#000000", opacity: 0.7))
))

// MARK: - Render & export

let renderer = DocumentRenderer()
let outDir = URL(fileURLWithPath: "site/assets")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func export(_ image: CGImage, _ name: String) {
    guard let data = ImageCodec.encode(image, format: .png) else {
        FileHandle.standardError.write(Data("failed to encode \(name)\n".utf8)); exit(1)
    }
    let url = outDir.appendingPathComponent(name)
    do { try data.write(to: url) } catch {
        FileHandle.standardError.write(Data("failed to write \(name): \(error)\n".utf8)); exit(1)
    }
    print("wrote \(url.path)  (\(image.width)×\(image.height))")
}

guard let hero = renderer.render(doc, store: store, scale: 2) else {
    FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
}
export(hero, "hero.png")
print("done")
