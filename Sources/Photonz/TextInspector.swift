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
extension TextAlign {
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
    var glyph: NSImage? {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) else {
            return nil
        }
        let sized = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)) ?? image
        sized.accessibilityDescription = title
        return sized
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
                              help: help("font", selection.count)) {
                    editorState.setTextStyle(ids: pickedIDs, fontName: $0)
                }
                // The three menus read the pick when chosen, not when drawn, so
                // they can skip picks that change nothing they show.
                .equatable()
                if Experiments.shared.panelRowsInOneColumnEnabled {
                    // The title mock's line (`video-title-wt.html`, `.numgrid`):
                    // a Size box you type into beside the Weight dropdown.
                    TextSizeAndWeightRow(
                        size: selection.number { $0.fontSize },
                        sizes: selection.fontSizes,
                        weight: selection.reading { $0.weight },
                        identity: AnyHashable(ids),
                        sizeHelp: help("size", selection.count),
                        weightHelp: help("weight", selection.count),
                        setSize: { editorState.setTextStyle(ids: pickedIDs, fontSize: $0) },
                        setWeight: { editorState.setTextStyle(ids: pickedIDs, weight: $0) })
                } else {
                PanelPair {
                    SelectionMenu(label: "Size",
                                  reading: selection.number { $0.fontSize },
                                  options: sizes(selection),
                                  title: { TextStyles.sizeWords($0) },
                                  help: help("size", selection.count)) {
                        editorState.setTextStyle(ids: pickedIDs, fontSize: $0)
                    }
                    .equatable()
                    SelectionMenu(label: "Weight",
                                  reading: selection.reading { $0.weight },
                                  options: TextWeight.allCases,
                                  title: { $0.rawValue.capitalized },
                                  help: help("weight", selection.count)) {
                        editorState.setTextStyle(ids: pickedIDs, weight: $0)
                    }
                    .equatable()
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
                                                ? editorState.textStyleSelection.unlinkNote : nil])
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
        return PanelPair {
            captioned("Across", isMixed: across.isMixed) {
                // Left, Center, Right, one on each picture, from the same
                // `allCases` that built them.
                SegmentedControl("Words across the box", selection: across.isMixed ? nil : across.value,
                                 options: TextAlign.allCases.map {
                                     .init($0, $0.title, image: SegmentedControl<TextAlign>.symbol($0.symbolName, named: $0.title))
                                 },
                                 form: .natural, showsTitles: false,
                                 systemHelp: across.isMixed
                                 ? "The picked layers sit their words differently across the box. Choosing one sets all of them."
                                 : "Where the words sit across the box") {
                    editorState.setTextAlignment(ids: ids, $0)
                }
                .controlSize(.small)
            }
            captioned("Down", isMixed: down.isMixed) {
                SegmentedControl("Words down the box", selection: down.isMixed ? nil : down.value,
                                 options: TextVerticalAlign.allCases.map { .init($0, $0.title, image: $0.glyph) },
                                 form: .natural, showsTitles: false,
                                 systemHelp: down.isMixed
                                 ? "The picked layers sit their words differently down the box. Choosing one sets all of them."
                                 : "Where the words sit down the box") {
                    editorState.setTextAlignment(ids: ids, $0)
                }
                .controlSize(.small)
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
        if Experiments.shared.panelRowsInOneColumnEnabled {
            // The mock's row: Mixed follows the buttons, since the label
            // column holds the name and nothing else.
            PanelFieldRow(label) {
                HStack(spacing: 6) {
                    content().fixedSize()
                    if isMixed { MixedWord() }
                }
            }
            .playtestField(label)
        } else {
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
    }

    /// The text picked at the moment a menu is used.
    private var pickedIDs: [UUID] { editorState.textSelection.layerIDs }

    /// What a menu says it is. Over a selection it says how far it reaches, so
    /// a menu reading Mixed also says what it is mixed about.
    private func help(_ part: String, _ count: Int) -> String {
        CrowdWords.all(count).map { "The \(part) of \($0) selected layers" }
            ?? "The \(part) of this text"
    }

    /// Curated families plus any the picked labels are already set in, so a
    /// label in an off-list font does not lose it just by being picked.
    private func fontFamilies(_ selection: TextLayerSelection) -> [String] {
        TextStyles.fontOptions(picked: selection.fontNames)
    }

    /// Preset sizes plus any the picked labels already wear.
    private func sizes(_ selection: TextLayerSelection) -> [CGFloat] {
        TextStyles.sizeOptions(picked: selection.fontSizes)
    }
}

/// Size and Weight on one line, the way the title mock draws them
/// (`video-title-wt.html`, the `.numgrid` in the Text section): a box you type
/// any size into, with the preset sizes on a list at its end, and the Weight
/// dropdown beside it. Half the line each, like X beside Y.
///
/// A box rather than a menu because type is a number. With a menu of seven
/// sizes the only way to 30 was to drag the text's box on the canvas;
/// Photoshop's size field takes any number and keeps its presets on the same
/// field, and so does this. Arrow keys nudge by one, Shift by ten.
///
/// Shared by text layers and the Captions layer, so both read the same.
struct TextSizeAndWeightRow: View {
    let size: StyleReading<CGFloat>
    /// The sizes the picked text wears, so one off the preset list joins it
    /// and can be ticked.
    let sizes: [CGFloat]
    let weight: StyleReading<TextWeight>
    /// What the box speaks for: a different pick starts a fresh draft.
    let identity: AnyHashable
    let sizeHelp: String
    let weightHelp: String
    let setSize: (CGFloat) -> Void
    let setWeight: (TextWeight) -> Void

    var body: some View {
        let shownSize = size.isMixed ? nil : size.value
        let shownWeight = weight.isMixed ? nil : weight.value
        HStack(spacing: 8) {
            PanelNumberField(
                showing: TextStyles.sizeShowing(size),
                label: "Size",
                identity: identity,
                width: .flexible(least: 28),
                floor: TextStyles.smallestSize,
                ceiling: TextStyles.largestSize,
                wholeNumbers: true,
                help: sizeHelp,
                look: .well,
                presets: .init(
                    label: "Size",
                    value: shownSize.map(TextStyles.sizeWords) ?? LayerStyleSelection.mixedText,
                    choices: .picking(TextStyles.sizeOptions(picked: sizes), current: shownSize,
                                      title: { TextStyles.sizeWords($0) }) { setSize($0) }),
                land: { value in
                    setSize(value)
                    return nil
                })
            .frame(maxWidth: .infinity)
            .playtestField("Size")
            VideoKit.Dropdown(
                label: "Weight",
                value: shownWeight.map { $0.rawValue.capitalized } ?? LayerStyleSelection.mixedText,
                valueStyle: shownWeight == nil ? MixedLook.style : nil,
                help: weightHelp,
                choices: .picking(TextWeight.allCases, current: shownWeight,
                                  title: { $0.rawValue.capitalized }) { setWeight($0) })
            .frame(maxWidth: .infinity)
            .playtestField("Weight")
            .panelHelp(weightHelp)
        }
    }
}
