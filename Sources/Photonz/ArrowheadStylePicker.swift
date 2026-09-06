import AppKit
import PhotonzCore
import SwiftUI

extension ArrowheadStyle {
    /// The picture the picker shows instead of the word. An ending is a shape,
    /// and five shapes side by side are read in one glance where five words
    /// ("Open", "Hollow dot") have to be read one at a time.
    var symbolName: String {
        switch self {
        case .triangle: "arrowtriangle.right.fill"
        case .open: "chevron.right"
        case .dot: "circle.fill"
        case .hollowDot: "circle"
        case .plain: "minus"
        }
    }

    /// That picture, carrying the ENDING's name rather than the symbol's.
    ///
    /// A segment of a segmented picker takes its name from the picture on it,
    /// and a plain `Image(systemName:)` hands over whatever the system happens
    /// to call that symbol — "Forward" for the open head, "remove" for the
    /// plain line, and nothing at all for the hollow dot, since most symbols
    /// carry no description. That is what a screen reader would have read out,
    /// and what an automated walk had to press it by. Built through `NSImage`
    /// the description is ours, so every ending answers to its own name.
    /// (A SwiftUI `.accessibilityLabel` on the Image does not reach the
    /// segment; this is the way in.)
    var glyph: Image {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) else {
            return Image(systemName: symbolName)
        }
        let sized = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)) ?? image
        sized.accessibilityDescription = title
        return Image(nsImage: sized)
    }

    /// What the tooltip says under the picture.
    var help: String {
        switch self {
        case .triangle: "A solid head, pointing at what you picked"
        case .open: "A fine open head, quieter over a busy screenshot"
        case .dot: "A solid dot, sitting on the point instead of pointing at it"
        case .hollowDot: "A hollow dot, so what it marks shows through"
        case .plain: "No head at all: a plain leader line for a label to hang off"
        }
    }
}

/// The row of endings an arrow can wear, as pictures, with the picked one named
/// in words beside the row's caption. Five glyphs side by side are how you
/// COMPARE endings; the word is how you remember three minutes later which one
/// you are looking at, the same bargain a tool's modes make.
///
/// One control, used by the arrow tool's own settings (what the NEXT arrow ends
/// in) and by the picked arrow's section in the dock (what THIS one ends in).
/// `selection` is optional so a mixture of picked arrows can show nothing
/// chosen rather than lying about one of them; picking then sets them all.
struct ArrowheadStylePicker: View {
    let selection: ArrowheadStyle?
    let isMixed: Bool
    let pick: (ArrowheadStyle) -> Void

    /// The word beside the caption: which ending is on, or that they differ.
    static func word(_ selection: ArrowheadStyle?, isMixed: Bool) -> String? {
        isMixed ? nil : selection?.title
    }

    var body: some View {
        Picker("Ending", selection: Binding<ArrowheadStyle?>(
            get: { isMixed ? nil : selection },
            set: { if let style = $0 { pick(style) } })) {
            ForEach(ArrowheadStyle.allCases, id: \.self) { style in
                style.glyph.tag(ArrowheadStyle?.some(style))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        // Five glyphs cannot fill a panel row the way a slider does, so the
        // row is claimed and the pictures sit at its leading edge — lined up
        // with the sliders above and below rather than floating in the middle
        // of them.
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(isMixed
              ? "The picked arrows end differently. Choosing one ending sets all of them."
              : (selection ?? .standard).help)
    }
}
