import Testing
@testable import PhotonzCore

/// Where a tile on the Components shelf came from, and the word it wears for
/// it. The shelf mixes three kinds of tile in one flat list, so the word is
/// the only thing that says whether a drop places another copy of something
/// you already have or brings a component in for the first time.
@Suite("Component shelf origin")
struct ComponentShelfOriginTests {

    @Test("A component in this document wears no word: it is the ordinary case")
    func thisDocumentHasNoTag() {
        #expect(ComponentShelfOrigin.thisDocument.tag == nil)
    }

    @Test("A component from the shared shelf says so")
    func sharedSaysShared() {
        #expect(ComponentShelfOrigin.shared.tag == "shared")
    }

    @Test("One of the app's own says so")
    func starterSaysStarter() {
        #expect(ComponentShelfOrigin.starter.tag == "starter")
    }

    @Test("The three words are the ones the shelf already wrote on its entries")
    func tagsMatchTheShelfDetailLines() {
        #expect(ComponentShelfOrigin.shared.tag == SharedComponentShelf.shelfDetail)
        #expect(ComponentShelfOrigin.starter.tag == StarterComponents.shelfDetail)
    }

    @Test("No two origins read the same")
    func everyOriginReadsDifferently() {
        let tags = ComponentShelfOrigin.allCases.map { $0.tag }
        #expect(Set(tags.map { $0 ?? "" }).count == tags.count)
    }

    @Test("Only the kinds not in the document arrive on a drop")
    func arrivesOnDrop() {
        #expect(ComponentShelfOrigin.thisDocument.arrivesOnDrop == false)
        #expect(ComponentShelfOrigin.shared.arrivesOnDrop)
        #expect(ComponentShelfOrigin.starter.arrivesOnDrop)
    }

    @Test("A tile knows its origin from the two things it is handed")
    func originFromWhatTheTileHolds() {
        #expect(ComponentShelfOrigin(isStarter: false, isShared: false) == .thisDocument)
        #expect(ComponentShelfOrigin(isStarter: false, isShared: true) == .shared)
        #expect(ComponentShelfOrigin(isStarter: true, isShared: false) == .starter)
        // A tile is never both; if it ever were, the app's own wins, because
        // that is the one whose picture it would be drawing.
        #expect(ComponentShelfOrigin(isStarter: true, isShared: true) == .starter)
    }

    @Test("The tooltip explains itself for exactly the kinds a drop brings in")
    func arrivalNoteFollowsTheDrop() {
        for origin in ComponentShelfOrigin.allCases {
            #expect((origin.arrivalNote != nil) == origin.arrivesOnDrop)
        }
        #expect(ComponentShelfOrigin.thisDocument.arrivalNote == nil)
    }

    @Test("Those sentences are plain and finished")
    func arrivalNotesReadLikeSentences() {
        for note in ComponentShelfOrigin.allCases.compactMap(\.arrivalNote) {
            #expect(note.hasSuffix("."))
            #expect(!note.contains("\u{2014}"))
            #expect(!note.contains("Claude"))
        }
    }

    @Test("A word stays short enough to sit in the corner of a 68 point tile")
    func wordsFitTheCorner() {
        for origin in ComponentShelfOrigin.allCases {
            #expect((origin.tag?.count ?? 0) <= 8)
        }
    }
}
