// The settings for picked text: font, size, weight, alignment and colour.

import AppKit
import PhotonzCore
import SwiftUI

/// The picked text layers' type (13.1): font face, size, weight and alignment,
/// over the WHOLE selection.
///
/// Pick three labels and one size reaches all three, in one undo step. Where
/// they differ the menu says Mixed and choosing anything makes them agree. The
/// ink is in the Color section with every other color; this is the type itself.
private extension TextAlign {
    /// The picture on this row's segment. `text.align*` is the system's own
    /// family for it, and a screen reader and a scripted walk both name the
    /// segment from the symbol, so these stay the standard ones.
    var symbolName: String {
        switch self {
        case .left: "text.alignleft"
        case .center: "text.aligncenter"
        case .right: "text.alignright"
        }
    }
}

private extension TextVerticalAlign {
    /// The same idea down the box.
    var symbolName: String {
        switch self {
        case .top: "align.vertical.top"
        case .middle: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        }
    }

    /// That picture, carrying the PLACE's name.
    ///
    /// A segment named itself out of the picture on it, and the three
    /// `align.vertical.*` symbols carry no description at all, so this row
    /// read out as nothing: a screen reader announced three anonymous buttons
    /// and a scripted walk skipped straight past them. (The Across row is fine
    /// by luck — the system happens to describe `text.align*` as "align left"
    /// and so on.) Built through `NSImage` the description is ours, so Top,
    /// Middle and Bottom each answer to their own word. The same way
    /// `ArrowheadStyle.glyph` names the endings; a SwiftUI
    /// `.accessibilityLabel` on the Image does not reach the segment.
    ///
    /// 11pt medium is the size `Image(systemName:)` already draws at inside a
    /// small segmented picker, so the pictures do not move: rendered both
    /// ways, light and dark, the row comes out pixel for pixel the same.
    var glyph: Image {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) else {
            return Image(systemName: symbolName)
        }
        let sized = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)) ?? image
        sized.accessibilityDescription = title
        return Image(nsImage: sized)
    }
}

