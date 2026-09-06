import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

/// Carrying a colour from one swatch to another, and in and out of other apps.
///
/// A colour well on a Mac has always been something you can pull a colour out
/// of and drop a colour onto, so this is muscle memory rather than an invention:
/// the swatch is the handle, and the panel is full of them.
///
/// Three things go on the pasteboard, in the order anything reading it should
/// prefer them:
///
/// - **The app's own type**, which is the only one that can carry a GRADIENT
///   and the only one that knows WHICH swatch the colour came from, so a colour
///   dropped straight back where it came from can be refused rather than
///   written into history as a no-op.
/// - **A colour**, the type every colour well on the Mac speaks, so a colour
///   dragged out of Photonz lands in another app's well and one dragged in from
///   the system Colors panel lands here.
/// - **Plain text**, the hex, so the colour survives a trip through anything
///   that only takes words — and so a build with no bundle around it, where the
///   app's own type carries zero bytes, still drags.
enum ColorDrag {
    /// DECLARED in the app's Info.plist (`Scripts/build-app.sh`,
    /// `UTExportedTypeDeclarations`). It has to be: an identifier the system
    /// has never heard of is accepted onto the drag pasteboard and then carries
    /// zero bytes, which is exactly how Library drag and drop looked broken
    /// until 2026-09-03. The plain text below is the safety net for a bare
    /// `swift build` binary, which has no Info.plist at all.
    static let typeIdentifier = "com.photonz.paint"
    static let pasteboardType = NSPasteboard.PasteboardType(typeIdentifier)

    /// The types a swatch takes a drop of, innermost meaning first.
    static let acceptedTypes: [UTType] = [
        UTType(typeIdentifier) ?? .data,
        UTType(NSPasteboard.PasteboardType.color.rawValue) ?? .data,
        .utf8PlainText,
    ]

    /// What a swatch hands over: the paint it is wearing, and the name of the
    /// swatch itself so the same swatch can recognise its own colour coming
    /// home.
    struct Payload: Hashable, Codable, Sendable {
        var paint: Paint
        /// The `wellKey` of the swatch the drag started from, empty when the
        /// colour came in from outside the app.
        var source: String
        /// The saved colour this drag IS, for one pulled off the Library
        /// shelf. Only the app's own pasteboard type can carry it — a colour
        /// handed to another app is a colour and nothing else — which is
        /// exactly right: the name means nothing outside this document.
        var style: ColorDrop.SavedColor?

        init(paint: Paint, source: String = "", style: ColorDrop.SavedColor? = nil) {
            self.paint = paint
            self.source = source
            self.style = style
        }
    }

    // MARK: - Picking one up

    /// The drag a swatch starts. Nothing in here touches the app's state, so a
    /// change made while the drag is being handed over redraws the swatch and
    /// SwiftUI asks for the item all over again.
    static func itemProvider(paint: Paint, source: String,
                             style: ColorDrop.SavedColor? = nil) -> NSItemProvider {
        let provider = NSItemProvider()
        let payload = Payload(paint: paint, source: source, style: style)
        if let data = try? JSONEncoder().encode(payload) {
            provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier,
                                                visibility: .ownProcess) { completion in
                completion(data, nil)
                return nil
            }
        }
        if let color = nsColor(paint.hex),
           let list = color.pasteboardPropertyList(forType: .color),
           let data = list as? Data {
            provider.registerDataRepresentation(
                forTypeIdentifier: NSPasteboard.PasteboardType.color.rawValue,
                visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
        }
        let text = Data(paint.hex.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier,
                                            visibility: .all) { completion in
            completion(text, nil)
            return nil
        }
        return provider
    }

    // MARK: - Reading one back

    /// The colour a set of loaded representations is carrying, nil for a drag
    /// that is not a colour at all. Ours first, because it is the only one
    /// that can be a gradient; then a colour from any Mac app; then a hex
    /// somebody dragged in as words.
    static func payload(ours: Data?, color: Data?, text: Data?) -> Payload? {
        if let ours, let decoded = try? JSONDecoder().decode(Payload.self, from: ours) {
            return decoded
        }
        if let color, let list = NSColor(pasteboardPropertyList: color, ofType: .color),
           let hex = hexString(list) {
            return Payload(paint: Paint(hex: hex))
        }
        if let text, let string = String(data: text, encoding: .utf8) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let rgba = RGBA(hex: trimmed) {
                return Payload(paint: Paint(hex: rgba.a < 1 ? rgba.hexStringWithAlpha
                                                            : rgba.hexString))
            }
        }
        return nil
    }

    /// The colour on the drag pasteboard right now, nil when what is in the
    /// air is not a colour.
    ///
    /// The DRAG pasteboard rather than the carrier a drop hands over, because
    /// a carrier gives up its bytes asynchronously and the swatch has to answer
    /// on the frame the pointer arrives: a ring that appears two frames late
    /// flickers on an 18pt square, and a drop let go of before the answer came
    /// back would land nothing.
    @MainActor static func payloadInFlight() -> Payload? {
        payload(on: dragPasteboard())
    }

    static func payload(on pasteboard: NSPasteboard) -> Payload? {
        payload(ours: pasteboard.data(forType: pasteboardType),
                color: pasteboard.data(forType: .color),
                text: pasteboard.data(forType: .string))
    }

    /// The board a drag in flight is written on. A scripted walk cannot start
    /// a real drag session — AppKit only begins one from an event that came
    /// off a real device — so a probe build lets the harness stand a board in
    /// its place, which is the same board the destination would have read.
    @MainActor private static func dragPasteboard() -> NSPasteboard {
        #if PHOTONZ_PLAYTEST
        if let board = playtestPasteboard { return board }
        #endif
        return NSPasteboard(name: .drag)
    }

    #if PHOTONZ_PLAYTEST
    /// Set by the harness for the length of one scripted colour drag, and put
    /// back to nil the moment it ends.
    @MainActor static var playtestPasteboard: NSPasteboard?
    #endif

    // MARK: - Colours, both ways round

    static func nsColor(_ hex: String) -> NSColor? {
        guard let rgba = RGBA(hex: hex) else { return nil }
        return NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    }

    /// A colour from anywhere on the Mac written the way the document writes
    /// them. Converted into sRGB first: a colour dragged out of the system
    /// Colors panel can be in any space at all, and reading its components
    /// without converting throws.
    static func hexString(_ color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let rgba = RGBA(r: srgb.redComponent, g: srgb.greenComponent,
                        b: srgb.blueComponent, a: srgb.alphaComponent)
        return rgba.a < 1 ? rgba.hexStringWithAlpha : rgba.hexString
    }
}

/// The colour under the pointer while a drag travels.
///
/// The same picture wherever a colour is picked up — a swatch on a row, a
/// swatch on the bar, a tile on the Library shelf — because a colour in the
/// air is one thing and it should look like one thing. A tile is a wide
/// rounded rectangle with a caption under it; dragging THAT would say a tile
/// was moving rather than a colour.
struct DraggedColorChip: View {
    let paint: Paint

    var body: some View {
        PaintFill(paint: paint)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 4)))
            .frame(width: 22, height: 22)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.primary.opacity(0.35), lineWidth: 1))
    }
}
