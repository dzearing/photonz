// The settings that hang under a part in Appearance: an arrow's thickness, its ending, its head size, and everything about its label.

import PhotonzCore
import SwiftUI

/// What an arrow used to keep in a section of its own.
///
/// There was an Annotation section — headed Arrow, Line, Shapes — carrying a
/// Thickness, an Ending, a Head Size, the caption field, its size and its
/// corner. Beside it, Appearance carried the arrow's one colour. Two places for
/// one question: what does this thing look like. The user asked on 2026-09-09
/// for one, so every one of those controls moved here, under the PART it
/// belongs to:
///
/// | Was in the arrow section | Is now under |
/// | --- | --- |
/// | Thickness | Line |
/// | Ending | Head |
/// | Head Size | Head |
/// | Caption | Caption, its own block |
/// | Label size | Caption |
/// | Label corners | Caption |
/// | Reset label position | the end of Appearance |
///
/// Each drawer sits behind the same bracket a shadow's settings sit behind
/// (`OwnedSettings`), so what a control belongs to is said by where it is
/// rather than left to be worked out from the order.
struct ShapePartSettings: View {
    @Environment(EditorState.self) private var editorState
    /// The row these belong to, which is also what decides what they ARE.
    let row: LayerPartRow

    var body: some View {
        let ids = reach
        let selection = shapes(ids)
        if row.part == .arrowHead, !selection.isEmpty {
            OwnedSettings(owner: row.title) {
                ending(selection, ids: ids)
                if selection.rows.contains(.headSize) { headSize(selection, ids: ids) }
            }
        } else if !selection.isEmpty, let slot = row.slot {
            switch slot {
            case .stroke where selection.rows.contains(.thickness):
                OwnedSettings(owner: row.title) {
                    thickness(selection, ids: ids)
                }
            case .captionText:
                // The old derivation could not make an unreadable pill; it
                // darkened the tone until white sat on it. Choosing the two
                // colours is worth more than that guarantee, so the guarantee
                // becomes a sentence: nothing is refused and nothing is
                // corrected behind anyone's back.
                if let note = legibilityNote(selection) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            default:
                EmptyView()
            }
        }
    }

    /// Said under the Label Text row when the words would not read on the fill
    /// they are sitting on. Over several arrows it is said once, because it is
    /// a warning rather than a reading.
    private func legibilityNote(_ selection: ShapeSelection) -> String? {
        selection.members.compactMap { $0.content.captionLegibilityNote }.first
    }

    /// The picked layers THIS row speaks for, which is not always the whole
    /// selection: pick an arrow and a box together and the Line row reaches the
    /// arrow alone, so its Thickness has to reach the arrow alone too.
    private var reach: [UUID] {
        // The Head row over an arrow that ends in nothing has no colour and so
        // no layers named on one, but its Ending picker still has to reach that
        // arrow: it is the control that gives it an ending back.
        if let ids = row.colors.first?.layerIDs, !ids.isEmpty { return ids }
        guard row.part == .arrowHead else { return [] }
        return editorState.shapeSelection.members
            .filter { $0.content.shape == .arrow }.map(\.id)
    }

    /// Those layers as shapes, so the sliders read what they actually wear.
    private func shapes(_ ids: [UUID]) -> ShapeSelection {
        let all = editorState.shapeSelection
        let wanted = Set(ids)
        return ShapeSelection(members: all.members.filter { wanted.contains($0.id) },
                              selectionCount: ids.count)
    }

    private func thickness(_ selection: ShapeSelection, ids: [UUID]) -> some View {
        ShapeSlider(layerIDs: ids, label: "Thickness",
                    reading: selection.outlineWidth,
                    range: AnnotationStyles.strokeWidthRange,
                    format: { DocumentUnit.text($0) },
                    preview: { editorState.previewOutlineWidth(ids: $0, $1) },
                    commit: { editorState.commitOutlineWidth(ids: $0, $1) })
            .panelHelp("How thick the line is. Its colour is the row above.")
    }

    /// What the arrow ENDS IN. A picture rather than a number, so it carries
    /// its own caption instead of a slider's readout.
    private func ending(_ selection: ShapeSelection, ids: [UUID]) -> some View {
        let reading = selection.reading { $0.arrowheadStyle }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Ending").font(.caption).foregroundStyle(.secondary)
                if reading.isMixed {
                    MixedWord()
                } else if let word = ArrowheadStylePicker.word(reading.value, isMixed: false) {
                    Text(word).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ArrowheadStylePicker(selection: reading.value, isMixed: reading.isMixed) {
                editorState.setArrowheadStyle(ids: ids, $0)
            }
        }
        .playtestField("Ending")
    }

