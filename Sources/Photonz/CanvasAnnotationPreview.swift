import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

// The live preview while an annotation is being drawn: the arrow or box under
// the pointer, its caption pill, and the zoom callout's flight into place.
// Split out of CanvasView.swift; `CanvasNSView`'s stored properties still live
// there.

extension CanvasNSView {
    // MARK: Annotation drag preview

    func clearAnnotationPreview() {
        annotationCommitImage = nil
        endpointHoldLayerID = nil
        annotationPreviewLayer.isHidden = true
        annotationPreviewLayer.path = nil
        annotationPreviewHeadLayer.path = nil
        captionPreviewLayer.isHidden = true
        captionPreviewLayer.contents = nil
        captionPreviewKey = nil
    }

    /// What the zoom tool's drag box previews with: a box in the callout's
    /// border style, rounded exactly as the source outline the renderer bakes
    /// will be. With the tool set to Circle that makes the draft round, so the
    /// shape you chose is visible while you are still dragging it out rather
    /// than a surprise when the callout lands.
    private func calloutDraftContent(docBox: CGRect) -> AnnotationContent {
        let style = ZoomCalloutBuilder.defaultStyle
        // Matches ZoomCalloutOverlayRasterizer: the callout's radius divided by
        // the magnification, so source outline and box read as one shape.
        let scaled = min(style.cornerRadius / ZoomCalloutBuilder.defaultMagnification,
                         min(docBox.width, docBox.height) / 2)
        let radius = ZoomCalloutContent(sourceRect: docBox, shape: calloutShape)
            .effectiveCornerRadius(boxSize: docBox.size, styleRadius: scaled)
        return AnnotationContent(shape: .rectangle, strokeWidth: max(1, style.borderWidth / 2),
                                 colorHex: style.borderColorHex, cornerRadius: radius)
    }

    /// What the frame tool's drag previews with: a hairline rectangle, so what
    /// you are dragging out reads as the edge of a screen rather than as a
    /// shape you are about to draw.
    private var frameDraftContent: AnnotationContent {
        AnnotationContent(shape: .rectangle, strokeWidth: 1, colorHex: "#8E8E93")
    }

    /// In-flight drag-to-create: preview the active tool's styled content.
    func refreshAnnotationPreview(constrained: Bool) {
        guard let drag = annotationDrag else {
            clearAnnotationPreview()
            return
        }
        // The callout draft is rounded from the box being dragged, so it is
        // built here where the box is known.
        let docEnd = drag.end(constrained: constrained, shape: .rectangle)
        var draft = tool == .zoomCallout
            ? calloutDraftContent(docBox: CGRect(x: min(drag.anchor.x, docEnd.x),
                                                 y: min(drag.anchor.y, docEnd.y),
                                                 width: abs(docEnd.x - drag.anchor.x),
                                                 height: abs(docEnd.y - drag.anchor.y)))
            : nil
        if tool == .frame { draft = frameDraftContent }
        guard let content = annotationContent ?? draft ?? tool.defaultAnnotation else {
            clearAnnotationPreview()
            return
        }
        displayAnnotationPreview(content: content, docStart: drag.anchor,
                                 docEnd: drag.end(constrained: constrained, shape: content.shape),
                                 style: annotationStyle)
    }

    /// In-flight endpoint drag: preview the selected layer's content with the
    /// dragged endpoint applied.
    func refreshEndpointPreview(constrained: Bool) {
        guard let session = endpointDrag else {
            clearAnnotationPreview()
            return
        }
        let (docStart, docEnd) = session.drag.endpoints(constrained: constrained)
        displayAnnotationPreview(content: session.content, docStart: docStart, docEnd: docEnd,
                                 style: document?.canvasLayer(id: session.layerID)?.style)
    }

