import Foundation

// Recordings and sounds brought into the Library WITHOUT going onto the
// timeline (`video.html`, onboarding step 2, "Fill the Library": Import, a file
// dropped on the panel, or a capture; step 3 then drags a tile onto an empty
// track). Premiere calls this importing into a bin, and it is how a video edit
// starts: gather the footage first, then cut.

/// What bringing some files into the Library came to, and the words for it.
public struct LibraryImport: Hashable, Sendable {
    /// The files that are new tiles, under their own names, in the order they came.
    public var added: [String]
    /// The files the shelf already had, under the names their tiles carry.
    public var alreadyThere: [String]
    /// The files that turned out to hold nothing the app can play.
    public var unreadable: [String]
    /// The first new tile, which the shelf scrolls to.
    public var firstNewID: UUID?
    /// The first tile this was about, new or not: the one worth showing.
    public var revealID: UUID?

    public init(added: [String] = [], alreadyThere: [String] = [], unreadable: [String] = [],
                firstNewID: UUID? = nil, revealID: UUID? = nil) {
        self.added = added
        self.alreadyThere = alreadyThere
        self.unreadable = unreadable
        self.firstNewID = firstNewID
        self.revealID = revealID
    }

    /// The verdict at the head of the pill.
    public var title: String {
        if !added.isEmpty { return "Added to Library" }
        if !alreadyThere.isEmpty { return "Already in Library" }
        return "Not added"
    }

    /// What happened, in plain words.
    public var detail: String {
        var said: [String] = []
        if !added.isEmpty {
            said.append("\(Self.names(added)) \(added.count == 1 ? "is" : "are") in the Library")
        } else if !alreadyThere.isEmpty {
            said.append("\(Self.names(alreadyThere)) \(alreadyThere.count == 1 ? "is" : "are") already in the Library")
        }
        if !unreadable.isEmpty {
            said.append("There is nothing in \(Self.names(unreadable)) the app can play")
        }
        return said.joined(separator: ". ")
    }

    /// One name, two names joined, or a count past that.
    private static func names(_ names: [String]) -> String {
        switch names.count {
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names.count) files"
        }
    }
}

extension PhotonzDocument {

    /// Puts files on the Library shelf and nowhere else. A file the shelf
    /// already holds keeps its tile and its name.
    @discardableResult
    public mutating func bringIntoLibrary(_ sources: [DocumentMediaSource],
                                          unreadable: [String] = []) -> LibraryImport {
        var outcome = LibraryImport(unreadable: unreadable)
        for source in sources {
            if let held = DocumentMedia.clips(in: self).first(where: { $0.id == source.id }) {
                // Picked twice in one go counts once, as new.
                if !outcome.added.contains(held.name) && !outcome.alreadyThere.contains(held.name) {
                    outcome.alreadyThere.append(held.name)
                }
            } else {
                rememberMedia(source.media, named: source.name)
                outcome.added.append(source.name)
                outcome.firstNewID = outcome.firstNewID ?? source.id
            }
            outcome.revealID = outcome.revealID ?? source.id
        }
        if let first = outcome.firstNewID { outcome.revealID = first }
        return outcome
    }
}