    private func headSize(_ selection: ShapeSelection, ids: [UUID]) -> some View {
        ShapeSlider(layerIDs: ids, label: "Head Size",
                    reading: selection.number { $0.arrowheadScale },
                    range: AnnotationStyles.arrowheadScaleRange,
                    format: { "×\(String(format: "%.1f", $0))" },
                    round: { $0 },
                    preview: { editorState.previewAnnotationRestyle(ids: $0, arrowheadScale: $1) },
                    commit: { editorState.commitAnnotationRestyle(ids: $0, arrowheadScale: $1) })
    }
}

/// An arrow's label: the words, how big they are, and how round the pill round
/// them is.
///
/// Its own block rather than a drawer under one of the label's colour rows, for
/// one reason: those rows only exist once there ARE words, and this is where
/// the words are typed. It sits directly above them, so the order reads as
/// "what the label says, then what it is painted".
///
/// The words are content rather than looks, and putting them in a section
/// called Appearance is the one compromise in this whole arrangement. The
/// alternative was a second section holding a single text field, which is a
/// worse answer to the same question.
struct ArrowLabelSettings: View {
    @Environment(EditorState.self) private var editorState
    /// Whether any row in the list has a tick, so this block's name starts in
    /// the same column as the names beside the ticks.
    let leadsWithColumn: Bool

    var body: some View {
        let selection = editorState.shapeSelection
        // ONE arrow only. A single field over three arrows could only give all
        // three the same words, and a caption is what the arrow says.
        if selection.count == 1, let only = selection.members.first,
           only.content.shape == .arrow, Experiments.shared.arrowCaptionsEnabled {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
                    PanelRowHead(title: "Caption", leadsWithColumn: leadsWithColumn) {
                        EmptyView()
                    }
                    Spacer(minLength: 0)
                }
                OwnedSettings(owner: "Caption") {
                    ArrowCaptionField(layerID: only.id, showsLabel: false)
                    if only.content.hasCaption {
                        labelSize(selection)
                        labelCorners(selection)
                    }
                }
            }
            .playtestField("Caption")
            .panelStartProbe(.row, owner: "Caption")
        }
    }

    private func labelSize(_ selection: ShapeSelection) -> some View {
        ShapeSlider(layerIDs: selection.layerIDs, label: "Label size",
                    reading: selection.number { $0.captionFontSize },
                    range: MeasureContent.labelSizeRangePx,
                    format: { DocumentUnit.text($0) },
                    preview: { editorState.previewCaptionFontSize(ids: $0, $1) },
                    commit: { editorState.commitCaptionFontSize(ids: $0, $1) })
    }

    private func labelCorners(_ selection: ShapeSelection) -> some View {
        ShapeSlider(layerIDs: selection.layerIDs, label: "Label corners",
                    reading: selection.number { $0.captionRoundness },
                    range: AnnotationContent.captionRoundnessRange,
                    format: { AnnotationRoundnessWord.text($0) },
                    round: { $0 },
                    preview: { editorState.previewCaptionRoundness(ids: $0, $1) },
                    commit: { editorState.commitCaptionRoundness(ids: $0, $1) })
            .panelHelp("How round the label's corners are, from a square box through a badge to a full pill")
    }
}

/// What the label corner row says it is on. The two ends are shapes with names,
/// because "Square" and "Pill" are what somebody is actually after; the middle
/// is how far it has travelled between them.
enum AnnotationRoundnessWord {
    static func text(_ value: CGFloat) -> String {
        switch value {
        case ..<0.02: "Square"
        case 0.98...: "Pill"
        default: "\(Int((value * 100).rounded()))%"
        }
    }
}

/// The button that puts hand-dragged label pills back where the app places
/// them. It sits at the END of Appearance rather than under the Caption block,
/// because it speaks for every picked arrow at once and the block above it
/// speaks for exactly one.
struct ArrowLabelPlacementReset: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let pinned = editorState.shapeSelection.pinnedCaptionIDs
        if !pinned.isEmpty, Experiments.shared.arrowCaptionsEnabled {
            Button(pinned.count > 1 ? "Reset label positions" : "Reset label position") {
                editorState.resetCaptionPlacement(ids: pinned)
            }
            .font(.caption)
            .controlSize(.small)
            .panelHelp(pinned.count > 1
                  ? "Put all \(pinned.count) labels back where the app places them"
                  : "Put the label back where the app places it")
            .panelStartProbe(.row, owner: "Reset label position")
        }
    }
}