struct TextInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let selection = editorState.textSelection
        let ids = selection.layerIDs
        if !selection.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // The Style row first: it sets every row under it at once, and
                // a control that does that placed below them is a control
                // nobody finds (Next, `next-styles`).
                TextStyleRow()
                SelectionMenu(label: "Font",
                              reading: selection.reading { $0.fontName },
                              options: fontFamilies(selection),
                              title: { $0 },
                              help: help("font", selection.count),
                              pinnedWidth: Self.fontMenuWidth) {
                    editorState.setTextStyle(ids: ids, fontName: $0)
                }
                HStack(alignment: .top, spacing: 8) {
                    SelectionMenu(label: "Size",
                                  reading: selection.number { $0.fontSize },
                                  options: sizes(selection),
                                  // Padded out to three digits, so every size
                                  // takes the same room and the box holds one
                                  // width whatever the list picked up. The
                                  // padding is invisible; `spoken` is the same
                                  // words without it, for the sentence a
                                  // hover says.
                                  title: { TextStyles.sizeTitle($0) },
                                  spoken: { TextStyles.sizeWords($0) },
                                  help: help("size", selection.count)) {
                        editorState.setTextStyle(ids: ids, fontSize: $0)
                    }
                    SelectionMenu(label: "Weight",
                                  reading: selection.reading { $0.weight },
                                  options: TextWeight.allCases,
                                  title: { $0.rawValue.capitalized },
                                  help: help("weight", selection.count)) {
                        editorState.setTextStyle(ids: ids, weight: $0)
                    }
                }
                // Where the words sit inside their own boxes. Only tells while
                // a box is bigger than its words, which is what a box told to
                // stretch is (Next, `next-placement`).
                if Experiments.shared.placementEnabled { alignRow(selection, ids: ids) }
                SelectionStyleNotes(notes: [selection.note,
                                            Experiments.shared.placementEnabled
                                                ? selection.downTheBoxNote : nil,
                                            // What a pick in Font, Size or
                                            // Weight would cost text wearing a
                                            // name: said BEFORE the click.
                                            editorState.textStylesEnabled
                                                ? editorState.textStyleSelection.unlinkNote : nil],
                                    caption: selectionCaption(selection.count, "A change here"))
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 8)
        }
    }

    // The pictures on the two alignment rows. They live beside the row that
    // draws them, and both rows build their pictures AND their tooltips by
    // walking `allCases`, so a name can never end up under the wrong picture.

    /// Align: where the words sit across their box and down it.
    ///
    /// Two segmented controls rather than menus, because this is the one thing
    /// in the section that is read as a picture, and because every tool that
    /// has it draws it exactly this way. Layers that differ leave both controls
    /// showing nothing picked, which is the Mac's own way of saying Mixed on a
    /// row of buttons.
    private func alignRow(_ selection: TextLayerSelection, ids: [UUID]) -> some View {
        let across = selection.reading { $0.usedAlignment }
        let down = selection.reading { $0.usedVerticalAlignment }
        return HStack(alignment: .top, spacing: 8) {
            captioned("Across", isMixed: across.isMixed) {
                Picker("Words across the box", selection: Binding<TextAlign?>(
                    get: { across.isMixed ? nil : across.value },
                    set: { if let v = $0 { editorState.setTextAlignment(ids: ids, v) } })) {
                    ForEach(TextAlign.allCases, id: \.self) { align in
                        Image(systemName: align.symbolName).tag(TextAlign?.some(align))
                    }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                // Left, Center, Right, one on each picture, from the same
                // `allCases` that built them.
                .segmentToolTips(TextAlign.allCases.map(\.title),
                                 fallback: across.isMixed
                                 ? "The picked layers sit their words differently across the box. Choosing one sets all of them."
                                 : "Where the words sit across the box")
            }
            captioned("Down", isMixed: down.isMixed) {
                Picker("Words down the box", selection: Binding<TextVerticalAlign?>(
                    get: { down.isMixed ? nil : down.value },
                    set: { if let v = $0 { editorState.setTextAlignment(ids: ids, v) } })) {
                    ForEach(TextVerticalAlign.allCases, id: \.self) { align in
                        align.glyph.tag(TextVerticalAlign?.some(align))
                    }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                .segmentToolTips(TextVerticalAlign.allCases.map(\.title),
                                 fallback: down.isMixed
                                 ? "The picked layers sit their words differently down the box. Choosing one sets all of them."
                                 : "Where the words sit down the box")
            }
        }
    }

    /// A control with its name in a small caption above it, the way the rest of
    /// this dock labels things. Both alignment controls show nothing picked
    /// when the layers differ, so without a caption a blank row of buttons
    /// cannot say which of the two is the one that differs.
    ///
    /// And the caption is where the word Mixed goes, because a row of picture
    /// buttons has nowhere else to put it: lighting no segment says the layers
    /// differ and says a value was never set in exactly the same way, and those
    /// are different answers.
    ///
    /// It sits right after the row's own word rather than out at the trailing
    /// edge, where a slider's readout sits. Across and Down are two columns on
    /// one line, and a trailing Mixed lands hard against the next column's
    /// caption: the first build of this read "Across      Mixed  Down", which
    /// says nothing about which of the two differs. Beside its own word it can
    /// only mean one of them.
    @ViewBuilder private func captioned<Content: View>(_ label: String,
                                                       isMixed: Bool = false,
                                                       @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if isMixed { MixedWord() }
                Spacer(minLength: 0)
            }
            content()
        }
        .playtestField(label)
    }

    /// What a menu says it is. Over a selection it says how far it reaches, so
    /// a menu reading Mixed also says what it is mixed about.
    private func help(_ part: String, _ count: Int) -> String {
        count > 1 ? "The \(part) of all \(count) selected layers" : "The \(part) of this text"
    }

    /// Curated families plus any the picked labels are already set in, so a
    /// label in an off-list font does not lose it just by being picked.
    private func fontFamilies(_ selection: TextLayerSelection) -> [String] {
        TextStyles.fontOptions(picked: selection.fontNames)
    }

    /// The width the Font menu holds, whatever is in its list.
    ///
    /// The curated families are in the list in every state it can be in, so the
    /// width they need is the narrowest the menu could ever be — and a pop-up
    /// never accepts a width wider than its content, so this is also the widest
    /// constant available. Every curated family therefore lands exactly where
    /// it does today, and only a longer name brought in by an opened document
    /// is shortened rather than shoving the row sideways.
    private static var fontMenuWidth: CGFloat {
        MenuMetrics.width(ofOptions: TextStyles.fonts)
    }

    /// Preset sizes plus any the picked labels already wear.
    private func sizes(_ selection: TextLayerSelection) -> [CGFloat] {
        let extra = selection.fontSizes.filter { !TextStyles.fontSizes.contains($0) }
        return extra.isEmpty ? TextStyles.fontSizes : (TextStyles.fontSizes + extra).sorted()
    }
}
