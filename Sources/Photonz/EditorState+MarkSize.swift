// Size (S, M, L) and the Advanced resets for arrows and measurements: one undo step each, remembered for the next mark (markup.md sections 7 and 8).

import Foundation
import PhotonzCore

/// Which simplified Appearance the panel shows, if any: every picked layer an
/// arrow, or every one a measurement. A mixture keeps the full parts list,
/// since its rows speak for things that have no Arrow, Chip or Size.
enum MarkupAppearanceKind: Equatable {
    case arrows
    case measurements
}

/// One part under Advanced, and where its colour comes from.
enum MarkupPartOrigin: Equatable {
    /// Still the one Color's.
    case fromColor
    /// Still what the chip style derives from the Color.
    case fromStyle
    /// Painted by hand; the reset hands it back.
    case byHand
}

extension EditorState {

    /// The simplified Appearance for what is picked (`MarkupAppearanceKind`).
    var markupAppearanceKind: MarkupAppearanceKind? {
        guard Experiments.shared.chipStylesEnabled, Experiments.shared.shapePartsEnabled,
              let document else { return nil }
        let picked = colorSlotTargetIDs.compactMap { document.layer(id: $0) }.filter { !$0.isLocked }
        guard !picked.isEmpty else { return nil }
        if picked.allSatisfy({ $0.annotation?.shape == .arrow }) { return .arrows }
        if picked.allSatisfy({ $0.measure != nil }) { return .measurements }
        return nil
    }

    /// The picked arrows' contents, for the Size and Advanced readings.
    var pickedArrowContents: [(id: UUID, content: AnnotationContent)] {
        guard let document else { return [] }
        return colorSlotTargetIDs.compactMap { id in
            guard let layer = document.layer(id: id), !layer.isLocked,
                  let a = layer.annotation, a.shape == .arrow else { return nil }
            return (id, a)
        }
    }

    // MARK: Arrows

    /// S, M or L over the picked arrows: the chip's type and padding, and the
    /// line's weight wherever Thickness was not set by hand. One undo step,
    /// and the size the next arrow is drawn at.
    func setArrowMarkSize(ids: [UUID], _ size: MarkSize) {
        guard let doc = document else { return }
        let targets = ids.filter { doc.layer(id: $0).map { $0.annotation?.shape == .arrow && !$0.isLocked } == true }
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { document in
            let canvas = document.canvasSize
            for id in targets {
                document.updateLayer(id: id) { layer in
                    guard var a = layer.annotation else { return }
                    a.applyMarkSize(size)
                    let sized = AnnotationBuilder.restyled(layer, strokeWidth: a.strokeWidth,
                                                           captionFontSize: a.captionFontSize)
                    layer = sized.annotation?.hasCaption == true
                        ? AnnotationBuilder.planningCaption(sized, canvas: canvas,
                                                            captionPillSize: sized.measuredCaptionPillSize)
                        : sized
                }
            }
        }
        rememberArrowMarkSize(size)
    }

    /// The Arrow tool's Size, for the next arrow: its chip's type, and its
    /// line's weight unless the tool's Thickness was set apart from the sizes.
    func setAnnotationMarkSize(_ size: MarkSize) {
        if let layer = selectedAnnotationLayer, layer.annotation?.shape == .arrow {
            setArrowMarkSize(ids: [layer.id], size)
            return
        }
        rememberArrowMarkSize(size)
    }

    /// The Size the Arrow tool's next arrow is drawn at, or nil when its
    /// chip's type was set to something else.
    var annotationToolMarkSize: MarkSize? {
        MarkSize.matching(scale: annotationStyles.captionFontSize(forShape: .arrow)
                          / AnnotationContent.captionFontSizeDefault)
    }

    private func rememberArrowMarkSize(_ size: MarkSize) {
        var next = AnnotationContent(shape: .arrow,
                                     strokeWidth: annotationStyles.strokeWidth(forShape: .arrow),
                                     captionFontSize: annotationStyles.captionFontSize(forShape: .arrow))
        next.applyMarkSize(size)
        annotationStyles.setCaptionFontSize(next.captionFontSize, forShape: .arrow)
        annotationStyles.setStrokeWidth(next.strokeWidth, forShape: .arrow)
        saveAnnotationStyles()
    }

    /// Hands one part of the picked arrows back to the Color or the style.
    func resetArrowPart(ids: [UUID], _ part: MarkupResetPart) {
        guard let doc = document else { return }
        let targets = ids.filter { doc.layer(id: $0).map { $0.annotation?.shape == .arrow && !$0.isLocked } == true }
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { document in
            let canvas = document.canvasSize
            for id in targets {
                document.updateLayer(id: id) { layer in
                    guard var a = layer.annotation,
                          let start = layer.annotationEndpoint(.start),
                          let end = layer.annotationEndpoint(.end) else { return }
                    switch part {
                    case .line: a.setInk(a.colorHex)
                    case .head: a.resetHeadToLine()
                    case .chip(let piece): a.resetCaptionPartsByHand([piece])
                    case .thickness: a.resetThicknessToSize()
                    case .headSize: a.resetHeadSize()
                    }
                    var changed = layer
                    changed.content = .annotation(a)
                    changed = AnnotationBuilder.updating(changed, start: start, end: end)
                    layer = changed.annotation?.hasCaption == true
                        ? AnnotationBuilder.planningCaption(changed, canvas: canvas,
                                                            captionPillSize: changed.measuredCaptionPillSize)
                        : changed
                }
            }
        }
    }

    // MARK: Measurements

    /// The picked measurements' Size, the same rule as an arrow's on the chip
    /// alone: the caliper keeps its hairline.
    func setMeasureMarkSize(ids: [UUID], _ size: MarkSize) {
        rechipMeasures(ids: ids, replan: true) { $0.applyMarkSize(size) }
    }

    /// The Measure tool's Size, for the next measurement.
    func setMeasureToolMarkSize(_ size: MarkSize) {
        updateMeasureStyles { styles in
            var next = styles.content
            next.applyMarkSize(size)
            styles.absorb(next)
        }
    }

    /// Hands one chip part, or the caliper, of the picked measurements back.
    func resetMeasurePart(ids: [UUID], _ part: MarkupResetPart) {
        let looks = measureStyles
        rechipMeasures(ids: ids, replan: false) { m in
            switch part {
            case .chip(let piece): m.resetChipPart(piece, toLookOf: looks.content(for: m.role))
            default: break
            }
        }
    }
}

/// What a reset under Advanced hands back.
enum MarkupResetPart: Equatable {
    case line
    case head
    case chip(CaptionPart)
    case thickness
    case headSize
}
