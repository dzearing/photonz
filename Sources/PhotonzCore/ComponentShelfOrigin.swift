/// Where a tile on the Components shelf came from.
///
/// The shelf is one flat list holding three kinds of thing at once: the
/// originals in the document you have open, the components you shared from
/// another file, and the app's own starters. They draw the same picture and
/// wear the same violet mark, so without a word for it there is no way to tell
/// what is already in your file from what a drop would bring into it.
///
/// Pure policy, so the words and the rule for choosing them are testable away
/// from the tile that draws them.
public enum ComponentShelfOrigin: String, CaseIterable, Hashable, Sendable {
    /// An original in the open document. Dropping it places another copy of
    /// something this file already holds.
    case thisDocument
    /// On the shelf every document on this Mac reaches (`SharedComponentShelf`).
    /// Dropping it brings the component into this file for the first time.
    case shared
    /// One of the app's own (`StarterComponent`). Dropping it brings it in too.
    case starter

    /// What a tile is handed: a starter to draw, a shared component to draw,
    /// or neither, in which case it is drawing a layer of the open document.
    public init(isStarter: Bool, isShared: Bool) {
        if isStarter { self = .starter } else if isShared { self = .shared } else { self = .thisDocument }
    }

    /// The word in the corner of the tile's picture, or nil for the one that
    /// needs none.
    ///
    /// What is already in your file is the shelf's ordinary case and usually
    /// most of it, so marking every one of those tiles would say nothing and
    /// cost every tile a badge. The two kinds a drop would bring IN are the
    /// ones worth calling out, and they name the shelf they would come from.
    public var tag: String? {
        switch self {
        case .thisDocument: return nil
        case .shared: return SharedComponentShelf.shelfDetail
        case .starter: return StarterComponents.shelfDetail
        }
    }

    /// The sentence a tile's tooltip adds to say where its component lives,
    /// or nil for one already in this document, which needs no explaining.
    ///
    /// The word in the corner is four to seven letters and cannot carry this;
    /// the tooltip has room, and it is where somebody who does not recognise
    /// the word goes looking.
    public var arrivalNote: String? {
        switch self {
        case .thisDocument: return nil
        case .shared: return "A component you made in another document, so a drop brings it into this one."
        case .starter: return "One of the app's own, so a drop brings it into this document."
        }
    }

    /// True when a drop brings this component into the document for the first
    /// time rather than placing another copy of what is already here.
    public var arrivesOnDrop: Bool { self != .thisDocument }
}