    /// Draws an annotation as vector shapes in view coordinates — faithful to
    /// the rasterizer so the held preview swaps invisibly for the real
    /// composite after commit.
    private func displayAnnotationPreview(content: AnnotationContent,
                                          docStart: CGPoint, docEnd: CGPoint,
                                          style: LayerStyle? = nil) {
        guard let viewport else {
            clearAnnotationPreview()
            return
        }
        let start = viewport.viewPoint(fromDocument: docStart)
        let end = viewport.viewPoint(fromDocument: docEnd)
        let strokeWidth = content.strokeWidth * viewport.zoom
        let rgba = RGBA(hex: content.colorHex) ?? RGBA(r: 1, g: 0, b: 0)
        let color = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y))

        let path = CGMutablePath()
        let headPath = CGMutablePath()
        var fill: CGColor?
        var stroke: CGColor? = color
        // The outline width the preview strokes with — the annotation's own
        // stroke by default, overridden below for box shapes whose outline is a
        // layer-style border.
        var lineWidth = strokeWidth
        var compositing: Any?
        switch content.shape {
        case .line:
            path.move(to: start)
            path.addLine(to: end)
        case .arrow:
            // Stop the shaft inside the head (doc space → view space) so its cap
            // doesn't poke past the tip, matching the rasterizer.
            let shaftEndDoc = Geometry.arrowShaftEnd(start: docStart, end: docEnd,
                                                     strokeWidth: content.strokeWidth,
                                                     scale: content.arrowheadScale)
            path.move(to: start)
            path.addLine(to: viewport.viewPoint(fromDocument: shaftEndDoc))
            // Head geometry in document space (its minimum size is in doc
            // points), then mapped to view coords.
            let head = Geometry.arrowhead(start: docStart, end: docEnd,
                                          strokeWidth: content.strokeWidth,
                                          scale: content.arrowheadScale)
            headPath.addLines(between: head.map { viewport.viewPoint(fromDocument: $0) })
            headPath.closeSubpath()
        case .rectangle, .ellipse:
            // A box shape's outline can be the annotation's own stroke OR a
            // layer-style border (the Border toggle — rectangles use this, with
            // strokeWidth 0). Draw whichever is set so the draft isn't invisible.
            if content.strokeWidth == 0, let border = style, border.borderWidth > 0 {
                lineWidth = border.borderWidth * viewport.zoom
                if let brgba = RGBA(hex: border.borderColorHex) {
                    stroke = CGColor(srgbRed: brgba.r, green: brgba.g, blue: brgba.b, alpha: brgba.a)
                }
            }
            // Inset by half the outline so it reads as an inner stroke, matching
            // the rasterizer and the layer border.
            let inset = box.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            if inset.width > 0, inset.height > 0 {
                if content.shape == .rectangle {
                    let radius = min(content.cornerRadius * viewport.zoom,
                                     min(inset.width, inset.height) / 2)
                    if radius > 0 {
                        path.addRoundedRect(in: inset, cornerWidth: radius, cornerHeight: radius)
                    } else {
                        path.addRect(inset)
                    }
                } else {
                    path.addEllipse(in: inset)
                }
            }
            // Interior fill previews live so the draft matches the commit.
            if let fillHex = content.fillColorHex, let rgba = RGBA(hex: fillHex) {
                fill = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
            }
            // Nothing to stroke if the shape carries no outline at all (fill
            // only): a zero line width would still draw a hairline.
            if lineWidth <= 0 { stroke = nil }
        case .highlight:
            path.addRect(box)
            fill = color
            stroke = nil
            compositing = "multiplyBlendMode"
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        annotationPreviewLayer.path = path
        annotationPreviewLayer.strokeColor = stroke
        annotationPreviewLayer.fillColor = fill
        annotationPreviewLayer.lineWidth = lineWidth
        // Match the rasterizer: rectangles corner with miters (no fake radius).
        annotationPreviewLayer.lineJoin = content.shape == .rectangle ? .miter : .round
        annotationPreviewLayer.compositingFilter = compositing
        annotationPreviewHeadLayer.path = headPath
        annotationPreviewHeadLayer.fillColor = color
        displayCaptionPreview(content: content, docStart: docStart, docEnd: docEnd,
                              viewport: viewport)
        annotationPreviewLayer.isHidden = false
        CATransaction.commit()
    }

    /// The caption pill inside the held preview, planned for the endpoints the
    /// drag is at RIGHT NOW. It goes through the same planner the commit does,
    /// so the pill you watch during the drag is the pill that lands and letting
    /// go changes nothing you can see.
    private func displayCaptionPreview(content: AnnotationContent,
                                       docStart: CGPoint, docEnd: CGPoint,
                                       viewport: Viewport) {
        guard content.shape == .arrow, content.hasCaption,
              Experiments.shared.arrowCaptionsEnabled else {
            captionPreviewLayer.isHidden = true
            return
        }
        let scale = max(1, viewport.zoom * (window?.backingScaleFactor ?? 2))
        let key = "\(content.caption ?? "")|\(content.captionFontSize)|\(content.colorHex)"
            + "|\(content.strokeWidth)|\(scale)"
        if key != captionPreviewKey {
            guard let baked = AnnotationRasterizer.captionPill(content, scale: scale) else {
                captionPreviewLayer.isHidden = true
                return
            }
            captionPreviewLayer.contents = baked.image
            captionPreviewLayer.contentsScale = scale
            captionPreviewKey = key
            captionPreviewSize = baked.size
        }
        guard let bitmap = captionPreviewSize else {
            captionPreviewLayer.isHidden = true
            return
        }
        var probe = content
        probe.start = docStart
        probe.end = docEnd
        let canvas = viewport.documentSize
        let pill = CaptionMetrics.pillSize(for: probe.caption ?? "", in: probe)
        if probe.captionPinned, let pinned = probe.captionOffset {
            probe.captionOffset = CaptionPlanner.keepingOnCanvas(pinned, for: probe,
                                                                 canvas: canvas, pillSize: pill)
        } else {
            let placement = CaptionPlanner.plan(for: probe, canvas: canvas, reserving: pill)
            probe.captionOffset = placement.attach
            probe.captionGrowth = placement.growth
        }
        let center = viewport.viewPoint(fromDocument: probe.captionPillCenter(forPillSize: pill))
        let size = CGSize(width: bitmap.width * viewport.zoom,
                          height: bitmap.height * viewport.zoom)
        captionPreviewLayer.bounds = CGRect(origin: .zero, size: size)
        captionPreviewLayer.position = center
        captionPreviewLayer.isHidden = false
    }

    // MARK: Zoom-callout creation flight

    /// Animates a just-committed callout from its source box to its placed
    /// frame: the sprite is the on-screen composite cropped to the source
    /// region (the pixels the callout magnifies), growing into the styled box
    /// while the source outline and leader lines fade in underneath. The
    /// pre-commit composite holds on screen for the duration; the baked render
    /// (already landed by then) is revealed when the flight ends.
    func beginCalloutFlight(for calloutLayer: Layer) {
        guard let viewport, let image, let callout = calloutLayer.zoomCallout,
              viewport.documentSize.width > 0, viewport.documentSize.height > 0 else { return }
        let scaleX = CGFloat(image.width) / viewport.documentSize.width
        let scaleY = CGFloat(image.height) / viewport.documentSize.height
        let cropRect = CGRect(x: callout.sourceRect.minX * scaleX,
                              y: callout.sourceRect.minY * scaleY,
                              width: callout.sourceRect.width * scaleX,
                              height: callout.sourceRect.height * scaleY)
        guard let sprite = image.cropping(to: cropRect) else { return }

        calloutHoldImage = image
        calloutFlightGeneration += 1
        let generation = calloutFlightGeneration

        let zoom = viewport.zoom
        let style = calloutLayer.style
        let magnification = max(callout.magnification, 0.01)
        let startFrame = viewRect(forDocRect: callout.sourceRect, in: viewport)
        let endFrame = viewRect(forDocRect: calloutLayer.frame, in: viewport)
        let rgba = RGBA(hex: style.borderColorHex) ?? RGBA(r: 1, g: 0, b: 0)
        let borderColor = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)

        // Chrome that fades in: source outline + leader lines, matching what
        // the renderer bakes (ZoomCalloutOverlayRasterizer's styling).
        // Both radii go through the callout's own rule, so a circle flies as a
        // circle instead of landing square and snapping round a frame later.
        let sourceRadius = callout.effectiveCornerRadius(
            boxSize: startFrame.size,
            styleRadius: (style.cornerRadius / magnification) * zoom)
        let boxRadius = callout.effectiveCornerRadius(boxSize: endFrame.size,
                                                      styleRadius: style.cornerRadius * zoom)
        let outlinePath = CGPath(roundedRect: startFrame,
                                 cornerWidth: sourceRadius, cornerHeight: sourceRadius,
                                 transform: nil)
        let leaderPath = CGMutablePath()
        for line in Geometry.leaderLines(source: callout.sourceRect, callout: calloutLayer.frame) {
            leaderPath.move(to: viewport.viewPoint(fromDocument: line.from))
            leaderPath.addLine(to: viewport.viewPoint(fromDocument: line.to))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        calloutFlightLayer.contents = sprite
        calloutFlightLayer.frame = startFrame
        calloutFlightLayer.borderColor = borderColor
        calloutFlightLayer.borderWidth = style.borderWidth * zoom
        calloutFlightLayer.cornerRadius = sourceRadius
        calloutFlightLayer.isHidden = false
        calloutFlightOutlineLayer.path = outlinePath
        calloutFlightOutlineLayer.strokeColor = borderColor
        calloutFlightOutlineLayer.lineWidth = style.borderWidth * zoom
        calloutFlightOutlineLayer.opacity = 0
        calloutFlightOutlineLayer.isHidden = false
        calloutFlightLeaderLayer.path = leaderPath
        calloutFlightLeaderLayer.strokeColor = borderColor.copy(alpha: 0.6 * borderColor.alpha)
        calloutFlightLeaderLayer.lineWidth = style.borderWidth * zoom
        calloutFlightLeaderLayer.opacity = 0
        calloutFlightLeaderLayer.isHidden = false
        CATransaction.commit()

        // The sprite springs into place (slight overshoot reads as the box
        // "landing"); the chrome fades in on a plain ease-out underneath.
        let startBounds = CGRect(origin: .zero, size: startFrame.size)
        let endBounds = CGRect(origin: .zero, size: endFrame.size)
        func spring(_ keyPath: String, from: Any?, to: Any?) -> CASpringAnimation {
            let animation = CASpringAnimation(perceptualDuration: 0.45, bounce: 0.25)
            animation.keyPath = keyPath
            animation.fromValue = from
            animation.toValue = to
            return animation
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.calloutFlightGeneration == generation else { return }
            self.endCalloutFlight()
        }
        calloutFlightLayer.add(spring("position",
                                      from: NSValue(point: CGPoint(x: startFrame.midX, y: startFrame.midY)),
                                      to: NSValue(point: CGPoint(x: endFrame.midX, y: endFrame.midY))),
                               forKey: "position")
        calloutFlightLayer.add(spring("bounds",
                                      from: NSValue(rect: startBounds),
                                      to: NSValue(rect: endBounds)),
                               forKey: "bounds")
        calloutFlightLayer.add(spring("cornerRadius",
                                      from: sourceRadius,
                                      to: boxRadius),
                               forKey: "cornerRadius")
        func fadeIn() -> CABasicAnimation {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.35
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            return fade
        }
        calloutFlightOutlineLayer.add(fadeIn(), forKey: "opacity")
        calloutFlightLeaderLayer.add(fadeIn(), forKey: "opacity")
        CATransaction.setDisableActions(true)
        calloutFlightLayer.position = CGPoint(x: endFrame.midX, y: endFrame.midY)
        calloutFlightLayer.bounds = endBounds
        calloutFlightLayer.cornerRadius = boxRadius
        calloutFlightOutlineLayer.opacity = 1
        calloutFlightLeaderLayer.opacity = 1
        CATransaction.commit()
    }

    /// Tears the flight down and reveals the latest composite (which has the
    /// callout baked in at its destination).
    func endCalloutFlight() {
        guard calloutHoldImage != nil || !calloutFlightLayer.isHidden else { return }
        calloutHoldImage = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for flightLayer in [calloutFlightLayer, calloutFlightOutlineLayer, calloutFlightLeaderLayer] {
            flightLayer.isHidden = true
            flightLayer.removeAllAnimations()
        }
        calloutFlightLayer.contents = nil
        contentLayer.contents = image
        CATransaction.commit()
    }
}
