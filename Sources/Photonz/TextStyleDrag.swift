import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

// Carrying a saved text style off the Library shelf and letting go of it on a
// piece of text (Next, `next-styles` + `next-color-drag`). The colour half of
// the same idea is `ColorDrag.swift`, and the picture's side of this one is
// `CanvasTextStyleDrop.swift`.

/// The bytes a text style tile hands over, and how to read them back.
///
/// What travels is the saved style ITSELF, an id and a name, not a copy of what
/// it looks like: text a style lands on follows the name the day the style
/// behind it is edited, exactly as it would if the name had been picked out of
/// the Style menu. A hex and a font size would be a quieter, lossier second way
/// to do one thing.
///
/// Only the app's own type, and no plain text fallback: a text style means
/// nothing outside this document, and a name dropped into another app as words
/// would be a promise nobody can keep.
enum TextStyleDrag {
    /// DECLARED in the app's Info.plist (`Scripts/build-app.sh`,
    /// `UTExportedTypeDeclarations`). It has to be: an identifier the system
    /// has never heard of is accepted onto the drag pasteboard and then carries
    /// zero bytes, which is how Library drag and drop looked broken until
    /// 2026-09-03. A plain `swift build` binary has no bundle around it and
    /// still behaves that way, so this is verified from the app bundle.
    static let typeIdentifier = "com.photonz.text-style"
    static let pasteboardType = NSPasteboard.PasteboardType(typeIdentifier)

    /// The drag a text style tile starts. Nothing in here touches the app's
    /// state, so a rename while the drag is being handed over redraws the tile
    /// and SwiftUI asks for the item again.
    static func itemProvider(style: TextStyle) -> NSItemProvider {
        let provider = NSItemProvider()
        let payload = TextStyleDrop.SavedStyle(id: style.id, name: style.name)
        if let data = try? JSONEncoder().encode(payload) {
            provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier,
                                                visibility: .ownProcess) { completion in
                completion(data, nil)
                return nil
            }
        }
        return provider
    }

    /// The saved style a pasteboard is carrying, nil for every other drag.
    static func payload(on pasteboard: NSPasteboard) -> TextStyleDrop.SavedStyle? {
        guard let data = pasteboard.data(forType: pasteboardType) else { return nil }
        return try? JSONDecoder().decode(TextStyleDrop.SavedStyle.self, from: data)
    }

    /// The style on the drag pasteboard right now, nil when what is in the air
    /// is not one.
    ///
    /// The DRAG pasteboard rather than the carrier a drop hands over, for the
    /// reason `ColorDrag.payloadInFlight` gives: a carrier gives up its bytes
    /// asynchronously and a row has to answer on the frame the pointer arrives.
    /// A ring that appears two frames late flickers as the pointer runs down a
    /// list, and a drop let go of before the answer came back would land
    /// nothing.
    @MainActor static func payloadInFlight() -> TextStyleDrop.SavedStyle? {
        payload(on: dragPasteboard())
    }

    /// The board a drag in flight is written on. A scripted walk cannot start a
    /// real drag session — AppKit only begins one from an event that came off a
    /// real device — so a probe build lets the harness stand a board in its
    /// place, which is the same board the destination would have read.
    @MainActor private static func dragPasteboard() -> NSPasteboard {
        #if PHOTONZ_PLAYTEST
        if let board = playtestPasteboard { return board }
        #endif
        return NSPasteboard(name: .drag)
    }

    #if PHOTONZ_PLAYTEST
    /// Set by the harness for the length of one scripted style drag, and put
    /// back to nil the moment it ends.
    @MainActor static var playtestPasteboard: NSPasteboard?
    #endif
}

/// The style under the pointer while a drag travels.
///
/// It draws the same two letters the tile draws, on the same plate that opposes
/// them, at the size a colour travels as: what is moving is a style, and a
/// style you cannot read is a grey square. The tile itself is not carried,
/// because a tile under the pointer would say a tile was moving.
struct DraggedTextStyleChip: View {
    let style: TextStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(TextStyleTileLook.plate(style.treatment))
            Text(TextStyleNaming.sample)
                .font(.system(size: 15,
                              weight: TextStyleTileLook.weight(style.treatment.weight)))
                .foregroundStyle(Color(hex: style.treatment.colorHex))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(width: 30, height: 22)
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(.primary.opacity(0.35), lineWidth: 1))
    }
}

/// How a text style is drawn wherever it stands for itself: on its shelf tile,
/// and on the chip that travels under the pointer. One place, so the thing you
/// picked up and the thing on the shelf are recognisably the same thing.
enum TextStyleTileLook {

    /// What the letters are drawn ON.
    ///
    /// Not the panel's own colour: the first build did that and a style whose
    /// text is near-black came out invisible on the dark dock, which is the one
    /// thing a tile has to not do. So the plate opposes the letters the same way
    /// the canvas contrast halo does — light letters get a dark plate, dark
    /// letters a light one — and the sample is legible whatever the style is and
    /// whichever theme the app is in.
    static func plate(_ treatment: TextTreatment) -> Color {
        let luminance = (RGBA(hex: treatment.colorHex)
                         ?? RGBA(r: 1, g: 1, b: 1)).relativeLuminance
        return luminance >= 0.5 ? Color.black.opacity(0.75) : Color.white.opacity(0.85)
    }

    static func weight(_ weight: TextWeight) -> Font.Weight {
        switch weight {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}
