import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

/// The one reading of what a drag is carrying, and the one order to ask in.
///
/// Everywhere you can let something go — a layer row, the picture, a colour
/// swatch, a part whose switch is off, the Library shelf — used to work this
/// out for itself: its own list of types to register for, its own chain of
/// ifs, and its own opinion about which question came first. The same answer
/// written out five times is five places to edit the day a sixth thing becomes
/// draggable, and five chances for two surfaces to disagree about what the very
/// same drag is.
///
/// So the kinds are named here once, the ORDER is `Kind.allCases` and nowhere
/// else, and a surface says only which kinds it takes.
///
/// The order is not arbitrary. The app's own pasteboard types come first,
/// because a style and a component mean exactly one thing and can never be
/// mistaken for anything else. A colour comes after them, because a colour
/// falls back to plain text (the hex) so that it survives a trip through
/// another app, and plain text is the vaguest thing on any pasteboard. A file
/// comes after that, so a picture dragged in from the Finder is always read as
/// a picture. A row of the layers list comes LAST and is the only kind that is
/// not on the pasteboard at all: it travels as its id in plain text, so what
/// says it is a row is the list still holding one, and that is the weakest
/// claim of the lot — a row can be picked up and let go somewhere that never
/// reports it (over the picture, outside the window, escape), leaving the list
/// holding it. Asking about it last is what stops the next thing dragged in
/// being read as that row coming back.
///
/// The DRAG side is deliberately not here. `ColorDrag` speaks the system colour
/// and plain text types on purpose, `TextStyleDrag` speaks only the app's own
/// type on purpose, and both say why in their own files. What repeated was the
/// receiving side.
@MainActor
enum DragCargo {
    /// A saved text style off the Library shelf.
    case textStyle(TextStyleDrop.SavedStyle)
    /// A component off the Library shelf, and the version the shelf was set to.
    case component(ComponentDrag.Payload)
    /// A colour: off a swatch here, off the Library shelf, or out of any colour
    /// well on the Mac.
    case color(ColorDrag.Payload)
    /// A file arriving from outside — a picture, or a Photonz document.
    case file
    /// A row of the layers list on its way up or down the list, and the row
    /// that was picked up.
    case layerRow(UUID)

    /// A kind named without having the thing itself, so a surface can say what
    /// it takes before anything is in the air.
    ///
    /// **The declaration order IS the order every surface asks in.** Adding a
    /// kind means adding a case here, in the right place, and saying in
    /// `types(of:)` what it travels as. Nothing else in the app changes unless
    /// a surface wants to take it.
    enum Kind: CaseIterable, Sendable {
        case textStyle
        case component
        case color
        case file
        case layerRow
    }

    var kind: Kind {
        switch self {
        case .textStyle: .textStyle
        case .component: .component
        case .color: .color
        case .file: .file
        case .layerRow: .layerRow
        }
    }

    // MARK: - What a surface registers for

    /// The types a SwiftUI drop target registers for to be offered these kinds
    /// at all. Always in `Kind.allCases` order, so two surfaces that take the
    /// same kinds register the same list whatever order they named them in.
    static func types(_ kinds: [Kind]) -> [UTType] {
        Kind.allCases.filter(kinds.contains).flatMap(types(of:))
    }

    /// What each kind travels as. The one table; a new kind adds one row.
    private static func types(of kind: Kind) -> [UTType] {
        switch kind {
        case .textStyle: [UTType(TextStyleDrag.typeIdentifier) ?? .data]
        case .component: [UTType(ComponentDrag.typeIdentifier) ?? .data]
        case .color: ColorDrag.acceptedTypes
        case .file: FileDrop.types
        // A row travels as its id in plain text, which is why a layer row is
        // also where every other text-shaped drag in the app lands.
        case .layerRow: [.text]
        }
    }

    // MARK: - What is in the air

    /// What the drag in flight is carrying, for a surface answering a SwiftUI
    /// `DropInfo`.
    ///
    /// The app's own kinds are read off the DRAG pasteboard rather than out of
    /// the carrier the drop hands over, because a surface has to answer on the
    /// frame the pointer arrives: a carrier gives up its bytes asynchronously,
    /// a ring that appears two frames late flickers as the pointer runs down a
    /// list, and a drop let go of before the answer came back would land
    /// nothing.
    ///
    /// `rowInHand` is the row the layers list is holding, for the one kind that
    /// is not on a pasteboard. Leave it nil anywhere that is not the list.
    ///
    /// `info` is optional because a surface that takes only the app's own kinds
    /// answers without one: a colour swatch works out its ring from a
    /// `@State`-driven redraw, not from inside a delegate callback. A file is
    /// the one kind that can only be seen through a `DropInfo`, so leaving it
    /// out means `.file` is never the answer.
    static func inFlight(_ info: DropInfo? = nil, among kinds: [Kind],
                         rowInHand: UUID? = nil) -> DragCargo? {
        for kind in Kind.allCases where kinds.contains(kind) {
            switch kind {
            case .textStyle:
                if let style = TextStyleDrag.payloadInFlight() { return .textStyle(style) }
            case .component:
                if let payload = ComponentDrag.payloadInFlight() { return .component(payload) }
            case .color:
                if let payload = ColorDrag.payloadInFlight() { return .color(payload) }
            case .file:
                if let info, FileDrop.isAboutAFile(info) { return .file }
            case .layerRow:
                if let rowInHand { return .layerRow(rowInHand) }
            }
        }
        return nil
    }

    /// The colour in the air right now, nil for every other drag. The one
    /// question the three colour surfaces ask, spelled once.
    static func colorInFlight() -> ColorDrag.Payload? {
        guard case .color(let payload)? = inFlight(among: [.color]) else { return nil }
        return payload
    }

    /// What an AppKit drag is carrying, for a view that answers an
    /// `NSDraggingInfo` — which on this side of the app means the picture.
    ///
    /// `.layerRow` is never answered here: it is not on a pasteboard, and
    /// nothing outside the layers list has any business reading it.
    static func on(_ pasteboard: NSPasteboard, among kinds: [Kind]) -> DragCargo? {
        for kind in Kind.allCases where kinds.contains(kind) {
            switch kind {
            case .textStyle:
                if let style = TextStyleDrag.payload(on: pasteboard) { return .textStyle(style) }
            case .component:
                if let payload = ComponentDrag.payload(on: pasteboard) { return .component(payload) }
            case .color:
                if let payload = ColorDrag.payload(on: pasteboard) { return .color(payload) }
            case .file:
                if fileURL(on: pasteboard) != nil { return .file }
            case .layerRow:
                continue
            }
        }
        return nil
    }

    /// The file a pasteboard is carrying, nil for every drag that is not one.
    static func fileURL(on pasteboard: NSPasteboard) -> URL? {
        pasteboard.readObjects(forClasses: [NSURL.self],
                               options: [.urlReadingFileURLsOnly: true])?.first as? URL
    }
}
