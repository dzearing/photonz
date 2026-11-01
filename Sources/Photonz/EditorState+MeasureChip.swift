// A measurement's chip style, marker and one Color: the same controls an arrow's label has, one undo step each, remembered for the next measurement.

import Foundation
import PhotonzCore

extension EditorState {

    /// The picked measurements the Chip, Color and Marker rows speak for.
    var pickedMeasureChipIDs: [UUID] {
        measureLookLayers.filter { $0.measure?.showLabel == true }.map(\.id)
    }

    /// Restyles measurements' chips in one undo step, the frame re-padded for
    /// the chip's new room. A chip that grew gets to pick its spot again,
    /// unless somebody placed it by hand.
    private func rechipMeasures(ids: [UUID], replan: Bool, _ change: @escaping (inout MeasureContent) -> Void) {
        guard let doc = document else { return }
        let targets = ids.filter { doc.layer(id: $0)?.measure != nil && doc.layer(id: $0)?.isLocked == false }
        guard !targets.isEmpty else { return }
        discardDragPreview()
        let canvas = doc.canvasSize
        perform { document in
            for id in targets {
                guard let layer = document.layer(id: id) else { continue }
                var updated = MeasureBuilder.rechipped(layer, change)
                if replan {
                    updated = MeasureBuilder.replanningLabel(updated, canvas: canvas,
                                                             avoiding: self.placedReadoutRects(excluding: id))
                }
                document.updateLayer(id: id) { $0 = updated }
            }
        }
        if let first = targets.first, let content = document?.layer(id: first)?.measure {
            updateMeasureStyles { $0.absorb(content) }
        }
    }

    /// The Chip tiles over picked measurements: one undo step, and the style
    /// the next measurement's chip wears.
    func setMeasureChipStyle(ids: [UUID], _ style: ChipStyle) {
        rechipMeasures(ids: ids, replan: true) { $0.applyChipStyle(style) }
    }

    /// The Marker row, the same way.
    func setMeasureChipMarker(ids: [UUID], _ marker: ChipMarker) {
        rechipMeasures(ids: ids, replan: true) { m in
            // A marker only shows on a styled chip, so asking for one on the
            // pill from before styles puts it on Today, the look it wears.
            if m.chipStyle == nil { m.applyChipStyle(.today) }
            m.chipMarker = marker
        }
    }

    /// The one Color (markup.md section 2): the caliper and the chip retinted
    /// together, the chip's plate and words derived so they read.
    func setMeasureInk(ids: [UUID], _ hex: String) {
        rechipMeasures(ids: ids, replan: false) { $0.setInk(hex) }
        recordRecentColor(hex: hex)
    }

    /// The same, live while a picker's square is dragged: nothing recorded
    /// until `setMeasureInk` lands on release.
    func previewMeasureInk(ids: [UUID], _ hex: String) {
        guard var doc = document else { return }
        let targets = ids.filter { doc.layer(id: $0)?.measure != nil }
        guard !targets.isEmpty else { return }
        discardDragPreview()
        for id in targets {
            doc.updateLayer(id: id) { layer in layer = MeasureBuilder.rechipped(layer) { $0.setInk(hex) } }
        }
        submit(doc)
    }

    /// The legibility warning's way back: the chip's automatic colours.
    func restoreMeasureChip(ids: [UUID]) {
        rechipMeasures(ids: ids, replan: false) { $0.restoreAutomaticChip() }
    }

    // MARK: The next measurement, from the Measure tool's settings

    /// The Measure tool's Chip tiles: the style the next measurement's chip
    /// wears.
    func setMeasureToolChipStyle(_ style: ChipStyle) {
        updateMeasureStyles { $0.chipStyle = style }
    }

    func setMeasureToolChipMarker(_ marker: ChipMarker) {
        updateMeasureStyles { styles in
            if styles.chipStyle == nil { styles.chipStyle = .today }
            styles.chipMarker = marker
        }
    }

    func setMeasureToolInk(_ hex: String) {
        updateMeasureStyles { styles in
            // The same rule as on a measurement: the chip from before styles
            // takes Today, the look it already wears, so the colour reaches it.
            var next = styles.content
            next.setInk(hex)
            styles.absorb(next)
        }
        recordRecentColor(hex: hex)
    }

    // MARK: Right-click

    /// A measurement's Chip Style submenu, for its right-click menu: the same
    /// ten an arrow label's offers, ticked on the one it wears.
    func measureChipStyleMenuRows(id: UUID) -> [MenuRow] {
        guard Experiments.shared.chipStylesEnabled, let doc = document,
              doc.layer(id: id)?.measure?.showLabel == true else { return [] }
        let targets = rowMenuTargets(id).filter { doc.layer(id: $0)?.measure?.showLabel == true }
        let worn = Set(targets.compactMap { doc.layer(id: $0)?.measure?.shownChipStyle })
        let markers = Set(targets.compactMap { id in
            doc.layer(id: id)?.measure.map { $0.chipStyle == nil ? ChipMarker.standard : $0.chipMarker }
        })
        return [
            .submenu(ChipStyle.menuTitle, ChipStyle.allCases.map { style in
                .toggle(style.title, isOn: worn == [style]) { [weak self] in
                    self?.setMeasureChipStyle(ids: Array(targets), style)
                }
            }),
            .submenu(ChipMarker.menuTitle, ChipMarker.allCases.map { marker in
                .toggle(marker.title, isOn: markers == [marker]) { [weak self] in
                    self?.setMeasureChipMarker(ids: Array(targets), marker)
                }
            }),
        ]
    }
}
