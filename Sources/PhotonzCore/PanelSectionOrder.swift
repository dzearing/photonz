/// The order of the sections down a panel: what a saved order becomes once the
/// app has learned a new section, and how one section is moved without
/// disturbing an order somebody arranged by hand.
///
/// Sections are identified by their stored string ids, so this stays a pure
/// list rule with nothing about panels in it.
public enum PanelSectionOrder {
    /// A saved order brought up to date. Sections the save has never seen are
    /// spliced in where they were designed to sit rather than dumped at the
    /// bottom, and ids that no longer exist fall out.
    ///
    /// Everything the save DID choose keeps its place: this never re-sorts.
    public static func merged(saved: [String], canonical: [String]) -> [String] {
        let known = Set(canonical)
        var result: [String] = []
        for id in saved where known.contains(id) && !result.contains(id) {
            result.append(id)
        }
        for section in canonical where !result.contains(section) {
            let rank = canonical.firstIndex(of: section) ?? 0
            let insertAt = result.firstIndex {
                (canonical.firstIndex(of: $0) ?? 0) > rank
            } ?? result.endIndex
            result.insert(section, at: insertAt)
        }
        return result
    }

    /// `section` moved to sit immediately after `anchor`, and nothing else
    /// touched. This is how a section that shipped in the wrong place reaches
    /// people who already have an order saved: one section relocates, and any
    /// arrangement they made by hand around it survives.
    ///
    /// Does nothing if either id is absent, or if it is already there.
    public static func moving(_ section: String, after anchor: String, in order: [String]) -> [String] {
        guard section != anchor,
              order.contains(section), let anchorIndex = order.firstIndex(of: anchor) else { return order }
        if order.indices.contains(anchorIndex + 1), order[anchorIndex + 1] == section { return order }
        var result = order
        result.removeAll { $0 == section }
        guard let landing = result.firstIndex(of: anchor) else { return order }
        result.insert(section, at: landing + 1)
        return result
    }

    /// `section` moved to sit immediately BEFORE `anchor`, and nothing else
    /// touched. The mirror of `moving(_:after:in:)`, for the fixes that read
    /// as "this belongs above that": a section whose whole point is to be the
    /// first thing you see about what you picked has no anchor underneath it
    /// to hang off, and naming the one it must beat says the rule plainly.
    ///
    /// Does nothing if either id is absent, or if it is already there.
    public static func moving(_ section: String, before anchor: String, in order: [String]) -> [String] {
        guard section != anchor,
              order.contains(section), let anchorIndex = order.firstIndex(of: anchor) else { return order }
        if anchorIndex > 0, order[anchorIndex - 1] == section { return order }
        var result = order
        result.removeAll { $0 == section }
        guard let landing = result.firstIndex(of: anchor) else { return order }
        result.insert(section, at: landing)
        return result
    }

    /// A whole GROUP of sections moved to sit immediately before `anchor`, in
    /// the order given, and nothing else touched.
    ///
    /// Chaining the single move above would work the group backwards (each one
    /// lands on the anchor and pushes the last one down), and a fix that reads
    /// "these four belong above that" should say exactly that once. Sections
    /// the order does not hold are skipped, so a group can name a section that
    /// only some documents have.
    ///
    /// Does nothing if the anchor is absent, if the group is empty, or if the
    /// group names the anchor itself.
    public static func moving(_ sections: [String], before anchor: String,
                              in order: [String]) -> [String] {
        let group = sections.filter { order.contains($0) && $0 != anchor }
        guard !group.isEmpty, group.count == sections.filter({ order.contains($0) }).count,
              order.contains(anchor) else { return order }
        var result = order
        result.removeAll { group.contains($0) }
        guard let landing = result.firstIndex(of: anchor) else { return order }
        result.insert(contentsOf: group, at: landing)
        return result
    }
}
