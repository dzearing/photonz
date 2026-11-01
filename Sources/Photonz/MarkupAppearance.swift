// The simplified Appearance of an arrow or a measurement: Size, and the Advanced fold that holds every part, each saying where its colour comes from (markup.md section 8).

import PhotonzCore
import SwiftUI

/// S, M and L: the chip's type size and padding, and an arrow's line weight
/// unless Thickness was set by hand (markup.md section 7).
struct MarkSizeRow: View, Equatable {
    /// The size that is lit, or nil over a mixture or a size typed by hand.
    let selection: MarkSize?
    var labelFont: Font = .caption
    /// The row's name in the panel's register, where a walk finds it.
    var field = "Size"
    let pick: (MarkSize) -> Void

    nonisolated static func == (a: MarkSizeRow, b: MarkSizeRow) -> Bool {
        a.selection == b.selection && a.labelFont == b.labelFont && a.field == b.field
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("Size").font(labelFont).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            SegmentedControl("Size", selection: selection,
                             options: MarkSize.allCases.map { .init($0, $0.title, help: $0.name) },
                             form: .natural) { pick($0) }
                .controlSize(.small)
                .panelHelp("How big the chip's words are, and the line with them")
        }
        .playtestField(field)
    }
}

/// Everything about a mark that its Color, style and Size already decide,
/// folded away until somebody asks for it. Closed until opened, and it stays
/// the way it was left, the way the panel's sections do.
struct MarkupAdvancedFold<Content: View>: View {
    @AppStorage(MarkupAdvancedFoldKey.open) private var isOpen = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Button {
                withAnimation(.snappy(duration: 0.22)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Advanced").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(isOpen ? "Hide" : "Show").font(.caption).foregroundStyle(Color.accentColor)
                }
                .frame(minHeight: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .playtestControl("Advanced", detail: isOpen ? "open" : "closed")
            .accessibilityLabel(isOpen ? "Hide Advanced" : "Show Advanced")
            .panelHelp(isOpen ? "Hide the parts" : "Each part on its own: colours, thickness, head")
            if isOpen {
                VStack(alignment: .leading, spacing: 10) { content }
                    .transition(.opacity)
            }
        }
        .playtestField("Advanced")
        .panelStartProbe(.row, owner: "Advanced")
    }
}

/// The key the fold remembers itself under, outside the generic type so the
/// walk harness can forget it with the rest of the panel.
enum MarkupAdvancedFoldKey {
    static let open = "panel.markupAdvancedOpen"
}

/// Where a part's colour comes from, said at the end of its row: from the
/// Color, from the style, or a Reset once it was painted by hand.
struct MarkupOriginTag: View {
    let origin: MarkupPartOrigin
    let reset: () -> Void

    var body: some View {
        switch origin {
        case .fromColor:
            Text("from Color").font(.caption).foregroundStyle(.secondary)
                .frame(minHeight: ColorPartLayout.rowHeight)
                .playtestControl("Origin", detail: "from Color")
        case .fromStyle:
            Text("from style").font(.caption).foregroundStyle(.secondary)
                .frame(minHeight: ColorPartLayout.rowHeight)
                .playtestControl("Origin", detail: "from style")
        case .byHand:
            Button("Reset", action: reset)
                .font(.caption)
                .buttonStyle(.link)
                .frame(minHeight: ColorPartLayout.rowHeight)
                .playtestControl("Reset", detail: "set by hand")
                .panelHelp("Back to the Color and the style")
        }
    }
}

/// Said under Thickness or Head Size once it was set by hand, with the way
/// back to what Size draws.
struct SizeOverrideNote: View {
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Overrides Size").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Reset", action: reset)
                .font(.caption)
                .buttonStyle(.link)
                .playtestControl("Reset", detail: "overrides Size")
                .panelHelp("Back to what Size draws")
        }
    }
}

/// The picked arrows' Size, under their Marker.
struct ArrowSizeRow: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        readingForTheLookRows { lookBody }
    }

    @ViewBuilder private var lookBody: some View {
        let arrows = editorState.pickedArrowContents
        if !arrows.isEmpty {
            let sizes = Set(arrows.map { $0.content.markSize })
            let state = editorState
            MarkSizeRow(selection: sizes.count == 1 ? sizes.first ?? nil : nil, field: "Arrow Size") { size in
                state.setArrowMarkSize(ids: state.pickedArrowContents.map(\.id), size)
            }
            .equatable()
            .panelStartProbe(.row, owner: "Size")
        }
    }
}

/// The picked measurements' Size, under their Marker.
struct MeasureSizeRow: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        readingForTheLookRows { lookBody }
    }

    @ViewBuilder private var lookBody: some View {
        let measures = editorState.measureLookLayers.compactMap(\.measure)
        if !measures.isEmpty {
            let sizes = Set(measures.map(\.markSize))
            let state = editorState
            MarkSizeRow(selection: sizes.count == 1 ? sizes.first ?? nil : nil, field: "Measure Size") { size in
                state.setMeasureMarkSize(ids: state.measureLookLayers.map(\.id), size)
            }
            .equatable()
            .panelStartProbe(.row, owner: "Size")
        }
    }
}

