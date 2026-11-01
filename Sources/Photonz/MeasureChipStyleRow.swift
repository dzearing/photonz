// A picked measurement's Chip, Color and Marker rows: the same three an arrow's label has, in the same order.

import PhotonzCore
import SwiftUI

/// The picked measurements' readout chip: the ten style tiles in the
/// caliper's colour, the one Color, and the marker at the chip's front
/// (`ChipStyleTiles`, `docs/design/markup.md` section 8). The same rows an
/// arrow's label shows (`ArrowChipRow`), so a redline is one system.
struct MeasureChipStyleRow: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        readingForTheLookRows { lookBody }
    }

    @ViewBuilder private var lookBody: some View {
        let measures = editorState.measureLookLayers.compactMap(\.measure).filter(\.showLabel)
        if Experiments.shared.chipStylesEnabled, !measures.isEmpty {
            let styles = Set(measures.map(\.shownChipStyle))
            let markers = Set(measures.map { $0.chipStyle == nil ? ChipMarker.standard : $0.chipMarker })
            let inks = Set(measures.map { $0.strokeColorHex.uppercased() })
            let ink = inks.count == 1 ? inks.first : nil
            let note = measures.lazy.compactMap { $0.chipStyle == nil ? nil : $0.chipLegibilityNote }.first
            let state = editorState
            // Looked up at the press, so it reaches what is picked then.
            let picked: () -> [UUID] = { state.pickedMeasureChipIDs }
            VStack(alignment: .leading, spacing: 10) {
                ChipStyleTiles(selection: styles.count == 1 ? styles.first : nil,
                               ink: ink ?? MeasureColors.standard.strokeColorHex) { style in
                    state.setMeasureChipStyle(ids: picked(), style)
                }
                .equatable()
                VStack(alignment: .leading, spacing: 6) {
                    MarkupInkRow(ink: ink,
                                 pick: { state.setMeasureInk(ids: picked(), $0) },
                                 preview: { state.previewMeasureInk(ids: picked(), $0) },
                                 field: "Measure Color")
                        .equatable()
                    if let note {
                        ChipLegibilityWarning(note: note) {
                            let ids = state.measureLookLayers
                                .filter { $0.measure?.chipStyle != nil && $0.measure?.chipLegibilityNote != nil }
                                .map(\.id)
                            state.restoreMeasureChip(ids: ids)
                        }
                    }
                }
                ChipMarkerPicker(selection: markers.count == 1 ? markers.first : nil) { marker in
                    state.setMeasureChipMarker(ids: picked(), marker)
                }
                .equatable()
            }
            .panelStartProbe(.row, owner: "Measure Chip Style")
        }
    }
}

/// The same three rows in the Measure tool's settings, for the NEXT
/// measurement. Only while nothing is picked: with a measurement picked its own
/// rows are in Appearance, and they set the next one too, so one set of rows
/// is on screen at a time.
struct MeasureToolChipRows: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        if Experiments.shared.chipStylesEnabled, editorState.pickedMeasureChipIDs.isEmpty {
            let next = editorState.measureStyles
            let style = next.chipStyle ?? .today
            let marker = next.chipStyle == nil ? .standard : next.chipMarker
            let ink = next.colors.strokeColorHex
            let state = editorState
            VStack(alignment: .leading, spacing: 10) {
                ChipStyleTiles(selection: style, ink: ink) { state.setMeasureToolChipStyle($0) }
                MarkupInkRow(ink: ink, pick: { state.setMeasureToolInk($0) }, field: "Measure Color")
                ChipMarkerPicker(selection: marker) { state.setMeasureToolChipMarker($0) }
            }
            .panelStartProbe(.row, owner: "Measure Tool Chip")
        }
    }
}
