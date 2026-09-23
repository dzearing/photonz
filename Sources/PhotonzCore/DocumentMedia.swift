import CoreGraphics
import Foundation

/// The pictures one document holds, which is what the Library's Media shelf
/// shows (`docs/design/modes.md` §6).
///
/// The split between the two shelves is by SCOPE, not by kind, and the user
/// settled it on 2026-09-15: **History is the global shelf** — everything you
/// have ever captured, across every document, reachable from the menu bar with
/// no window open — and **the Library is this document's own shelf**: what
/// this file contains and can place again.
///
/// Until this existed, Media listed the app's whole capture folder, so a brand
/// new document opened onto a shelf full of other people's work. That was the
/// global shelf wearing the local one's clothes.
///
/// Two rules decide what is here, and both come out of that model:
///
/// * **One tile per picture, not per layer.** Three placements of one bell are
///   three rows in the layers list and one tile here. Layers is where things
///   ARE; the Library is what there IS to place.
/// * **The canvas the document is drawn on is not on the shelf.** You do not
///   place the paper into the picture. That is the bottom layer when it is a
///   locked picture, which is exactly what opening a file, opening a
///   recording, and File ▸ New each leave behind — and it is why File ▸ New
///   opens onto an empty shelf rather than onto a tile of white.
public struct DocumentMediaItem: Identifiable, Hashable, Sendable {
    /// The picture itself. Placing this item again reuses this very ref, so
    /// the document never ends up holding the same bitmap twice.
    public let image: ImageRef
    /// What the tile is captioned: the name of the layer that placed it
    /// first. The FIRST rather than the latest, so putting a second copy down
    /// does not rename the tile under your hand.
    public let name: String
    /// How many layers draw it.
    public let uses: Int

    public var id: UUID { image.id }

    public init(image: ImageRef, name: String, uses: Int) {
        self.image = image
        self.name = name
        self.uses = uses
    }

    /// The tile's second line, and half of what search reads. It answers the
    /// question only the document's own shelf can answer: how much of this
    /// picture is in here already.
    public var detail: String {
        uses == 1 ? "used once" : "used \(uses) times"
    }
}

public enum DocumentMedia {
    /// The layer holding the picture the document IS, as opposed to the
    /// pictures put INTO it: the lowest LOCKED picture in the stack.
    /// `PhotonzDocument.withBaseImage` is the one thing in the app that makes
    /// one, and the lock is what a person sees of it — the Background row in
    /// the layers list that cannot be dragged.
    ///
    /// The lowest locked one rather than simply the lowest, because a picture
    /// CAN be dropped underneath the Background: a drop on a row of the layers
    /// list lands where the line said it would, and the bottom of the list is
    /// one of the places that line can be. The canvas does not stop being the
    /// canvas because something slid under it.
    public static func canvasLayerID(in document: PhotonzDocument) -> UUID? {
        document.layers.first { layer in
            guard layer.isLocked, case .image = layer.content else { return false }
            return true
        }?.id
    }

    /// The shelf, newest first — the order the layers panel reads the stack
    /// in, so the picture you just put down is the first tile.
    public static func items(in document: PhotonzDocument) -> [DocumentMediaItem] {
        let canvas = canvasLayerID(in: document)
        var order: [UUID] = []
        var images: [UUID: ImageRef] = [:]
        var names: [UUID: [String]] = [:]
        // Top down, so `order` comes out newest first.
        for layer in document.allLayersTopDown where layer.id != canvas {
            for (image, name) in pictures(of: layer) {
                if images[image.id] == nil {
                    order.append(image.id)
                    images[image.id] = image
                }
                names[image.id, default: []].append(name)
            }
        }
        return order.compactMap { id in
            guard let image = images[id], let drawn = names[id], let name = caption(of: drawn)
            else { return nil }
            return DocumentMediaItem(image: image, name: name, uses: drawn.count)
        }
    }

    /// Which of the names drawing one picture the tile wears: the ORIGINAL
    /// placement's, so putting a copy down never renames the tile under your
    /// hand, wherever in the stack that copy ends up.
    ///
    /// A copy is told from an original by the number on the end of it, which
    /// is not a guess: a picture arriving where its name is already spoken for
    /// takes the next free number (`PlacedImageNaming`), and it is always the
    /// one ARRIVING that steps aside. So the name no other name here is a
    /// numbered copy of is the one that was placed first. Failing that — every
    /// one of them renamed by hand, say — the bottom-most, which is the oldest
    /// the stack can tell us about.
    private static func caption(of drawn: [String]) -> String? {
        let bottomFirst = Array(drawn.reversed())
        return bottomFirst.first { candidate in
            !bottomFirst.contains { isNumberedCopy(candidate, of: $0) }
        } ?? bottomFirst.first
    }

    /// True for "Hero banner 2" against "Hero banner".
    static func isNumberedCopy(_ name: String, of base: String) -> Bool {
        guard name != base, name.hasPrefix("\(base) ") else { return false }
        let tail = name.dropFirst(base.count + 1)
        return !tail.isEmpty && tail.allSatisfy(\.isNumber)
    }

    /// The same shelf as Library entries, which is what search, selection and
    /// the picked item's section all speak.
    public static func entries(in document: PhotonzDocument) -> [LibraryEntry] {
        entriesOf(items(in: document))
    }

    /// The same, for a shelf that has already read its items and would rather
    /// not walk the whole layer tree twice to caption them.
    public static func entriesOf(_ items: [DocumentMediaItem]) -> [LibraryEntry] {
        items.map {
            LibraryEntry(id: $0.id.uuidString, scope: .media, name: $0.name, detail: $0.detail)
        }
    }

    /// The item a tile was picked by, nil for an id that is not one of this
    /// document's pictures (a component's, a style's, or a stale pick left
    /// over from the document before this one).
    public static func item(id: String, in document: PhotonzDocument) -> DocumentMediaItem? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return items(in: document).first { $0.id == uuid }
    }

    /// Every picture one layer draws, each with the name it would wear on the
    /// shelf. A collage draws several, so its photos are numbered after it —
    /// they are pictures this document holds like any other, and a person who
    /// dropped four photos into a collage can put one of them down again.
    private static func pictures(of layer: Layer) -> [(ImageRef, String)] {
        switch layer.content {
        case .image(let ref):
            return [(ref, layer.name)]
        case .collage(let collage):
            let filled = collage.slots.enumerated().compactMap { index, slot in
                slot.imageRef.map { (index, $0) }
            }
            guard filled.count > 1 else { return filled.map { ($0.1, layer.name) } }
            return filled.map { ($0.1, "\(layer.name) \($0.0 + 1)") }
        default:
            return []
        }
    }
}