/// An arrow's Advanced: Line, Head, Chip Fill, Chip Edge and Chip Text, each
/// saying where its colour comes from; then Thickness, Head Size and Ending;
/// then the words on the chip.
struct ArrowAdvancedRows: View {
    @Environment(EditorState.self) private var editorState
    let rows: [LayerPartRow]
    let leadsWithColumn: Bool

    var body: some View {
        let arrows = editorState.pickedArrowContents
        let state = editorState
        ForEach(rows) { row in
            let tag = Self.origin(of: row, arrows.map(\.content))
            PartRowView(row: row, leadsWithColumn: leadsWithColumn,
                        shownTitle: Self.mockTitle(row),
                        origin: tag.map { origin in
                            (origin.0, { state.resetArrowPart(ids: state.pickedArrowContents.map(\.id), origin.1) })
                        })
        }
        if let line = rows.first(where: { $0.slot == .stroke }) {
            ShapePartSettings(row: line, flat: true)
        }
        if let head = rows.first(where: { $0.part == .arrowHead }) {
            ShapePartSettings(row: head, flat: true)
        }
        ArrowLabelSettings(leadsWithColumn: leadsWithColumn, inFold: true)
    }

    /// The mock's names: the label is a chip, as it is on a measurement.
    static func mockTitle(_ row: LayerPartRow) -> String {
        switch row.slot {
        case .captionFill?: "Chip Fill"
        case .captionBorder?: "Chip Edge"
        case .captionText?: "Chip Text"
        default: row.title
        }
    }

    /// Where the row's colour comes from over the picked arrows, and what its
    /// reset hands back; nil for a pill from before chip styles, whose parts
    /// were only ever its own.
    static func origin(of row: LayerPartRow,
                       _ arrows: [AnnotationContent]) -> (MarkupPartOrigin, MarkupResetPart)? {
        guard !arrows.isEmpty else { return nil }
        func chip(_ piece: CaptionPart) -> (MarkupPartOrigin, MarkupResetPart)? {
            let styled = arrows.filter { $0.chipStyle != nil && $0.hasCaption }
            guard !styled.isEmpty else { return nil }
            let byHand = styled.contains { $0.captionPartsByHand.contains(piece) }
            return (byHand ? .byHand : .fromStyle, .chip(piece))
        }
        switch row.slot {
        case .stroke?: return (arrows.contains(where: \.lineByHand) ? .byHand : .fromColor, .line)
        case .arrowHead?: return (arrows.contains(where: \.headByHand) ? .byHand : .fromColor, .head)
        case .captionFill?: return chip(.fill)
        case .captionBorder?: return chip(.edge)
        case .captionText?: return chip(.text)
        default:
            if row.part == .arrowHead {
                return (arrows.contains(where: \.headByHand) ? .byHand : .fromColor, .head)
            }
            return nil
        }
    }
}

/// A measurement's Advanced: the Caliper and the chip's three, each saying
/// where its colour comes from, then the caliper's thickness, the chip's
/// edge, what the number reads in, and the Role it calls out.
struct MeasureAdvancedRows: View {
    @Environment(EditorState.self) private var editorState
    let rows: [LayerPartRow]
    let leadsWithColumn: Bool

    var body: some View {
        let measures = editorState.measureLookLayers.compactMap(\.measure)
        let state = editorState
        ForEach(rows) { row in
            let tag = Self.origin(of: row, measures)
            PartRowView(row: row, leadsWithColumn: leadsWithColumn,
                        origin: tag.map { origin in
                            (origin.0, { state.resetMeasurePart(ids: state.measureLookLayers.map(\.id), origin.1) })
                        })
        }
        ForEach(rows) { row in
            MeasurePartSettings(row: row, flat: true)
        }
        MeasureChipSettings(leadsWithColumn: leadsWithColumn, inFold: true)
        MeasureRoleRow()
    }

    static func origin(of row: LayerPartRow,
                       _ measures: [MeasureContent]) -> (MarkupPartOrigin, MarkupResetPart)? {
        guard !measures.isEmpty else { return nil }
        func chip(_ piece: CaptionPart) -> (MarkupPartOrigin, MarkupResetPart)? {
            // The pill from before styles counts too: it wears the look a new
            // measurement starts with, which the Chip row shows as Today.
            let shown = measures.filter(\.showLabel)
            guard !shown.isEmpty else { return nil }
            let byHand = shown.contains { $0.chipPartsByHand.contains(piece) }
            return (byHand ? .byHand : .fromStyle, .chip(piece))
        }
        switch row.slot {
        case .caliper?: return (.fromColor, .line)
        case .chipFill?: return chip(.fill)
        case .chipBorder?: return chip(.edge)
        case .chipText?: return chip(.text)
        default: return nil
        }
    }
}
