import Foundation

/// Finding one layer in a list too long to scroll.
///
/// Separating a whole screenshot can put well over a hundred pieces in the
/// layers list, and the panel shows about five rows at a time. Scrolling that
/// to reach the one label you wanted is the moment the feature stops feeling
/// like a gift. Typing a few letters is the answer that costs the same however
/// long the list is.
public enum LayerSearch {

    /// The query with its edges trimmed. Empty means nothing was typed, which
    /// is not a search at all.
    public static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a row called `name` answers `query`.
    ///
    /// Every whitespace-separated word in the query has to appear somewhere in
    /// the name, in any order, so "save ch" finds "Save Changes" and so does
    /// "changes save". Case and accents do not count, because nobody hunting a
    /// button remembers whether the label was capitalised.
    ///
    /// An empty query matches everything, so a caller can ask one question
    /// rather than first asking whether there is a question.
    public static func matches(name: String, query: String) -> Bool {
        let words = normalized(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        return words.allSatisfy { word in
            name.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

extension PhotonzDocument {

    /// The rows the layers panel shows while a query is typed: every layer in
    /// the document whose name answers it, at any depth, topmost first.
    ///
    /// Results are FLAT. A search is a way to reach one thing, so a result is a
    /// plain row you click rather than a branch you have to read: no indent, no
    /// twist, no ancestors taking up the four rows the panel has. A group whose
    /// own name matches comes back as one row and its contents stay where they
    /// are, which is why a search for "Card" is one result rather than
    /// seventeen.
    ///
    /// Nothing typed gives back nothing rather than everything: the panel asks
    /// this only while there is a query, so an empty one is a mistake, and
    /// quietly flattening the whole tree would be the worst possible answer to
    /// it.
    public func layerRows(matching query: String, selected: Set<UUID>,
                          saysItsWords: Bool = true) -> [LayerRowDisplay] {
        guard !LayerSearch.normalized(query).isEmpty else { return [] }
        // Every row the panel could ever show, which is what makes a piece
        // inside a shut group findable. `marksOutOfView` is off: a result row
        // is drawn flat and away from its container, so a mark saying the
        // container cut it off has nothing to point at, and working one out for
        // every layer in a dense document is the most expensive thing this
        // walk can do.
        return layerRows(expanded: openableGroupIDs, selected: selected,
                         marksOutOfView: false, saysItsWords: saysItsWords)
            .filter { LayerSearch.matches(name: $0.name, query: query) }
            .map { display in
                LayerRowDisplay(
                    row: LayerPanelRow(id: display.id, depth: 0, isGroup: false,
                                       childCount: 0, isExpanded: false, parentID: nil),
                    name: display.name,
                    isVisible: display.isVisible,
                    isLocked: display.isLocked,
                    isSelected: display.isSelected,
                    isMainComponent: display.isMainComponent,
                    isComponentInstance: display.isComponentInstance,
                    versionName: display.versionName,
                    componentNote: display.componentNote,
                    isRasterizable: display.isRasterizable,
                    canTurnIntoPath: display.canTurnIntoPath)
            }
    }
}
